import 'package:flutter_test/flutter_test.dart';
import 'package:quiet_restaurant_finder/models/current_loudness.dart';
import 'package:quiet_restaurant_finder/models/mic_reading.dart';

void main() {
  final observedAt = DateTime.utc(2026, 8, 21, 12);
  const baseline = 85.0; // Quiet historical average.
  final current = CurrentLoudness(
    subscore: 0,
    observedAt: observedAt,
  ); // Loud right now.

  test('a new on-site report completely controls the displayed loudness', () {
    expect(current.effectiveScore(baseline, now: observedAt), 0);
    expect(current.freshness(now: observedAt), 1);
  });

  test(
    'a fresh report blends halfway back to the venue baseline after 10.5 days',
    () {
      final halfway = observedAt.add(const Duration(days: 10, hours: 12));

      expect(
        current.effectiveScore(baseline, now: halfway),
        closeTo(42.5, 0.001),
      );
      expect(current.freshness(now: halfway), closeTo(0.5, 0.001));
    },
  );

  test('a report no longer overrides the baseline after 21 days', () {
    final expired = observedAt.add(currentLoudnessDecay);

    expect(current.effectiveScore(baseline, now: expired), baseline);
    expect(current.freshness(now: expired), 0);
  });

  test(
    'a direct report remains visible when a new venue has no baseline yet',
    () {
      expect(
        current.effectiveScore(null, now: observedAt.add(currentLoudnessDecay)),
        0,
      );
    },
  );

  test('a microphone reading shorter than 10 seconds is rejected', () {
    expect(
      () => MicReading.capture(
        placeId: 'test-venue',
        decibelValue: 70,
        captureDuration: const Duration(seconds: 9),
      ),
      throwsArgumentError,
    );
  });
}
