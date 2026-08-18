// A single crowdsourced decibel reading captured on-device, matching the
// "Microphone signal" table in stage 2's data-schema.md. Submission to a
// backend is not implemented yet — see README's "what's stubbed" section.

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

class MicReading {
  final String placeId;
  final double decibelValue;
  final String platform; // 'ios' | 'android' | 'web'
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
      platform: _capturePlatform(),
      recordedAt: DateTime.now(),
    );
  }

  // dart:io's Platform isn't available on web, and mic capture itself is
  // gated off web (see restaurant_detail_screen.dart) — this 'web' branch
  // should be unreachable in practice, but the file still needs to compile
  // for the web target.
  static String _capturePlatform() {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  }

  Map<String, dynamic> toJson() => {
        'placeId': placeId,
        'decibelValue': decibelValue,
        'platform': platform,
        'recordedAt': recordedAt.toIso8601String(),
      };
}

/// One of the signed-in user's own past readings, joined with the
/// restaurant's name for display — see AccountScreen's activity history.
/// Distinct from [MicReading] (which is what gets submitted) since this one
/// carries a display name, not just the place_id.
class MyReading {
  final String placeId;
  final String restaurantName;
  final double decibelValue;
  final String platform;
  final DateTime recordedAt;

  const MyReading({
    required this.placeId,
    required this.restaurantName,
    required this.decibelValue,
    required this.platform,
    required this.recordedAt,
  });
}
