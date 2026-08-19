// Wraps the noise_meter package for on-device decibel metering.
// Reads ambient sound level only (meanDecibel/maxDecibel from the device
// microphone's amplitude stream) — no audio is recorded or stored, per the
// privacy constraint in the PRD. Mobile/desktop only — see mic_service.dart
// for why (audio_streamer, which noise_meter wraps, declares no web
// platform at all) and mic_service_web.dart for the web equivalent.

import 'dart:async';

import 'package:noise_meter/noise_meter.dart';
import 'package:permission_handler/permission_handler.dart';

class MicPermissionDenied implements Exception {}

class MicService {
  final NoiseMeter _noiseMeter = NoiseMeter();
  StreamSubscription<NoiseReading>? _subscription;

  /// Requests microphone permission if needed. Throws [MicPermissionDenied]
  /// if the user declines — the caller should show the app's own honest
  /// explanation before this triggers the OS prompt (App Store / Play Store
  /// review both expect a specific purpose string, not a generic one).
  Future<void> ensurePermission() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      throw MicPermissionDenied();
    }
  }

  /// Starts metering and calls [onReading] with each sample's mean decibel
  /// level, or [onError] if the underlying platform stream fails. Call
  /// [stop] when the user finishes taking a reading.
  Future<void> start(
    void Function(double meanDecibel) onReading, {
    required void Function(Object error) onError,
  }) async {
    await ensurePermission();
    _subscription = _noiseMeter.noise.listen(
      (NoiseReading reading) {
        // meanDecibel is 20*log10(amplitude) under the hood, so true
        // silence (zero amplitude — confirmed to happen on the Android
        // emulator, whose virtual mic can fail to deliver real frames) is
        // mathematically -Infinity, not a small number. That crashed the
        // UI's rounding unguarded. A silent room is exactly what this app
        // is meant to detect, so clamp instead of dropping the sample.
        final value = reading.meanDecibel;
        onReading(value.isFinite ? value : 0);
      },
      onError: onError,
      cancelOnError: true,
    );
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
