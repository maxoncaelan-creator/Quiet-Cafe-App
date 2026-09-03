import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/restaurant.dart';
import '../providers/favourites_provider.dart';
import '../providers/restaurant_list_provider.dart';
import '../services/supabase_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/restaurant_tile.dart';
import '../widgets/skeleton_loader.dart';

class FavouritesScreen extends ConsumerWidget {
  const FavouritesScreen({super.key});

  Future<void> _removeFavorite(
      BuildContext context, WidgetRef ref, Restaurant restaurant) async {
    // The provider updates optimistically and restores itself on failure, so
    // this no longer keeps its own copy to revert.
    try {
      await ref.read(favouriteIdsProvider.notifier).toggle(restaurant.placeId);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove favorite — try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favourites')),
      drawer: const AppDrawer(currentRoute: AppRoute.favourites),
      body: _buildBody(context, ref),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref) {
    // Checked before watching anything below — a signed-out visitor has no
    // favourites by definition, so this must not force the (possibly
    // uncached) full restaurant list to fetch just to prove that. Same
    // early-out the old per-screen _load() had; only how the rest of this
    // screen gets its data has changed.
    if (!SupabaseService().isSignedIn) {
      return const _EmptyFavourites(
        icon: Icons.login,
        title: 'Sign in to save favourites',
        message:
            'Favouriting a restaurant needs an account, same as submitting a noise reading.',
      );
    }

    // Both providers are shared with HomeScreen/RestaurantDetailScreen, so
    // this screen no longer runs its own fetch for either — it reads
    // whatever is already cached (or triggers the first load, if this is the
    // first screen visited) and reflects a change from any of those screens
    // immediately.
    final restaurantsAsync = ref.watch(restaurantListProvider);
    final favouriteIds =
        ref.watch(favouriteIdsProvider).valueOrNull ?? const <String>{};

    return restaurantsAsync.when(
      loading: () => const PageSkeleton(itemCount: 3),
      error: (error, _) =>
          Center(child: Text('Could not load favourites: $error')),
      data: (all) {
        final favourites =
            all.where((r) => favouriteIds.contains(r.placeId)).toList();

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
              onToggleFavorite: () =>
                  _removeFavorite(context, ref, restaurant),
            );
          },
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
