// Recomputes and writes back one restaurant's mic/vote sub-scores and
// overall quietness_score/confidence — added 2026-08-20 after Caelan
// reported the loudness-vote buttons doing nothing visible.
//
// Root cause: only the Node data-pipeline (data-pipeline/src/pipeline.js)
// ever wrote these columns, and that only runs when Caelan manually
// triggers it — it also re-fetches every restaurant from Google Places
// (real API cost) on every run, so it can't just run after every vote or
// mic reading. A vote/reading was landing correctly in loudness_votes/
// mic_readings the whole time; nothing ever recomputed the aggregate
// afterward.
//
// This function does the same combineScores() math scoring.js does, but
// only for the one affected restaurant, and reads review/popular data
// already stored on `restaurants` rather than re-fetching or re-mining
// anything — no external API calls, so it's safe to call after every vote
// or reading. Called from SupabaseService.submitLoudnessVote/
// submitMicReading, best-effort (a failure here doesn't undo the vote/
// reading write, which already succeeded — the next full pipeline run
// would still pick it up eventually).
//
// This duplicates scoring.js's formulas in TypeScript rather than sharing
// code with the Node pipeline (different runtimes, no package shared
// between them today). Keep the two in sync by hand if the formula ever
// changes — flagged in build-log.md so it isn't missed.

import { createClient } from 'npm:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

// Mirrors data-pipeline/src/scoring.js's constants exactly — see that file
// for the reasoning behind each one.
const MIN_DBA = 50;
const MAX_DBA = 90;
const HUMAN_VOICE_REFERENCE_DBA = 60;
const PLATFORM_WEIGHT: Record<string, number> = { ios: 1.0, android: 0.5, web: 0.35 };
const DEFAULT_WEIGHTS: Record<string, number> = { mic: 0.4, review: 0.25, vote: 0.2, popular: 0.15 };
const VOTE_SUBSCORE: Record<string, number> = { quiet: 100, normal: 50, loud: 0 };
const VOTE_TIERS = [3, 10];
const REVIEW_MENTION_TIERS = [3, 6];
const MIC_READING_TIERS = [3, 10];
const CONFIDENCE_LEVELS = ['Very Low', 'Low', 'Moderate', 'High', 'Very High', 'Certain'];
const VOTE_PRECEDENCE_WINDOW_MS = 5 * 60 * 1000;

function dbaToSubscore(dba: number) {
  const ratio = (dba - MIN_DBA) / (MAX_DBA - MIN_DBA);
  return clamp(100 - ratio * 100, 0, 100);
}

function calibrationOffset(calibrationDba: number) {
  return calibrationDba - HUMAN_VOICE_REFERENCE_DBA;
}

function tierPoints(count: number, tiers: number[]) {
  if (!count || count <= 0) return 0;
  let points = 1;
  for (const threshold of tiers) if (count >= threshold) points += 1;
  return points;
}

type MicReading = { decibel: number; platform: string; userId: string | null; submittedAt: string };
type Vote = { vote: string; userId: string; submittedAt: string };
type CurrentLoudnessObservation = { subscore: number; observedAt: string; source: 'mic' | 'vote' };

function micSubscore(readings: MicReading[]): number | null {
  if (readings.length === 0) return null;
  const byPlatform: Record<string, number[]> = { ios: [], android: [], web: [] };
  for (const r of readings) {
    if (byPlatform[r.platform]) byPlatform[r.platform].push(r.decibel);
  }
  const platformAverages: { avgDba: number; weight: number }[] = [];
  for (const platform of ['ios', 'android', 'web']) {
    const values = byPlatform[platform];
    if (values.length === 0) continue;
    const avgDba = values.reduce((a, b) => a + b, 0) / values.length;
    platformAverages.push({ avgDba, weight: PLATFORM_WEIGHT[platform] });
  }
  if (platformAverages.length === 0) return null;
  const weightSum = platformAverages.reduce((s, p) => s + p.weight, 0);
  const weightedDba = platformAverages.reduce((s, p) => s + p.avgDba * p.weight, 0) / weightSum;
  return dbaToSubscore(weightedDba);
}

function voteSubscore(votes: Vote[]): number | null {
  if (votes.length === 0) return null;
  const total = votes.reduce((sum, v) => sum + VOTE_SUBSCORE[v.vote], 0);
  return clamp(total / votes.length, 0, 100);
}

function filterVotesSupersededByMic(votes: Vote[], micReadings: MicReading[]): Vote[] {
  return votes.filter((vote) => {
    const voteTime = new Date(vote.submittedAt).getTime();
    return !micReadings.some((reading) => {
      if (reading.userId !== vote.userId) return false;
      const readingTime = new Date(reading.submittedAt).getTime();
      return Math.abs(readingTime - voteTime) <= VOTE_PRECEDENCE_WINDOW_MS;
    });
  });
}

/// The newest report describes the venue *right now*. It is persisted apart
/// from the historical aggregate so the client can show it at full weight and
/// then decay it toward the long-term score. When a same-user mic reading and
/// vote land within five minutes, retain the mic's more direct observation.
function latestCurrentLoudness(readings: MicReading[], votes: Vote[]): CurrentLoudnessObservation | null {
  const latestMic = readings.reduce<MicReading | null>((latest, reading) => {
    if (
      !latest ||
      new Date(reading.submittedAt).getTime() >
          new Date(latest.submittedAt).getTime()
    ) {
      return reading;
    }
    return latest;
  }, null);
  const latestVote = votes.reduce<Vote | null>((latest, vote) => {
    if (
      !latest ||
      new Date(vote.submittedAt).getTime() >
          new Date(latest.submittedAt).getTime()
    ) {
      return vote;
    }
    return latest;
  }, null);

  if (!latestMic && !latestVote) return null;

  if (
    latestVote &&
    (!latestMic ||
      new Date(latestVote.submittedAt).getTime() >
          new Date(latestMic.submittedAt).getTime())
  ) {
    const supersedingMic = readings
      .filter((reading) => {
        if (reading.userId !== latestVote.userId) return false;
        return Math.abs(new Date(reading.submittedAt).getTime() - new Date(latestVote.submittedAt).getTime()) <=
          VOTE_PRECEDENCE_WINDOW_MS;
      })
      .sort((a, b) => new Date(b.submittedAt).getTime() - new Date(a.submittedAt).getTime())[0];
    if (supersedingMic) {
      return {
        subscore: dbaToSubscore(supersedingMic.decibel),
        observedAt: supersedingMic.submittedAt,
        source: 'mic',
      };
    }
    return {
      subscore: VOTE_SUBSCORE[latestVote.vote],
      observedAt: latestVote.submittedAt,
      source: 'vote',
    };
  }

  return {
    subscore: dbaToSubscore(latestMic!.decibel),
    observedAt: latestMic!.submittedAt,
    source: 'mic',
  };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  let body: { placeId?: string };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: 'Invalid JSON body' }, 400);
  }

  const placeId = body.placeId?.trim();
  if (!placeId) {
    return jsonResponse({ error: '"placeId" is required' }, 400);
  }

  const { data: restaurant, error: restaurantError } = await supabaseAdmin
    .from('restaurants')
    .select('review_positive_count, review_negative_count, review_subscore, popular_subscore')
    .eq('place_id', placeId)
    .maybeSingle();

  if (restaurantError || !restaurant) {
    return jsonResponse({ error: 'Restaurant not found', detail: restaurantError?.message }, 404);
  }

  const [micResult, voteResult] = await Promise.all([
    supabaseAdmin.from('mic_readings').select('decibel_value, platform, user_id, submitted_at').eq('place_id', placeId),
    supabaseAdmin.from('loudness_votes').select('vote, user_id, submitted_at').eq('place_id', placeId),
  ]);

  if (micResult.error || voteResult.error) {
    return jsonResponse(
      { error: 'Could not load signals', detail: micResult.error?.message ?? voteResult.error?.message },
      500,
    );
  }

  const rawReadings: MicReading[] = (micResult.data ?? []).map((r) => ({
    decibel: Number(r.decibel_value),
    platform: r.platform as string,
    userId: r.user_id as string | null,
    submittedAt: r.submitted_at as string,
  }));

  // Calibration offsets — only for the users who actually have a reading
  // here, not every calibrated user in the project.
  const userIds = [...new Set(rawReadings.map((r) => r.userId).filter((id): id is string => Boolean(id)))];
  const calibrationByUser = new Map<string, number>();
  if (userIds.length > 0) {
    const { data: calRows } = await supabaseAdmin
      .from('mic_calibrations')
      .select('user_id, decibel_value, recorded_at')
      .in('user_id', userIds)
      .order('recorded_at', { ascending: false });
    for (const row of calRows ?? []) {
      const uid = row.user_id as string;
      if (!calibrationByUser.has(uid)) calibrationByUser.set(uid, Number(row.decibel_value));
    }
  }

  const readings = rawReadings.map((r) => {
    const calibrationDba = r.userId ? calibrationByUser.get(r.userId) : undefined;
    if (calibrationDba === undefined) return r;
    return { ...r, decibel: r.decibel - calibrationOffset(calibrationDba) };
  });

  const votes: Vote[] = (voteResult.data ?? []).map((v) => ({
    vote: v.vote as string,
    userId: v.user_id as string,
    submittedAt: v.submitted_at as string,
  }));
  const countedVotes = filterVotesSupersededByMic(votes, readings);
  const currentLoudness = latestCurrentLoudness(readings, votes);

  const mic = micSubscore(readings);
  const vote = voteSubscore(countedVotes);
  const review = restaurant.review_subscore === null ? null : Number(restaurant.review_subscore);
  const popular = restaurant.popular_subscore === null ? null : Number(restaurant.popular_subscore);

  const subscores: Record<string, number | null> = { review, popular, mic, vote };
  const present = Object.entries(subscores).filter(
    ([, v]) => v !== null && v !== undefined,
  ) as [string, number][];

  let quietnessScore: number | null = null;
  let confidence: string | null = null;

  if (present.length > 0) {
    const weightSum = present.reduce((sum, [key]) => sum + DEFAULT_WEIGHTS[key], 0);
    const score = present.reduce((sum, [key, value]) => sum + value * (DEFAULT_WEIGHTS[key] / weightSum), 0);

    const reviewCount = (restaurant.review_positive_count as number) + (restaurant.review_negative_count as number);
    const reviewPoints = tierPoints(reviewCount, REVIEW_MENTION_TIERS);
    const micPoints = tierPoints(readings.length, MIC_READING_TIERS);
    const votePoints = tierPoints(countedVotes.length, VOTE_TIERS);
    const popularPoints = popular !== null ? 3 : 0;
    const confidenceLevel = Math.min(6, Math.max(1, reviewPoints + micPoints + votePoints + popularPoints));

    quietnessScore = clamp(score, 0, 100);
    confidence = CONFIDENCE_LEVELS[confidenceLevel - 1];
  }

  const readingCountIos = readings.filter((r) => r.platform === 'ios').length;
  const readingCountAndroid = readings.filter((r) => r.platform === 'android').length;
  const nowIso = new Date().toISOString();

  const { error: updateError } = await supabaseAdmin
    .from('restaurants')
    .update({
      mic_reading_count_ios: readingCountIos,
      mic_reading_count_android: readingCountAndroid,
      mic_subscore: mic,
      mic_signal_updated_at: nowIso,
      vote_count: countedVotes.length,
      vote_subscore: vote,
      vote_signal_updated_at: nowIso,
      current_loudness_subscore: currentLoudness?.subscore ?? null,
      current_loudness_observed_at: currentLoudness?.observedAt ?? null,
      current_loudness_source: currentLoudness?.source ?? null,
      quietness_score: quietnessScore,
      confidence,
      score_updated_at: nowIso,
    })
    .eq('place_id', placeId);

  if (updateError) {
    return jsonResponse({ error: 'Failed to update restaurant', detail: updateError.message }, 500);
  }

  return jsonResponse({ quietnessScore, confidence });
});
