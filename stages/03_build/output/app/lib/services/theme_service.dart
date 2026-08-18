// Dark mode toggle, controlled from Settings → Display. Local-only for now
// (SharedPreferences) — no cross-device sync was asked for.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService {
  static const _prefsKey = 'theme_mode';

  /// The whole app listens to this via ValueListenableBuilder in main.dart.
  /// Defaults to light, not system — the Settings toggle is a plain on/off
  /// switch, not a three-way system/light/dark picker, so the app's actual
  /// theme should never silently diverge from what the switch shows.
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.light);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    mode.value = stored == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }

  static Future<void> setDarkMode(bool enabled) async {
    mode.value = enabled ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, enabled ? 'dark' : 'light');
  }

  static bool get isDark => mode.value == ThemeMode.dark;
}
