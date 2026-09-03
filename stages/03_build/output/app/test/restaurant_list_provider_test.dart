import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiet_restaurant_finder/models/restaurant.dart';
import 'package:quiet_restaurant_finder/providers/restaurant_list_provider.dart';
import 'package:quiet_restaurant_finder/providers/supabase_service_provider.dart';
import 'package:quiet_restaurant_finder/services/restaurant_repository.dart';
import 'package:quiet_restaurant_finder/services/supabase_service.dart';

Restaurant _restaurant(String placeId, {double? score}) {
  return Restaurant(
    placeId: placeId,
    name: placeId,
    review: const SignalScore(subscore: 80),
    popular: const SignalScore(subscore: 80),
    mic: const MicSignal(
        subscore: 80, readingCountIos: 1, readingCountAndroid: 0),
    quietnessScore: score,
    signalCount: 3,
  );
}

/// Stands in for the real backend. Only [fetchRankedRestaurants] is
/// overridden — same "anything else would throw" discipline as
/// favourites_provider_test.dart's fake, so a test that silently reached the
/// real network or the real asset bundle would not be a unit test.
class _FakeSupabaseService extends SupabaseService {
  _FakeSupabaseService({this.restaurants = const [], this.configured = true});

  List<Restaurant> restaurants;
  bool configured;
  int fetchCount = 0;

  /// Set to make the next call raise something other than
  /// [SupabaseNotConfigured] — the "real backend failure" case, which must
  /// propagate rather than being swallowed into the bundled-sample fallback.
  Object? failNextFetchWith;

  @override
  Future<List<Restaurant>> fetchRankedRestaurants() async {
    fetchCount++;
    if (failNextFetchWith != null) {
      final error = failNextFetchWith!;
      failNextFetchWith = null;
      throw error;
    }
    if (!configured) throw SupabaseNotConfigured();
    return List<Restaurant>.from(restaurants);
  }
}

ProviderContainer _containerWith(_FakeSupabaseService fake) {
  final container = ProviderContainer(
    overrides: [supabaseServiceProvider.overrideWithValue(fake)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('RestaurantRepository', () {
    test('returns the backend list when configured', () async {
      final fake = _FakeSupabaseService(restaurants: [_restaurant('a')]);
      final repository = RestaurantRepository(fake);

      final result = await repository.loadAll();

      expect(result.map((r) => r.placeId), ['a']);
      expect(fake.fetchCount, 1);
    });

    // The case execution-plan-2026-08-23.md calls out by name: the
    // standalone no-Supabase build must keep working. loadAll() must reach
    // the bundled assets/data/restaurants.json fallback purely from the
    // instance-level SupabaseNotConfigured the service throws — not from the
    // static SupabaseService.isConfigured, which a test can never make true.
    test('falls back to the bundled sample when unconfigured', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final fake = _FakeSupabaseService(configured: false);
      final repository = RestaurantRepository(fake);

      final result = await repository.loadAll();

      expect(result, isNotEmpty);
      expect(result.first.placeId, 'sample-001'); // assets/data/restaurants.json
    });

    // A real failure on a *configured* backend must not be mistaken for "no
    // backend" and silently masked by the bundled sample — that would show
    // every user stale demo data during an outage instead of an error.
    test('a configured backend failure propagates instead of falling back',
        () async {
      final fake = _FakeSupabaseService()
        ..failNextFetchWith = Exception('network down');
      final repository = RestaurantRepository(fake);

      await expectLater(repository.loadAll(), throwsA(isA<Exception>()));
    });
  });

  group('restaurantListProvider', () {
    test('loads the ranked list once and caches it', () async {
      final fake = _FakeSupabaseService(restaurants: [_restaurant('a'), _restaurant('b')]);
      final container = _containerWith(fake);

      final first = await container.read(restaurantListProvider.future);
      // A second read without an intervening reload() must not refetch —
      // this is the whole point of moving the list onto a provider instead
      // of each screen's own initState() fetch.
      final second = container.read(restaurantListProvider).valueOrNull;

      expect(first.map((r) => r.placeId), ['a', 'b']);
      expect(second?.map((r) => r.placeId), ['a', 'b']);
      expect(fake.fetchCount, 1);
    });

    // The cache-invalidation behaviour this slice deliberately added:
    // reload() is the only way the list changes after the first load, used
    // by HomeScreen after a coverage refresh that may have added venues.
    test('reload() re-fetches and replaces the cached list', () async {
      final fake = _FakeSupabaseService(restaurants: [_restaurant('a')]);
      final container = _containerWith(fake);
      await container.read(restaurantListProvider.future);

      fake.restaurants = [_restaurant('a'), _restaurant('new-venue')];
      await container.read(restaurantListProvider.notifier).reload();

      expect(
        container.read(restaurantListProvider).valueOrNull?.map((r) => r.placeId),
        ['a', 'new-venue'],
      );
      expect(fake.fetchCount, 2);
    });

    test('an error surfaces as AsyncError rather than an empty list',
        () async {
      final fake = _FakeSupabaseService()
        ..failNextFetchWith = Exception('boom');
      final container = _containerWith(fake);

      await expectLater(
        container.read(restaurantListProvider.future),
        throwsA(isA<Exception>()),
      );
      expect(container.read(restaurantListProvider).hasError, isTrue);
    });
  });

  group('restaurantRepositoryProvider', () {
    test('is built from the injected supabaseServiceProvider', () async {
      final fake = _FakeSupabaseService(restaurants: [_restaurant('a')]);
      final container = _containerWith(fake);

      final repository = container.read(restaurantRepositoryProvider);
      final result = await repository.loadAll();

      expect(result.single.placeId, 'a');
      expect(fake.fetchCount, 1);
    });
  });
}
