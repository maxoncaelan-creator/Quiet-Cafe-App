import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/restaurant.dart';
import '../services/restaurant_repository.dart';
import 'supabase_service_provider.dart';

/// [RestaurantRepository], injected rather than constructed in place —
/// mirrors supabase_service_provider.dart's seam and exists for the same
/// reason: it is what lets [RestaurantList] below be tested against a fake
/// [SupabaseService] instead of only on a device.
final restaurantRepositoryProvider = Provider<RestaurantRepository>((ref) {
  return RestaurantRepository(ref.watch(supabaseServiceProvider));
});

/// The full ranked restaurant list, shared across screens.
///
/// This is step 3d of the incremental Riverpod migration
/// (execution-plan-2026-08-23.md, "Step 3b remaining"). Before this,
/// `HomeScreen` and `FavouritesScreen` each held their own
/// `RestaurantRepository` and fetched the whole list independently in their
/// own `initState`, so switching between List View and Favourites re-ran the
/// same query twice for data that hadn't changed, and reopening either
/// screen (e.g. via the drawer, which unmounts and remounts) fetched it
/// again from scratch. One shared cache removes both the duplicate round
/// trip and the pointless refetch on every mount — the exact shape of
/// waste, if not the exact bug, that `favouriteIdsProvider` fixed for
/// favourites in step 3a.
///
/// **This list is NOT invalidated on sign-in/sign-out**, unlike
/// `favouriteIdsProvider`. That invalidation exists there because favourites
/// are per-account data — caching them risked showing one account's set to
/// the next signed-in user. The restaurant list is public, unscoped data
/// (`fetchRankedRestaurants` has no `isSignedIn` check); every account and
/// every signed-out browser sees the same rows, so there is no
/// cross-account leak to guard against and adding auth-triggered
/// invalidation here would only cause pointless refetches.
///
/// **Cache invalidation is explicit, not automatic.** A cached list that
/// never refreshes is a different bug from the one this fixes, so this is
/// not a fetch-once-forever cache: [reload] exists specifically for the
/// moments the data actually changes server-side. `HomeScreen` calls it
/// after `refreshVenueCoverage`/`refreshVenueCoverageNear` report they may
/// have added rows — the same two call sites that used to call the screen's
/// own `_load()`. Nothing else changes the underlying rows from this app, so
/// no other trigger is needed; a pull-to-refresh or a timer would be solving
/// a problem that does not exist yet.
class RestaurantList extends AsyncNotifier<List<Restaurant>> {
  RestaurantRepository get _repository => ref.read(restaurantRepositoryProvider);

  @override
  Future<List<Restaurant>> build() => _repository.loadAll();

  /// Re-fetches from the backend (or the bundled asset, on a standalone
  /// build) and replaces the cached list. Called after an operation that may
  /// have actually added venues — see the class doc for why this is opt-in
  /// rather than automatic.
  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repository.loadAll);
  }
}

final restaurantListProvider =
    AsyncNotifierProvider<RestaurantList, List<Restaurant>>(RestaurantList.new);
