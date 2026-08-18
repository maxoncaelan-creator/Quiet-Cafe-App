// Only shown when someone taps "Take a reading here" and isn't signed in —
// browsing the ranked list never requires an account.
//
// Sign-in only as of 2026-08-18 — creating an account is its own flow now
// (CreateAccountScreen → CreateAccountPasswordScreen), per Caelan: this
// screen used to toggle between a sign-in and a sign-up form sharing one
// email/password pair, which meant a brand-new user set their password on
// the same screen as everything else with no confirmation step. See
// create_account_screen.dart's file header for the rest of that flow.
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
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/oauth_service.dart';
import 'create_account_screen.dart';
import 'forgot_password_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  String? _error;
  String? _info;

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
      _info = null;
    });
    try {
      await _client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
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
      if (popOnSuccess && mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Pushes the create-account flow and relays its result: `true` means a
  /// session was established (cascade the pop up to whoever opened this
  /// sign-in screen), `false` means the account was created but needs email
  /// confirmation first (the message was already delivered via
  /// `onPendingConfirmation` below — stay on this screen to show it), and
  /// `null` means the user backed out without finishing.
  Future<void> _createAccount() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateAccountScreen(
          initialEmail: _emailController.text.trim(),
          onPendingConfirmation: (message) {
            if (mounted) setState(() => _info = message);
          },
        ),
      ),
    );
    if (result == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showAppleButton = OAuthService.appleConfigured && !kIsWeb && Platform.isIOS;

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showAppleButton) ...[
                SignInWithAppleButton(
                  onPressed: _submitting
                      ? null
                      : () => _runOAuth(OAuthService.signInWithApple, popOnSuccess: true),
                ),
                const SizedBox(height: 12),
              ],
              if (OAuthService.googleConfigured) ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.login),
                  label: const Text('Continue with Google'),
                  onPressed:
                      _submitting ? null : () => _runOAuth(OAuthService.signInWithGoogle, popOnSuccess: true),
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
              if (OAuthService.googleConfigured || OAuthService.facebookConfigured) ...[
                const SizedBox(height: 8),
                const Row(children: [
                  Expanded(child: Divider()),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('or')),
                  Expanded(child: Divider()),
                ]),
                const SizedBox(height: 20),
              ],
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                onSubmitted: (_) => _submitting ? null : _submit(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ForgotPasswordScreen(initialEmail: _emailController.text.trim()),
                            ),
                          ),
                  child: const Text('Forgot password?'),
                ),
              ),
              const SizedBox(height: 20),
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
              if (_info != null) Text(_info!, style: const TextStyle(color: Colors.green)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: Text(_submitting ? 'Please wait…' : 'Sign in'),
              ),
              TextButton(
                onPressed: _submitting ? null : _createAccount,
                child: const Text("Don't have an account? Create one"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
