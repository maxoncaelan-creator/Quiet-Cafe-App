import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/mic_reading.dart';
import '../services/mic_service.dart';
import '../services/observability_service.dart';
import '../services/supabase_service.dart';
import 'skeleton_loader.dart';

/// Captures one fixed, ten-second venue reading directly on the venue detail
/// screen. There is deliberately no stop button: a partial sample would be a
/// misleading picture of the room and is rejected both here and in Postgres.
class VenueLoudnessCapture extends StatefulWidget {
  final String placeId;
  final Future<bool> Function(BuildContext context) ensureSignedIn;
  final VoidCallback onSubmitted;
  final ValueChanged<bool> onRecordingChanged;

  const VenueLoudnessCapture({
    super.key,
    required this.placeId,
    required this.ensureSignedIn,
    required this.onSubmitted,
    required this.onRecordingChanged,
  });

  @override
  State<VenueLoudnessCapture> createState() => _VenueLoudnessCaptureState();
}

class _VenueLoudnessCaptureState extends State<VenueLoudnessCapture> {
  final _micService = MicService();
  final _supabaseService = SupabaseService();
  final List<double> _samples = [];

  Timer? _fiveSecondTimer;
  Timer? _finishTimer;
  bool _starting = false;
  bool _recording = false;
  bool _saving = false;
  DateTime? _startedAt;
  String? _fiveSecondAssessment;
  double? _averageDecibel;
  String? _error;

  @override
  void dispose() {
    _cancelTimers();
    unawaited(_micService.stop());
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting || _recording || _saving) return;

    final signedIn = await widget.ensureSignedIn(context);
    if (!signedIn || !mounted) return;

    setState(() {
      _starting = true;
      _error = null;
      _averageDecibel = null;
      _fiveSecondAssessment = null;
      _samples.clear();
    });

    try {
      await _micService.start(
        (meanDecibel) {
          // The number is intentionally not displayed while recording. It is
          // retained only to calculate the five- and ten-second averages.
          if (_recording) _samples.add(meanDecibel);
        },
        onError: (error) =>
            unawaited(_fail('Lost connection to the microphone: $error')),
      );
    } on MicPermissionDenied {
      if (mounted) {
        setState(
          () {
            _starting = false;
            _error = 'Microphone permission is needed to take a reading.';
          },
        );
      }
      return;
    } catch (error, st) {
      unawaited(ObservabilityService.captureError(error, st,
          context: 'venue_loudness_capture.start'));
      if (mounted) {
        setState(() {
          _starting = false;
          _error = 'Could not start the microphone: $error';
        });
      }
      return;
    }

    if (!mounted || !_starting) {
      await _micService.stop();
      return;
    }

    setState(() {
      _startedAt = DateTime.now();
      _starting = false;
      _recording = true;
    });
    widget.onRecordingChanged(true);
    _fiveSecondTimer = Timer(
      const Duration(seconds: 5),
      _showFiveSecondAssessment,
    );
    _finishTimer = Timer(MicReading.minimumCaptureDuration, _finish);
  }

  void _showFiveSecondAssessment() {
    if (!_recording || !mounted || _samples.isEmpty) return;
    final average = _averageSamples();
    setState(
      () =>
          _fiveSecondAssessment = 'Sounds like it’s ${_loudnessWord(average)}.',
    );
  }

  Future<void> _finish() async {
    if (!_recording) return;

    final startedAt = _startedAt;
    if (startedAt == null) return;
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < MicReading.minimumCaptureDuration) {
      // Timers are allowed to fire fractionally early. Never turn that into a
      // short database sample; wait for the remaining measurement time.
      _finishTimer = Timer(
        MicReading.minimumCaptureDuration - elapsed,
        _finish,
      );
      return;
    }

    _cancelTimers();
    setState(() => _recording = false);
    widget.onRecordingChanged(false);
    await _micService.stop();

    if (!mounted) return;
    if (_samples.isEmpty) {
      setState(() => _error = 'No sound level was captured — try again.');
      return;
    }

    final average = _averageSamples();
    setState(() => _averageDecibel = average);
    final reading = MicReading.capture(
      placeId: widget.placeId,
      decibelValue: average,
      captureDuration: elapsed,
    );

    if (!SupabaseService.isConfigured) {
      setState(
        () => _error =
            'This build is not connected to the live database, so the reading was not submitted.',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _supabaseService.submitMicReading(reading);
      if (!mounted) return;
      widget.onSubmitted();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thanks — your 10-second reading was submitted.'),
        ),
      );
    } on PostgrestException catch (error, st) {
      final isRateLimited = error.message.startsWith('rate_limited:');
      if (!isRateLimited) {
        // A rate-limited submission is the server's mic-reading throttle
        // doing its job, same as a search-assistant rate limit — expected,
        // not reported. Anything else here (an RLS rejection, a constraint
        // failure, an unanticipated Postgrest error) is not.
        unawaited(ObservabilityService.captureError(error, st,
            context: 'venue_loudness_capture.submit'));
      }
      if (!mounted) return;
      final message = isRateLimited
          ? error.message.replaceFirst('rate_limited: ', '')
          : 'Could not submit reading: ${error.message}';
      setState(() => _error = message);
    } catch (error, st) {
      unawaited(ObservabilityService.captureError(error, st,
          context: 'venue_loudness_capture.submit'));
      if (mounted) setState(() => _error = 'Could not submit reading: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _fail(String message) async {
    if (!_starting && !_recording) return;
    final wasRecording = _recording;
    _cancelTimers();
    if (mounted) {
      setState(() {
        _starting = false;
        _recording = false;
        _error = message;
      });
      if (wasRecording) widget.onRecordingChanged(false);
    }
    await _micService.stop();
  }

  void _cancelTimers() {
    _fiveSecondTimer?.cancel();
    _fiveSecondTimer = null;
    _finishTimer?.cancel();
    _finishTimer = null;
  }

  double _averageSamples() =>
      _samples.reduce((a, b) => a + b) / _samples.length;

  String _loudnessWord(double average) {
    if (average < 70) return 'Quiet';
    if (average < 75) return 'Normal';
    return 'Loud';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Take a reading here', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'This measures ambient sound only. No audio is recorded or stored.',
            ),
            const SizedBox(height: 20),
            if (_recording) ...[
              const Center(
                child: SkeletonBox(
                  width: 44,
                  height: 44,
                  borderRadius: BorderRadius.all(Radius.circular(99)),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  _fiveSecondAssessment ?? 'Listening',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please keep this screen open while the 10-second reading finishes.',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall,
              ),
            ] else ...[
              if (_averageDecibel != null)
                Center(
                  child: Text(
                    'Average ${_averageDecibel!.round()} dB',
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: (_starting || _saving) ? null : _start,
                icon: const Icon(Icons.mic),
                label: Text(
                  _starting
                      ? 'Preparing microphone…'
                      : _saving
                          ? 'Submitting…'
                          : (_averageDecibel == null
                              ? 'Start 10-second reading'
                              : 'Take another 10-second reading'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
