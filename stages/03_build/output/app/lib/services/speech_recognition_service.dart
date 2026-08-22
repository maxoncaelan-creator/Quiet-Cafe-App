import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// One app-wide owner for the platform speech recognizer.
///
/// `speech_to_text` keeps the status and error callbacks from its first
/// `initialize` call. Keeping one instance here prevents the List search and
/// Search Assistant from silently replacing one another's callbacks.
class SpeechRecognitionService extends ChangeNotifier {
  SpeechRecognitionService._();

  static final SpeechRecognitionService shared = SpeechRecognitionService._();

  final stt.SpeechToText _speech = stt.SpeechToText();
  Future<bool>? _initialization;
  ValueChanged<String>? _onWords;
  ValueChanged<String>? _onErrorMessage;

  bool _available = false;
  bool _listening = false;
  String? _lastError;

  bool get isAvailable => _available;
  bool get isListening => _listening;
  String get unavailableMessage =>
      _lastError ?? "Speech recognition isn't available on this device.";

  Future<bool> _initialize() async {
    try {
      _available = await _speech.initialize(
        onStatus: _handleStatus,
        onError: _handleError,
        debugLogging: kDebugMode,
      );
      if (!_available) {
        _lastError =
            'Voice search is unavailable. Allow microphone access and try again.';
      }
    } catch (_) {
      _available = false;
      _lastError = 'Voice search could not start. Please try again.';
    }
    notifyListeners();
    return _available;
  }

  Future<bool> start({
    required ValueChanged<String> onWords,
    required ValueChanged<String> onError,
  }) async {
    final available = await (_initialization ??= _initialize());
    if (!available) {
      onError(unavailableMessage);
      return false;
    }

    if (_listening) {
      await stop();
    }

    _lastError = null;
    _onWords = onWords;
    _onErrorMessage = onError;
    _listening = true;
    notifyListeners();

    try {
      await _speech.listen(onResult: (result) {
        _onWords?.call(result.recognizedWords);
      });
      return true;
    } catch (_) {
      _lastError = 'Voice search could not listen. Please try again.';
      _listening = false;
      notifyListeners();
      _onErrorMessage?.call(_lastError!);
      return false;
    }
  }

  Future<void> stop() async {
    if (!_listening) return;
    try {
      await _speech.stop();
    } finally {
      _listening = false;
      notifyListeners();
    }
  }

  void _handleStatus(String status) {
    if (status == 'done' ||
        status == 'doneNoResult' ||
        status == 'notListening') {
      _listening = false;
      notifyListeners();
    }
  }

  void _handleError(SpeechRecognitionError error) {
    _listening = false;
    _lastError = _messageFor(error.errorMsg);
    notifyListeners();
    _onErrorMessage?.call(_lastError!);
  }

  String _messageFor(String error) {
    switch (error) {
      case 'error_permission':
      case 'error_audio_error':
        return 'Please allow microphone and speech recognition access in Settings.';
      case 'error_network':
        return 'Voice search needs an internet connection. Please try again.';
      case 'error_speech_timeout':
      case 'error_no_match':
        return 'I did not hear any words. Try the microphone again.';
      default:
        return 'Voice search stopped. Please try again.';
    }
  }
}
