import 'dart:async';

import 'package:flutter/material.dart';

import '../models/restaurant.dart';
import '../services/restaurant_repository.dart';
import '../services/supabase_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/restaurant_tile.dart';
import '../widgets/voice_search_bar.dart';
import 'account_screen.dart';
import 'auth_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repository = RestaurantRepository();
  final _supabaseService = SupabaseService();

  List<Restaurant> _all = [];
  String? _suburbFilter;
  String? _cuisineFilter;
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
      final signedIn = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
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
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _signedInEmail != null ? const AccountScreen() : const AuthScreen(),
    ));
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
      if (query.isNotEmpty) {
        final haystack = [r.name, r.cuisine, r.suburb].whereType<String>().join(' ').toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(body: Center(child: Text('Could not load restaurants: $_error')));
    }

    final ranked = _repository.rankedByQuietness(_filtered);
    final needsData = _repository.withoutEnoughData(_filtered);
    final suburbs = _all.map((r) => r.suburb).whereType<String>().toSet().toList()..sort();
    final cuisines = _all.map((r) => r.cuisine).whereType<String>().toSet().toList()..sort();

    return Scaffold(
      drawer: const AppDrawer(currentRoute: AppRoute.list),
      appBar: AppBar(
        title: const Text('Quietest in Sydney'),
        actions: [
          if (SupabaseService.isConfigured)
            IconButton(
              tooltip: _signedInEmail != null ? 'Signed in as $_signedInEmail' : 'Sign in',
              icon: Icon(_signedInEmail != null ? Icons.account_circle : Icons.account_circle_outlined),
              onPressed: _handleAccountTap,
            ),
        ],
      ),
      body: Column(
        children: [
          VoiceSearchBar(onQueryChanged: (q) => setState(() => _searchQuery = q)),
          _FilterBar(
            suburbs: suburbs,
            cuisines: cuisines,
            selectedSuburb: _suburbFilter,
            selectedCuisine: _cuisineFilter,
            onSuburbChanged: (v) => setState(() => _suburbFilter = v),
            onCuisineChanged: (v) => setState(() => _cuisineFilter = v),
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

class _FilterBar extends StatelessWidget {
  final List<String> suburbs;
  final List<String> cuisines;
  final String? selectedSuburb;
  final String? selectedCuisine;
  final ValueChanged<String?> onSuburbChanged;
  final ValueChanged<String?> onCuisineChanged;

  const _FilterBar({
    required this.suburbs,
    required this.cuisines,
    required this.selectedSuburb,
    required this.selectedCuisine,
    required this.onSuburbChanged,
    required this.onCuisineChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: selectedSuburb,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Suburb'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All suburbs')),
                for (final s in suburbs)
                  DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: onSuburbChanged,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: selectedCuisine,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Cuisine'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All cuisines')),
                for (final c in cuisines)
                  DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: onCuisineChanged,
            ),
          ),
        ],
      ),
    );
  }
}
