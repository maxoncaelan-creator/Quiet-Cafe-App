// Mic calibration — added 2026-08-19 per Caelan. An average human speaking
// voice measures ~60 dBA; comparing a user's own recording of themself
// speaking against that reference works out how far off their specific
// device/browser mic reads, so their future ambient readings can be
// corrected (data-pipeline/src/scoring.js's calibrationOffset/
// applyCalibrationOffsets). Pushed automatically on first sign-in and every
// ~3 months after — see main.dart's global auth-state listener for the
// trigger logic; this screen itself just records and submits.
//
// Skippable (a "Skip for now" text action) rather than a hard block —
// nothing else in this app force-gates a screen the user can't get past
// (browsing never requires sign-in, "Take a reading" prompts inline), and
// forcing a mic-permission prompt the instant someone signs in seemed like
// the wrong tradeoff. Skipping doesn't record anything, so the same
// due-ness check will surface it again next time it's evaluated — flagged
// as a judgment call, not an explicit instruction either way.

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/mic_reading.dart';
import '../services/mic_service.dart';
import '../services/observability_service.dart';
import '../services/supabase_service.dart';
import '../widgets/max_width_content.dart';

class MicCalibrationScreen extends StatefulWidget {
  const MicCalibrationScreen({super.key});

  @override
  State<MicCalibrationScreen> createState() => _MicCalibrationScreenState();
}

class _MicCalibrationScreenState extends State<MicCalibrationScreen> {
  final _micService = MicService();
  final _supabaseService = SupabaseService();

  bool _listening = false;
  bool _saving = false;
  double? _currentDb;
  final List<double> _samples = [];
  String? _error;

  @override
  void dispose() {
    _micService.stop();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _samples.clear();
    });
    try {
      await _micService.start(
        (meanDecibel) {
          setState(() {
            _currentDb = meanDecibel;
            _samples.add(meanDecibel);
          });
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _error = 'Lost connection to the microphone: $error';
            _listening = false;
          });
        },
      );
      setState(() => _listening = true);
    } on MicPermissionDenied {
      setState(() => _error = 'Microphone permission is needed to calibrate.');
    } catch (error, st) {
      unawaited(ObservabilityService.captureError(error, st,
          context: 'mic_calibration.start'));
      setState(() => _error = 'Could not start the microphone: $error');
    }
  }

  Future<void> _stopAndSave() async {
    await _micService.stop();
    setState(() => _listening = false);

    if (_samples.isEmpty) {
      setState(() => _error = 'No sound level was captured — try again.');
      return;
    }
    final average = _samples.reduce((a, b) => a + b) / _samples.length;
    _samples.clear();

    setState(() => _saving = true);
    try {
      await _supabaseService.submitMicCalibration(average, MicReading.capturePlatform());
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error, st) {
      unawaited(ObservabilityService.captureError(error, st,
          context: 'mic_calibration.submit'));
      if (!mounted) return;
      setState(() {
        _error = 'Could not save calibration: $error';
        _saving = false;
      });
    }
  }

  void _skip() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calibrate your microphone'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _saving ? null : _skip,
            child: const Text('Skip for now'),
          ),
        ],
      ),
      body: MaxWidthContent(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'An average speaking voice measures about 60 dB. Say something '
                'out loud, like you\'re having a normal conversation — this helps '
                'us correct for how loud or quiet your microphone reads compared '
                'to everyone else\'s, so your readings are more accurate.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Text(
                _currentDb == null ? '—' : '${_currentDb!.round()} dB',
                style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : (_listening ? _stopAndSave : _start),
                child: Text(_saving ? 'Saving…' : (_listening ? 'Done speaking' : 'Start speaking')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
