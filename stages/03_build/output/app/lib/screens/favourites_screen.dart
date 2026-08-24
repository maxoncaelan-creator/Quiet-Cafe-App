import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/restaurant.dart';
import '../providers/favourites_provider.dart';
import '../services/restaurant_repository.dart';
import '../services/supabase_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/restaurant_tile.dart';
import '../widgets/skeleton_loader.dart';

class FavouritesScreen extends ConsumerStatefulWidget {
  const FavouritesScreen({super.key});

  @override
  ConsumerState<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends ConsumerState<FavouritesScreen> {
  final _repository = RestaurantRepository();
  final _supabaseService = SupabaseService();

  bool _loading = true;
  List<Restaurant> _allRestaurants = [];

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
    // everything (same as the List screen) and filters by the favourited
    // id set at build time. Fine at today's single-city scale.
    //
    // The id set deliberately is NOT stored here any more. It lives in
    // favouriteIdsProvider, so unfavouriting from the detail screen updates
    // this list immediately instead of leaving a stale row until the screen
    // is rebuilt from scratch.
    final all = await _repository.loadAll();
    if (!mounted) return;
    setState(() {
      _allRestaurants = all;
      _loading = false;
    });
  }

  Future<void> _removeFavorite(Restaurant restaurant) async {
    // The provider updates optimistically and restores itself on failure, so
    // this no longer keeps its own copy to revert.
    try {
      await ref.read(favouriteIdsProvider.notifier).toggle(restaurant.placeId);
    } catch (_) {
      if (!mounted) return;
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
      return const PageSkeleton(itemCount: 3);
    }
    if (!_supabaseService.isSignedIn) {
      return const _EmptyFavourites(
        icon: Icons.login,
        title: 'Sign in to save favourites',
        message:
            'Favouriting a restaurant needs an account, same as submitting a noise reading.',
      );
    }
    // Derived at build time from the shared set, so a change made anywhere —
    // including the detail screen — is reflected here without a reload.
    final favouriteIds = ref.watch(favouriteIdsProvider).valueOrNull ?? const <String>{};
    final favourites = _allRestaurants
        .where((r) => favouriteIds.contains(r.placeId))
        .toList();

    if (favourites.isEmpty) {
      return const _EmptyFavourites(
        icon: Icons.star_border_rounded,
        title: 'No favourites yet',
        message: 'Tap the star on any restaurant to save it here.',
      );
    }
    return ListView.separated(
      itemCount: favourites.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final restaurant = favourites[index];
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

  const _EmptyFavourites(
      {required this.icon, required this.title, required this.message});

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
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
