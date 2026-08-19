-- Web mic decibel capture, added 2026-08-19. mic_readings.platform's CHECK
-- constraint only ever allowed 'ios'/'android' (0001_init.sql) — the Dart
-- side already had a 'web' branch ready (MicReading._capturePlatform) but
-- it was unreachable because capture itself was gated off on web (no real
-- Web Audio implementation existed yet, and audio_streamer/noise_meter has
-- zero web platform support). Now that a real getUserMedia-based capture
-- exists (mic_service_web.dart), the database needs to actually accept it.
alter table mic_readings drop constraint mic_readings_platform_check;
alter table mic_readings add constraint mic_readings_platform_check
  check (platform in ('ios', 'android', 'web'));
