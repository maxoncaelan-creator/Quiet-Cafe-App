// Mobile implementation of GoogleAuthButton — see google_auth_button.dart
// for why this is split from the web one. Just wraps the existing custom
// pill button (google_sign_in_button.dart) and OAuthService.signInWithGoogle(),
// which is exactly what auth_screen.dart/create_account_screen.dart used to
// do directly before this widget existed.

import 'package:flutter/material.dart';

import '../services/oauth_service.dart';
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
      await OAuthService.signInWithGoogle();
      onSignedIn();
    } catch (e) {
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
