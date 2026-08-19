// A pure chooser as of 2026-08-18, per Caelan (reference: cal.com's
// sign-up screen) — Google is styled to stand out
// (widgets/google_sign_in_button.dart, with Google's actual logo), Facebook
// stays its existing outlined style, and "Sign up with email" leads to
// CreateAccountEmailScreen rather than an inline field on this screen (the
// OAuth buttons don't need a separate step at all — signInWithIdToken
// creates the account on first use, same call as signing in). From there,
// continuing pushes CreateAccountPasswordScreen, where the password is
// actually set (and confirmed).
//
// Replaces the old design where AuthScreen toggled between a sign-in and a
// sign-up form sharing one email+password pair.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/oauth_service.dart';
import '../widgets/centered_scroll_form.dart';
import '../widgets/email_option_button.dart';
import '../widgets/google_auth_button.dart';

class CreateAccountScreen extends StatefulWidget {
  /// Fired if the account is created but needs email confirmation before a
  /// session exists — carries the message AuthScreen should show once this
  /// flow pops back to it. See CreateAccountPasswordScreen for where this
  /// actually fires.
  final ValueChanged<String> onPendingConfirmation;

  const CreateAccountScreen({super.key, required this.onPendingConfirmation});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  bool _submitting = false;
  String? _error;

  Future<void> _runOAuth(Future<void> Function() signIn, {required bool popOnSuccess}) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await signIn();
      if (popOnSuccess && mounted) context.pop(true);
    } catch (e) {
      setState(() => _error = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signUpWithEmail() async {
    final result = await context.push<bool>('/sign-up/email', extra: widget.onPendingConfirmation);
    if (result != null && mounted) context.pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: CenteredScrollForm(
          children: [
              if (OAuthService.googleConfigured) ...[
                GoogleAuthButton(
                  label: 'Sign up with Google',
                  submitting: _submitting,
                  onSignedIn: () {
                    if (mounted) context.pop(true);
                  },
                  onError: (e) => setState(() => _error = 'Sign-in failed: $e'),
                ),
                const SizedBox(height: 12),
              ],
              if (OAuthService.facebookConfigured) ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.facebook),
                  label: const Text('Continue with Facebook'),
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
                label: 'Sign up with email',
                onPressed: _submitting ? null : _signUpWithEmail,
              ),
              const SizedBox(height: 20),
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _submitting ? null : () => context.pop(),
                child: const Text('Already have an account? Sign in'),
              ),
          ],
        ),
      ),
    );
  }
}
