import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiet_restaurant_finder/providers/beta_gate_provider.dart';
import 'package:quiet_restaurant_finder/providers/supabase_service_provider.dart';
import 'package:quiet_restaurant_finder/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState;

/// Stands in for the real backend, same shape as favourites_provider_test's
/// fake — only the members `BetaAccess` touches are overridden; anything
/// else would throw, which is the point.
class _FakeSupabaseService extends SupabaseService {
  _FakeSupabaseService({this.signedIn = true, this.access = true});

  bool signedIn;
  bool access;

  /// When true, hasBetaAccess() doesn't resolve on its own — a test must
  /// call [resolveNextAccessCheck]. Lets a test observe the checking state
  /// and control exactly which in-flight RPC answers, and when.
  bool holdAccessCheck = false;

  int hasBetaAccessCallCount = 0;
  final _pendingAccessChecks = <Completer<bool>>[];

  final _authController = StreamController<AuthState>.broadcast();

  @override
  bool get isSignedIn => signedIn;

  @override
  Stream<AuthState> get authStateChanges => _authController.stream;

  @override
  Future<bool> hasBetaAccess() {
    hasBetaAccessCallCount++;
    if (!holdAccessCheck) return Future.value(access);
    final completer = Completer<bool>();
    _pendingAccessChecks.add(completer);
    return completer.future;
  }

  /// Resolves the oldest not-yet-resolved hasBetaAccess() call, FIFO — lets
  /// a test control exactly which in-flight RPC answers first.
  void resolveNextAccessCheck(bool result) {
    _pendingAccessChecks.removeAt(0).complete(result);
  }

  void emit(AuthChangeEvent event) =>
      _authController.add(AuthState(event, null));

  /// Supabase puts network and token-refresh failures on this same stream,
  /// not just auth events — simulates one.
  void emitError(Object error) => _authController.addError(error);

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
  group('betaAccessProvider', () {
    test('signed-out has no access, and never calls hasBetaAccess()',
        () async {
      final fake = _FakeSupabaseService(signedIn: false);
      final container = _containerWith(fake);

      expect(await container.read(betaAccessProvider.future), isFalse);
      expect(fake.hasBetaAccessCallCount, 0);
    });

    test('signed-in with a redeemed code has access', () async {
      final fake = _FakeSupabaseService(signedIn: true, access: true);
      final container = _containerWith(fake);

      expect(await container.read(betaAccessProvider.future), isTrue);
      expect(fake.hasBetaAccessCallCount, 1);
    });

    test('signed-in without a redeemed code has no access', () async {
      final fake = _FakeSupabaseService(signedIn: true, access: false);
      final container = _containerWith(fake);

      expect(await container.read(betaAccessProvider.future), isFalse);
      expect(fake.hasBetaAccessCallCount, 1);
    });

    // router.dart's _gateRedirect reads this as "still checking" and sends
    // the user to /checking-access rather than flashing /beta-gate while
    // the RPC that would tell them otherwise is still in flight.
    test('reads as checking (no value yet) while the access RPC is in flight',
        () {
      final fake = _FakeSupabaseService(signedIn: true)
        ..holdAccessCheck = true;
      final container = _containerWith(fake);

      // Starts the build synchronously up to the RPC call, without waiting
      // for it to resolve.
      container.read(betaAccessProvider.future);

      final state = container.read(betaAccessProvider);
      expect(state.isLoading, isTrue);
      expect(state.valueOrNull, isNull);
      expect(fake.hasBetaAccessCallCount, 1);

      // Let the fake finish cleanly rather than leaving a Completer dangling.
      fake.resolveNextAccessCheck(true);
    });

    // The bug-shaped case: access must be re-checked on every sign-in and
    // sign-out, not just once at cold start, or a second account on the
    // same session would inherit the first account's answer.
    test('re-checks access on sign-in and sign-out', () async {
      final fake = _FakeSupabaseService(signedIn: false);
      final container = _containerWith(fake);
      expect(await container.read(betaAccessProvider.future), isFalse);

      fake.signedIn = true;
      fake.access = true;
      fake.emit(AuthChangeEvent.signedIn);
      await Future<void>.delayed(Duration.zero);

      expect(await container.read(betaAccessProvider.future), isTrue);
      expect(fake.hasBetaAccessCallCount, 1);

      fake.signedIn = false;
      fake.emit(AuthChangeEvent.signedOut);
      await Future<void>.delayed(Duration.zero);

      expect(await container.read(betaAccessProvider.future), isFalse);
    });

    // valueOrNull alone is NOT "still checking" on a re-check, only on the
    // very first build — confirmed here before relying on it anywhere.
    // Riverpod's invalidateSelf-triggered rebuild sets state via
    // AsyncLoading().copyWithPrevious(previous, isRefresh: true), and
    // AsyncLoading.copyWithPrevious folds a previously-resolved value into
    // an AsyncData with isLoading: true rather than clearing it — so
    // valueOrNull reads the STALE prior answer here, not null, even though a
    // real check is genuinely in flight. isLoading is true in both cases
    // (first build and re-check), which is why asGateAccess (below, and in
    // beta_gate_provider.dart) reads that instead.
    test(
        'a re-check retains the previous value — valueOrNull is not '
        '"checking" on its own, only isLoading is', () async {
      final fake = _FakeSupabaseService(signedIn: false);
      final container = _containerWith(fake);
      expect(await container.read(betaAccessProvider.future), isFalse);

      fake.signedIn = true;
      fake.holdAccessCheck = true;
      fake.emit(AuthChangeEvent.signedIn);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(betaAccessProvider);
      expect(state.isLoading, isTrue);
      expect(state.valueOrNull, isFalse); // stale — NOT the "checking" null
      expect(state.asGateAccess, isNull); // what router.dart actually reads

      fake.resolveNextAccessCheck(true);
      expect(await container.read(betaAccessProvider.future), isTrue);
    });

    // The race BetaGateNotifier's `_refreshGeneration` counter used to
    // guard against: a slow hasBetaAccess() RPC for an account that has
    // since signed out must not overwrite the correct signed-out state once
    // it finally answers.
    test('a slower RPC for an old session cannot overwrite a newer sign-out',
        () async {
      final fake = _FakeSupabaseService(signedIn: true)
        ..holdAccessCheck = true;
      final container = _containerWith(fake);

      // First build starts and its hasBetaAccess() RPC is left hanging.
      container.read(betaAccessProvider.future);
      expect(fake.hasBetaAccessCallCount, 1);

      // A sign-out arrives before that RPC answers.
      fake.signedIn = false;
      fake.emit(AuthChangeEvent.signedOut);
      await Future<void>.delayed(Duration.zero);

      // The new build (for "signed out") resolves to false on its own,
      // without waiting on the stale RPC — it never even calls it.
      expect(await container.read(betaAccessProvider.future), isFalse);
      expect(fake.hasBetaAccessCallCount, 1);

      // The old RPC finally answers, with `true` — as if the previous
      // account did have access. Unguarded, this would overwrite the
      // correct signed-out state.
      fake.resolveNextAccessCheck(true);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(betaAccessProvider).valueOrNull, isFalse);
    });

    // BetaGateNotifier's authStateChanges.listen() carried an onError that
    // did nothing but exist — Supabase puts network and token-refresh
    // failures on this stream too, not just auth events, and an unhandled
    // error on a stream this class owns would otherwise crash the app
    // rather than just leaving betaAccessProvider showing its last-known
    // answer until the next auth event or app launch retries the check.
    test('a stream error on authStateChanges does not crash the provider',
        () async {
      final fake = _FakeSupabaseService(signedIn: false);
      final container = _containerWith(fake);
      expect(await container.read(betaAccessProvider.future), isFalse);

      fake.emitError(Exception('network blip'));
      await Future<void>.delayed(Duration.zero);

      // Still readable afterwards — the error did not propagate as an
      // unhandled Zone error and take the provider (or, in the real app,
      // everything else on this Zone) down with it.
      expect(container.read(betaAccessProvider).valueOrNull, isFalse);
    });
  });
}
