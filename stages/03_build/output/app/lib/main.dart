import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'router.dart';
import 'services/download_banner_service.dart';
import 'services/observability_service.dart';
import 'services/supabase_service.dart';
import 'services/theme_service.dart';
import 'widgets/download_app_banner.dart';

// Same hue used to build the Figma color-role variables (see
// ui-design-decisions.md) — ColorScheme.fromSeed derives the full M3 tonal
// palette from this one value, the same mechanism used to build that file,
// so this is the source of truth now, not a hand-ported copy of it.
const _seedColor = Color(0xFF006874);

void main() async {
  // Sentry wraps the rest of startup so an error thrown during initialisation
  // is reported too — those are the ones that leave a tester staring at a
  // blank screen with nothing to tell us. No-op without a SENTRY_DSN
  // dart-define, so CI and the standalone build are unaffected.
  await ObservabilityService.runApp(() async {
    WidgetsFlutterBinding.ensureInitialized();
    if (kIsWeb) usePathUrlStrategy(); // plain /restaurant/abc URLs, not /#/restaurant/abc
    await SupabaseService.initialize(); // no-op if SUPABASE_URL/SUPABASE_ANON_KEY aren't set — see supabase_service.dart
    await ThemeService.load();
    await DownloadBannerService.load();
    // ProviderScope is added here in step 0 so step 3's incremental Riverpod
    // migration has a root to attach to. Nothing reads from it yet — see
    // execution-plan-2026-08-23.md.
    runApp(const ProviderScope(child: QuietRestaurantFinderApp()));
  });
}

class QuietRestaurantFinderApp extends StatefulWidget {
  const QuietRestaurantFinderApp({super.key});

  @override
  State<QuietRestaurantFinderApp> createState() => _QuietRestaurantFinderAppState();
}

class _QuietRestaurantFinderAppState extends State<QuietRestaurantFinderApp> {
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    // Global, not screen-scoped — the recovery link (tapped from an email,
    // possibly cold-launching the app) can land while any screen happens to
    // be on top, so this can't live inside one screen's State the way
    // home_screen.dart's own auth listener does. Mic calibration (added
    // 2026-08-19) piggybacks on the same listener for the same reason: it
    // needs to fire regardless of which screen someone's on, both right
    // after a fresh sign-in (signedIn) and when an already-persisted
    // session is restored on cold launch (initialSession — supabase_flutter
    // emits this once on subscribe, which is what makes the "every 3
    // months" recheck work without requiring an actual new sign-in event).
    if (SupabaseService.isConfigured) {
      _authSubscription = SupabaseService().authStateChanges.listen((state) {
        if (state.event == AuthChangeEvent.passwordRecovery) {
          appRouter.push('/reset-password');
        }
        if (state.event == AuthChangeEvent.signedIn || state.event == AuthChangeEvent.initialSession) {
          _maybeShowMicCalibration();
        }
      });
    }
  }

  /// Due if the signed-in user has never calibrated, or their last
  /// calibration was more than ~3 months (90 days) ago. Push happens on the
  /// GoRouter directly (not via a screen's context) since this can fire
  /// before any particular screen is guaranteed mounted. During the closed
  /// beta, router.dart's gate redirect intercepts this push the same as any
  /// other navigation if the account hasn't cleared the gate yet — correct,
  /// since calibration shouldn't happen before beta access is confirmed.
  Future<void> _maybeShowMicCalibration() async {
    if (!SupabaseService().isSignedIn) return;
    final lastCalibration = await SupabaseService().fetchLatestCalibrationAt();
    final due = lastCalibration == null || DateTime.now().difference(lastCalibration) >= const Duration(days: 90);
    if (due) appRouter.push('/mic-calibration');
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.mode,
      builder: (context, themeMode, _) {
        return MaterialApp.router(
          title: 'Quiet Restaurant Finder',
          themeMode: themeMode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: _seedColor, brightness: Brightness.dark),
            useMaterial3: true,
          ),
          routerConfig: appRouter,
          builder: (context, child) => Column(
            children: [
              const DownloadAppBanner(),
              Expanded(child: child!),
            ],
          ),
        );
      },
    );
  }
}
