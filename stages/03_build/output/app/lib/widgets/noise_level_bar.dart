// Replaces QuietnessGauge (semicircle + number) — added 2026-08-17. Caelan's
// call: numbers weren't landing with users, so the primary display moves to
// a named category on a colored spectrum bar instead of a raw 0-100 figure.
// Categories run quiet-to-loud, matching reading order and the existing
// "noise" framing QuietnessGauge established (100 - quietnessScore = noise,
// so a louder venue still fills more of the bar, not less).
//
// Seven categories over a 0-100 quietness_score is a starting split, same
// status as DEFAULT_WEIGHTS/REVIEW_MENTION_TIERS in scoring.js — even
// thirds-of-a-third boundaries for now, open to tuning once real usage data
// says otherwise.

import 'package:flutter/material.dart';

class NoiseLevelBar extends StatelessWidget {
  static const categories = [
    'Silent',
    'Very Quiet',
    'Quiet',
    'Moderate',
    'Loud',
    'Very Loud',
    'Earsplitting',
  ];

  final double? quietnessScore;
  final bool compact;

  const NoiseLevelBar({super.key, required this.quietnessScore, this.compact = false});

  static int? categoryIndexFor(double? quietnessScore) {
    if (quietnessScore == null) return null;
    final noise = (100 - quietnessScore).clamp(0, 100);
    final index = (noise / 100 * categories.length).floor();
    return index.clamp(0, categories.length - 1);
  }

  // Same red -> amber -> teal ramp QuietnessGauge used, sampled once per
  // category at its band's midpoint rather than continuously, so each
  // category reads as one distinct color instead of a gradient smear.
  static Color _colorForQuietness(double quietness, ColorScheme scheme) {
    const red = Color(0xFFBA1A1A);
    const amber = Color(0xFFC77800);
    final teal = scheme.primary;
    if (quietness <= 35) {
      return Color.lerp(red, amber, quietness / 35)!;
    } else if (quietness <= 75) {
      return Color.lerp(amber, teal, (quietness - 35) / 40)!;
    }
    return teal;
  }

  static Color _categoryColor(int index, ColorScheme scheme) {
    // Index 0 (Silent) is the quietest category -> highest quietness_score.
    final bandWidth = 100 / categories.length;
    final midQuietness = 100 - (index * bandWidth + bandWidth / 2);
    return _colorForQuietness(midQuietness, scheme);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final index = categoryIndexFor(quietnessScore);
    final barHeight = compact ? 6.0 : 14.0;
    final gap = compact ? 2.0 : 4.0;
    final width = compact ? 64.0 : 260.0;

    final bar = SizedBox(
      width: width,
      height: barHeight,
      child: Row(
        children: List.generate(categories.length, (i) {
          final isCurrent = i == index;
          final segmentColor = index == null
              ? scheme.surfaceContainerHigh
              : _categoryColor(i, scheme).withValues(alpha: isCurrent ? 1.0 : 0.28);
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i == categories.length - 1 ? 0 : gap),
              decoration: BoxDecoration(
                color: segmentColor,
                borderRadius: BorderRadius.circular(barHeight / 2),
              ),
            ),
          );
        }),
      ),
    );

    final labelText = index == null
        ? (compact ? '—' : 'Not enough data yet')
        : categories[index];
    final label = Text(
      labelText,
      style: compact
          ? Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)
          : Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
      textAlign: TextAlign.center,
    );

    if (compact) {
      // Bar to the left of the label, not stacked above it — list rows are
      // wide enough for this and it reads faster than two lines.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [bar, const SizedBox(width: 6), label],
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [label, const SizedBox(height: 10), bar]);
  }
}
