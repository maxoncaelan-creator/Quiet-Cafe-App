// Wraps the noise_meter package for on-device decibel metering.
// Reads ambient sound level only (meanDecibel/maxDecibel from the device
// microphone's amplitude stream) — no audio is recorded or stored, per the
// privacy constraint in the PRD.

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
  /// level, or [onError] if the underlying platform stream fails (e.g. on a
  /// platform audio_streamer doesn't support, like web — confirmed by
  /// testing: this previously failed silently with no readings and no
  /// visible error, which looked indistinguishable from "nothing happened
  /// when I tapped the button"). Call [stop] when the user finishes taking
  /// a reading.
  Future<void> start(
    void Function(double meanDecibel) onReading, {
    required void Function(Object error) onError,
  }) async {
    await ensurePermission();
    _subscription = _noiseMeter.noise.listen(
      (NoiseReading reading) => onReading(reading.meanDecibel),
      onError: onError,
      cancelOnError: true,
    );
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
