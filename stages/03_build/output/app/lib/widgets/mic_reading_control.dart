// The whole take-a-reading interaction, inline on the restaurant detail
// screen — replaces the old separate "Reading at X" screen entirely
// (Caelan's call, 2026-08-18: that screen shouldn't exist; capture and
// submit should happen right where the button already is). A tap starts a
// fixed-length capture; the button's own color and pulsing state carry the
// phase (idle/recording/finished) instead of navigating anywhere.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/mic_reading.dart';
import '../services/mic_service.dart';
import '../services/supabase_service.dart';
import 'pulsing_mic_button.dart';

enum _Phase { idle, recording, finished }

class MicReadingControl extends StatefulWidget {
  final String placeId;

  /// Prompts sign-in if needed (same gate the old TakeReadingScreen used)
  /// and reports back whether the user is signed in afterward.
  final Future<bool> Function(BuildContext context) ensureSignedIn;

  const MicReadingControl({super.key, required this.placeId, required this.ensureSignedIn});

  @override
  State<MicReadingControl> createState() => _MicReadingControlState();
}

class _MicReadingControlState extends State<MicReadingControl> {
  // "For a while" — long enough to average out a couple of seconds of
  // ambient sound, short enough not to feel like a stuck button.
  static const _captureDuration = Duration(seconds: 5);
  static const _restDuration = Duration(seconds: 4);

  final _micService = MicService();
  final _supabaseService = SupabaseService();

  _Phase _phase = _Phase.idle;
  double? _currentDb;
  final List<double> _samples = [];
  String? _resultMessage;
  Timer? _captureTimer;
  Timer? _restTimer;

  @override
  void dispose() {
    _captureTimer?.cancel();
    _restTimer?.cancel();
    _micService.stop();
    super.dispose();
  }

  Future<void> _start() async {
    if (_phase != _Phase.idle) return;

    final signedIn = await widget.ensureSignedIn(context);
    if (!signedIn || !mounted) return;

    setState(() {
      _phase = _Phase.recording;
      _currentDb = null;
      _samples.clear();
      _resultMessage = null;
    });

    try {
      await _micService.start(
        (meanDecibel) {
          if (!mounted) return;
          setState(() {
            _currentDb = meanDecibel;
            _samples.add(meanDecibel);
          });
        },
        onError: (error) {
          if (!mounted) return;
          _finish('Lost connection to the microphone: $error');
        },
      );
    } on MicPermissionDenied {
      _finish('Microphone permission is needed to take a reading.');
      return;
    } catch (error) {
      _finish('Could not start the microphone: $error');
      return;
    }

    _captureTimer = Timer(_captureDuration, _stopAndSubmit);
  }

  Future<void> _stopAndSubmit() async {
    await _micService.stop();
    if (!mounted) return;

    if (_samples.isEmpty) {
      _finish('No sound level was captured — try again.');
      return;
    }

    final average = _samples.reduce((a, b) => a + b) / _samples.length;
    final reading = MicReading.capture(placeId: widget.placeId, decibelValue: average);
    _samples.clear();

    // Grey and stopped pulsing the moment capture ends — the network round
    // trip to submit shouldn't leave the button looking like it's still
    // listening.
    setState(() => _phase = _Phase.finished);

    if (!SupabaseService.isConfigured) {
      _finish('Reading captured: ${reading.decibelValue.round()} dB (not submitted — Supabase not configured).');
      return;
    }

    try {
      await _supabaseService.submitMicReading(reading);
      _finish('Thanks! Your recording helps others know how loud this venue is.');
    } on PostgrestException catch (error) {
      // Server-side cooldown (supabase/migrations/0006_mic_reading_rate_limit.sql).
      final message = error.message.startsWith('rate_limited:')
          ? error.message.replaceFirst('rate_limited: ', '')
          : 'Could not submit reading: ${error.message}';
      _finish(message);
    } catch (error) {
      _finish('Could not submit reading: $error');
    }
  }

  void _finish(String message) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.finished;
      _resultMessage = message;
    });
    _restTimer?.cancel();
    _restTimer = Timer(_restDuration, () {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _currentDb = null;
        _resultMessage = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final String topText;
    switch (_phase) {
      case _Phase.idle:
        topText = 'Record how loud this venue is';
        break;
      case _Phase.recording:
        topText = _currentDb == null ? 'Listening…' : '${_currentDb!.round()} dB';
        break;
      case _Phase.finished:
        topText = _resultMessage ?? '';
        break;
    }

    final Color buttonColor;
    if (_phase == _Phase.idle) {
      buttonColor = scheme.primary;
    } else if (_phase == _Phase.recording) {
      buttonColor = scheme.error;
    } else {
      buttonColor = scheme.onSurfaceVariant;
    }

    return Column(
      children: [
        Text(topText, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 20),
        PulsingMicButton(
          onPressed: _phase == _Phase.idle ? _start : null,
          pulsing: _phase == _Phase.idle,
          color: buttonColor,
        ),
        const SizedBox(height: 20),
        Text(
          'Take a reading here',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
