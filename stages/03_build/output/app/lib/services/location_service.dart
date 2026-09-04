// Backs the Search Assistant screen's "Are you at X?" guess — added
// 2026-08-18 per Caelan, recovered 2026-08-20 from the stale
// feature/loudness-votes-and-venue-guess branch (built and partially
// live-verified there, never merged — see build-log.md). This app has no
// other use for location, so this stays narrow: get the current position
// (or null, if that's not possible right now for any reason), plus the
// local "don't ask again for 30 minutes" cooldown after the user says no.
// Not a general-purpose location API.

import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'observability_service.dart';

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
      // just this Dart Future — found by testing live 2026-08-18: a
      // poor/absent network fix can leave the underlying Play Services
      // location request retrying well past any wrapper-level timeout,
      // pinning the CPU badly enough to make the whole app appear hung
      // (a real ANR). A bounded native request is the actual fix; the
      // outer .timeout() is a second line of defense, not the primary one.
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 8)),
      ).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      // A slow or absent GPS fix is routine (weak signal, indoors) — not a
      // bug worth reporting, just this convenience feature not working out.
      return null;
    } catch (e, st) {
      // Anything else here — a platform channel throwing, an unexpected
      // Geolocator failure — is not the routine case above.
      await ObservabilityService.captureError(e, st,
          context: 'location.get_current_position');
      return null;
    }
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
