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
  final SupabaseService _supabase = SupabaseService();

  Future<List<Restaurant>> loadAll() async {
    if (SupabaseService.isConfigured) {
      return _supabase.fetchRankedRestaurants();
    }
    return _loadBundledSample();
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
