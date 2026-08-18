// Supabase's own "weak password" rejection dumps the full allowed
// character sets verbatim — "Password should contain at least one
// character of each: abcdefghijklmnopqrstuvwxyz, ABCDEFG...,
// 0123456789, !@#$%^&*()..." — which reads as confusing noise, not a
// requirement. Caelan's call (2026-08-18): the policy itself is
// intentional and correct (upper/lower/digit/symbol required, set in the
// Supabase dashboard's Auth settings, not in this app's code) — only the
// message shown for it needed rewriting.

import 'package:supabase_flutter/supabase_flutter.dart';

/// Returns a clean message for this specific rejection, or null if `error`
/// isn't that — callers fall back to their own normal error formatting.
String? friendlyPasswordPolicyError(Object error) {
  if (error is AuthException && error.message.toLowerCase().contains('password should contain')) {
    return 'Password must contain at least one uppercase letter, one lowercase letter, one number, and one special character.';
  }
  return null;
}
