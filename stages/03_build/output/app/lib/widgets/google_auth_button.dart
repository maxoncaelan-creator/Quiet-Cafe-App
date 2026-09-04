// Unified as of 2026-08-19 — this used to be a dart.library.html-conditional
// export between separate mobile/web implementations (google_auth_button_io.dart
// / google_auth_button_web.dart), because Google's web SDK couldn't drive
// sign-in from a custom button at all (authenticate() throws
// UnimplementedError on web by design). Now that web goes through
// OAuthService.signInWithGoogleOAuth() — Supabase's redirect-based flow,
// the same mechanism the Facebook button below uses — there's no
// web-specific SDK involved here anymore, so one widget covers both
// platforms: same pill button, different OAuthService call underneath.

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/oauth_service.dart';
import '../services/observability_service.dart';
import 'google_sign_in_button.dart';

class GoogleAuthButton extends StatelessWidget {
  final String label;
  final bool submitting;
  final VoidCallback onSignedIn;
  final ValueChanged<Object> onError;

  const GoogleAuthButton({
    super.key,
    required this.label,
    required this.submitting,
    required this.onSignedIn,
    required this.onError,
  });

  Future<void> _signIn() async {
    try {
      if (kIsWeb) {
        // Redirect-based flow — the tab navigates to Google and back to
        // Supabase's own origin, so this Future may never resolve here
        // (the page can leave before it does). Completion is picked up by
        // the global auth-state listener in main.dart, not this callback —
        // same reasoning as the Facebook button in auth_screen.dart, which
        // is why onSignedIn() is deliberately not called on this branch.
        await OAuthService.signInWithGoogleOAuth();
      } else {
        await OAuthService.signInWithGoogle();
        onSignedIn();
      }
    } catch (e, st) {
      // A user backing out of Google's account picker throws a typed
      // cancellation on native — that's them declining, not a failure.
      final isUserCancelled =
          e is GoogleSignInException && e.code == GoogleSignInExceptionCode.canceled;
      if (!isUserCancelled) {
        unawaited(ObservabilityService.captureError(e, st,
            context: 'auth.google_sign_in'));
      }
      onError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GoogleSignInButton(
      label: label,
      onPressed: submitting ? null : _signIn,
    );
  }
}
