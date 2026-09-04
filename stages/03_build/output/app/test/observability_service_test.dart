// Every catch site wired to ObservabilityService.captureError in this
// change relies on the same two guarantees: it is a no-op without a
// configured DSN (true for every `flutter test` run, since SENTRY_DSN is
// never passed via --dart-define here), and it never throws — none of the
// ~30 call sites added alongside this file guard the call with its own
// try/catch or an isConfigured check first. This file is the only direct
// coverage of ObservabilityService itself; it existed with zero tests
// before this change.
//
// What this does NOT prove: that a captureError call at any individual site
// fires with the arguments intended, or that a configured build actually
// delivers an event to Sentry. captureError is static, so a call site can't
// be intercepted from a test without either giving ObservabilityService an
// injectable seam (a bigger change than wiring call sites) or wrapping every
// call in something to record it (which would go beyond what the ~30 sites
// themselves need). See the PR description for the same caveat.

import 'package:flutter_test/flutter_test.dart';
import 'package:quiet_restaurant_finder/services/observability_service.dart';

void main() {
  test('is not configured without a SENTRY_DSN define', () {
    expect(ObservabilityService.isConfigured, isFalse);
  });

  test('captureError completes without throwing when unconfigured', () async {
    // The exact shape every wired catch block depends on: it can call this
    // unconditionally, with no isConfigured guard of its own.
    await expectLater(
      ObservabilityService.captureError(
        Exception('boom'),
        StackTrace.current,
        context: 'test.smoke',
      ),
      completes,
    );
  });

  test('captureError completes when passed a null stack trace', () async {
    // A couple of call sites (stream/callback onError handlers with no
    // stack trace available) pass null — confirm that's accepted too.
    await expectLater(
      ObservabilityService.captureError(Exception('boom'), null),
      completes,
    );
  });

  test('captureError completes with no context supplied', () async {
    await expectLater(
      ObservabilityService.captureError(Exception('boom'), null),
      completes,
    );
  });

  test('runApp calls the runner directly and returns its result when unconfigured', () async {
    var ran = false;
    await ObservabilityService.runApp(() {
      ran = true;
    });
    expect(ran, isTrue);
  });
}
