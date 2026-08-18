import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/mic_reading.dart';
import '../services/mic_service.dart';
import '../services/supabase_service.dart';

class TakeReadingScreen extends StatefulWidget {
  final String placeId;
  final String name;

  const TakeReadingScreen({super.key, required this.placeId, required this.name});

  @override
  State<TakeReadingScreen> createState() => _TakeReadingScreenState();
}

class _TakeReadingScreenState extends State<TakeReadingScreen> {
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
          // Previously a no-op placeholder — a stream failure (e.g. this
          // platform not being supported by the underlying audio_streamer
          // plugin, confirmed to happen on web) silently produced zero
          // readings with no feedback at all, indistinguishable from
          // "nothing happened when I tapped the button." Found by actually
          // testing the flow, not by inspection.
          if (!mounted) return;
          setState(() {
            _error = 'Lost connection to the microphone: $error';
            _listening = false;
          });
        },
      );
      setState(() => _listening = true);
    } on MicPermissionDenied {
      setState(() => _error = 'Microphone permission is needed to take a reading.');
    } catch (error) {
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
    final reading = MicReading.capture(placeId: widget.placeId, decibelValue: average);
    // Clear now, not just on the next _start() — otherwise a second
    // attempt in this same screen instance would silently average this
    // attempt's samples in with the new ones.
    _samples.clear();

    if (!SupabaseService.isConfigured) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reading captured: ${reading.decibelValue.round()} dB (not submitted — Supabase not configured, see PLATFORM_SETUP.md)')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _supabaseService.submitMicReading(reading);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Thanks! Reading of ${reading.decibelValue.round()} dB submitted.')),
      );
    } on PostgrestException catch (error) {
      // Server-side cooldown (supabase/migrations/0006_mic_reading_rate_limit.sql,
      // `enforce_mic_reading_cooldown`) — raised as a plain Postgres
      // exception, not a distinct error code, so it's matched by message
      // prefix rather than a status/code check.
      if (!mounted) return;
      final message = error.message.startsWith('rate_limited:')
          ? error.message.replaceFirst('rate_limited: ', '')
          : 'Could not submit reading: ${error.message}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit reading: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Reading at ${widget.name}')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'This measures ambient sound level only. No audio is recorded or stored.',
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
              child: Text(_saving ? 'Saving…' : (_listening ? 'Stop and save' : 'Start listening')),
            ),
          ],
        ),
      ),
    );
  }
}
