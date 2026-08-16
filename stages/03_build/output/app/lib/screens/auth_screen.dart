// Only shown when someone taps "Take a reading here" and isn't signed in —
// browsing the ranked list never requires an account.
//
// Three ways in, wired up: email/password (Supabase's default, no external
// account needed), Google, and Apple (iOS only). Google/Apple both need
// Caelan's own developer accounts configured before they'll work — see
// PLATFORM_SETUP.md. Both stay hidden until explicitly turned on, rather
// than showing a button that would just error:
// - Google: hidden until GOOGLE_WEB_CLIENT_ID is set (`_googleConfigured`).
// - Apple: skipped for now (decided 2026-08-15) — Caelan hasn't settled
//   whether a free Xcode Personal Team even supports the capability, and
//   shipping needs the paid $99/year Developer Program regardless. The
//   implementation (`_signInWithApple`) is untouched and ready; only the
//   button's visibility is gated, via APPLE_SIGN_IN_ENABLED, off by
//   default. Flip it on with
//   `flutter run --dart-define=APPLE_SIGN_IN_ENABLED=true` once ready to
//   test — no code change needed.

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Google OAuth client IDs — not secret, but environment-specific, so passed
// at build/run time rather than hardcoded. See PLATFORM_SETUP.md for where
// these come from (Google Cloud Console) and how to pass them:
// flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=... --dart-define=GOOGLE_IOS_CLIENT_ID=...
const _googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
const _googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
bool get _googleConfigured => _googleWebClientId.isNotEmpty;

// Off by default — see the file header. Not about whether Apple is
// configured in Supabase (Google's _googleConfigured checks that); this is
// specifically "has Caelan decided to test/ship this yet."
const _appleSignInEnabled = bool.fromEnvironment('APPLE_SIGN_IN_ENABLED');

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
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

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      if (_isSignUp) {
        final response = await _client.auth.signUp(email: email, password: password);
        // Supabase requires email confirmation by default — signUp does not
        // return an active session in that case. Don't assume success means
        // "signed in"; tell the user what actually needs to happen next.
        if (response.session == null) {
          setState(() {
            _info = 'Check $email for a confirmation link, then sign in.';
            _isSignUp = false;
          });
        } else if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        await _client.auth.signInWithPassword(email: email, password: password);
        if (mounted) Navigator.of(context).pop(true);
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _submitting = true;
      _error = null;
      _info = null;
    });
    try {
      final googleSignIn = GoogleSignIn.instance;
      await googleSignIn.initialize(
        serverClientId: _googleWebClientId,
        clientId: _googleIosClientId.isNotEmpty ? _googleIosClientId : null,
      );

      final googleUser = await googleSignIn.authenticate();
      const scopes = ['email', 'profile'];
      // authorizationForScopes returns null if the user hasn't already
      // granted these scopes (e.g. first sign-in) — falls back to
      // authorizeScopes, which prompts for consent.
      final authorization = await googleUser.authorizationClient.authorizationForScopes(scopes) ??
          await googleUser.authorizationClient.authorizeScopes(scopes);
      final idToken = googleUser.authentication.idToken;

      if (idToken == null) {
        throw Exception('Google did not return an ID token.');
      }

      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: authorization.accessToken,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'Google sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _submitting = true;
      _error = null;
      _info = null;
    });
    try {
      final rawNonce = _client.auth.generateRawNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        throw Exception('Apple did not return an identity token.');
      }

      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'Apple sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showAppleButton = _appleSignInEnabled && !kIsWeb && Platform.isIOS;

    return Scaffold(
      appBar: AppBar(title: Text(_isSignUp ? 'Create account' : 'Sign in')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'An account is only needed to submit a noise reading — browsing stays open to everyone.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (showAppleButton) ...[
              SignInWithAppleButton(
                onPressed: _submitting ? null : () { _signInWithApple(); },
              ),
              const SizedBox(height: 12),
            ],
            if (_googleConfigured) ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.login),
                label: const Text('Continue with Google'),
                onPressed: _submitting ? null : _signInWithGoogle,
              ),
              const SizedBox(height: 20),
              const Row(children: [Expanded(child: Divider()), Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('or'),
              ), Expanded(child: Divider())]),
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
            ),
            const SizedBox(height: 20),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            if (_info != null) Text(_info!, style: const TextStyle(color: Colors.green)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Please wait…' : (_isSignUp ? 'Create account' : 'Sign in')),
            ),
            TextButton(
              onPressed: _submitting ? null : () => setState(() => _isSignUp = !_isSignUp),
              child: Text(_isSignUp ? 'Already have an account? Sign in' : "Don't have an account? Create one"),
            ),
          ],
        ),
      ),
    );
  }
}
