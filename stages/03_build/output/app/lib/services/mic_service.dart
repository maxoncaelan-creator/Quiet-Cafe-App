// Platform-conditional export — mic capture needs genuinely different
// implementations, not just a runtime kIsWeb branch inside one file:
// audio_streamer (mic_service_io.dart's noise_meter wraps it) declares no
// web platform at all, and the web implementation (mic_service_web.dart)
// uses dart:js_interop/package:web, which isn't available when compiling
// for a native target. dart.library.html is Flutter's standard "am I
// compiling for web" conditional-import flag — still valid despite
// dart:html itself being deprecated elsewhere. Both files expose the same
// MicService/MicPermissionDenied API, so every caller (take_reading_screen.dart)
// needs no platform-specific code of its own.
export 'mic_service_io.dart' if (dart.library.html) 'mic_service_web.dart';
