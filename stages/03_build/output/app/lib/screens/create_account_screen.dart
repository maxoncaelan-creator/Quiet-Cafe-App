// Step 1 of creating an account, per Caelan (2026-08-18): just the email,
// plus the OAuth buttons (which don't need a separate password step at
// all — signInWithIdToken creates the account on first use, same call as
// signing in). Continuing with email pushes CreateAccountPasswordScreen,
// step 2, where the password is actually set (and confirmed).
//
// Replaces the old design where AuthScreen toggled between a sign-in and a
// sign-up form sharing one email+password pair.

import 'package:flutter/material.dart';

import '../services/oauth_service.dart';
import 'create_account_password_screen.dart';

class CreateAccountScreen extends StatefulWidget {
  final String initialEmail;

  /// Fired if the account is created but needs email confirmation before a
  /// session exists — carries the message AuthScreen should show once this
  /// flow pops back to it. See CreateAccountPasswordScreen for where this
  /// actually fires.
  final ValueChanged<String> onPendingConfirmation;

  const CreateAccountScreen({super.key, this.initialEmail = '', required this.onPendingConfirmation});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  late final _emailController = TextEditingController(text: widget.initialEmail);
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _runOAuth(Future<void> Function() signIn, {required bool popOnSuccess}) async {
    setState(() {
      _submitting = true;
      _error = null;
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

  /// Only checks for an "@" — not full RFC validation, since Supabase
  /// itself is the real authority on whether an address is usable and will
  /// reject it on the next screen if not. This just catches an obviously
  /// empty or malformed entry before making the user set a password for it.
  Future<void> _continue() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() => _error = null);

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateAccountPasswordScreen(
          email: email,
          onPendingConfirmation: widget.onPendingConfirmation,
        ),
      ),
    );
    if (result == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                autofocus: widget.initialEmail.isEmpty,
                decoration: const InputDecoration(labelText: 'Email'),
                onSubmitted: (_) => _submitting ? null : _continue(),
              ),
              const SizedBox(height: 20),
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _submitting ? null : _continue,
                child: Text(_submitting ? 'Please wait…' : 'Continue'),
              ),
              TextButton(
                onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                child: const Text('Already have an account? Sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
