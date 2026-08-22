import 'package:flutter_test/flutter_test.dart';
import 'package:quiet_restaurant_finder/services/speech_recognition_service.dart';

void main() {
  test('gives a settings action for microphone and audio permission errors', () {
    const expected =
        'Please allow microphone and speech recognition access in Settings.';

    expect(speechRecognitionMessageForError('error_permission'), expected);
    expect(speechRecognitionMessageForError('error_audio_error'), expected);
  });

  test('gives a connection action for network errors', () {
    expect(
      speechRecognitionMessageForError('error_network'),
      'Voice search needs an internet connection. Please try again.',
    );
  });

  test('asks for another attempt when no words were recognised', () {
    const expected = 'I did not hear any words. Try the microphone again.';

    expect(speechRecognitionMessageForError('error_speech_timeout'), expected);
    expect(speechRecognitionMessageForError('error_no_match'), expected);
  });

  test('uses a safe retry action for unknown recognizer errors', () {
    expect(
      speechRecognitionMessageForError('error_busy'),
      'Voice search stopped. Please try again.',
    );
  });
}
