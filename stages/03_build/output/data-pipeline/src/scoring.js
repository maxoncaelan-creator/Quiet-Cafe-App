// Implements the scoring model from stage 2's ranking-spec.md.
// All functions here are pure (no I/O) so they can be unit tested without
// real API keys or a live Outscraper account.

// Minimum noise mentions before the review-text signal counts at all.
// Lowered 2026-08-17 (was 3) — decided with Caelan alongside the move to
// graduated confidence levels below: any venue with at least one noise
// mention now gets a score, at minimum "Very Low" confidence, rather than
// being excluded outright.
export const MIN_REVIEW_MENTIONS = 1;

// dBA range used to map a decibel reading onto the 0-100 quietness scale.
// Below MIN_DBA -> subscore 100 (quietest). Above MAX_DBA -> subscore 0 (loudest).
// Chosen so SoundPrint's public bands (quiet <70, moderate 70-75, loud 75-80,
// very loud >80) land in the upper-middle of the range rather than at the edges.
export const MIN_DBA = 50;
export const MAX_DBA = 90;

// Android microphone readings are trusted at half the weight of iOS readings,
// per the research brief: iPhone hardware is uniform (~2 dBA accuracy),
// Android accuracy varies by device with no reliable cross-device calibration.
export const PLATFORM_WEIGHT = { ios: 1.0, android: 0.5 };

// Starting weights for combining the three sub-scores. Renormalized at
// combine time over whichever signals are actually present for a venue.
// Marked as an open tuning item in ranking-spec.md.
export const DEFAULT_WEIGHTS = { mic: 0.5, review: 0.3, popular: 0.2 };

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

/**
 * Review-text sub-score: ratio of positive to total noise-related mentions,
 * mapped to 0-100. Returns null (no signal) below the minimum mention count.
 */
export function reviewSubscore(positiveCount, negativeCount, minMentions = MIN_REVIEW_MENTIONS) {
  const total = positiveCount + negativeCount;
  if (total < minMentions) return null;
  return clamp((positiveCount / total) * 100, 0, 100);
}

/**
 * Popular Times sub-score: busynessPercent is 0-100 ("as busy as it gets").
 * Busier maps to louder maps to a lower quietness sub-score.
 * Returns null if no Popular Times data exists for this venue/time.
 */
export function popularSubscore(busynessPercent) {
  if (busynessPercent === null || busynessPercent === undefined) return null;
  return clamp(100 - busynessPercent, 0, 100);
}

/** Converts a single decibel reading to a 0-100 quietness sub-score. */
export function dbaToSubscore(dba) {
  const ratio = (dba - MIN_DBA) / (MAX_DBA - MIN_DBA);
  return clamp(100 - ratio * 100, 0, 100);
}

/**
 * Microphone sub-score: averages within each platform first, then combines
 * platforms using PLATFORM_WEIGHT, per ranking-spec.md. Returns null if
 * there are no readings at all.
 * @param {Array<{decibel: number, platform: 'ios'|'android'}>} readings
 */
export function micSubscore(readings) {
  if (!readings || readings.length === 0) return null;

  const byPlatform = { ios: [], android: [] };
  for (const r of readings) {
    if (byPlatform[r.platform]) byPlatform[r.platform].push(r.decibel);
  }

  const platformAverages = [];
  for (const platform of ['ios', 'android']) {
    const values = byPlatform[platform];
    if (values.length === 0) continue;
    const avgDba = values.reduce((a, b) => a + b, 0) / values.length;
    platformAverages.push({ platform, avgDba, weight: PLATFORM_WEIGHT[platform] });
  }

  if (platformAverages.length === 0) return null;

  const weightSum = platformAverages.reduce((sum, p) => sum + p.weight, 0);
  const weightedDba =
    platformAverages.reduce((sum, p) => sum + p.avgDba * p.weight, 0) / weightSum;

  return dbaToSubscore(weightedDba);
}

// Confidence — six graduated levels, added 2026-08-17 (was three buckets
// purely based on how many signal types were present). Now also weighs how
// much data backs each signal: a venue with 1 review mention and one with
// 20 both "have the review signal," but they shouldn't read as equally
// trustworthy. Each present signal contributes 1-3 points depending on its
// data volume (0 if absent); points sum and clamp to 1-6, mapping 1:1 onto
// the six labels below. Today's max reachable total is exactly 6 (review's
// 3 + mic's 3 — Popular Times is dormant, contributing 0); if it's ever
// revived its extra points simply saturate at "Certain" rather than needing
// a 7th tier. Thresholds are a starting point, same as DEFAULT_WEIGHTS —
// flagged as an open tuning item, not a final calibration.
export const REVIEW_MENTION_TIERS = [3, 6];
export const MIC_READING_TIERS = [3, 10];
export const CONFIDENCE_LEVELS = ['Very Low', 'Low', 'Moderate', 'High', 'Very High', 'Certain'];

function tierPoints(count, tiers) {
  if (!count || count <= 0) return 0;
  let points = 1;
  for (const threshold of tiers) {
    if (count >= threshold) points += 1;
  }
  return points;
}

/**
 * Combines the three sub-scores into a single quietness score, renormalizing
 * weights over whichever signals are present (cold-start handling), and
 * computes a graduated confidence level from each present signal's data
 * volume.
 * @param {{
 *   review: { subscore: number|null, count?: number },
 *   popular: { subscore: number|null },
 *   mic: { subscore: number|null, count?: number },
 * }} signals `count` is the mention/reading total backing that signal.
 * @param {{review: number, popular: number, mic: number}} weights
 * @returns {{score: number|null, confidence: string|null, signalCount: number}}
 */
export function combineScores(signals, weights = DEFAULT_WEIGHTS) {
  const { review = {}, popular = {}, mic = {} } = signals;
  const subscores = { review: review.subscore, popular: popular.subscore, mic: mic.subscore };
  const present = Object.entries(subscores).filter(([, v]) => v !== null && v !== undefined);

  if (present.length === 0) {
    return { score: null, confidence: null, signalCount: 0 };
  }

  const weightSum = present.reduce((sum, [key]) => sum + weights[key], 0);
  const score = present.reduce((sum, [key, value]) => sum + value * (weights[key] / weightSum), 0);

  const reviewPoints = tierPoints(review.count, REVIEW_MENTION_TIERS);
  const micPoints = tierPoints(mic.count, MIC_READING_TIERS);
  const popularPoints = popular.subscore !== null && popular.subscore !== undefined ? 3 : 0;
  const confidenceLevel = Math.min(6, Math.max(1, reviewPoints + micPoints + popularPoints));
  const confidence = CONFIDENCE_LEVELS[confidenceLevel - 1];

  return { score: clamp(score, 0, 100), confidence, signalCount: present.length };
}
