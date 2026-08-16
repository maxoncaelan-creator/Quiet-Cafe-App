// A single crowdsourced decibel reading captured on-device, matching the
// "Microphone signal" table in stage 2's data-schema.md. Submission to a
// backend is not implemented yet — see README's "what's stubbed" section.

import 'dart:io' show Platform;

class MicReading {
  final String placeId;
  final double decibelValue;
  final String platform; // 'ios' | 'android'
  final DateTime recordedAt;

  const MicReading({
    required this.placeId,
    required this.decibelValue,
    required this.platform,
    required this.recordedAt,
  });

  factory MicReading.capture({
    required String placeId,
    required double decibelValue,
  }) {
    return MicReading(
      placeId: placeId,
      decibelValue: decibelValue,
      platform: Platform.isIOS ? 'ios' : 'android',
      recordedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'placeId': placeId,
        'decibelValue': decibelValue,
        'platform': platform,
        'recordedAt': recordedAt.toIso8601String(),
      };
}
