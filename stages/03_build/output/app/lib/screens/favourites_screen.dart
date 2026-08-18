import 'package:flutter/material.dart';

import '../models/restaurant.dart';
import '../services/restaurant_repository.dart';
import '../services/supabase_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/restaurant_tile.dart';

class FavouritesScreen extends StatefulWidget {
  const FavouritesScreen({super.key});

  @override
  State<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends State<FavouritesScreen> {
  final _repository = RestaurantRepository();
  final _supabaseService = SupabaseService();

  bool _loading = true;
  List<Restaurant> _favorites = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_supabaseService.isSignedIn) {
      setState(() => _loading = false);
      return;
    }
    // No dedicated "fetch my favorited restaurants" query — loads
    // everything (same as the List screen) and filters by the favorited
    // id set client-side. Fine at today's single-city scale.
    final ids = await _supabaseService.fetchFavoritePlaceIds();
    final all = await _repository.loadAll();
    if (!mounted) return;
    setState(() {
      _favorites = all.where((r) => ids.contains(r.placeId)).toList();
      _loading = false;
    });
  }

  Future<void> _removeFavorite(Restaurant restaurant) async {
    setState(() => _favorites.removeWhere((r) => r.placeId == restaurant.placeId));
    try {
      await _supabaseService.removeFavorite(restaurant.placeId);
    } catch (_) {
      if (!mounted) return;
      setState(() => _favorites.add(restaurant));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove favorite — try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favourites')),
      drawer: const AppDrawer(currentRoute: AppRoute.favourites),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_supabaseService.isSignedIn) {
      return const _EmptyFavourites(
        icon: Icons.login,
        title: 'Sign in to save favourites',
        message: 'Favouriting a restaurant needs an account, same as submitting a noise reading.',
      );
    }
    if (_favorites.isEmpty) {
      return const _EmptyFavourites(
        icon: Icons.star_border_rounded,
        title: 'No favourites yet',
        message: 'Tap the star on any restaurant to save it here.',
      );
    }
    return ListView.separated(
      itemCount: _favorites.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final restaurant = _favorites[index];
        return RestaurantTile(
          restaurant: restaurant,
          isFavorite: true,
          onToggleFavorite: () => _removeFavorite(restaurant),
        );
      },
    );
  }
}

class _EmptyFavourites extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyFavourites({required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).disabledColor),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
