// Tracks whether the current session has cleared the closed-beta gate —
// the single source of truth router.dart's top-level redirect reads.
// Refreshed on every auth-state change (sign-in, sign-out, token refresh)
// and whenever BetaGateScreen redeems a code, via notifyListeners() firing
// GoRouter's refreshListenable, so the redirect re-evaluates automatically
// instead of any screen needing to manually navigate on success — see
// router.dart's redirect for how this is read.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class BetaGateNotifier extends ChangeNotifier {
  final _supabaseService = SupabaseService();
  StreamSubscription<AuthState>? _authSubscription;
  int _refreshGeneration = 0;

  /// null = still checking (or nothing to check yet — signed out);
  /// true/false once resolved for whoever is currently signed in.
  bool? hasAccess;

  BetaGateNotifier() {
    if (SupabaseService.isConfigured) {
      _authSubscription = _supabaseService.authStateChanges.listen(
        (_) => unawaited(refresh()),
        // Supabase emits network and token-refresh failures on this stream.
        // Handling them here prevents an unhandled async error from crashing
        // the app; the next auth event or app launch will retry the check.
        onError: (_, __) {},
      );
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    final refreshGeneration = ++_refreshGeneration;
    if (!_supabaseService.isSignedIn) {
      hasAccess = false;
      notifyListeners();
      return;
    }

    // Keep the router on the short checking screen while a newly installed
    // session is being verified. This avoids presenting beta-code entry until
    // the authenticated RPC is actually ready to run.
    hasAccess = null;
    notifyListeners();
    final hasAccessForCurrentSession = await _supabaseService.hasBetaAccess();

    // An earlier RPC must not overwrite the state of a newer sign-in/out.
    if (refreshGeneration != _refreshGeneration || !_supabaseService.isSignedIn) return;

    hasAccess = hasAccessForCurrentSession;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
