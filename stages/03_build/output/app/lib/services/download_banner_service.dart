// Mirrors theme_service.dart's static-class-plus-ValueNotifier pattern —
// tracks whether the "get the app" banner has been dismissed, persisted so
// it doesn't reappear every visit.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadBannerService {
  static const _prefsKey = 'download_banner_dismissed';
  static final ValueNotifier<bool> dismissed = ValueNotifier(false);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    dismissed.value = prefs.getBool(_prefsKey) ?? false;
  }

  static Future<void> dismiss() async {
    dismissed.value = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }
}
