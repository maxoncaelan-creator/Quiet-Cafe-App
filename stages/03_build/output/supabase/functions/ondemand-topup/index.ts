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
const MIN_COVERAGE = 15;
const DEFAULT_LOCATION_RADIUS_METERS = 5000;
const LIST_NEARBY_RADIUS_METERS = 1000;
const AREA_RECHECK_AFTER_MS = 24 * 60 * 60 * 1000;

type UserLocation = {
  latitude: number;
  longitude: number;
};

type TopupTarget =
  | { kind: 'area'; areaQuery: string; eventKey: string }
  | {
      kind: 'location';
      location: UserLocation;
      eventKey: string;
      radiusMeters: number;
      usesNearbyCheckpoint: boolean;
    };

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
    if (!res.ok) throw new Error(`places-search failed: ${res.status} ${await res.text()}`);
    const data = await res.json();
    places.push(...(data.places ?? []));
    if (!data.nextPageToken) break;
    pageToken = data.nextPageToken;
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }

  return { places: places.map(normalizePlace), possiblyTruncated: places.length >= maxPages * 20 };
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
  if (!res.ok) throw new Error(`places-search nearby failed: ${res.status} ${await res.text()}`);
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
  if (target.kind === 'location' && target.usesNearbyCheckpoint) {
    return 'A user requested a direct 1 km nearby venue check.';
  }
  if (currentResultCount === 0) {
    return 'No venues are currently listed for this search scope.';
  }
  return `${currentResultCount} venues are below the ${MIN_COVERAGE}-venue coverage threshold.`;
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

  let body: { areaQuery?: string; location?: unknown; coverageMode?: unknown };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: 'Invalid JSON body' }, 400);
  }

  const areaQuery = typeof body.areaQuery === 'string'
    ? body.areaQuery.trim().replace(/\s+/g, ' ')
    : undefined;
  const location = parseLocation(body.location);
  const useNearbyRefresh = body.coverageMode === 'nearby';
  if (body.coverageMode !== undefined && !useNearbyRefresh) {
    return jsonResponse({ error: 'Unknown coverage mode' }, 400);
  }
  if (areaQuery && areaQuery.length > AREA_QUERY_MAX_LENGTH) {
    return jsonResponse({ error: `"areaQuery" must be under ${AREA_QUERY_MAX_LENGTH} characters` }, 400);
  }
  if ((!areaQuery && !location) || (areaQuery && location)) {
    return jsonResponse({ error: 'Provide exactly one of "areaQuery" or "location"' }, 400);
  }
  if (useNearbyRefresh && !location) {
    return jsonResponse({ error: 'The nearby coverage mode requires a location' }, 400);
  }
  const target: TopupTarget = areaQuery
    ? { kind: 'area', areaQuery, eventKey: `area:${areaQuery.toLowerCase()}` }
    : {
        kind: 'location',
        location: location!,
        eventKey: locationEventKey(location!),
        radiusMeters: useNearbyRefresh
          ? LIST_NEARBY_RADIUS_METERS
          : DEFAULT_LOCATION_RADIUS_METERS,
        usesNearbyCheckpoint: useNearbyRefresh,
      };

  // 1. Current coverage + recency. Explicit suburbs count their exact
  // database scope; coordinate requests use their own explicit radius rather
  // than treating the device's raw coordinates as a fake suburb string.
  let currentResultCount: number;
  if (target.kind === 'area') {
    const { count, error } = await supabaseAnon
      .from('restaurants')
      .select('place_id', { count: 'exact', head: true })
      .ilike('suburb', `%${target.areaQuery}%`);
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
  // already stored locally. Its separate seven-day checkpoint above controls
  // repetition. The pre-existing assistant 5 km and area flows retain their
  // broader minimum-coverage policy.
  if (
    (target.kind === 'location' && !target.usesNearbyCheckpoint && currentResultCount >= MIN_COVERAGE) ||
    (target.kind === 'area' && currentResultCount >= MIN_COVERAGE)
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
    !(target.kind === 'location' && target.usesNearbyCheckpoint) &&
    lastEvent &&
    Date.now() - new Date(lastEvent.triggered_at).getTime() < AREA_RECHECK_AFTER_MS
  ) {
    return jsonResponse({ triggered: false, reason: 'recently_checked', resultCount: currentResultCount });
  }

  // 2. The explicit 1 km mode always checks Google after an atomically
  // claimed nearby-cache reservation. Every other scope checks whenever its
  // result count is below MIN_COVERAGE and the recency guard has passed.
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

  // 4. Yes — search, score, upsert additively. Once the Google request is
  // attempted, complete the reservation even if a later response or write
  // fails: that conservative accounting cannot understate paid API usage.
  let paidGoogleRequestAttempted = false;
  try {
    const byPlaceId = new Map<string, ReturnType<typeof normalizePlace>>();
    paidGoogleRequestAttempted = true;
    if (target.kind === 'location') {
      for (const place of await searchNearbyPlaces(target.location, target.radiusMeters)) byPlaceId.set(place.placeId, place);
    } else {
      const baseQuery = `restaurants, cafes, pubs and bars in ${target.areaQuery} NSW`;
      const { places: baseResults, possiblyTruncated } = await searchPlaces(baseQuery, BASE_MAX_PAGES);
      for (const place of baseResults) byPlaceId.set(place.placeId, place);
      if (possiblyTruncated) {
        for (const category of FOLLOWUP_CATEGORIES) {
          const { places: followupResults } = await searchPlaces(`${category} in ${target.areaQuery} NSW`, 1);
          for (const place of followupResults) byPlaceId.set(place.placeId, place);
        }
      }
    }

    const rows = [...byPlaceId.values()]
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
        };
      });

    // Additive only — see the file header. ignoreDuplicates makes this an
    // INSERT ... ON CONFLICT (place_id) DO NOTHING under the hood.
    const { error: upsertError } = await supabaseAdmin
      .from('restaurants')
      .upsert(rows, { onConflict: 'place_id', ignoreDuplicates: true });

    await supabaseAdmin.from('ondemand_topup_events').insert({
      user_id: userData.user.id,
      reservation_id: reservation.reservation_id,
      area_query: target.eventKey,
      haiku_decision: 'yes',
      haiku_reason: reason,
      result_count_before: currentResultCount,
      places_found: rows.length,
    });

    if (upsertError) {
      return jsonResponse({ triggered: true, placesFound: rows.length, upsertError: upsertError.message }, 207);
    }

    // A failed request/upsert stays retryable. Record the location only once
    // Google’s outcome has made it into the venue list, including a valid
    // zero-place search result.
    if (target.kind === 'location' && target.usesNearbyCheckpoint) {
      await recordNearbyCheckpoint(target.location, currentResultCount, rows.length);
    }
    return jsonResponse({ triggered: true, placesFound: rows.length, reason });
  } catch (err) {
    console.error('ondemand-topup: Search/upsert failed', err);
    return jsonResponse({ error: 'Search/upsert failed' }, 502);
  } finally {
    if (paidGoogleRequestAttempted) {
      await completeTopupReservation(reservation.reservation_id);
    } else {
      await releaseTopupReservation(reservation.reservation_id);
    }
  }
});
