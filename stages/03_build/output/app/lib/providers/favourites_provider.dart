import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import '../services/supabase_service.dart';

/// The signed-in user's favourited place ids, shared across screens.
///
/// This is the first slice of the incremental Riverpod adoption described in
/// execution-plan-2026-08-23.md, and it exists to fix a real bug rather than to
/// tidy up: `FavouritesScreen` loaded once in `initState` and never again, while
/// `RestaurantDetailScreen` kept its own separate `_isFavorite` flag. Unstarring
/// a venue from the detail screen and going back left it still listed, because
/// `go_router`'s pop does not re-run `initState`. Two screens owning two copies
/// of the same fact is the bug; one shared copy is the fix.
///
/// It also removes a redundant round trip: the detail screen used to fetch the
/// whole favourites set on open purely to answer "is this one favourited?".
class FavouriteIds extends AsyncNotifier<Set<String>> {
  SupabaseService get _service => SupabaseService();

  @override
  Future<Set<String>> build() async {
    if (!SupabaseService.isConfigured) return <String>{};

    // Caching the set introduces a hazard that per-screen fetching did not
    // have: without this, one account's favourites would survive a sign-out and
    // be shown to whoever signs in next. Re-reading on both events also covers
    // sign-in, where the set starts empty and must be filled.
    final subscription = _service.authStateChanges.listen((auth) {
      if (auth.event == AuthChangeEvent.signedIn ||
          auth.event == AuthChangeEvent.signedOut) {
        ref.invalidateSelf();
      }
    });
    ref.onDispose(subscription.cancel);

    if (!_service.isSignedIn) return <String>{};
    return _service.fetchFavoritePlaceIds();
  }

  /// Adds or removes a favourite, updating every watcher immediately.
  ///
  /// Optimistic: the UI must not wait on a round trip for a star tap. On
  /// failure the previous set is restored and the error rethrown, so the caller
  /// can tell the user rather than leaving a star that lies about what the
  /// server holds.
  Future<void> toggle(String placeId) async {
    final current = state.valueOrNull ?? <String>{};
    final wasFavourite = current.contains(placeId);
    final updated = Set<String>.from(current);
    wasFavourite ? updated.remove(placeId) : updated.add(placeId);

    state = AsyncData(updated);

    try {
      if (wasFavourite) {
        await _service.removeFavorite(placeId);
      } else {
        await _service.addFavorite(placeId);
      }
    } catch (_) {
      state = AsyncData(current);
      rethrow;
    }
  }

  /// Drops the cached set — used on sign-out so the next account does not see
  /// the previous one's favourites.
  void clear() => state = const AsyncData(<String>{});

  /// Re-reads from the server. For pull-to-refresh and after sign-in.
  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

final favouriteIdsProvider =
    AsyncNotifierProvider<FavouriteIds, Set<String>>(FavouriteIds.new);

/// Whether one specific venue is favourited.
///
/// Kept separate so a detail screen rebuilds only when *its* venue changes,
/// rather than on every change to the whole set.
final isFavouriteProvider = Provider.family<bool, String>((ref, placeId) {
  return ref.watch(favouriteIdsProvider).valueOrNull?.contains(placeId) ?? false;
});
