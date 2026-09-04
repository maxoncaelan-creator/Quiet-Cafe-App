// Riverpod replacement for BetaGateNotifier (execution-plan-2026-08-23.md,
// step 3c). Same reason step 3a/3b needed a seam at all: the old
// ChangeNotifier constructed `SupabaseService()` itself and gated on the
// static `SupabaseService.isConfigured`, so no test double could ever stand
// in for it and the closed-beta gate shipped with zero coverage.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import '../services/observability_service.dart';
import '../services/supabase_service.dart';
import 'supabase_service_provider.dart';

/// Whether the signed-in session has cleared the closed-beta gate.
///
/// router.dart's `_gateRedirect` reads this via `.asGateAccess` (below),
/// which reproduces the exact three states `BetaGateNotifier.hasAccess` used
/// to hold directly:
///  - still checking, same as the old `null` — routes to `/checking-access`.
///  - `false` — signed in, no redeemed code yet — routes to `/beta-gate`.
///  - `true` — cleared the gate — normal routes.
///
/// This is deliberately *not* plain `.valueOrNull`. `AsyncValue.valueOrNull`
/// only reads as null on this provider's very first build, when there is no
/// previous state to fall back on. On a re-check — sign in right after a
/// signed-out `false`, say — `ref.invalidateSelf()`'s rebuild sets state via
/// `AsyncLoading().copyWithPrevious(previous, isRefresh: true)`, and
/// `AsyncLoading.copyWithPrevious` folds a previously-resolved value into an
/// `AsyncData` with `isLoading: true` rather than clearing it. So
/// `valueOrNull` would read the *stale* prior answer during that check, not
/// null — sending someone straight to `/beta-gate` for a flash before the
/// real answer replaces it, exactly the flicker `BetaGateNotifier` avoided
/// by unconditionally setting `hasAccess = null` before every check, not
/// just the first. `isLoading` is `true` in both cases (first build and
/// re-check), which is what `asGateAccess` reads instead. Verified against
/// riverpod 2.6.1's source and exercised directly in
/// beta_gate_provider_test.dart — not assumed.
///
/// The reverse direction (a stale `true` surviving into a sign-out) needs no
/// guard: `_gateRedirect` checks `SupabaseService().isSignedIn` before ever
/// reading this provider, so a signed-out user is routed to `/sign-in`
/// without this value being read at all.
///
/// No `SupabaseService.isConfigured` check here, on purpose — same shape as
/// `FavouriteIds.build()` in favourites_provider.dart. `authStateChanges`
/// yields an empty stream and `isSignedIn` is false when there's no backend,
/// so an unconfigured build falls through to `false` (gate closed) without a
/// special case a test double could defeat. That's harmless because
/// router.dart's `_gateRedirect` still short-circuits the *whole* gate ahead
/// of this for that build (`if (!SupabaseService.isConfigured) return null`)
/// — this class just doesn't need its own copy of that bypass to be correct
/// on its own terms.
class BetaAccess extends AsyncNotifier<bool> {
  // Injected, not constructed here — see supabase_service_provider.dart.
  SupabaseService get _service => ref.read(supabaseServiceProvider);

  @override
  Future<bool> build() async {
    // Re-checked on every sign-in and sign-out, same trigger as
    // FavouriteIds — a stale answer for an account that isn't current
    // anymore must never be shown as this session's access.
    //
    // This is also the entire replacement for BetaGateNotifier's hand-rolled
    // `_refreshGeneration` counter, which existed so a slow `hasBetaAccess()`
    // RPC couldn't overwrite the result of a newer sign-in/out that finished
    // first. AsyncNotifier needs no counter of its own: calling
    // `ref.invalidateSelf()` synchronously cancels *this* build's in-flight
    // future as part of Riverpod's own rebuild bookkeeping
    // (`ProviderElementBase.invalidateSelf` runs `runOnDispose`, which flips
    // the `running` flag `AsyncNotifier`'s `handleFuture` closed over before
    // the new build starts) — so when a stale RPC answer arrives after that,
    // its result is discarded rather than applied to `state`. Checked
    // against riverpod 2.6.1's source, not assumed; the race is exercised
    // directly in beta_gate_provider_test.dart.
    final subscription = _service.authStateChanges.listen(
      (auth) {
        if (auth.event == AuthChangeEvent.signedIn ||
            auth.event == AuthChangeEvent.signedOut) {
          ref.invalidateSelf();
        }
      },
      // Supabase puts network and token-refresh failures on this same
      // stream, not just auth events — carried over from BetaGateNotifier's
      // own listener, which existed for the same reason: left unhandled, an
      // error here becomes an unhandled Zone error and crashes the app,
      // rather than just leaving betaAccessProvider showing its last-known
      // answer until the next auth event or app launch retries the check.
      // Genuinely unexpected (a network blip or token-refresh failure, not
      // anything the user did), so worth knowing about.
      onError: (error, stackTrace) {
        ObservabilityService.captureError(error, stackTrace,
            context: 'beta_gate.auth_state_stream');
      },
    );
    ref.onDispose(subscription.cancel);

    if (!_service.isSignedIn) return false;
    return _service.hasBetaAccess();
  }
}

final betaAccessProvider =
    AsyncNotifierProvider<BetaAccess, bool>(BetaAccess.new);

/// Reads a beta-access [AsyncValue] the way the gate needs it read: `null`
/// while genuinely checking, `true`/`false` once settled. See the doc
/// comment above for why plain `.valueOrNull` cannot be used for this —
/// it stays `true`/`false` (the retained previous answer) through a
/// re-check, not just through the first one.
extension BetaGateAccessReading on AsyncValue<bool> {
  bool? get asGateAccess => isLoading ? null : valueOrNull;
}
