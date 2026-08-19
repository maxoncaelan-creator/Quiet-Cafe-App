// Platform-conditional export, added 2026-08-19 — Google's web SDK doesn't
// allow a custom button to imperatively trigger sign-in the way
// GoogleSignInButton + OAuthService.signInWithGoogle() does on mobile.
// google_sign_in_web's authenticate() throws UnimplementedError outright:
// "authenticate is not supported on the web. Instead, use renderButton to
// create a sign-in widget." (confirmed live, Caelan). So web needs a
// genuinely different widget — Google's own rendered button, completion
// reported via a stream rather than an awaited call — behind the same
// GoogleAuthButton API both auth_screen.dart and create_account_screen.dart
// use, so neither screen needs to know which platform it's on.
//
// dart.library.html is Flutter's standard "am I compiling for web"
// conditional-import flag — same pattern as mic_service.dart earlier this
// session, for the same reason (google_auth_button_web.dart's
// google_sign_in_web import isn't meant to compile for a native target).
export 'google_auth_button_io.dart' if (dart.library.html) 'google_auth_button_web.dart';
