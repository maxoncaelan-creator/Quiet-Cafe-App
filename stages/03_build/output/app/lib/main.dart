import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'router.dart';
import 'screens/beta_gate_screen.dart';
import 'services/beta_gate_service.dart';
import 'services/download_banner_service.dart';
import 'services/supabase_service.dart';
import 'services/theme_service.dart';
import 'widgets/download_app_banner.dart';

// Same hue used to build the Figma color-role variables (see
// ui-design-decisions.md) — ColorScheme.fromSeed derives the full M3 tonal
// palette from this one value, the same mechanism used to build that file,
// so this is the source of truth now, not a hand-ported copy of it.
const _seedColor = Color(0xFF006874);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) usePathUrlStrategy(); // plain /restaurant/abc URLs, not /#/restaurant/abc
  await SupabaseService.initialize(); // no-op if SUPABASE_URL/SUPABASE_ANON_KEY aren't set — see supabase_service.dart
  await ThemeService.load();
  await DownloadBannerService.load();
  // Closed-beta referral gate (2026-08-20): skipped entirely when Supabase
  // isn't configured, so the no-backend standalone/demo build documented in
  // PLATFORM_SETUP.md keeps working without a code. Otherwise, checked once
  // at launch — BetaGateScreen itself re-checks the server on submission,
  // this local flag just avoids asking again once a device has unlocked.
  final betaUnlocked = !SupabaseService.isConfigured || await BetaGateService.isUnlocked();
  runApp(QuietRestaurantFinderApp(initialBetaUnlocked: betaUnlocked));
}

class QuietRestaurantFinderApp extends StatefulWidget {
  final bool initialBetaUnlocked;

  const QuietRestaurantFinderApp({super.key, required this.initialBetaUnlocked});

  @override
  State<QuietRestaurantFinderApp> createState() => _QuietRestaurantFinderAppState();
}

class _QuietRestaurantFinderAppState extends State<QuietRestaurantFinderApp> {
  StreamSubscription<AuthState>? _authSubscription;
  late bool _betaUnlocked = widget.initialBetaUnlocked;

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
  /// before any particular screen is guaranteed mounted.
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
        final theme = ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
          useMaterial3: true,
        );
        final darkTheme = ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: _seedColor, brightness: Brightness.dark),
          useMaterial3: true,
        );

        if (!_betaUnlocked) {
          // No router, no drawer, nothing else reachable — the whole point
          // of a hard-block gate is that there's genuinely nothing behind
          // it to navigate to yet.
          return MaterialApp(
            title: 'Quiet Restaurant Finder',
            themeMode: themeMode,
            theme: theme,
            darkTheme: darkTheme,
            home: BetaGateScreen(onUnlocked: () => setState(() => _betaUnlocked = true)),
          );
        }

        return MaterialApp.router(
          title: 'Quiet Restaurant Finder',
          themeMode: themeMode,
          theme: theme,
          darkTheme: darkTheme,
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
