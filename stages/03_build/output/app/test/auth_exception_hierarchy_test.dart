// Guards the external invariant that issue #69's fix depends on.
//
// gotrue throws AuthRetryableFetchException from its transport layer on a
// network failure, and that class *extends* AuthException. Every auth screen
// here catches AuthException to show an expected, user-caused error — a wrong
// password, a rejected sign-up — and deliberately does not report those to
// Sentry. So a transport failure silently arrived as an expected credential
// error and was never reported. In change_password_screen it was worse than
// silent: the user was told "Current password is incorrect." when nothing had
// reached the server to check it.
//
// The fix is ordering: catch AuthRetryableFetchException *before*
// AuthException at every one of those sites. That ordering is only necessary
// because of the subclass relationship asserted below — and only correct
// while it holds.
//
// If a future supabase_flutter upgrade makes AuthRetryableFetchException a
// sibling rather than a subclass, this test fails, and that is the signal to
// revisit the ordering rather than discover the regression in production.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('gotrue exception hierarchy', () {
    test('AuthRetryableFetchException is an AuthException', () {
      final error = AuthRetryableFetchException(message: 'network failure');
      expect(error, isA<AuthException>(),
          reason: 'If this ever fails, the catch ordering in '
              'sign_in_email_screen, create_account_password_screen and '
              'change_password_screen can be simplified — see issue #69.');
    });

    test('a plain AuthException is not retryable', () {
      // The other half of the distinction: an ordinary credential rejection
      // must NOT match the retryable branch, or every wrong password would
      // start reporting to Sentry — the noise issue #67 set out to avoid.
      expect(const AuthException('Invalid login credentials'),
          isNot(isA<AuthRetryableFetchException>()));
    });
  });
}
