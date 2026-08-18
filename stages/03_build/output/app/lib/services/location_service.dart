// Backs the Search Assistant screen's "Are you at X?" guess — added
// 2026-08-18 per Caelan. This app has no other use for location, so this
// stays narrow: get the current position (or null, if that's not possible
// right now for any reason), plus the local "don't ask again for 30
// minutes" cooldown after the user says no. Not a general-purpose location
// API.

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationService {
  static const _dismissedAtPrefsKey = 'venue_guess_dismissed_at';

  /// How long to wait before guessing again after the user says "No" to a
  /// guess — Caelan's number, not derived from anything.
  static const dismissCooldown = Duration(minutes: 30);

  /// The device's current position, or null if unavailable for any reason
  /// — permission denied/restricted, the location service itself is off,
  /// or the lookup times out. Callers should treat null as "just don't
  /// guess," not an error to surface — this is a convenience feature.
  Future<Position?> getCurrentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return null;
    }

    try {
      // timeLimit tells the platform side itself to give up after 8s, not
      // just this Dart Future — found by testing live: a poor/absent
      // network fix can leave the underlying Play Services location
      // request retrying well past any wrapper-level timeout, pinning the
      // CPU badly enough to make the whole app appear hung. A bounded
      // native request is the actual fix; the outer .timeout() is a second
      // line of defense, not the primary one.
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 8)),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    }
  }

  /// Meters between two coordinates — thin wrapper so callers matching
  /// this against restaurant lat/lng don't need their own Geolocator import.
  static double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  }

  static Future<bool> canGuessAgain() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt(_dismissedAtPrefsKey);
    if (millis == null) return true;
    final dismissedAt = DateTime.fromMillisecondsSinceEpoch(millis);
    return DateTime.now().difference(dismissedAt) >= dismissCooldown;
  }

  static Future<void> recordDismissal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dismissedAtPrefsKey, DateTime.now().millisecondsSinceEpoch);
  }
}
