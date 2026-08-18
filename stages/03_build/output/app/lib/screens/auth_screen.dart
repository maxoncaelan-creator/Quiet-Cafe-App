// Only shown when someone taps "Take a reading here" and isn't signed in —
// browsing the ranked list never requires an account.
//
// Four ways in, wired up: email/password (Supabase's default, no external
// account needed), Google, Apple (iOS only), and Facebook. All three social
// providers need Caelan's own developer accounts configured before they'll
// work — see PLATFORM_SETUP.md. Each stays hidden until explicitly turned
// on, rather than showing a button that would just error:
// - Google: hidden until GOOGLE_WEB_CLIENT_ID is set (`_googleConfigured`).
// - Apple: on by default as of 2026-08-16 (decided — activate alongside
//   Google/Facebook rather than stay deferred). The two caveats from the
//   original decision still apply and are unaffected by this flag: Sign in
//   with Apple only shows on iOS, and shipping to the App Store needs the
//   paid $99/year Developer Program regardless of whether the free Personal
//   Team path works for local testing. Turn back off with
//   `flutter run --dart-define=APPLE_SIGN_IN_ENABLED=false` if needed.
// - Facebook: hidden until FACEBOOK_SIGN_IN_ENABLED is set to true
//   (`_facebookConfigured`) — unlike Google/Apple this one needs no
//   dart-define client ID, since it goes through Supabase's redirect-based
//   OAuth flow (`signInWithOAuth`) rather than a native SDK; the Facebook
//   App ID/secret are configured entirely on the Supabase dashboard side
//   (Authentication → Providers → Facebook). The flag just prevents showing
//   a button that would error before that's done.
//
// Facebook (and the web-based half of any future provider) relies on a
// custom redirect URL, `quietrestaurantfinder://login-callback`, registered
// as an Additional Redirect URL in Supabase's Auth settings and declared in
// each platform's native config (AndroidManifest.xml, ios/Runner/Info.plist)
// — see PLATFORM_SETUP.md. The same redirect is now also used for email
// confirmation links (`emailRedirectTo` below), so confirming an account
// routes back into the app instead of Supabase's generic hosted page.
// Not yet verified live — needs a real installed build on a device, which
// isn't available in this environment (see PLATFORM_SETUP.md).

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

// On by default as of 2026-08-16 — see the file header. Not about whether
// Apple is configured in Supabase; this is "has Caelan decided to
// show/hide this," defaulting to shown now that it's activated.
const _appleSignInEnabled = bool.fromEnvironment('APPLE_SIGN_IN_ENABLED', defaultValue: true);

// Off by default until Caelan has configured the Facebook provider in the
// Supabase dashboard — see the file header.
const _facebookConfigured = bool.fromEnvironment('FACEBOOK_SIGN_IN_ENABLED');

// Redirect target for Supabase's browser-based auth flows (OAuth and email
// confirmation) on mobile. Not used on web, where Supabase's own origin is
// the redirect target instead. Must exactly match an Additional Redirect
// URL in Supabase's Auth settings, and the scheme must be declared in each
// platform's native config — see PLATFORM_SETUP.md.
const _oauthRedirectUrl = 'quietrestaurantfinder://login-callback';

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
        final response = await _client.auth.signUp(
          email: email,
          password: password,
          // Routes the confirmation link back into the app via the same
          // redirect used for OAuth, instead of Supabase's generic hosted
          // confirmation page — see the file header. Ignored on web, where
          // there's no app to redirect back into.
          emailRedirectTo: kIsWeb ? null : _oauthRedirectUrl,
        );
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

  /// Prompts for the account's email (pre-filled if already typed above)
  /// and sends a reset link via Supabase Auth's built-in flow. Doesn't
  /// reveal whether the address has an account — Supabase's API itself
  /// returns success regardless, so there's nothing more specific to tell
  /// the user either way.
  Future<void> _forgotPassword() async {
    final controller = TextEditingController(text: _emailController.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset password'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
          autofocus: controller.text.isEmpty,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Send link'),
          ),
        ],
      ),
    );
    if (!mounted || email == null || email.isEmpty) return;

    setState(() {
      _submitting = true;
      _error = null;
      _info = null;
    });
    try {
      await _client.auth.resetPasswordForEmail(
        email,
        redirectTo: kIsWeb ? null : _oauthRedirectUrl,
      );
      if (!mounted) return;
      setState(() => _info = 'If $email has an account, a password reset link is on its way.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not send reset link: $e');
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

  /// Facebook has no equivalent to Google's/Apple's native ID-token flow
  /// generally available on both platforms, so this goes through Supabase's
  /// redirect-based `signInWithOAuth` instead: a browser tab opens for
  /// Facebook's login/consent, then redirects back to `_oauthRedirectUrl`,
  /// which the OS hands back to this app (native config in
  /// AndroidManifest.xml / Info.plist makes that handoff possible).
  /// `Navigator.pop` doesn't happen here on success — unlike the ID-token
  /// flows above, the app loses foreground focus during the redirect, so the
  /// sign-in completing is reported via `authStateChanges`
  /// (`supabase_service.dart`), not this call returning normally.
  Future<void> _signInWithFacebook() async {
    setState(() {
      _submitting = true;
      _error = null;
      _info = null;
    });
    try {
      await _client.auth.signInWithOAuth(
        OAuthProvider.facebook,
        redirectTo: kIsWeb ? null : _oauthRedirectUrl,
        authScreenLaunchMode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      );
      // No Navigator.pop here — see the doc comment above.
    } catch (e) {
      setState(() => _error = 'Facebook sign-in failed: $e');
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
              const SizedBox(height: 12),
            ],
            if (_facebookConfigured) ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.facebook),
                label: const Text('Continue with Facebook'),
                onPressed: _submitting ? null : _signInWithFacebook,
              ),
              const SizedBox(height: 12),
            ],
            if (_googleConfigured || _facebookConfigured) ...[
              const SizedBox(height: 8),
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
            if (!_isSignUp)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _submitting ? null : _forgotPassword,
                  child: const Text('Forgot password?'),
                ),
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
