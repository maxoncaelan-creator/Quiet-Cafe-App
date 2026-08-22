// Search bar with voice input for the List screen. Distinct from the
// noise-reading microphone elsewhere in the app: this one transcribes
// speech into the search field via on-device speech recognition, it
// doesn't measure decibels or write to Supabase.

import 'package:flutter/material.dart';

import '../services/speech_recognition_service.dart';

class VoiceSearchBar extends StatefulWidget {
  final ValueChanged<String> onQueryChanged;

  const VoiceSearchBar({super.key, required this.onQueryChanged});

  @override
  State<VoiceSearchBar> createState() => _VoiceSearchBarState();
}

class _VoiceSearchBarState extends State<VoiceSearchBar> {
  final _controller = TextEditingController();
  final _speech = SpeechRecognitionService.shared;

  Future<void> _toggleListening() async {
    if (_speech.isListening) {
      await _speech.stop();
      return;
    }

    await _speech.start(
      onWords: (words) {
        if (!mounted) return;
        _controller.text = words;
        _controller.selection =
            TextSelection.collapsed(offset: _controller.text.length);
        widget.onQueryChanged(words);
      },
      onError: _showVoiceError,
    );
  }

  void _showVoiceError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
              AnimatedBuilder(
                animation: _speech,
                builder: (context, _) => IconButton(
                  icon: Icon(
                    _speech.isListening ? Icons.mic : Icons.mic_none,
                    color: _speech.isListening
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  tooltip: _speech.isListening
                      ? 'Stop listening'
                      : 'Search by voice',
                  onPressed: _toggleListening,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
