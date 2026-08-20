// Local (on-device) half of the closed-beta referral gate — added
// 2026-08-20. The server side (redeem_beta_code RPC, beta_codes table) is
// the actual source of truth for whether a code is valid; this just
// remembers "this device already unlocked" so the gate doesn't ask again
// on every launch, and gives redeem_beta_code() something to tell "the
// same device redeeming again" apart from "a different device trying the
// same code" with.
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class BetaGateService {
  static const _unlockedKey = 'beta_access_unlocked';
  static const _deviceIdKey = 'beta_device_id';

  static Future<bool> isUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_unlockedKey) ?? false;
  }

  static Future<void> markUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_unlockedKey, true);
  }

  /// A random id generated once and persisted per install — not a real
  /// hardware identifier, and doesn't need to be: all redeem_beta_code()
  /// needs from this is a stable value that survives app restarts on the
  /// same phone but differs across phones.
  static Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null) {
      final rand = Random.secure();
      id = List.generate(16, (_) => rand.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString(_deviceIdKey, id);
    }
    return id;
  }
}
