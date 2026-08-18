import 'package:flutter/material.dart';

import 'screens/search_assistant_screen.dart';
import 'services/supabase_service.dart';
import 'services/theme_service.dart';

// Same hue used to build the Figma color-role variables (see
// ui-design-decisions.md) — ColorScheme.fromSeed derives the full M3 tonal
// palette from this one value, the same mechanism used to build that file,
// so this is the source of truth now, not a hand-ported copy of it.
const _seedColor = Color(0xFF006874);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize(); // no-op if SUPABASE_URL/SUPABASE_ANON_KEY aren't set — see supabase_service.dart
  await ThemeService.load();
  runApp(const QuietRestaurantFinderApp());
}

class QuietRestaurantFinderApp extends StatelessWidget {
  const QuietRestaurantFinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.mode,
      builder: (context, themeMode, _) {
        return MaterialApp(
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
          home: const SearchAssistantScreen(),
        );
      },
    );
  }
}
