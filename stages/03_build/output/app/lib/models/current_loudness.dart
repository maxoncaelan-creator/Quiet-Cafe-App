/// How long a fresh, on-site report is allowed to override a venue's
/// long-term loudness baseline. This is intentionally a product constant,
/// rather than a hidden formula, so real usage data can tune it later.
const currentLoudnessDecay = Duration(days: 21);

/// A direct observation of how loud a venue was at a specific time.
///
/// The restaurant's normal [baselineQuietnessScore] remains the historical
/// aggregate. A new on-site report is the best description of *right now*,
/// so it starts at full weight and then linearly blends back to that baseline
/// over [currentLoudnessDecay].
class CurrentLoudness {
  final double subscore;
  final DateTime observedAt;

  const CurrentLoudness({required this.subscore, required this.observedAt});

  /// Returns the score a person should see now. If no historical baseline is
  /// available yet, retain the direct observation instead of making a newly
  /// measured venue disappear once the freshness window expires.
  double effectiveScore(double? baselineQuietnessScore, {DateTime? now}) {
    if (baselineQuietnessScore == null) return subscore;

    final elapsed = (now ?? DateTime.now()).toUtc().difference(
      observedAt.toUtc(),
    );
    if (elapsed <= Duration.zero) return subscore;

    final freshness =
        (1 - elapsed.inMilliseconds / currentLoudnessDecay.inMilliseconds)
            .clamp(0.0, 1.0);
    return baselineQuietnessScore +
        (subscore - baselineQuietnessScore) * freshness;
  }

  double freshness({DateTime? now}) {
    final elapsed = (now ?? DateTime.now()).toUtc().difference(
      observedAt.toUtc(),
    );
    if (elapsed <= Duration.zero) return 1;
    return (1 - elapsed.inMilliseconds / currentLoudnessDecay.inMilliseconds)
        .clamp(0.0, 1.0);
  }
}
