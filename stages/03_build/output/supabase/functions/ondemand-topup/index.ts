// On-demand suburb top-up — added 2026-08-20. The batch data-pipeline
// (data-pipeline/src/pipeline.js) pre-populates a curated, representative
// set of areas; this function is the other half — when a real search comes
// up thin for a suburb outside (or under-covered within) that curated set,
// this applies an explicit, auditable coverage policy before spending a real
// Google Places API call. It avoids both ignoring the gap and asking a
// probabilistic language model to make a billing decision.
//
// Deliberately additive-only: on conflict with an existing place_id this
// does nothing rather than overwriting. The batch pipeline's upsert
// intentionally overwrites every column, including mic/vote signals,
// because it always re-fetches those fresh — this function never fetches
// mic readings or votes at all, so upserting the same way here would wipe
// out real accumulated user data on any venue this happens to re-discover.
// New venues only; re-scoring an existing venue stays the batch pipeline's
// job.
//
// Cost guardrails: a database-backed reservation atomically enforces the
// global and per-account daily Google allowance before a paid request starts.
// Each accepted area top-up has a per-run request ceiling (2 pages base + up to 3
// single-page category follow-ups = 5 Places requests max, well under the
// batch pipeline's per-area allowance, since this can fire far more often).

import { createClient } from 'npm:@supabase/supabase-js@2';

import {
  retainPlacesInClaimedSuburb,
  type ResolvedNswSuburb,
} from '../canonicalise_claimed_suburb.ts';

const GOOGLE_PLACES_KEY_CONFIGURED = Boolean(Deno.env.get('GOOGLE_PLACES_KEY'));
const PIPELINE_SHARED_SECRET = Deno.env.get('PIPELINE_SHARED_SECRET');
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
// Auto-injected by the Supabase runtime, not a dashboard secret that needed
// setting. Used narrowly, same precedent as search-assistant's use of it
// for search_assistant_usage: restaurants has no write policy for anon,
// and this function can't hold the pipeline_service Postgres role's own
// credential (that's a raw DB connection string, not settable via any
// tool this session has — dashboard/CLI only, unlike ANTHROPIC_API_KEY
// and GOOGLE_PLACES_KEY which were already configured as Function secrets
// for other functions in this same project).
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

const BASE_MAX_PAGES = 2;
const FOLLOWUP_CATEGORIES = ['cafes', 'pubs', 'bars'];
const AREA_QUERY_MAX_LENGTH = 80;
const VENUE_NAME_MAX_LENGTH = 120;
// This is deliberately location-only. Suburbs now use canonical sweep
// freshness, never how many restaurants happen to be stored there. Keeping the
// existing five-kilometre GPS guard distinct avoids silently increasing mobile
// Google spend while Step 1 fixes the suburb policy.
const MIN_ASSISTANT_LOCATION_COVERAGE = 15;
const DEFAULT_LOCATION_RADIUS_METERS = 5000;
const LIST_NEARBY_RADIUS_METERS = 1000;
const AREA_RECHECK_AFTER_MS = 24 * 60 * 60 * 1000;

type UserLocation = {
  latitude: number;
  longitude: number;
};

type TopupTarget =
  | {
      kind: 'area';
      suburbId: string;
      areaQuery: string;
      venueName?: string;
      previewOnly?: boolean;
      eventKey: string;
    }
  | {
      kind: 'location';
      location: UserLocation;
      eventKey: string;
      radiusMeters: number;
      usesNearbyCheckpoint: boolean;
    };

class MonthlyPlacesBudgetReached extends Error {
  constructor() {
    super('monthly_places_budget_reached');
  }
}

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

function parseLocation(value: unknown): UserLocation | null {
  if (!value || typeof value !== 'object') return null;
  const candidate = value as { latitude?: unknown; longitude?: unknown };
  const latitude = candidate.latitude;
  const longitude = candidate.longitude;
  if (
    typeof latitude !== 'number' ||
    typeof longitude !== 'number' ||
    !Number.isFinite(latitude) ||
    !Number.isFinite(longitude) ||
    latitude < -90 ||
    latitude > 90 ||
    longitude < -180 ||
    longitude > 180
  ) {
    return null;
  }
  return { latitude, longitude };
}

function locationEventKey({ latitude, longitude }: UserLocation) {
  // The existing assistant flow treats roughly 1 km coordinate cells as one
  // 5 km search scope. The List View's stricter check uses its own exact-radius
  // checkpoint table below rather than this approximate key.
  return `location:${latitude.toFixed(2)},${longitude.toFixed(2)}`;
}

function haversineMeters(a: UserLocation, b: UserLocation) {
  const radians = Math.PI / 180;
  const latDelta = (b.latitude - a.latitude) * radians;
  const lngDelta = (b.longitude - a.longitude) * radians;
  const value =
    Math.sin(latDelta / 2) ** 2 +
    Math.cos(a.latitude * radians) * Math.cos(b.latitude * radians) * Math.sin(lngDelta / 2) ** 2;
  return 2 * 6371000 * Math.asin(Math.sqrt(value));
}

async function countNearbyRestaurants(location: UserLocation, radiusMeters: number) {
  const latitudeDelta = radiusMeters / 111000;
  const longitudeDelta = radiusMeters / (111000 * Math.max(Math.cos((location.latitude * Math.PI) / 180), 0.01));
  const { data, error } = await supabaseAnon
    .from('restaurants')
    .select('lat, lng')
    .gte('lat', location.latitude - latitudeDelta)
    .lte('lat', location.latitude + latitudeDelta)
    .gte('lng', location.longitude - longitudeDelta)
    .lte('lng', location.longitude + longitudeDelta);
  if (error) throw new Error(`Could not count nearby venues: ${error.message}`);

  return (data ?? []).filter((row) => {
    if (typeof row.lat !== 'number' || typeof row.lng !== 'number') return false;
    return haversineMeters(location, { latitude: row.lat, longitude: row.lng }) <= radiusMeters;
  }).length;
}

async function recordNearbyCheckpoint(
  location: UserLocation,
  resultCountBefore: number,
  placesFound: number,
) {
  const { error } = await supabaseAdmin
    .from('venue_coverage_checkpoints')
    .insert({
      latitude: location.latitude,
      longitude: location.longitude,
      result_count_before: resultCountBefore,
      places_found: placesFound,
    });
  if (error) throw new Error(`Could not record nearby coverage check: ${error.message}`);
}

type TopupReservationClaim = {
  reservation_id: string | null;
  outcome: string;
  checked_at: string | null;
};

async function claimTopupReservation(userId: string, target: TopupTarget): Promise<TopupReservationClaim> {
  const nearbyLocation =
    target.kind === 'location' && target.usesNearbyCheckpoint ? target.location : null;
  const { data, error } = await supabaseAdmin
    .rpc('claim_ondemand_topup_reservation', {
      p_user_id: userId,
      p_scope_key: target.eventKey,
      p_latitude: nearbyLocation?.latitude ?? null,
      p_longitude: nearbyLocation?.longitude ?? null,
    })
    .single();
  if (error || !data) {
    throw new Error(`Could not reserve paid coverage refresh: ${error?.message ?? 'No result returned'}`);
  }
  return data as TopupReservationClaim;
}

async function releaseTopupReservation(reservationId: string) {
  const { error } = await supabaseAdmin.rpc('release_ondemand_topup_reservation', {
    p_reservation_id: reservationId,
  });
  if (error) console.error('Could not release paid coverage reservation:', error.message);
}

async function completeTopupReservation(reservationId: string) {
  const { error } = await supabaseAdmin.rpc('complete_ondemand_topup_reservation', {
    p_reservation_id: reservationId,
  });
  if (error) console.error('Could not complete paid coverage reservation:', error.message);
}

async function resolveNswSuburb(areaQuery: string): Promise<ResolvedNswSuburb | null> {
  const { data, error } = await supabaseAdmin
    .rpc('resolve_nsw_suburb', { p_query: areaQuery })
    .maybeSingle();
  if (error) throw new Error(`Could not resolve NSW suburb: ${error.message}`);
  return data as ResolvedNswSuburb | null;
}

async function recordSuburbDemand(suburbId: string, source: 'assistant' | 'list' | 'named_venue') {
  const { error } = await supabaseAdmin.rpc('record_nsw_suburb_coverage_demand', {
    p_suburb_id: suburbId,
    p_source: source,
  });
  if (error) throw new Error(`Could not record suburb demand: ${error.message}`);
}

type SuburbSweepClaim = { outcome: string; lease_token: string | null };

async function claimSuburbSweep(suburbId: string): Promise<SuburbSweepClaim> {
  const { data, error } = await supabaseAdmin
    .rpc('claim_nsw_suburb_sweep', { p_suburb_id: suburbId })
    .single();
  if (error || !data) {
    throw new Error(`Could not claim suburb sweep: ${error?.message ?? 'No result returned'}`);
  }
  return data as SuburbSweepClaim;
}

async function completeSuburbSweep(
  suburbId: string,
  leaseToken: string,
  outcome: 'completed' | 'failed' | 'blocked_budget',
  pagesAttempted: number,
  pagesExhausted: boolean,
  placesFound: number,
  errorMessage?: string,
) {
  const { error } = await supabaseAdmin.rpc('complete_nsw_suburb_sweep', {
    p_suburb_id: suburbId,
    p_lease_token: leaseToken,
    p_outcome: outcome,
    p_pages_attempted: pagesAttempted,
    p_pages_exhausted: pagesExhausted,
    p_places_found: placesFound,
    p_error: errorMessage ?? null,
  });
  if (error) console.error('Could not complete suburb sweep:', error.message);
}

// --- Places search, mirroring data-pipeline/src/places.js's approach ---
// (a small, deliberate duplication rather than a shared module — this runs
// in Deno, the pipeline runs in Node, and the two call different things:
// the pipeline calls this project's own places-search Edge Function over
// HTTP either way, so there's no native-code dependency to actually share.)

async function fetchWithRetry(url: string, options: RequestInit, retries = 2, delayMs = 3000): Promise<Response> {
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(url, options);
    if (res.ok || res.status < 500 || attempt >= retries) return res;
    await new Promise((resolve) => setTimeout(resolve, delayMs));
  }
}

type RawPlace = {
  id: string;
  displayName?: { text?: string };
  formattedAddress?: string;
  addressComponents?: { longText?: string; types?: string[] }[];
  location?: { latitude?: number; longitude?: number };
  priceLevel?: string;
  primaryType?: string;
  rating?: number;
  reviews?: { text?: { text?: string } }[];
};

const SUBURB_COMPONENT_TYPES = ['locality', 'sublocality', 'sublocality_level_1'];
function extractSuburb(components: RawPlace['addressComponents']): string | null {
  for (const type of SUBURB_COMPONENT_TYPES) {
    const match = (components || []).find((c) => c.types?.includes(type));
    if (match?.longText) return match.longText;
  }
  return null;
}

const PRICE_LEVEL_MAP: Record<string, number> = {
  PRICE_LEVEL_FREE: 1,
  PRICE_LEVEL_INEXPENSIVE: 1,
  PRICE_LEVEL_MODERATE: 2,
  PRICE_LEVEL_EXPENSIVE: 3,
  PRICE_LEVEL_VERY_EXPENSIVE: 4,
};

function normalizePlace(place: RawPlace) {
  return {
    placeId: place.id,
    name: place.displayName?.text ?? null,
    address: place.formattedAddress ?? null,
    suburb: extractSuburb(place.addressComponents),
    lat: place.location?.latitude ?? null,
    lng: place.location?.longitude ?? null,
    priceLevel: place.priceLevel ? PRICE_LEVEL_MAP[place.priceLevel] ?? null : null,
    cuisine: place.primaryType ?? null,
    googleRating: place.rating ?? null,
    reviewTexts: (place.reviews || []).map((r) => r.text?.text).filter((t): t is string => Boolean(t)),
  };
}

async function searchPlaces(query: string, maxPages: number) {
  const places: RawPlace[] = [];
  let pageToken: string | undefined;
  let pagesAttempted = 0;
  let pagesExhausted = false;

  for (let page = 0; page < maxPages; page++) {
    const res = await fetchWithRetry(`${SUPABASE_URL}/functions/v1/places-search`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
        apikey: SUPABASE_ANON_KEY,
        'x-pipeline-secret': PIPELINE_SHARED_SECRET ?? '',
      },
      body: JSON.stringify({ query, ...(pageToken ? { pageToken } : {}) }),
    });
    if (!res.ok) {
      const detail = await res.text();
      if (res.status === 429 && detail.includes('monthly_places_budget_reached')) {
        throw new MonthlyPlacesBudgetReached();
      }
      throw new Error(`places-search failed: ${res.status} ${detail}`);
    }
    const data = await res.json();
    pagesAttempted += 1;
    places.push(...(data.places ?? []));
    if (!data.nextPageToken) {
      pagesExhausted = true;
      break;
    }
    pageToken = data.nextPageToken;
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }

  return {
    places: places.map(normalizePlace),
    possiblyTruncated: places.length >= maxPages * 20,
    pagesAttempted,
    pagesExhausted,
  };
}

async function searchNearbyPlaces(location: UserLocation, radiusMeters: number) {
  const res = await fetchWithRetry(`${SUPABASE_URL}/functions/v1/places-search`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
      apikey: SUPABASE_ANON_KEY,
      'x-pipeline-secret': PIPELINE_SHARED_SECRET ?? '',
    },
    body: JSON.stringify({
      nearby: {
        latitude: location.latitude,
        longitude: location.longitude,
        radiusMeters,
      },
    }),
  });
  if (!res.ok) {
    const detail = await res.text();
    if (res.status === 429 && detail.includes('monthly_places_budget_reached')) {
      throw new MonthlyPlacesBudgetReached();
    }
    throw new Error(`places-search nearby failed: ${res.status} ${detail}`);
  }
  const data = await res.json();
  return (data.places ?? []).map(normalizePlace);
}

// --- Scoring, ported from data-pipeline/src/reviewMining.js + scoring.js ---
// Only the review-text path is needed here: a venue this function inserts
// is by definition brand new to `restaurants`, so it has zero mic readings
// and zero votes — those signals are correctly absent, not skipped. The
// batch pipeline picks them up over time the normal way once real users
// submit them for a venue that now exists to submit them against.

const POSITIVE_PHRASES = ['quiet', 'peaceful', 'great for conversation', 'easy to talk', 'could hear each other', 'calm atmosphere', 'not loud', 'low key'];
const NEGATIVE_PHRASES = ['loud', 'noisy', "couldn't hear", 'could not hear', 'hard to hear', 'had to shout', 'ear-splitting', 'deafening', 'too much noise'];

function countPhraseOccurrences(text: string, phrases: string[]) {
  const lower = text.toLowerCase();
  return phrases.reduce((count, phrase) => {
    let idx = 0;
    let found = 0;
    while ((idx = lower.indexOf(phrase, idx)) !== -1) {
      found += 1;
      idx += phrase.length;
    }
    return count + found;
  }, 0);
}

function mineNoiseMentions(reviewTexts: string[]) {
  let positiveCount = 0;
  let negativeCount = 0;
  for (const text of reviewTexts || []) {
    if (!text) continue;
    positiveCount += countPhraseOccurrences(text, POSITIVE_PHRASES);
    negativeCount += countPhraseOccurrences(text, NEGATIVE_PHRASES);
  }
  return { positiveCount, negativeCount };
}

const MIN_REVIEW_MENTIONS = 1;
const REVIEW_MENTION_TIERS = [3, 6];
const CONFIDENCE_LEVELS = ['Very Low', 'Low', 'Moderate', 'High', 'Very High', 'Certain'];

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

function scoreFromReviews(positiveCount: number, negativeCount: number) {
  const total = positiveCount + negativeCount;
  if (total < MIN_REVIEW_MENTIONS) return { subscore: null, confidence: null };
  const subscore = clamp((positiveCount / total) * 100, 0, 100);
  let points = 1;
  for (const threshold of REVIEW_MENTION_TIERS) if (total >= threshold) points += 1;
  return { subscore, confidence: CONFIDENCE_LEVELS[clamp(points, 1, 6) - 1] };
}

function coverageReason(target: TopupTarget, currentResultCount: number) {
  if (target.kind === 'area' && target.venueName) {
    return 'A user asked the Search Assistant to look for one named venue.';
  }
  if (target.kind === 'location' && target.usesNearbyCheckpoint) {
    return 'A user requested a direct 1 km nearby venue check.';
  }
  if (currentResultCount === 0) {
    return 'No venues are currently listed for this search scope.';
  }
  if (target.kind === 'area') {
    return `The verified NSW locality is stale despite ${currentResultCount} stored venues.`;
  }
  return `${currentResultCount} venues are below the location coverage threshold.`;
}

// --- Handler ---

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  if (!GOOGLE_PLACES_KEY_CONFIGURED) return jsonResponse({ error: 'GOOGLE_PLACES_KEY is not configured' }, 500);
  if (!PIPELINE_SHARED_SECRET) return jsonResponse({ error: 'PIPELINE_SHARED_SECRET is not configured' }, 500);

  // verify_jwt is enabled for this function, but validate the token here as
  // well because this endpoint can spend a billed Google request. A valid JWT
  // alone is not enough: only accounts that have passed the beta gate may
  // trigger a top-up, including callers that bypass the Flutter UI.
  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '');
  const { data: userData, error: userError } = await supabaseAnon.auth.getUser(token);
  if (userError || !userData.user) {
    return jsonResponse({ error: 'auth_required', message: 'Sign in to refresh venue coverage.' }, 401);
  }
  const { data: betaAccess, error: betaAccessError } = await supabaseAdmin
    .from('beta_codes')
    .select('id')
    .eq('redeemed_by', userData.user.id)
    .not('redeemed_at', 'is', null)
    .limit(1)
    .maybeSingle();
  if (betaAccessError) {
    console.error('Could not check beta access:', betaAccessError.message);
    return jsonResponse({ error: 'beta_access_unavailable' }, 502);
  }
  if (!betaAccess) return jsonResponse({ error: 'beta_access_required' }, 403);

  let body: {
    areaQuery?: string;
    venueName?: string;
    previewOnly?: unknown;
    location?: unknown;
    coverageMode?: unknown;
    requestSource?: unknown;
  };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: 'Invalid JSON body' }, 400);
  }

  const areaQuery = typeof body.areaQuery === 'string'
    ? body.areaQuery.trim().replace(/\s+/g, ' ')
    : undefined;
  const venueName = typeof body.venueName === 'string'
    ? body.venueName.trim().replace(/\s+/g, ' ')
    : undefined;
  const previewOnly = body.previewOnly === true;
  const location = parseLocation(body.location);
  const useNearbyRefresh = body.coverageMode === 'nearby';
  const requestSource = body.requestSource === undefined
    ? 'list'
    : body.requestSource === 'assistant' || body.requestSource === 'list'
      ? body.requestSource
      : null;
  if (body.coverageMode !== undefined && !useNearbyRefresh) {
    return jsonResponse({ error: 'Unknown coverage mode' }, 400);
  }
  if (requestSource === null) {
    return jsonResponse({ error: 'Unknown request source' }, 400);
  }
  if (areaQuery && areaQuery.length > AREA_QUERY_MAX_LENGTH) {
    return jsonResponse({ error: `"areaQuery" must be under ${AREA_QUERY_MAX_LENGTH} characters` }, 400);
  }
  if (venueName && venueName.length > VENUE_NAME_MAX_LENGTH) {
    return jsonResponse({ error: `"venueName" must be under ${VENUE_NAME_MAX_LENGTH} characters` }, 400);
  }
  if (venueName && !areaQuery) {
    return jsonResponse({ error: '"venueName" requires "areaQuery"' }, 400);
  }
  if (body.previewOnly !== undefined && !previewOnly) {
    return jsonResponse({ error: '"previewOnly" must be true when supplied' }, 400);
  }
  if (previewOnly && !venueName) {
    return jsonResponse({ error: '"previewOnly" requires "venueName"' }, 400);
  }
  if ((!areaQuery && !location) || (areaQuery && location)) {
    return jsonResponse({ error: 'Provide exactly one of "areaQuery" or "location"' }, 400);
  }
  if (useNearbyRefresh && !location) {
    return jsonResponse({ error: 'The nearby coverage mode requires a location' }, 400);
  }
  let resolvedSuburb: ResolvedNswSuburb | null = null;
  if (areaQuery) {
    try {
      resolvedSuburb = await resolveNswSuburb(areaQuery);
    } catch (error) {
      console.error('Could not resolve area query:', error);
      return jsonResponse({ error: 'suburb_resolution_unavailable' }, 502);
    }
    // This check intentionally happens before a coverage read, daily
    // reservation, event key, queue entry or Places call. A natural-language
    // fragment such as "louder the better" therefore cannot spend Google.
    if (!resolvedSuburb) {
      return jsonResponse({ triggered: false, reason: 'unrecognised_suburb' });
    }
    if (!resolvedSuburb.is_active) {
      return jsonResponse({ triggered: false, reason: 'retired_suburb' });
    }
    try {
      await recordSuburbDemand(
        resolvedSuburb.suburb_id,
        venueName ? 'named_venue' : requestSource,
      );
    } catch (error) {
      console.error('Could not record area demand:', error);
      return jsonResponse({ error: 'suburb_demand_unavailable' }, 502);
    }
  }

  const target: TopupTarget = resolvedSuburb
    ? {
        kind: 'area',
        suburbId: resolvedSuburb.suburb_id,
        areaQuery: resolvedSuburb.canonical_name,
        ...(venueName ? { venueName } : {}),
        ...(previewOnly ? { previewOnly: true } : {}),
        eventKey: venueName
          ? `venue:${venueName.toLowerCase()}|suburb:${resolvedSuburb.suburb_id}`
          : `suburb:${resolvedSuburb.suburb_id}`,
      }
    : {
        kind: 'location',
        location: location!,
        eventKey: locationEventKey(location!),
        radiusMeters: useNearbyRefresh
          ? LIST_NEARBY_RADIUS_METERS
          : DEFAULT_LOCATION_RADIUS_METERS,
        usesNearbyCheckpoint: useNearbyRefresh,
      };

  // 1. Current coverage + recency. Explicit suburbs have already been resolved
  // to an official canonical label, so this is exact (case-insensitive) rather
  // than a user-controlled ILIKE substring with wildcard semantics. Coordinate
  // requests use their own explicit radius rather than a fake suburb string.
  let currentResultCount: number;
  if (target.kind === 'area') {
    const { count, error } = await supabaseAnon
      .from('restaurants')
      .select('place_id', { count: 'exact', head: true })
      .ilike('suburb', target.areaQuery);
    if (error) {
      console.error('Could not check area coverage:', error.message);
      return jsonResponse({ error: 'coverage_unavailable' }, 502);
    }
    currentResultCount = count ?? 0;
  } else {
    try {
      currentResultCount = await countNearbyRestaurants(target.location, target.radiusMeters);
    } catch (err) {
      console.error('Could not check nearby coverage:', err);
      return jsonResponse({ error: 'coverage_unavailable' }, 502);
    }
  }

  // A deliberate 1 km coordinate refresh asks Google regardless of the rows
  // already stored locally. Its separate seven-day checkpoint controls
  // repetition. The pre-existing Assistant 5 km path retains its old bounded
  // location policy; canonical suburb paths use freshness below, never count.
  if (
    target.kind === 'location' &&
    !target.usesNearbyCheckpoint &&
    currentResultCount >= MIN_ASSISTANT_LOCATION_COVERAGE
  ) {
    return jsonResponse({ triggered: false, reason: 'coverage_sufficient', resultCount: currentResultCount });
  }

  const { data: lastEvent } = await supabaseAdmin
    .from('ondemand_topup_events')
    .select('triggered_at')
    .eq('area_query', target.eventKey)
    .order('triggered_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (
    // Canonical suburb sweeps have their own durable freshness state. Keep the
    // event cooldown only for the named-venue exception and existing 5 km GPS
    // path; the explicit 1 km mode is governed by its checkpoint RPC.
    (target.kind === 'location' || Boolean(target.venueName)) &&
    !(target.kind === 'location' && target.usesNearbyCheckpoint) &&
    lastEvent &&
    Date.now() - new Date(lastEvent.triggered_at).getTime() < AREA_RECHECK_AFTER_MS
  ) {
    return jsonResponse({ triggered: false, reason: 'recently_checked', resultCount: currentResultCount });
  }

  // 2. The explicit 1 km mode always checks Google after an atomically claimed
  // nearby-cache reservation. A canonical suburb's own sweep lease below
  // decides freshness, independent of how many rows it already has.
  const reason = coverageReason(target, currentResultCount);

  // 3. Claim global, per-user, and (for 1 km mode) nearby capacity in one
  // database transaction, before any Google request, so concurrent requests
  // cannot overspend.
  let reservation: TopupReservationClaim;
  try {
    reservation = await claimTopupReservation(userData.user.id, target);
  } catch (err) {
    console.error('Could not reserve coverage refresh:', err);
    return jsonResponse({ error: 'coverage_reservation_unavailable' }, 502);
  }
  if (reservation.outcome !== 'granted' || !reservation.reservation_id) {
    return jsonResponse({
      triggered: false,
      reason: reservation.outcome,
      ...(reservation.checked_at ? { checkedAt: reservation.checked_at } : {}),
    });
  }

  // A normal area refresh shares one lease with the background worker. This
  // makes a dense but stale suburb sweepable while preventing an API caller and
  // cron from running the same paid sweep concurrently. Named-venue lookups
  // deliberately retain their one bounded immediate exception.
  let suburbSweepClaimed = false;
  let suburbSweepLeaseToken: string | null = null;
  if (target.kind === 'area' && !target.venueName) {
    let suburbClaim: SuburbSweepClaim;
    try {
      suburbClaim = await claimSuburbSweep(target.suburbId);
    } catch (error) {
      await releaseTopupReservation(reservation.reservation_id);
      console.error('Could not claim suburb sweep:', error);
      return jsonResponse({ error: 'suburb_sweep_unavailable' }, 502);
    }
    if (suburbClaim.outcome !== 'granted') {
      await releaseTopupReservation(reservation.reservation_id);
      return jsonResponse({
        triggered: false,
        reason: suburbClaim.outcome,
        resultCount: currentResultCount,
      });
    }
    if (!suburbClaim.lease_token) {
      await releaseTopupReservation(reservation.reservation_id);
      console.error('Suburb sweep grant did not include a lease token');
      return jsonResponse({ error: 'suburb_sweep_unavailable' }, 502);
    }
    suburbSweepClaimed = true;
    suburbSweepLeaseToken = suburbClaim.lease_token;
  }

  // 4. Yes — search and score. A named-venue preview returns candidates to
  // the Assistant without changing the public list; exact matches are saved
  // immediately by the Assistant, while close matches wait for confirmation.
  // Once the Google request is attempted, complete the reservation even if a
  // later response or write fails: that conservative accounting cannot
  // understate paid API usage.
  let paidGoogleRequestAttempted = false;
  let monthlyBudgetBlocked = false;
  let suburbSweepFinalised = false;
  let pagesAttempted = 0;
  let pagesExhausted = false;
  let insertedCount = 0;
  try {
    const byPlaceId = new Map<string, ReturnType<typeof normalizePlace>>();
    const materialiseRows = async () => {
      const fetchedPlaces = [...byPlaceId.values()];
      const places = target.kind === 'area'
        ? await retainPlacesInClaimedSuburb(
          fetchedPlaces,
          target.suburbId,
          resolveNswSuburb,
        )
        : fetchedPlaces;
      if (target.kind === 'area' && fetchedPlaces.length > 0 && places.length === 0) {
        // Text Search can return a neighbouring locality despite the query. Do
        // not let that unrelated result mark the requested canonical locality
        // fresh for thirty days.
        throw new Error('Places search returned no venues in the claimed NSW suburb');
      }
      return places
        .filter((r) => r.placeId && r.name)
        .map((r) => {
          const { positiveCount, negativeCount } = mineNoiseMentions(r.reviewTexts);
          const { subscore, confidence } = scoreFromReviews(positiveCount, negativeCount);
          return {
            place_id: r.placeId,
            name: r.name,
            cuisine: r.cuisine,
            price_level: r.priceLevel,
            google_rating: r.googleRating,
            address: r.address,
            suburb: r.suburb,
            lat: r.lat,
            lng: r.lng,
            review_positive_count: positiveCount,
            review_negative_count: negativeCount,
            review_subscore: subscore,
            review_signal_updated_at: new Date().toISOString(),
            mic_reading_count_ios: 0,
            mic_reading_count_android: 0,
            vote_count: 0,
            quietness_score: subscore,
            confidence,
            score_updated_at: new Date().toISOString(),
            discovered_via: target.kind === 'location'
              ? 'GPS nearby check'
              : target.venueName
                ? 'named-venue lookup'
                : 'suburb sweep',
          };
        });
    };
    const persistRows = async (rows: Awaited<ReturnType<typeof materialiseRows>>) => {
      // Additive only — see the file header. Persist each successful provider
      // page before asking for optional follow-ups. If the monthly ceiling
      // blocks a later request, already-billed results remain available rather
      // than being needlessly re-fetched next month.
      if (target.kind === 'area' && target.previewOnly) return;
      if (rows.length === 0) return;
      const { data: insertedRows, error: upsertError } = await supabaseAdmin
        .from('restaurants')
        .upsert(rows, { onConflict: 'place_id', ignoreDuplicates: true })
        .select('place_id');
      if (upsertError) throw new Error(`Restaurant upsert failed: ${upsertError.message}`);
      insertedCount += insertedRows?.length ?? 0;
    };
    let rows: Awaited<ReturnType<typeof materialiseRows>> = [];
    if (target.kind === 'location') {
      paidGoogleRequestAttempted = true;
      for (const place of await searchNearbyPlaces(target.location, target.radiusMeters)) byPlaceId.set(place.placeId, place);
      pagesAttempted = 1;
      pagesExhausted = true;
      rows = await materialiseRows();
      await persistRows(rows);
    } else {
      const baseQuery = target.venueName
        ? `${target.venueName} in ${target.areaQuery} NSW`
        : `restaurants, cafes, pubs and bars in ${target.areaQuery} NSW`;
      paidGoogleRequestAttempted = true;
      const base = await searchPlaces(
        baseQuery,
        target.venueName ? 1 : BASE_MAX_PAGES,
      );
      pagesAttempted += base.pagesAttempted;
      pagesExhausted = base.pagesExhausted;
      for (const place of base.places) byPlaceId.set(place.placeId, place);
      rows = await materialiseRows();
      await persistRows(rows);
      if (!target.venueName && base.possiblyTruncated) {
        for (const category of FOLLOWUP_CATEGORIES) {
          const followup = await searchPlaces(`${category} in ${target.areaQuery} NSW`, 1);
          pagesAttempted += followup.pagesAttempted;
          pagesExhausted = pagesExhausted && followup.pagesExhausted;
          for (const place of followup.places) byPlaceId.set(place.placeId, place);
          rows = await materialiseRows();
          await persistRows(rows);
        }
      }
    }

    const { error: eventError } = await supabaseAdmin.from('ondemand_topup_events').insert({
      user_id: userData.user.id,
      reservation_id: reservation.reservation_id,
      area_query: target.eventKey,
      haiku_decision: 'yes',
      haiku_reason: reason,
      result_count_before: currentResultCount,
      places_found: insertedCount,
    });
    if (eventError) {
      throw new Error(`Coverage event insert failed: ${eventError.message}`);
    }

    // A failed request/upsert stays retryable. Record the location only once
    // Google’s outcome has made it into the venue list, including a valid
    // zero-place search result.
    if (target.kind === 'location' && target.usesNearbyCheckpoint) {
      await recordNearbyCheckpoint(target.location, currentResultCount, insertedCount);
    }
    const candidates = target.kind === 'area' && target.previewOnly
      ? rows.slice(0, 5).map(({ place_id, name, suburb, address, cuisine, google_rating, lat, lng }) => ({
          place_id,
          name,
          suburb,
          address,
          cuisine,
          google_rating,
          lat,
          lng,
        }))
      : undefined;
    return jsonResponse({
      triggered: true,
      placesFound: insertedCount,
      ...(candidates ? { candidates } : {}),
      reason,
    });
  } catch (err) {
    if (err instanceof MonthlyPlacesBudgetReached) {
      monthlyBudgetBlocked = true;
      if (suburbSweepClaimed && suburbSweepLeaseToken && target.kind === 'area') {
        await completeSuburbSweep(
          target.suburbId,
          suburbSweepLeaseToken,
          'blocked_budget',
          pagesAttempted,
          pagesExhausted,
          insertedCount,
          'monthly Places request ceiling reached',
        );
        suburbSweepFinalised = true;
      }
      return jsonResponse({
        triggered: false,
        reason: 'monthly_places_budget_reached',
        resultCount: currentResultCount,
      });
    }
    if (suburbSweepClaimed && suburbSweepLeaseToken && target.kind === 'area') {
      await completeSuburbSweep(
        target.suburbId,
        suburbSweepLeaseToken,
        'failed',
        pagesAttempted,
        pagesExhausted,
        insertedCount,
        err instanceof Error ? err.message : 'unknown suburb sweep error',
      );
      suburbSweepFinalised = true;
    }
    console.error('ondemand-topup: Search/upsert failed', err);
    return jsonResponse({ error: 'Search/upsert failed' }, 502);
  } finally {
    if (suburbSweepClaimed && suburbSweepLeaseToken && target.kind === 'area' && !suburbSweepFinalised) {
      // A successful zero-result search is still a completed sweep. Failure
      // paths above mark failed/blocked explicitly and never advance freshness.
      await completeSuburbSweep(
        target.suburbId,
        suburbSweepLeaseToken,
        'completed',
        pagesAttempted,
        pagesExhausted,
        insertedCount,
      );
    }
    if (paidGoogleRequestAttempted && !monthlyBudgetBlocked) {
      await completeTopupReservation(reservation.reservation_id);
    } else {
      await releaseTopupReservation(reservation.reservation_id);
    }
  }
});
