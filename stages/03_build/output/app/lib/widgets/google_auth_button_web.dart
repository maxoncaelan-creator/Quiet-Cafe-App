// Web implementation of GoogleAuthButton — see google_auth_button.dart for
// why this exists separately from the mobile one. Renders Google's own GIS
// button widget (the only sign-in UI Google's web SDK allows — a custom
// button calling authenticate() throws UnimplementedError there) and
// completes the Supabase sign-in when a GoogleSignInAuthenticationEventSignIn
// arrives on OAuthService.googleAuthenticationEvents, since there's no
// tap-and-await path here the way there is on mobile.
//
// [label] is unused here — Google's own button owns its text/branding,
// unlike the custom pill button on mobile. Kept as a required parameter
// anyway so both platform implementations share one call site in the
// screens that use this widget.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/web_only.dart' as gsi_web;

import '../services/oauth_service.dart';

class GoogleAuthButton extends StatefulWidget {
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

  @override
  State<GoogleAuthButton> createState() => _GoogleAuthButtonState();
}

class _GoogleAuthButtonState extends State<GoogleAuthButton> {
  StreamSubscription<GoogleSignInAuthenticationEvent>? _subscription;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await OAuthService.ensureGoogleInitializedForWeb();
    } catch (e) {
      if (mounted) widget.onError(e);
      return;
    }
    if (!mounted) return;

    _subscription = OAuthService.googleAuthenticationEvents.listen(
      (event) async {
        if (event is! GoogleSignInAuthenticationEventSignIn) return;
        try {
          await OAuthService.completeGoogleSignIn(event.user);
          if (mounted) widget.onSignedIn();
        } catch (e) {
          if (mounted) widget.onError(e);
        }
      },
      onError: (Object e) {
        if (mounted) widget.onError(e);
      },
    );
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const SizedBox(
        height: 40,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    // Google's widget manages its own click/loading state internally —
    // this just blocks interaction while another OAuth method (Apple,
    // Facebook, email) is mid-flight on the same screen, matching how the
    // mobile pill button disables via `submitting` too.
    return IgnorePointer(
      ignoring: widget.submitting,
      child: Opacity(
        opacity: widget.submitting ? 0.5 : 1,
        child: gsi_web.renderButton(),
      ),
    );
  }
}
