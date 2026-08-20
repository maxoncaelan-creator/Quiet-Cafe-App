// Real browser microphone capture via the Web Audio API — added 2026-08-19.
// audio_streamer (which mic_service_io.dart's noise_meter wraps) declares
// no web platform at all, so this is a from-scratch implementation, not a
// gated-off stub: getUserMedia for the raw audio stream, an AnalyserNode
// for time-domain amplitude samples, RMS -> dB the same way noise_meter
// does it so both platforms feed scoring.js's micSubscore the same
// dBA-shaped scale.
//
// Fixed 2026-08-20: this previously computed 20*log10(rms) directly, which
// is dBFS (decibels relative to *full scale*, where 1.0 = 0dB) — negative
// for any rms below 1.0, which is essentially always, since normalized
// samples live in roughly [-1, 1]. That's why readings showed up negative
// (Caelan reported this live). noise_meter's own source
// (package:noise_meter's NoiseReading, wrapping audio_streamer) computes
// 20*log10(maxAmp * amplitude) with maxAmp = 2^15 (32768, the max value of
// a 16-bit PCM sample) — i.e. it rescales the normalized amplitude back up
// before taking the log, which is what actually lands it in the same
// positive, real-world-plausible dB range native readings produce. Applying
// the same maxAmp factor here is what "the same way noise_meter does it"
// was always supposed to mean; the multiplication was just missing.
//
// No audio is recorded or stored — same privacy constraint as the native
// path, just enforced by never calling anything but getByteTimeDomainData
// on the analyser.

import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class MicPermissionDenied implements Exception {}

class MicService {
  web.MediaStream? _stream;
  web.AudioContext? _audioContext;
  Timer? _timer;

  /// No separate permission-check step on web — getUserMedia() itself
  /// triggers the browser's own prompt. A denial surfaces as an exception
  /// from start() instead (caught there and rethrown as
  /// [MicPermissionDenied]), so this is a no-op kept only to match
  /// mic_service_io.dart's interface.
  Future<void> ensurePermission() async {}

  Future<void> start(
    void Function(double meanDecibel) onReading, {
    required void Function(Object error) onError,
  }) async {
    final web.MediaStream stream;
    try {
      stream = await web.window.navigator.mediaDevices
          .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
          .toDart;
    } catch (_) {
      throw MicPermissionDenied();
    }
    _stream = stream;

    final audioContext = web.AudioContext();
    _audioContext = audioContext;
    final source = audioContext.createMediaStreamSource(stream);
    final analyser = audioContext.createAnalyser();
    analyser.fftSize = 2048;
    source.connect(analyser);

    final buffer = Uint8List(analyser.frequencyBinCount);

    // Polled rather than driven by an animation frame — this has no visible
    // frame to sync with, and a fixed interval matches noise_meter's own
    // stream-of-samples shape closely enough for take_reading_screen.dart
    // (which just averages whatever samples arrive) to need no changes.
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      try {
        analyser.getByteTimeDomainData(buffer.toJS);
        var sumSquares = 0.0;
        for (final sample in buffer) {
          final normalized = (sample - 128) / 128.0;
          sumSquares += normalized * normalized;
        }
        final rms = math.sqrt(sumSquares / buffer.length);
        // Matches noise_meter's own calibration exactly (NoiseReading in
        // package:noise_meter) — see the file-header comment for why this
        // factor is what turns a negative dBFS-style result into the same
        // positive scale native readings use.
        const maxAmp = 32768.0; // 2^15
        final db = rms > 0 ? 20 * math.log(maxAmp * rms) / math.ln10 : 0.0;
        onReading(db.isFinite ? db : 0);
      } catch (e) {
        onError(e);
      }
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    for (final track in _stream?.getTracks().toDart ?? const []) {
      track.stop();
    }
    await _audioContext?.close().toDart;
    _stream = null;
    _audioContext = null;
  }
}
