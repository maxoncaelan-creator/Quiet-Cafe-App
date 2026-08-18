// Search bar with voice input for the List screen. Distinct from the
// noise-reading microphone elsewhere in the app: this one transcribes
// speech into the search field via on-device speech recognition, it
// doesn't measure decibels or write to Supabase.

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceSearchBar extends StatefulWidget {
  final ValueChanged<String> onQueryChanged;

  const VoiceSearchBar({super.key, required this.onQueryChanged});

  @override
  State<VoiceSearchBar> createState() => _VoiceSearchBarState();
}

class _VoiceSearchBarState extends State<VoiceSearchBar> {
  final _controller = TextEditingController();
  final _speech = stt.SpeechToText();
  bool _listening = false;
  bool _speechAvailable = false;

  bool _initAttempted = false;

  // Deliberately NOT called from initState — speech_to_text's initialize()
  // triggers the OS microphone-permission prompt immediately, and doing
  // that the instant this screen loads (before the user has touched
  // anything) is a bad surprise. Only runs on the first real tap of the
  // mic button instead. Found by actually running the app on a device,
  // not by reading the code.
  Future<void> _initSpeech() async {
    if (_initAttempted) return;
    _initAttempted = true;
    final available = await _speech.initialize(
      onStatus: _onStatus,
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (mounted) setState(() => _speechAvailable = available);
  }

  void _onStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      if (mounted) setState(() => _listening = false);
    }
  }

  Future<void> _toggleListening() async {
    if (!_initAttempted) await _initSpeech(); // first tap only — see _initSpeech's doc comment
    if (!_speechAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Speech recognition isn't available on this device.")),
        );
      }
      return;
    }
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        _controller.text = result.recognizedWords;
        _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
        widget.onQueryChanged(result.recognizedWords);
      },
    );
  }

  @override
  void dispose() {
    _speech.stop();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(Icons.search, color: scheme.onSurfaceVariant, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'Search restaurants…',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onChanged: widget.onQueryChanged,
                ),
              ),
              IconButton(
                icon: Icon(
                  _listening ? Icons.mic : Icons.mic_none,
                  color: _listening ? scheme.primary : scheme.onSurfaceVariant,
                ),
                tooltip: _listening ? 'Stop listening' : 'Search by voice',
                onPressed: _toggleListening,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
