// Supabase wiring for the app side: reads the ranked restaurant list (no
// account needed — public read), submits crowdsourced mic readings (account
// required — see supabase/migrations/0003_auth_required_for_mic_readings.sql
// and AuthScreen). Uses the public anon key throughout; the signed-in user's
// identity comes from their session, not this key. The pipeline connects
// separately, as its own scoped `pipeline_service` role
// (0002_pipeline_role.sql), not this anon key and not a service-role bypass.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/mic_reading.dart';
import '../models/restaurant.dart';

// Passed at build/run time via --dart-define, not hardcoded, since these
// differ per environment (dev/prod) and the anon key shouldn't be committed
// as a literal even though it's safe for client-side use under RLS.
// Example: flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

class SupabaseNotConfigured implements Exception {}

class SupabaseService {
  static bool get isConfigured => _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;

  static Future<void> initialize() async {
    if (!isConfigured) return;
    // supabase_flutter renamed this param from anonKey to publishableKey —
    // still accepts the legacy JWT-format anon key we're passing, not just
    // the newer sb_publishable_... format.
    await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseAnonKey);
  }

  SupabaseClient get _client => Supabase.instance.client;

  bool get isSignedIn => isConfigured && _client.auth.currentUser != null;

  String? get currentUserEmail => _client.auth.currentUser?.email;

  /// Fires on sign-in, sign-out, and token refresh — lets the UI show
  /// current auth state live instead of only checking it once at build time.
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<void> signOut() => _client.auth.signOut();

  Future<void> updatePassword(String newPassword) async {
    if (!isConfigured) throw SupabaseNotConfigured();
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// The signed-in user's own submitted readings, newest first, joined with
  /// the restaurant name for display. RLS on `mic_readings` (see
  /// 0003_auth_required_for_mic_readings.sql) already scopes this to the
  /// caller's own rows — no explicit user_id filter needed here.
  Future<List<MyReading>> fetchMyReadings() async {
    if (!isConfigured || !isSignedIn) return [];
    final rows = await _client
        .from('mic_readings')
        .select('place_id, decibel_value, platform, recorded_at, restaurants(name)')
        .order('recorded_at', ascending: false);

    return (rows as List).map((row) {
      final restaurant = row['restaurants'] as Map<String, dynamic>?;
      return MyReading(
        placeId: row['place_id'] as String,
        restaurantName: restaurant?['name'] as String? ?? 'Unknown restaurant',
        decibelValue: (row['decibel_value'] as num).toDouble(),
        platform: row['platform'] as String,
        recordedAt: DateTime.parse(row['recorded_at'] as String),
      );
    }).toList();
  }

  Future<List<Restaurant>> fetchRankedRestaurants() async {
    if (!isConfigured) throw SupabaseNotConfigured();

    final rows = await _client
        .from('restaurants')
        .select()
        .order('quietness_score', ascending: false, nullsFirst: false);

    return (rows as List).map((row) => _restaurantFromRow(row as Map<String, dynamic>)).toList();
  }

  /// Empty for a signed-out user — favoriting requires an account (same gate
  /// as mic readings, see 0004_favorites.sql), browsing doesn't.
  Future<Set<String>> fetchFavoritePlaceIds() async {
    if (!isConfigured || !isSignedIn) return {};
    final rows = await _client.from('favorites').select('place_id');
    return (rows as List).map((row) => row['place_id'] as String).toSet();
  }

  /// user_id is filled server-side (defaults to auth.uid() — see the
  /// migration), not passed here, so a client can't favorite under someone
  /// else's identity even by mistake.
  Future<void> addFavorite(String placeId) async {
    if (!isConfigured) throw SupabaseNotConfigured();
    await _client.from('favorites').insert({'place_id': placeId});
  }

  Future<void> removeFavorite(String placeId) async {
    if (!isConfigured) throw SupabaseNotConfigured();
    await _client.from('favorites').delete().eq('place_id', placeId);
  }

  /// Proxies through the `search-assistant` Edge Function
  /// (supabase/functions/search-assistant) — the Anthropic API key lives
  /// only there, never in this app. `history` is the prior turns of the
  /// conversation, kept client-side; there's no server-side chat-session
  /// table (yet).
  Future<String> askSearchAssistant(String message, List<Map<String, String>> history) async {
    if (!isConfigured) throw SupabaseNotConfigured();

    final response = await _client.functions.invoke(
      'search-assistant',
      body: {'message': message, 'history': history},
    );

    if (response.status != 200) {
      throw Exception('Search Assistant request failed (${response.status})');
    }
    final data = response.data as Map<String, dynamic>;
    return data['reply'] as String? ?? '';
  }

  Future<void> submitMicReading(MicReading reading) async {
    if (!isConfigured) throw SupabaseNotConfigured();

    await _client.from('mic_readings').insert({
      'place_id': reading.placeId,
      'decibel_value': reading.decibelValue,
      'platform': reading.platform,
      'recorded_at': reading.recordedAt.toIso8601String(),
    });
  }

  /// Maps a `restaurants` table row (see 0001_init.sql) onto the same
  /// [Restaurant] model the bundled-JSON path uses, so screens don't need
  /// to know which data source they're reading from.
  Restaurant _restaurantFromRow(Map<String, dynamic> row) {
    return Restaurant.fromJson({
      'placeId': row['place_id'],
      'yelpId': row['yelp_id'],
      'name': row['name'],
      'cuisine': row['cuisine'],
      'priceLevel': row['price_level'],
      'address': row['address'],
      'suburb': row['suburb'],
      'lat': row['lat'],
      'lng': row['lng'],
      'googleRating': row['google_rating'],
      'yelpRating': row['yelp_rating'],
      'signals': {
        'review': {
          'positiveCount': row['review_positive_count'],
          'negativeCount': row['review_negative_count'],
          'subscore': row['review_subscore'],
        },
        'popular': {
          'busynessPercent': row['popular_busyness_percent'],
          'subscore': row['popular_subscore'],
        },
        'mic': {
          'readingCountIos': row['mic_reading_count_ios'],
          'readingCountAndroid': row['mic_reading_count_android'],
          'subscore': row['mic_subscore'],
        },
      },
      'quietnessScore': row['quietness_score'],
      'confidence': row['confidence'],
      'signalCount': [
        row['review_subscore'],
        row['popular_subscore'],
        row['mic_subscore'],
      ].where((v) => v != null).length,
    });
  }
}
