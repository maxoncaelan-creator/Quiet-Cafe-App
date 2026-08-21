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

  /// null = still checking (or nothing to check yet — signed out);
  /// true/false once resolved for whoever is currently signed in.
  bool? hasAccess;

  BetaGateNotifier() {
    if (SupabaseService.isConfigured) {
      _authSubscription = _supabaseService.authStateChanges.listen((_) => refresh());
      refresh();
    }
  }

  Future<void> refresh() async {
    hasAccess = _supabaseService.isSignedIn ? await _supabaseService.hasBetaAccess() : false;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
