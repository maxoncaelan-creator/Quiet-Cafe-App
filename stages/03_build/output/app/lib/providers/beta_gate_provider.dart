// Riverpod replacement for BetaGateNotifier (execution-plan-2026-08-23.md,
// step 3c). Same reason step 3a/3b needed a seam at all: the old
// ChangeNotifier constructed `SupabaseService()` itself and gated on the
// static `SupabaseService.isConfigured`, so no test double could ever stand
// in for it and the closed-beta gate shipped with zero coverage.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import '../services/supabase_service.dart';
import 'supabase_service_provider.dart';

/// Whether the signed-in session has cleared the closed-beta gate.
///
/// router.dart's `_gateRedirect` reads this via `.valueOrNull`, which
/// reproduces the exact three states `BetaGateNotifier.hasAccess` used to
/// hold directly:
///  - no value yet (`AsyncLoading`, `valueOrNull == null`) — still checking,
///    same as the old `null` — routes to `/checking-access`.
///  - `false` — signed in, no redeemed code yet — routes to `/beta-gate`.
///  - `true` — cleared the gate — normal routes.
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
    final subscription = _service.authStateChanges.listen((auth) {
      if (auth.event == AuthChangeEvent.signedIn ||
          auth.event == AuthChangeEvent.signedOut) {
        ref.invalidateSelf();
      }
    });
    ref.onDispose(subscription.cancel);

    if (!_service.isSignedIn) return false;
    return _service.hasBetaAccess();
  }
}

final betaAccessProvider =
    AsyncNotifierProvider<BetaAccess, bool>(BetaAccess.new);
