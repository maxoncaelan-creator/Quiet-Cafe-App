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

/// Mirrors redeem_beta_code()'s text return values
/// (0015_beta_code_account_binding.sql) — kept as distinct cases rather
/// than a bool so BetaGateScreen can tell "wrong code" apart from "expired"
/// apart from "someone else already used this one," per Caelan's "hard
/// block with a message" call.
enum BetaCodeResult { ok, invalid, expired, alreadyRedeemed, error }

/// The signed-in user's current Search Assistant usage window — see
/// search_assistant_usage in 0007_search_assistant_rate_limit.sql. Kept in
/// sync with the search-assistant Edge Function's own constants
/// (TOKEN_LIMIT, WINDOW_MS), which are the actual source of truth; this
/// file's copies exist only so the app can show status without a round
/// trip through the assistant itself.
const searchAssistantTokenLimit = 10000;
const searchAssistantWindow = Duration(hours: 5);

class SearchAssistantUsage {
  final DateTime windowStart;
  final int tokensUsed;
  const SearchAssistantUsage(
      {required this.windowStart, required this.tokensUsed});

  DateTime get resetAt => windowStart.add(searchAssistantWindow);
  bool get isRateLimited =>
      tokensUsed >= searchAssistantTokenLimit &&
      resetAt.isAfter(DateTime.now());
}

/// Thrown by [SupabaseService.askSearchAssistant] when the Edge Function
/// rejects a request for being over the per-account token budget.
class SearchAssistantRateLimited implements Exception {
  final DateTime resetAt;
  const SearchAssistantRateLimited(this.resetAt);
}

/// The outcome of a user-requested venue-coverage refresh. The backend is the
/// authority for whether a paid Google Places lookup may run; this only gives
/// the List View enough information to explain the resulting state.
class VenueCoverageRefresh {
  final bool triggered;
  final int? placesFound;
  final int? resultCount;
  final String? reason;

  const VenueCoverageRefresh({
    required this.triggered,
    this.placesFound,
    this.resultCount,
    this.reason,
  });

  factory VenueCoverageRefresh.fromJson(Map<String, dynamic> json) {
    return VenueCoverageRefresh(
      triggered: json['triggered'] == true,
      placesFound: (json['placesFound'] as num?)?.toInt(),
      resultCount: (json['resultCount'] as num?)?.toInt(),
      reason: json['reason'] as String?,
    );
  }
}

/// A restaurant near the user's current position — see
/// [SupabaseService.findNearestRestaurant]. Deliberately just enough to
/// show "Are you at X?" and navigate; the full [Restaurant] is fetched by
/// router.dart's own by-id loader only if the user says yes.
class NearbyRestaurant {
  final String placeId;
  final String name;
  final double distanceMeters;
  const NearbyRestaurant(
      {required this.placeId,
      required this.name,
      required this.distanceMeters});
}

class SupabaseService {
  static bool get isConfigured =>
      _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;

  static Future<void> initialize() async {
    if (!isConfigured) return;
    // supabase_flutter renamed this param from anonKey to publishableKey —
    // still accepts the legacy JWT-format anon key we're passing, not just
    // the newer sb_publishable_... format.
    await Supabase.initialize(
        url: _supabaseUrl, publishableKey: _supabaseAnonKey);
  }

  SupabaseClient get _client => Supabase.instance.client;

  /// Account-gated calls require a session with an access token, not merely a
  /// cached [User]. During an email-confirmation callback Supabase can expose
  /// the user before it has finished installing the callback session; using
  /// `currentUser` in that window would send an anonymous RPC and make a
  /// valid beta code look invalid.
  bool get isSignedIn => isConfigured && _client.auth.currentSession != null;

  String? get currentUserEmail => _client.auth.currentUser?.email;

  /// True only for accounts that actually have a password — i.e. they have
  /// an 'email' identity, from signing up directly rather than exclusively
  /// through Google/Facebook/Apple. An OAuth-only account has no password to
  /// change, so the Account screen's "Change password" row should not show
  /// for it (Caelan, 2026-08-20).
  bool get currentUserHasPassword =>
      _client.auth.currentUser?.identities?.any((i) => i.provider == 'email') ??
      false;

  /// Fires on sign-in, sign-out, and token refresh — lets the UI show
  /// current auth state live instead of only checking it once at build time.
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<void> signOut() => _client.auth.signOut();

  /// Redeems a referral code for the *signed-in account* via the
  /// security-definer redeem_beta_code() RPC
  /// (0015_beta_code_account_binding.sql) — requires a session, since the
  /// gate now signs someone in before ever asking for a code (Caelan,
  /// 2026-08-21: codes need to travel with the person, not whichever
  /// device happened to redeem them first — see that migration's header
  /// for the incident that prompted this). Re-entering a code already
  /// redeemed by this same account is idempotent ('ok').
  Future<BetaCodeResult> redeemBetaCode(String code) async {
    if (!isConfigured || !isSignedIn) return BetaCodeResult.error;
    try {
      final result =
          await _client.rpc('redeem_beta_code', params: {'p_code': code});
      return switch (result as String?) {
        'ok' => BetaCodeResult.ok,
        'expired' => BetaCodeResult.expired,
        'already_redeemed' => BetaCodeResult.alreadyRedeemed,
        _ => BetaCodeResult.invalid,
      };
    } catch (_) {
      return BetaCodeResult.error;
    }
  }

  /// Whether the signed-in account already has a redeemed beta code —
  /// checked right after sign-in to decide whether to show the code-entry
  /// screen at all. False (not thrown) for a signed-out caller or any
  /// error, since the gate should fail toward asking for a code rather
  /// than silently letting someone through.
  Future<bool> hasBetaAccess() async {
    if (!isConfigured || !isSignedIn) return false;
    try {
      final result = await _client.rpc('has_beta_access');
      return result == true;
    } catch (_) {
      return false;
    }
  }

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
        .select(
            'place_id, decibel_value, platform, recorded_at, restaurants(name)')
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

    return (rows as List)
        .map((row) => _restaurantFromRow(row as Map<String, dynamic>))
        .toList();
  }

  /// Used to load `/restaurant/:placeId` directly (a URL open or browser
  /// refresh with no in-memory Restaurant already available) — see
  /// router.dart's `_RestaurantByIdLoader`.
  Future<Restaurant> fetchRestaurantByPlaceId(String placeId) async {
    if (!isConfigured) throw SupabaseNotConfigured();

    final row = await _client
        .from('restaurants')
        .select()
        .eq('place_id', placeId)
        .single();
    return _restaurantFromRow(row);
  }

  /// Nearest restaurant to (lat, lng) within [maxDistanceMeters], or null if
  /// none qualify — backs the Search Assistant screen's "Are you at X?" GPS
  /// guess. Server-side (find_nearest_restaurant, 0014_find_nearest_restaurant.sql)
  /// rather than fetching every restaurant and computing distance in Dart —
  /// that was the original 2026-08-18 approach, fine at the table's size
  /// then, wasteful bandwidth at today's 5,000+ rows.
  Future<NearbyRestaurant?> findNearestRestaurant(
    double lat,
    double lng, {
    double maxDistanceMeters = 100,
  }) async {
    if (!isConfigured) return null;
    final rows = await _client.rpc('find_nearest_restaurant', params: {
      'user_lat': lat,
      'user_lng': lng,
      'max_distance_meters': maxDistanceMeters,
    });
    final list = rows as List;
    if (list.isEmpty) return null;
    final row = list.first as Map<String, dynamic>;
    return NearbyRestaurant(
      placeId: row['place_id'] as String,
      name: row['name'] as String,
      distanceMeters: (row['distance_meters'] as num).toDouble(),
    );
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
  /// table (yet). The function itself requires a signed-in caller and
  /// enforces the per-account token budget — this only surfaces what it
  /// says, it doesn't duplicate that logic.
  Future<String> askSearchAssistant(
    String message,
    List<Map<String, String>> history, {
    double? latitude,
    double? longitude,
    double? accuracyMeters,
  }) async {
    if (!isConfigured) throw SupabaseNotConfigured();

    final body = <String, dynamic>{'message': message, 'history': history};
    if (latitude != null && longitude != null) {
      // Raw coordinates travel only to the authenticated Search Assistant
      // backend, which stores the account's latest fix and uses it to refresh
      // nearby venue coverage. They never go into the chat history or prompt.
      body['location'] = {
        'latitude': latitude,
        'longitude': longitude,
        if (accuracyMeters != null) 'accuracyMeters': accuracyMeters,
      };
    }

    final response = await _client.functions.invoke(
      'search-assistant',
      body: body,
    );

    if (response.status == 429) {
      final data = response.data as Map<String, dynamic>;
      throw SearchAssistantRateLimited(
          DateTime.parse(data['resetAt'] as String));
    }
    if (response.status != 200) {
      throw Exception('Search Assistant request failed (${response.status})');
    }
    final data = response.data as Map<String, dynamic>;
    return data['reply'] as String? ?? '';
  }

  /// Requests more coverage for an explicitly named area from the guarded
  /// on-demand-topup Edge Function. It enforces beta access, shared and
  /// per-account daily Google Places allowances, and a 24-hour area cooldown
  /// server-side; the app must never attempt to duplicate or bypass them.
  Future<VenueCoverageRefresh> refreshVenueCoverage(String areaQuery) async {
    if (!isConfigured) throw SupabaseNotConfigured();
    final response = await _client.functions.invoke(
      'ondemand-topup',
      body: {'areaQuery': areaQuery},
    );
    if (response.status < 200 || response.status >= 300) {
      throw Exception('Venue coverage refresh failed (${response.status})');
    }
    final data = response.data as Map<String, dynamic>;
    return VenueCoverageRefresh.fromJson(data);
  }

  /// Requests a Google Nearby Search for the 1 km circle. The server records a
  /// completed coordinate check and blocks another one within 250 m for seven
  /// days, with an atomic in-flight reservation to prevent concurrent duplicate
  /// calls; those rules are intentionally not reproduced in the client.
  Future<VenueCoverageRefresh> refreshVenueCoverageNear(
    double latitude,
    double longitude,
  ) async {
    if (!isConfigured) throw SupabaseNotConfigured();
    final response = await _client.functions.invoke(
      'ondemand-topup',
      body: {
        'location': {
          'latitude': latitude,
          'longitude': longitude,
        },
        'coverageMode': 'nearby',
      },
    );
    if (response.status < 200 || response.status >= 300) {
      throw Exception('Nearby venue coverage refresh failed (${response.status})');
    }
    final data = response.data as Map<String, dynamic>;
    return VenueCoverageRefresh.fromJson(data);
  }

  /// The signed-in user's current Search Assistant usage, or null if
  /// they haven't used it yet this window (equivalent to 0 tokens used).
  /// Scoped by RLS (search_assistant_usage's own-row SELECT policy from
  /// 0007_search_assistant_rate_limit.sql) — no explicit user_id filter
  /// needed. Lets the screen show current status on load without spending
  /// any tokens or going through the assistant itself.
  Future<SearchAssistantUsage?> fetchSearchAssistantUsage() async {
    if (!isConfigured || !isSignedIn) return null;
    final rows = await _client
        .from('search_assistant_usage')
        .select('window_start, tokens_used')
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    final row = list.first as Map<String, dynamic>;
    return SearchAssistantUsage(
      windowStart: DateTime.parse(row['window_start'] as String),
      tokensUsed: row['tokens_used'] as int,
    );
  }

  Future<void> submitMicReading(MicReading reading) async {
    if (!isConfigured) throw SupabaseNotConfigured();

    await _client.from('mic_readings').insert({
      'place_id': reading.placeId,
      'decibel_value': reading.decibelValue,
      'platform': reading.platform,
      'recorded_at': reading.recordedAt.toIso8601String(),
      'capture_duration_ms': reading.captureDuration.inMilliseconds,
    });
    await _recomputeScore(reading.placeId);
  }

  /// Calls the recompute-restaurant-score Edge Function so a submitted vote
  /// or reading actually shows up in quietness_score/confidence, instead of
  /// only ever being picked up by the next full data-pipeline run (which
  /// Caelan triggers manually and which re-fetches every restaurant from
  /// Google Places — real API cost, so it can't run on every submission).
  /// Best-effort: the vote/reading write this follows already succeeded, so
  /// a recompute failure here isn't surfaced to the user — the next full
  /// pipeline run would still pick it up eventually.
  Future<void> _recomputeScore(String placeId) async {
    try {
      await _client.functions
          .invoke('recompute-restaurant-score', body: {'placeId': placeId});
    } catch (_) {
      // Non-fatal — see doc comment above.
    }
  }

  /// The signed-in user's most recent mic calibration, or null if they've
  /// never done one — see 0010_mic_calibrations.sql and
  /// mic_calibration_screen.dart. Used to decide whether one is due
  /// (never done, or the last one was more than ~3 months ago).
  Future<DateTime?> fetchLatestCalibrationAt() async {
    if (!isConfigured || !isSignedIn) return null;
    final rows = await _client
        .from('mic_calibrations')
        .select('recorded_at')
        .order('recorded_at', ascending: false)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return DateTime.parse(
        (list.first as Map<String, dynamic>)['recorded_at'] as String);
  }

  /// user_id is filled server-side (defaults to auth.uid()), same pattern
  /// as favorites/loudness_votes — a client can't submit under someone
  /// else's identity even by mistake.
  Future<void> submitMicCalibration(
      double decibelValue, String platform) async {
    if (!isConfigured) throw SupabaseNotConfigured();
    await _client.from('mic_calibrations').insert({
      'decibel_value': decibelValue,
      'platform': platform,
    });
  }

  /// A lightweight "Quiet / Normal / Loud" alternative to a mic reading —
  /// same account gate (see 0008_loudness_votes.sql), user_id filled
  /// server-side same as favorites. [vote] must be 'quiet', 'normal', or
  /// 'loud' — the table's own CHECK constraint is the real enforcement,
  /// this is just what the UI is expected to send.
  Future<void> submitLoudnessVote(String placeId, String vote) async {
    if (!isConfigured) throw SupabaseNotConfigured();
    await _client
        .from('loudness_votes')
        .insert({'place_id': placeId, 'vote': vote});
    await _recomputeScore(placeId);
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
      'currentLoudnessSubscore': row['current_loudness_subscore'],
      'currentLoudnessObservedAt': row['current_loudness_observed_at'],
      'confidence': row['confidence'],
      'signalCount': [
        row['review_subscore'],
        row['popular_subscore'],
        row['mic_subscore'],
      ].where((v) => v != null).length,
    });
  }
}
