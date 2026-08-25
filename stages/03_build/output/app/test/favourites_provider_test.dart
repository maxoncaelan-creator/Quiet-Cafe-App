import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiet_restaurant_finder/providers/favourites_provider.dart';
import 'package:quiet_restaurant_finder/providers/supabase_service_provider.dart';
import 'package:quiet_restaurant_finder/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState;

/// Stands in for the real backend. Only the members `FavouriteIds` touches are
/// overridden; anything else would throw, which is the point — a test that
/// silently reached the network would not be a unit test.
class _FakeSupabaseService extends SupabaseService {
  _FakeSupabaseService({
    Set<String> initial = const <String>{},
    this.signedIn = true,
  }) : stored = Set<String>.from(initial);

  Set<String> stored;
  bool signedIn;

  /// Forces the next write to fail, for the revert path.
  bool failNextWrite = false;

  int fetchCount = 0;
  final List<String> added = [];
  final List<String> removed = [];

  final _authController = StreamController<AuthState>.broadcast();

  @override
  bool get isSignedIn => signedIn;

  @override
  Stream<AuthState> get authStateChanges => _authController.stream;

  @override
  Future<Set<String>> fetchFavoritePlaceIds() async {
    fetchCount++;
    return Set<String>.from(stored);
  }

  @override
  Future<void> addFavorite(String placeId) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw Exception('network');
    }
    added.add(placeId);
    stored.add(placeId);
  }

  @override
  Future<void> removeFavorite(String placeId) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw Exception('network');
    }
    removed.add(placeId);
    stored.remove(placeId);
  }

  void emit(AuthChangeEvent event) =>
      _authController.add(AuthState(event, null));

  void disposeController() => _authController.close();
}

ProviderContainer _containerWith(_FakeSupabaseService fake) {
  final container = ProviderContainer(
    overrides: [supabaseServiceProvider.overrideWithValue(fake)],
  );
  addTearDown(container.dispose);
  addTearDown(fake.disposeController);
  return container;
}

void main() {
  group('favouriteIdsProvider', () {
    test('loads the signed-in account\'s favourites once', () async {
      final fake = _FakeSupabaseService(initial: {'a', 'b'});
      final container = _containerWith(fake);

      final ids = await container.read(favouriteIdsProvider.future);

      expect(ids, {'a', 'b'});
      expect(fake.fetchCount, 1);
    });

    test('returns an empty set when signed out, without hitting the backend',
        () async {
      final fake = _FakeSupabaseService(initial: {'a'}, signedIn: false);
      final container = _containerWith(fake);

      expect(await container.read(favouriteIdsProvider.future), isEmpty);
      expect(fake.fetchCount, 0);
    });

    // The bug step 3a existed to fix: two screens each held their own copy of
    // "is this favourited", so unstarring on one left the other stale. One
    // shared set means a single toggle is visible everywhere at once.
    test('a toggle is visible to every reader immediately', () async {
      final fake = _FakeSupabaseService(initial: {'a'});
      final container = _containerWith(fake);
      await container.read(favouriteIdsProvider.future);

      expect(container.read(isFavouriteProvider('b')), isFalse);

      await container.read(favouriteIdsProvider.notifier).toggle('b');

      // Both the set and the per-venue view reflect it with no refetch.
      expect(container.read(favouriteIdsProvider).valueOrNull, {'a', 'b'});
      expect(container.read(isFavouriteProvider('b')), isTrue);
      expect(fake.fetchCount, 1);
    });

    test('toggling an existing favourite removes it', () async {
      final fake = _FakeSupabaseService(initial: {'a', 'b'});
      final container = _containerWith(fake);
      await container.read(favouriteIdsProvider.future);

      await container.read(favouriteIdsProvider.notifier).toggle('a');

      expect(container.read(favouriteIdsProvider).valueOrNull, {'b'});
      expect(container.read(isFavouriteProvider('a')), isFalse);
      expect(fake.removed, ['a']);
    });

    test('restores the previous set and rethrows when the write fails',
        () async {
      // The star must not keep claiming something the server rejected.
      final fake = _FakeSupabaseService(initial: {'a'})..failNextWrite = true;
      final container = _containerWith(fake);
      await container.read(favouriteIdsProvider.future);

      await expectLater(
        container.read(favouriteIdsProvider.notifier).toggle('b'),
        throwsA(isA<Exception>()),
      );

      expect(container.read(favouriteIdsProvider).valueOrNull, {'a'});
      expect(container.read(isFavouriteProvider('b')), isFalse);
    });

    test('clear() empties the set', () async {
      final fake = _FakeSupabaseService(initial: {'a', 'b'});
      final container = _containerWith(fake);
      await container.read(favouriteIdsProvider.future);

      container.read(favouriteIdsProvider.notifier).clear();

      expect(container.read(favouriteIdsProvider).valueOrNull, isEmpty);
    });

    // The hazard caching introduced: without self-invalidation one account's
    // favourites would survive a sign-out and be shown to whoever signed in
    // next. Per-screen fetching never risked this.
    test('drops the set on sign-out rather than showing it to the next account',
        () async {
      final fake = _FakeSupabaseService(initial: {'a', 'b'});
      final container = _containerWith(fake);
      expect(await container.read(favouriteIdsProvider.future), {'a', 'b'});

      fake.signedIn = false;
      fake.stored = <String>{};
      fake.emit(AuthChangeEvent.signedOut);
      await Future<void>.delayed(Duration.zero);

      expect(await container.read(favouriteIdsProvider.future), isEmpty);
    });

    test('re-reads on sign-in, when the set starts empty', () async {
      final fake = _FakeSupabaseService(initial: <String>{}, signedIn: false);
      final container = _containerWith(fake);
      expect(await container.read(favouriteIdsProvider.future), isEmpty);

      fake.signedIn = true;
      fake.stored = {'x'};
      fake.emit(AuthChangeEvent.signedIn);
      await Future<void>.delayed(Duration.zero);

      expect(await container.read(favouriteIdsProvider.future), {'x'});
    });

    test('reload() re-reads from the backend', () async {
      final fake = _FakeSupabaseService(initial: {'a'});
      final container = _containerWith(fake);
      await container.read(favouriteIdsProvider.future);

      fake.stored = {'a', 'c'};
      await container.read(favouriteIdsProvider.notifier).reload();

      expect(container.read(favouriteIdsProvider).valueOrNull, {'a', 'c'});
      expect(fake.fetchCount, 2);
    });
  });
}
