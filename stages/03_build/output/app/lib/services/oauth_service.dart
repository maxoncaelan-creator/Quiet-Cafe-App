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

  // Set alongside _googleInitialization, once, the first time this runs —
  // see the nonce comment on initialize() below for why it lives here
  // rather than being generated fresh per sign-in attempt.
  static String? _googleRawNonce;

  static Future<void> _ensureGoogleInitialized() {
    if (_googleInitialization == null) {
      // Found live 2026-08-19 (Caelan): signInWithIdToken failed with
      // "Passed nonce and nonce in id_token should either both exist or
      // not" — google_sign_in's initialize() embeds `nonce` into every ID
      // token it subsequently produces (see its doc comment), but this call
      // wasn't passing one, so Supabase saw a nonce claim in the token with
      // nothing supplied to check it against. Same rawNonce/hashedNonce
      // pattern signInWithApple() already uses below, adapted to this
      // package's shape: Apple takes a nonce per call, but
      // GoogleSignIn.instance.initialize() only accepts one at
      // initialization time and reuses it for every authenticate() call for
      // the lifetime of this singleton (its own contract: call exactly
      // once) — so the raw nonce is generated here, once, and stashed for
      // completeGoogleSignIn() to pass to signInWithIdToken later, rather
      // than minted fresh per attempt the way Apple's is.
      final rawNonce = _client.auth.generateRawNonce();
      _googleRawNonce = rawNonce;
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      _googleInitialization = GoogleSignIn.instance
          .initialize(
            // The actual root cause of the "Null check operator" crash,
            // found 2026-08-19 after the accessToken fix below didn't make it
            // go away: google_sign_in_web's init() only ever reads
            // `params.clientId` (falling back to a <meta
            // name="google-signin-client_id"> tag this app's web/index.html
            // doesn't have) — it ignores `serverClientId` entirely and even
            // asserts it must be null on web. Passing the web client ID as
            // serverClientId (correct on iOS/Android, where it sets the ID
            // token's audience to match what Supabase's Google provider is
            // configured with) left `clientId` null on web specifically,
            // so google_sign_in_web's own `appClientId!` — unguarded, no
            // fallback error — is what actually threw. Splitting the
            // parameter by platform fixes both without changing native
            // behavior.
            serverClientId: kIsWeb ? null : _googleWebClientId,
            clientId: kIsWeb
                ? _googleWebClientId
                : (_googleIosClientId.isNotEmpty ? _googleIosClientId : null),
            nonce: hashedNonce,
          )
          // If initialize() itself throws (e.g. a transient network error),
          // don't leave the failure memoized forever — that would brick
          // Google sign-in for the rest of the session after one hiccup.
          // Only a genuinely *successful* call counts as "the one" the docs
          // require; clearing on failure lets the next attempt retry cleanly.
          .catchError((Object error, StackTrace stackTrace) {
            _googleInitialization = null;
            _googleRawNonce = null;
            Error.throwWithStackTrace(error, stackTrace);
          });
    }
    return _googleInitialization!;
  }

  /// Mobile only — see GoogleAuthButton (widgets/google_auth_button.dart)
  /// for why this can't be shared with web: google_sign_in_web explicitly
  /// throws `UnimplementedError` from `authenticate()` (confirmed live
  /// 2026-08-19, Caelan: "authenticate is not supported on the web.
  /// Instead, use renderButton to create a sign-in widget.") — this isn't a
  /// bug like the previous two Google issues this session, it's the
  /// documented, intentional design of Google's own web SDK: only Google's
  /// own rendered button can start the flow on web, not an imperative call
  /// from a custom one. `google_auth_button_web.dart` covers web via
  /// `renderButton()` + `googleAuthenticationEvents`/
  /// `completeGoogleSignIn()` below instead of calling this at all.
  static Future<void> signInWithGoogle() async {
    await _ensureGoogleInitialized();
    final googleUser = await GoogleSignIn.instance.authenticate();
    await completeGoogleSignIn(googleUser);
  }

  /// Shared tail for both sign-in paths: mobile's `signInWithGoogle()`
  /// (from `authenticate()`'s return value) and web's
  /// `GoogleAuthButton`/`google_auth_button_web.dart` (from a
  /// `GoogleSignInAuthenticationEventSignIn` on `googleAuthenticationEvents`
  /// — Google's own rendered button drives this, not app code).
  static Future<void> completeGoogleSignIn(GoogleSignInAccount googleUser) async {
    const scopes = ['email', 'profile'];
    // Best-effort only — Supabase's signInWithIdToken doesn't require an
    // access token (accessToken is nullable there), and nothing else in
    // this app uses the Google access token, so a failure requesting it
    // shouldn't fail the sign-in itself. Found live 2026-08-19 (Caelan):
    // google_sign_in_web 1.1.3 has a real bug here — its token-client
    // response handler does `response.expires_in!` with no null check
    // (gis_client.dart), which throws "Null check operator used on a null
    // value" whenever Google's token response omits expires_in. Can't fix
    // the package itself, so this catches it (and anything else that can
    // go wrong in this step) and falls back to accessToken: null rather
    // than blocking sign-in on a token this app doesn't actually use.
    String? accessToken;
    try {
      // authorizationForScopes returns null if the user hasn't already
      // granted these scopes (e.g. first sign-in) — falls back to
      // authorizeScopes, which prompts for consent.
      final authorization = await googleUser.authorizationClient.authorizationForScopes(scopes) ??
          await googleUser.authorizationClient.authorizeScopes(scopes);
      accessToken = authorization.accessToken;
    } catch (_) {
      // Swallowed deliberately — see comment above. The ID token alone is
      // enough for signInWithIdToken to establish a real session.
    }
    final idToken = googleUser.authentication.idToken;

    if (idToken == null) {
      throw Exception('Google did not return an ID token.');
    }

    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
      nonce: _googleRawNonce,
    );
  }

  /// Web only, added 2026-08-19 to replace the ID-token/GIS-button approach
  /// entirely, after it produced five separate real bugs in a row across
  /// two sessions (re-init crash, unguarded null-check, wrong init param on
  /// web, authenticate() unsupported on web by design, then this nonce
  /// mismatch) — each one a genuinely different failure mode in
  /// google_sign_in_web's web integration, not the same bug recurring. Root
  /// cause wasn't any single one of those; it's that the ID-token flow
  /// forces this app to reimplement Google's web integration itself
  /// (button rendering, a once-per-session init contract, manual nonce
  /// wiring). Switching to Supabase's redirect-based signInWithOAuth here
  /// — the exact mechanism signInWithFacebook() already uses below —
  /// removes all of that: no Flutter-side Google SDK involved on web at
  /// all, Supabase's own server completes the OAuth exchange with Google
  /// and redirects back. Deliberately NOT touching signInWithGoogle()
  /// above: the native ID-token flow is confirmed working end to end on
  /// Android already, so mobile has no reason to change.
  static Future<void> signInWithGoogleOAuth() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      authScreenLaunchMode: LaunchMode.platformDefault,
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
