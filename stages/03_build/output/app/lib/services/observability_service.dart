import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

// Supplied at build time, same convention as SUPABASE_URL/SUPABASE_ANON_KEY in
// supabase_service.dart — see PLATFORM_SETUP.md. A Sentry DSN is not a secret
// (it ships inside every released binary and only permits *sending* events),
// but it still differs per environment, so it stays out of the source.
// Example: flutter run --dart-define=SENTRY_DSN=https://...@o0.ingest.sentry.io/0
const _sentryDsn = String.fromEnvironment('SENTRY_DSN');

/// Crash and error reporting.
///
/// Deliberately a no-op when no DSN is supplied, mirroring
/// [SupabaseService.initialize]'s behaviour. That keeps three things working
/// untouched: `flutter test`, hosted CI, and the standalone demo build that
/// runs without any backend at all. Adding Sentry must not become a new
/// required build input.
class ObservabilityService {
  ObservabilityService._();

  static bool get isConfigured => _sentryDsn.isNotEmpty;

  /// Runs [appRunner] with error reporting attached when configured, and
  /// plainly when it isn't.
  ///
  /// Sentry's own guidance is to run the app inside its zone so uncaught async
  /// errors are captured too; `SentryFlutter.init` does that via `appRunner`.
  /// When unconfigured we simply call [appRunner] directly rather than
  /// initialising a disabled client, so no Sentry zone or integration is
  /// installed at all.
  static Future<void> runApp(FutureOr<void> Function() appRunner) async {
    if (!isConfigured) {
      await appRunner();
      return;
    }

    await SentryFlutter.init(
      (options) {
        options.dsn = _sentryDsn;

        // Release builds only send a fraction; debug sends everything so a
        // local repro actually shows up. Tracing stays off — this is for
        // crashes, not performance, and traces consume the free quota fast.
        options.tracesSampleRate = 0.0;
        options.environment = kDebugMode ? 'debug' : 'production';
        options.debug = false;

        // Beta testers have not consented to their identity being attached to
        // an error, and we never need it to fix a crash. This must stay false
        // unless Caelan decides otherwise and the privacy policy says so —
        // see SENTRY_SETUP.md.
        options.sendDefaultPii = false;

        // Screenshots can contain a tester's search text and location. Same
        // reasoning as above. View-hierarchy capture is off by default and its
        // option is still marked experimental, so it is left alone rather than
        // set explicitly — setting it trips `experimental_member_use` and this
        // project keeps `flutter analyze` clean.
        options.attachScreenshot = false;
      },
      appRunner: appRunner,
    );
  }

  /// Reports a handled error that the user was shown a friendly message for.
  ///
  /// Silently drops the event when unconfigured, so callers never need to
  /// check first.
  static Future<void> captureError(
    Object error,
    StackTrace? stackTrace, {
    String? context,
  }) async {
    if (!isConfigured) return;
    await Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: context == null
          ? null
          : (scope) => scope.setContexts('operation', {'name': context}),
    );
  }
}
