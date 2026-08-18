// Confidence indicator — added 2026-08-17 alongside the move to six
// graduated confidence levels (data-pipeline/src/scoring.js,
// ranking-spec.md "Confidence levels"). A row of six dots, filled up to the
// current level, mirrors the six named levels directly rather than trying
// to compress them into a single color the way NoiseLevelBar does for the
// noise score. Shown wherever a restaurant's quietness score appears —
// list rows (compact, dots only) and the detail screen (dots + label).

import 'package:flutter/material.dart';

class ConfidenceIndicator extends StatelessWidget {
  static const levels = ['Very Low', 'Low', 'Moderate', 'High', 'Very High', 'Certain'];

  final String? confidence;
  final bool showLabel;
  final bool showDots;
  final double dotSize;

  const ConfidenceIndicator({
    super.key,
    required this.confidence,
    this.showLabel = true,
    this.showDots = true,
    this.dotSize = 6,
  });

  int? get _level {
    final index = levels.indexOf(confidence ?? '');
    return index == -1 ? null : index + 1;
  }

  @override
  Widget build(BuildContext context) {
    final level = _level;
    if (level == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final dots = Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(levels.length, (i) {
        final filled = i < level;
        return Container(
          width: dotSize,
          height: dotSize,
          margin: EdgeInsets.only(right: i == levels.length - 1 ? 0 : dotSize * 0.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? scheme.primary : scheme.outlineVariant,
          ),
        );
      }),
    );

    return Semantics(
      label: '$confidence confidence',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showDots) dots,
            if (showLabel) ...[
              if (showDots) const SizedBox(width: 6),
              Text(
                // Without the dots, the level name alone ("Very Low") reads
                // as ambiguous floating text — "confidence" gives it the
                // context the dots otherwise provided visually.
                showDots ? confidence! : '$confidence confidence',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
