// Redesigned 2026-08-19, per Caelan: the loudness word now sits fully
// inside a single colored box (calmest teal for Silent, angriest red for
// Earsplitting) instead of the previous 7-segment bar. Same category
// taxonomy, same color ramp (_colorForQuietness) — only the shape changed.
// Used both compact (list tile) and full-size (detail screen), so the
// class name/public API stayed put even though the rendering didn't.

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

  // Red -> amber -> teal ramp: index 0 (Silent) is calmest teal, the last
  // category (Earsplitting) is angriest red.
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
    final bandWidth = 100 / categories.length;
    final midQuietness = 100 - (index * bandWidth + bandWidth / 2);
    return _colorForQuietness(midQuietness, scheme);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final index = categoryIndexFor(quietnessScore);

    final boxColor = index == null ? scheme.surfaceContainerHigh : _categoryColor(index, scheme);
    final textColor = index == null
        ? scheme.onSurfaceVariant
        : (ThemeData.estimateBrightnessForColor(boxColor) == Brightness.dark ? Colors.white : Colors.black);
    final labelText = index == null ? (compact ? '—' : 'Not enough data yet') : categories[index];

    final box = Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 20, vertical: compact ? 5 : 12),
      decoration: BoxDecoration(
        color: boxColor,
        borderRadius: BorderRadius.circular(compact ? 8 : 12),
      ),
      child: Text(
        labelText,
        textAlign: TextAlign.center,
        overflow: TextOverflow.visible,
        softWrap: false,
        style: (compact
                ? Theme.of(context).textTheme.bodySmall
                : Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600))
            ?.copyWith(color: textColor),
      ),
    );

    return box;
  }
}
