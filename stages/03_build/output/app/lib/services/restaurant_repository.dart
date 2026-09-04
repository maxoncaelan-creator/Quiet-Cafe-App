// Loads restaurant + score data. Reads live from Supabase's `restaurants`
// table when SUPABASE_URL/SUPABASE_ANON_KEY are configured (see
// supabase_service.dart); otherwise falls back to the bundled JSON asset
// (assets/data/restaurants.json — a copy of the pipeline's sample output),
// so the app still runs without a backend for local dev/demo purposes.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

import '../models/restaurant.dart';
import 'supabase_service.dart';

class RestaurantRepository {
  /// Injected rather than constructed here, same seam as
  /// supabase_service_provider.dart's [SupabaseService] and for the same
  /// reason: step 3a shipped a provider with no unit test at all because its
  /// notifier built its own `SupabaseService()` and nothing could stand in
  /// for it. Requiring the service explicitly means this repository can be
  /// exercised with a fake in a plain `ProviderContainer` test instead of
  /// only on a device — see restaurant_list_provider_test.dart.
  const RestaurantRepository(this._supabase);

  final SupabaseService _supabase;

  /// Tries the live backend and falls back to the bundled sample only when
  /// [SupabaseService] itself reports there is no backend to try.
  ///
  /// This deliberately does NOT check the static `SupabaseService.isConfigured`
  /// the way the old code did — that static is unfakeable in a test (same
  /// obstacle step 3b removed from favouriteIdsProvider), so a repository
  /// built around it could never have its bundled-asset branch exercised by
  /// anything but a device. [SupabaseService.fetchRankedRestaurants] already
  /// throws the typed [SupabaseNotConfigured] in exactly that case, so
  /// catching it here keeps the fallback instance-level and fake-able while
  /// leaving every other failure (a real network/query error on a configured
  /// backend) to propagate — the standalone build falls back silently, a
  /// broken live backend must not.
  Future<List<Restaurant>> loadAll() async {
    try {
      return await _supabase.fetchRankedRestaurants();
    } on SupabaseNotConfigured {
      return _loadBundledSample();
    }
  }

  Future<List<Restaurant>> _loadBundledSample() async {
    final raw = await rootBundle.loadString('assets/data/restaurants.json');
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => Restaurant.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Restaurants with enough data to rank, sorted quietest first.
  /// Restaurants with no score yet (cold start) are excluded, per
  /// ranking-spec.md's cold-start handling.
  List<Restaurant> rankedByQuietness(List<Restaurant> restaurants) {
    final ranked = restaurants.where((r) => r.hasEnoughData).toList();
    ranked.sort((a, b) => b.quietnessScore!.compareTo(a.quietnessScore!));
    return ranked;
  }

  List<Restaurant> withoutEnoughData(List<Restaurant> restaurants) {
    return restaurants.where((r) => !r.hasEnoughData).toList();
  }
}
