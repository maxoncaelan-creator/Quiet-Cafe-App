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

// An average human speaking voice measures ~60 dBA. Added 2026-08-19 per
// Caelan: every signed-in user is walked through a "say something" screen
// once on first sign-in and again every 3 months (see mic_calibration_screen.dart);
// comparing their recording against this reference works out how far off
// their specific device/browser mic reads on a "true" dBA scale, which then
// corrects that user's future ambient readings before they're weighted into
// micSubscore. See calibrationOffset/applyCalibrationOffsets below.
export const HUMAN_VOICE_REFERENCE_DBA = 60;

// Android microphone readings are trusted at half the weight of iOS readings,
// per the research brief: iPhone hardware is uniform (~2 dBA accuracy),
// Android accuracy varies by device with no reliable cross-device calibration.
// Web readings (added 2026-08-19, real Web Audio capture, not a plugin) are
// trusted even less than Android's uncalibrated-but-native mics — browsers
// commonly apply their own automatic gain control / noise suppression to
// the raw input, which further distorts an ambient-level reading beyond
// device-to-device variance alone. Starting value, same tuning-item status
// as the rest of this weighting.
export const PLATFORM_WEIGHT = { ios: 1.0, android: 0.5, web: 0.35 };

// Starting weights for combining the four sub-scores. Renormalized at
// combine time over whichever signals are actually present for a venue.
// Marked as an open tuning item in ranking-spec.md. mic stays highest — a
// decibel reading is more trustworthy than a self-reported vote, which is
// itself why a mic reading within VOTE_PRECEDENCE_WINDOW_MS overrides a
// vote from the same user in the first place (see filterVotesSupersededByMic).
export const DEFAULT_WEIGHTS = { mic: 0.4, review: 0.25, vote: 0.2, popular: 0.15 };

// Quiet/Normal/Loud votes, added 2026-08-19 per Caelan: a lightweight
// alternative to a mic reading, feeding into the same score.
export const VOTE_SUBSCORE = { quiet: 100, normal: 50, loud: 0 };
export const VOTE_TIERS = [3, 10];

// A mic reading from the same user, at the same venue, within this window
// either side of a vote supersedes it for scoring purposes — the vote is
// still recorded in loudness_votes either way, just excluded here.
export const VOTE_PRECEDENCE_WINDOW_MS = 5 * 60 * 1000;

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
 * A user's calibration recording (them speaking normally) minus the human-
 * voice reference — positive means their mic/device reads loud relative to
 * "true," negative means quiet. Applied to that user's readings as a
 * subtraction (see applyCalibrationOffsets) so a chronically-loud-reading
 * phone doesn't just make every venue that user visits look noisier.
 * @param {number} calibrationDba
 */
export function calibrationOffset(calibrationDba) {
  return calibrationDba - HUMAN_VOICE_REFERENCE_DBA;
}

/**
 * Corrects each reading's decibel value using the submitting user's own
 * calibration offset, where known. Readings from a user with no calibration
 * on file (or with no userId at all — e.g. the bundled sample dataset) pass
 * through unchanged rather than being dropped; an uncorrected reading is
 * still better than no reading.
 * @param {Array<{decibel: number, platform: string, userId?: string}>} readings
 * @param {Map<string, number>} latestCalibrationByUser userId -> their most recent calibration's dBA
 */
export function applyCalibrationOffsets(readings, latestCalibrationByUser) {
  if (!latestCalibrationByUser || latestCalibrationByUser.size === 0) return readings;
  return readings.map((r) => {
    const calibrationDba = r.userId ? latestCalibrationByUser.get(r.userId) : undefined;
    if (calibrationDba === undefined) return r;
    return { ...r, decibel: r.decibel - calibrationOffset(calibrationDba) };
  });
}

/**
 * Microphone sub-score: averages within each platform first, then combines
 * platforms using PLATFORM_WEIGHT, per ranking-spec.md. Returns null if
 * there are no readings at all. Expects readings already corrected by
 * applyCalibrationOffsets, if calibration data exists — this function
 * itself has no opinion on calibration.
 * @param {Array<{decibel: number, platform: 'ios'|'android'|'web'}>} readings
 */
export function micSubscore(readings) {
  if (!readings || readings.length === 0) return null;

  const byPlatform = { ios: [], android: [], web: [] };
  for (const r of readings) {
    if (byPlatform[r.platform]) byPlatform[r.platform].push(r.decibel);
  }

  const platformAverages = [];
  for (const platform of ['ios', 'android', 'web']) {
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

/**
 * Vote sub-score: averages Quiet/Normal/Loud votes onto the same 0-100
 * quietness scale micSubscore uses, unweighted (a vote doesn't carry a
 * platform-accuracy distinction the way mic readings do).
 * Returns null if there are no countable votes.
 * @param {Array<{vote: 'quiet'|'normal'|'loud'}>} votes already filtered by
 *   the caller via filterVotesSupersededByMic
 */
export function voteSubscore(votes) {
  if (!votes || votes.length === 0) return null;
  const total = votes.reduce((sum, v) => sum + VOTE_SUBSCORE[v.vote], 0);
  return clamp(total / votes.length, 0, 100);
}

/**
 * Drops any vote that has a mic reading from the *same user*, at the same
 * venue, within VOTE_PRECEDENCE_WINDOW_MS either side of it — the decibel
 * reading is the more trustworthy signal in that case. The vote itself
 * still stays in loudness_votes regardless; this only affects scoring.
 * @param {Array<{userId: string, submittedAt: string|number|Date}>} votes
 * @param {Array<{userId: string, submittedAt: string|number|Date}>} micReadings same venue's mic readings
 */
export function filterVotesSupersededByMic(votes, micReadings) {
  return votes.filter((vote) => {
    const voteTime = new Date(vote.submittedAt).getTime();
    return !micReadings.some((reading) => {
      if (reading.userId !== vote.userId) return false;
      const readingTime = new Date(reading.submittedAt).getTime();
      return Math.abs(readingTime - voteTime) <= VOTE_PRECEDENCE_WINDOW_MS;
    });
  });
}

// Confidence — six graduated levels, added 2026-08-17 (was three buckets
// purely based on how many signal types were present). Now also weighs how
// much data backs each signal: a venue with 1 review mention and one with
// 20 both "have the review signal," but they shouldn't read as equally
// trustworthy. Each present signal contributes 1-3 points depending on its
// data volume (0 if absent); points sum and clamp to 1-6, mapping 1:1 onto
// the six labels below. Votes (added 2026-08-19) count the same way, on
// VOTE_TIERS. Max reachable total now exceeds 6 (review's 3 + mic's 3 +
// vote's 3 — Popular Times is still dormant, contributing 0); it simply
// saturates at "Certain" rather than needing more tiers. Thresholds are a
// starting point, same as DEFAULT_WEIGHTS — flagged as an open tuning item,
// not a final calibration.
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
 * Combines the four sub-scores into a single quietness score, renormalizing
 * weights over whichever signals are present (cold-start handling), and
 * computes a graduated confidence level from each present signal's data
 * volume.
 * @param {{
 *   review: { subscore: number|null, count?: number },
 *   popular: { subscore: number|null },
 *   mic: { subscore: number|null, count?: number },
 *   vote: { subscore: number|null, count?: number },
 * }} signals `count` is the mention/reading/vote total backing that signal.
 * @param {{review: number, popular: number, mic: number, vote: number}} weights
 * @returns {{score: number|null, confidence: string|null, signalCount: number}}
 */
export function combineScores(signals, weights = DEFAULT_WEIGHTS) {
  const { review = {}, popular = {}, mic = {}, vote = {} } = signals;
  const subscores = {
    review: review.subscore,
    popular: popular.subscore,
    mic: mic.subscore,
    vote: vote.subscore,
  };
  const present = Object.entries(subscores).filter(([, v]) => v !== null && v !== undefined);

  if (present.length === 0) {
    return { score: null, confidence: null, signalCount: 0 };
  }

  const weightSum = present.reduce((sum, [key]) => sum + weights[key], 0);
  const score = present.reduce((sum, [key, value]) => sum + value * (weights[key] / weightSum), 0);

  const reviewPoints = tierPoints(review.count, REVIEW_MENTION_TIERS);
  const micPoints = tierPoints(mic.count, MIC_READING_TIERS);
  const votePoints = tierPoints(vote.count, VOTE_TIERS);
  const popularPoints = popular.subscore !== null && popular.subscore !== undefined ? 3 : 0;
  const confidenceLevel = Math.min(6, Math.max(1, reviewPoints + micPoints + votePoints + popularPoints));
  const confidence = CONFIDENCE_LEVELS[confidenceLevel - 1];

  return { score: clamp(score, 0, 100), confidence, signalCount: present.length };
}
