import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/restaurant.dart';
import '../services/restaurant_repository.dart';
import '../services/supabase_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/filter_drawer.dart';
import '../widgets/noise_level_bar.dart';
import '../widgets/restaurant_tile.dart';
import '../widgets/voice_search_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repository = RestaurantRepository();
  final _supabaseService = SupabaseService();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  List<Restaurant> _all = [];
  String? _suburbFilter;
  String? _cuisineFilter;
  int? _loudnessFilterIndex; // index into NoiseLevelBar.categories; null = any
  double? _minRatingFilter;
  SortOption _sortBy = SortOption.quietestFirst;
  String _searchQuery = '';
  bool _loading = true;
  Object? _error;

  StreamSubscription? _authSubscription;
  String? _signedInEmail;
  Set<String> _favoritePlaceIds = {};

  @override
  void initState() {
    super.initState();
    _load();
    // Reflects sign-in state live in the app bar — the previous UI never
    // showed this anywhere, which is easy to mistake for "sessions don't
    // persist" even when they actually do (supabase_flutter persists by
    // default; nothing in this app overrides that).
    if (SupabaseService.isConfigured) {
      _signedInEmail = _supabaseService.currentUserEmail;
      _loadFavorites();
      _authSubscription = _supabaseService.authStateChanges.listen((_) {
        if (!mounted) return;
        setState(() => _signedInEmail = _supabaseService.currentUserEmail);
        _loadFavorites(); // re-fetch on sign-in/out — favorites are empty while signed out
      });
    }
  }

  Future<void> _loadFavorites() async {
    final ids = await _supabaseService.fetchFavoritePlaceIds();
    if (mounted) setState(() => _favoritePlaceIds = ids);
  }

  Future<void> _toggleFavorite(Restaurant restaurant) async {
    if (!_supabaseService.isSignedIn) {
      // Same point-of-need prompt as "Take a reading here" — browsing and
      // favoriting share the account gate, but only favoriting needs it.
      final signedIn = await context.push<bool>('/sign-in');
      if (signedIn != true || !mounted) return;
    }

    final placeId = restaurant.placeId;
    final wasFavorite = _favoritePlaceIds.contains(placeId);
    setState(() {
      // Optimistic — flips immediately, corrected below only if the write fails.
      if (wasFavorite) {
        _favoritePlaceIds.remove(placeId);
      } else {
        _favoritePlaceIds.add(placeId);
      }
    });
    try {
      if (wasFavorite) {
        await _supabaseService.removeFavorite(placeId);
      } else {
        await _supabaseService.addFavorite(placeId);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (wasFavorite) {
          _favoritePlaceIds.add(placeId);
        } else {
          _favoritePlaceIds.remove(placeId);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update favorite — try again.')),
      );
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _handleAccountTap() async {
    await context.push(_signedInEmail != null ? '/account' : '/sign-in');
  }

  Future<void> _load() async {
    try {
      final restaurants = await _repository.loadAll();
      setState(() {
        _all = restaurants;
        _loading = false;
      });
    } catch (error) {
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  List<Restaurant> get _filtered {
    final query = _searchQuery.trim().toLowerCase();
    return _all.where((r) {
      if (_suburbFilter != null && r.suburb != _suburbFilter) return false;
      if (_cuisineFilter != null && r.cuisine != _cuisineFilter) return false;
      if (_loudnessFilterIndex != null &&
          NoiseLevelBar.categoryIndexFor(r.quietnessScore) != _loudnessFilterIndex) {
        return false;
      }
      if (_minRatingFilter != null && (r.googleRating == null || r.googleRating! < _minRatingFilter!)) {
        return false;
      }
      if (query.isNotEmpty) {
        final haystack = [r.name, r.cuisine, r.suburb].whereType<String>().join(' ').toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      return true;
    }).toList();
  }

  /// Starts from the repository's quietest-first ranking (already limited to
  /// restaurants with enough data to score) and re-orders it when a
  /// different Sort By option is selected — Loudest First is just that same
  /// list reversed, Rating sorts push restaurants with no rating yet to the
  /// end regardless of direction rather than clumping them at the top.
  List<Restaurant> get _sortedRanked {
    final quietestFirst = _repository.rankedByQuietness(_filtered);
    switch (_sortBy) {
      case SortOption.quietestFirst:
        return quietestFirst;
      case SortOption.loudestFirst:
        return quietestFirst.reversed.toList();
      case SortOption.ratingHighest:
        return [...quietestFirst]..sort((a, b) => _compareRating(a, b, descending: true));
      case SortOption.ratingLowest:
        return [...quietestFirst]..sort((a, b) => _compareRating(a, b, descending: false));
    }
  }

  int _compareRating(Restaurant a, Restaurant b, {required bool descending}) {
    final ar = a.googleRating;
    final br = b.googleRating;
    if (ar == null && br == null) return 0;
    if (ar == null) return 1; // no rating yet sorts last either way
    if (br == null) return -1;
    return descending ? br.compareTo(ar) : ar.compareTo(br);
  }

  void _clearFilters() {
    setState(() {
      _suburbFilter = null;
      _cuisineFilter = null;
      _loudnessFilterIndex = null;
      _minRatingFilter = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(body: Center(child: Text('Could not load restaurants: $_error')));
    }

    final ranked = _sortedRanked;
    final needsData = _repository.withoutEnoughData(_filtered);
    final suburbs = _all.map((r) => r.suburb).whereType<String>().toSet().toList()..sort();
    final cuisines = _all.map((r) => r.cuisine).whereType<String>().toSet().toList()..sort();
    final hasActiveFilters =
        _suburbFilter != null || _cuisineFilter != null || _loudnessFilterIndex != null || _minRatingFilter != null;

    return Scaffold(
      key: _scaffoldKey,
      drawer: const AppDrawer(currentRoute: AppRoute.list),
      endDrawer: FilterDrawer(
        suburbs: suburbs,
        cuisines: cuisines,
        selectedSuburb: _suburbFilter,
        selectedCuisine: _cuisineFilter,
        selectedLoudnessIndex: _loudnessFilterIndex,
        selectedMinRating: _minRatingFilter,
        sortBy: _sortBy,
        onSuburbChanged: (v) => setState(() => _suburbFilter = v),
        onCuisineChanged: (v) => setState(() => _cuisineFilter = v),
        onLoudnessChanged: (v) => setState(() => _loudnessFilterIndex = v),
        onRatingChanged: (v) => setState(() => _minRatingFilter = v),
        onSortByChanged: (v) => setState(() => _sortBy = v),
        onClear: _clearFilters,
      ),
      appBar: AppBar(
        title: const Text('List View'),
        actions: [
          if (SupabaseService.isConfigured)
            _signedInEmail != null
                ? IconButton(
                    tooltip: 'Signed in as $_signedInEmail',
                    icon: const Icon(Icons.account_circle),
                    onPressed: _handleAccountTap,
                  )
                : Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: const Icon(Icons.login, size: 18),
                      label: const Text('Sign In'),
                      onPressed: _handleAccountTap,
                    ),
                  ),
        ],
      ),
      body: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: VoiceSearchBar(onQueryChanged: (q) => setState(() => _searchQuery = q)),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: IconButton(
                  tooltip: 'Filters',
                  icon: Badge(
                    isLabelVisible: hasActiveFilters,
                    smallSize: 8,
                    child: const Icon(Icons.filter_list),
                  ),
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                ),
              ),
            ],
          ),
          Expanded(
            child: _all.isEmpty
                ? const _EmptyState()
                : ListView(
                    children: [
                      for (final restaurant in ranked)
                        RestaurantTile(
                          restaurant: restaurant,
                          isFavorite: _favoritePlaceIds.contains(restaurant.placeId),
                          onToggleFavorite: () => _toggleFavorite(restaurant),
                        ),
                      if (needsData.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Not enough data yet',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        for (final restaurant in needsData)
                          RestaurantTile(
                          restaurant: restaurant,
                          isFavorite: _favoritePlaceIds.contains(restaurant.placeId),
                          onToggleFavorite: () => _toggleFavorite(restaurant),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restaurant_outlined, size: 48, color: Theme.of(context).disabledColor),
            const SizedBox(height: 12),
            const Text(
              'No restaurants yet',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              'Check back soon — we\'re still gathering data.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

