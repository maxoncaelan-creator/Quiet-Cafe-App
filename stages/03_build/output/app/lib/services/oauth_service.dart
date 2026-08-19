// Shared Google/Apple/Facebook sign-in mechanics, extracted 2026-08-18 so
// AuthScreen (sign in) and CreateAccountScreen (sign up) don't each carry
// their own copy of the same nonce/idToken/redirect handling. Each method
// performs the actual sign-in and returns normally on success, or throws on
// failure — callers own their own submitting/error UI state and what
// happens after success (both screens currently pop with `true`, but that's
// the caller's call, not this service's).
//
// Config flags and the shared redirect URL live here too, since anything
// that needs to know "is Google configured" already needs this file.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Google OAuth client IDs — not secret, but environment-specific, so passed
// at build/run time rather than hardcoded. See PLATFORM_SETUP.md for where
// these come from (Google Cloud Console) and how to pass them:
// flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=... --dart-define=GOOGLE_IOS_CLIENT_ID=...
const _googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
const _googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

// On by default as of 2026-08-16 — see PLATFORM_SETUP.md. Not about whether
// Apple is configured in Supabase; this is "has Caelan decided to
// show/hide this," defaulting to shown now that it's activated.
const _appleSignInEnabled = bool.fromEnvironment('APPLE_SIGN_IN_ENABLED', defaultValue: true);

// Off by default until Caelan has configured the Facebook provider in the
// Supabase dashboard — see PLATFORM_SETUP.md.
const _facebookConfigured = bool.fromEnvironment('FACEBOOK_SIGN_IN_ENABLED');

// Redirect target for Supabase's browser-based auth flows (OAuth and email
// confirmation) on mobile. Not used on web, where Supabase's own origin is
// the redirect target instead. Must exactly match an Additional Redirect
// URL in Supabase's Auth settings, and the scheme must be declared in each
// platform's native config — see PLATFORM_SETUP.md.
const oauthRedirectUrl = 'quietrestaurantfinder://login-callback';

class OAuthService {
  static bool get googleConfigured => _googleWebClientId.isNotEmpty;
  static bool get appleConfigured => _appleSignInEnabled;
  static bool get facebookConfigured => _facebookConfigured;

  static SupabaseClient get _client => Supabase.instance.client;

  // GoogleSignIn.instance.initialize() carries an explicit contract in its
  // own doc comment: "Clients must call this method exactly once, and wait
  // for its future to complete... Calling this method more than once will
  // result in undefined behavior." Found live 2026-08-19 (Caelan) — calling
  // it fresh inside signInWithGoogle() on every tap works the first time
  // and throws "Bad state: init() has already been called" on any retry
  // (a cancelled attempt, backing out and trying again, a second visit to
  // the sign-in screen). Memoizing the Future — not just guarding with a
  // bool — also covers two taps landing close enough together that the
  // first initialize() hasn't resolved yet, which the docs call out as
  // its own undefined-behavior case.
  static Future<void>? _googleInitialization;

  static Future<void> _ensureGoogleInitialized() {
    _googleInitialization ??= GoogleSignIn.instance
        .initialize(
          serverClientId: _googleWebClientId,
          clientId: _googleIosClientId.isNotEmpty ? _googleIosClientId : null,
        )
        // If initialize() itself throws (e.g. a transient network error),
        // don't leave the failure memoized forever — that would brick
        // Google sign-in for the rest of the session after one hiccup.
        // Only a genuinely *successful* call counts as "the one" the docs
        // require; clearing on failure lets the next attempt retry cleanly.
        .catchError((Object error, StackTrace stackTrace) {
          _googleInitialization = null;
          Error.throwWithStackTrace(error, stackTrace);
        });
    return _googleInitialization!;
  }

  static Future<void> signInWithGoogle() async {
    await _ensureGoogleInitialized();
    final googleSignIn = GoogleSignIn.instance;

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
  }

  static Future<void> signInWithApple() async {
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
  }

  /// Facebook has no equivalent to Google's/Apple's native ID-token flow
  /// generally available on both platforms, so this goes through Supabase's
  /// redirect-based `signInWithOAuth` instead: a browser tab opens for
  /// Facebook's login/consent, then redirects back to `oauthRedirectUrl`,
  /// which the OS hands back to this app (native config in
  /// AndroidManifest.xml / Info.plist makes that handoff possible). Unlike
  /// the ID-token methods above, this returning normally does NOT mean
  /// signed in yet — the app loses foreground focus during the redirect, so
  /// the caller can't just pop on return. The sign-in completing is reported
  /// via `authStateChanges` (`supabase_service.dart`) instead.
  static Future<void> signInWithFacebook() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.facebook,
      redirectTo: kIsWeb ? null : oauthRedirectUrl,
      authScreenLaunchMode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
  }
}
