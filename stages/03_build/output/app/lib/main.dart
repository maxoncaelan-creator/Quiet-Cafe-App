import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'router.dart';
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
  runApp(const QuietRestaurantFinderApp());
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
    // home_screen.dart's own auth listener does.
    if (SupabaseService.isConfigured) {
      _authSubscription = SupabaseService().authStateChanges.listen((state) {
        if (state.event == AuthChangeEvent.passwordRecovery) {
          appRouter.push('/reset-password');
        }
      });
    }
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
