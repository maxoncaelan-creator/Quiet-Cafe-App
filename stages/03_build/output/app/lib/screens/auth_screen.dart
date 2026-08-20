// Only shown when someone taps "Take a reading here" and isn't signed in —
// browsing the ranked list never requires an account.
//
// A pure chooser as of 2026-08-18, per Caelan (reference: cal.com's
// sign-in/sign-up screens) — Google is styled to stand out
// (widgets/google_sign_in_button.dart, with Google's actual logo), Apple
// and Facebook stay as their existing native/outlined styles, and email
// sign-in is a button leading to SignInEmailScreen rather than inline
// fields on this screen. Before this, the screen also toggled into a
// sign-up form sharing one email/password pair — creating an account is its
// own flow now (CreateAccountScreen → CreateAccountEmailScreen →
// CreateAccountPasswordScreen).
//
// Four ways in, wired up: email/password (Supabase's default, no external
// account needed), Google, Apple (iOS only), and Facebook, via
// services/oauth_service.dart (shared with CreateAccountScreen, since
// signing in and signing up via OAuth are the same Supabase call). All three
// social providers need Caelan's own developer accounts configured before
// they'll work — see PLATFORM_SETUP.md. Each stays hidden until explicitly
// turned on, rather than showing a button that would just error — see
// oauth_service.dart for the specifics of each flag.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../services/oauth_service.dart';
import '../widgets/centered_scroll_form.dart';
import '../widgets/email_option_button.dart';
import '../widgets/google_auth_button.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _submitting = false;
  String? _error;
  String? _info;

  /// Was this screen reached via a push (from _ensureSignedIn/_startReading,
  /// pre-beta pattern) or via router.dart's top-level gate redirect (added
  /// 2026-08-21 — no caller waiting for a pop result in that case)? Popping
  /// with nothing beneath this route would be a no-op at best; go('/') lets
  /// the gate redirect itself decide where this account actually belongs
  /// (straight in, or to /beta-gate) rather than assuming '/' is reachable.
  void _completeSignIn() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop(true);
    } else {
      context.go('/');
    }
  }

  Future<void> _runOAuth(Future<void> Function() signIn, {required bool popOnSuccess}) async {
    setState(() {
      _submitting = true;
      _error = null;
      _info = null;
    });
    try {
      await signIn();
      if (popOnSuccess) _completeSignIn();
    } catch (e) {
      setState(() => _error = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signInWithEmail() async {
    final result = await context.push<bool>('/sign-in/email');
    if (result == true) _completeSignIn();
  }

  /// Pushes the create-account flow and relays its result: `true` means a
  /// session was established (cascade the pop up to whoever opened this
  /// sign-in screen), `false` means the account was created but needs email
  /// confirmation first (the message was already delivered via
  /// `onPendingConfirmation` below — stay on this screen to show it), and
  /// `null` means the user backed out without finishing.
  Future<void> _createAccount() async {
    final result = await context.push<bool>(
      '/sign-up',
      extra: (String message) {
        if (mounted) setState(() => _info = message);
      },
    );
    if (result == true) _completeSignIn();
  }

  @override
  Widget build(BuildContext context) {
    final showAppleButton = OAuthService.appleConfigured && !kIsWeb && Platform.isIOS;

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: SafeArea(
        child: CenteredScrollForm(
          children: [
              if (OAuthService.googleConfigured) ...[
                GoogleAuthButton(
                  label: 'Sign in with Google',
                  submitting: _submitting,
                  onSignedIn: _completeSignIn,
                  onError: (e) => setState(() => _error = 'Sign-in failed: $e'),
                ),
                const SizedBox(height: 12),
              ],
              if (showAppleButton) ...[
                SignInWithAppleButton(
                  onPressed: _submitting
                      ? null
                      : () => _runOAuth(OAuthService.signInWithApple, popOnSuccess: true),
                ),
                const SizedBox(height: 12),
              ],
              if (OAuthService.facebookConfigured) ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.facebook),
                  label: const Text('Continue with Facebook'),
                  // No popOnSuccess: the app loses foreground focus during
                  // Facebook's redirect flow — see oauth_service.dart.
                  onPressed: _submitting
                      ? null
                      : () => _runOAuth(OAuthService.signInWithFacebook, popOnSuccess: false),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 8),
              const Row(children: [
                Expanded(child: Divider()),
                Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('or')),
                Expanded(child: Divider()),
              ]),
              const SizedBox(height: 20),
              EmailOptionButton(
                label: 'Sign in with email',
                onPressed: _submitting ? null : _signInWithEmail,
              ),
              const SizedBox(height: 20),
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
              if (_info != null) Text(_info!, style: const TextStyle(color: Colors.green)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _submitting ? null : _createAccount,
                child: const Text("Don't have an account? Create one"),
              ),
          ],
        ),
      ),
    );
  }
}
