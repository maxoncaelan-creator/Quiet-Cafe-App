// Search Assistant backend — added 2026-08-17. Proxies chat messages to
// Anthropic's Claude Haiku, grounded in the real restaurants table so it
// can't invent a restaurant that isn't actually listed.
//
// The Anthropic API key lives only in this function's environment
// (Supabase Edge Function secrets — set via the dashboard, never in this
// file or in the Flutter client). See ui-design-decisions.md for why this
// has to be a server-side proxy rather than calling Anthropic directly
// from the app.
//
// Sign-in required + per-account rate limiting added 2026-08-18, per
// Caelan: only signed-in users may call this, and each account gets 10,000
// tokens per fixed 5-hour window (see 0007_search_assistant_rate_limit.sql
// for the accounting table). Enforced here, not just in the Flutter UI —
// the UI gate (search_assistant_screen.dart) is the normal path, but this
// function has to reject an anonymous or over-limit caller on its own,
// same as every other server-side gate in this app (mic reading auth,
// mic reading cooldown).

import { createClient } from 'npm:@supabase/supabase-js@2';

const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY');
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
// Auto-injected into every Edge Function by the Supabase runtime — not a
// dashboard secret that needed setting, unlike ANTHROPIC_API_KEY.
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

// Public data only (restaurants are publicly readable per 0001_init.sql's
// RLS policy) — the anon key is the right scope here, not service_role.
// Also used to validate the caller's JWT (auth.getUser), which needs no
// elevated privileges.
const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Rate-limit accounting only — search_assistant_usage has no write policy
// for regular users (see the migration), so this has to be the service-role
// client, not one scoped to the caller's own JWT.
const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

const TOKEN_LIMIT = 10000;
const MAX_MESSAGE_CHARS = 800;
const MAX_HISTORY_TURNS = 6;
const MAX_HISTORY_TURN_CHARS = 500;
const MAX_CONTEXT_VENUES = 20;
const MAX_CONTEXT_LINE_CHARS = 180;
const MAX_OUTPUT_TOKENS = 120;

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

type ChatMessage = { role: 'user' | 'assistant'; content: string };

type UserLocation = {
  latitude: number;
  longitude: number;
  accuracyMeters?: number;
};

type SearchScope =
  | { kind: 'area'; areaQuery: string; suburbId: string }
  | { kind: 'location'; location: UserLocation }
  | null;

// Reported to the app alongside the reply so a thin suburb can say so honestly
// instead of looking like the venue does not exist. Additive: `reply` is still
// always present, so an older build that reads only `reply` is unaffected.
type CoverageStatus =
  | { status: 'refresh_queued'; suburb: string; nextEligibleAt: string | null }
  | { status: 'refresh_pending'; suburb: string; nextEligibleAt: string | null }
  | { status: 'up_to_date'; suburb: string };

const LOCATION_RADIUS_METERS = 5000;
const LOCATION_STATE_MAX_AGE_MS = 6 * 60 * 60 * 1000;

function parseLocation(value: unknown): UserLocation | null {
  if (!value || typeof value !== 'object') return null;
  const candidate = value as { latitude?: unknown; longitude?: unknown; accuracyMeters?: unknown };
  const { latitude, longitude, accuracyMeters } = candidate;
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
  return {
    latitude,
    longitude,
    ...(typeof accuracyMeters === 'number' && Number.isFinite(accuracyMeters) && accuracyMeters >= 0
      ? { accuracyMeters }
      : {}),
  };
}

async function storeCurrentLocation(userId: string, location: UserLocation) {
  const now = new Date().toISOString();
  const { error } = await supabaseAdmin.from('user_location_state').upsert({
    user_id: userId,
    latitude: location.latitude,
    longitude: location.longitude,
    accuracy_meters: location.accuracyMeters ?? null,
    captured_at: now,
    updated_at: now,
  });
  if (error) console.error('Failed to store user location:', error.message);
}

async function loadRecentLocation(userId: string): Promise<UserLocation | null> {
  const cutoff = new Date(Date.now() - LOCATION_STATE_MAX_AGE_MS).toISOString();
  const { data, error } = await supabaseAdmin
    .from('user_location_state')
    .select('latitude, longitude, accuracy_meters')
    .eq('user_id', userId)
    .gte('captured_at', cutoff)
    .maybeSingle();
  if (error) {
    console.error('Failed to load user location:', error.message);
    return null;
  }
  return data
    ? parseLocation({
        latitude: data.latitude,
        longitude: data.longitude,
        accuracyMeters: data.accuracy_meters,
      })
    : null;
}

type ResolvedSuburbText = {
  suburb_id: string;
  canonical_name: string;
  is_active: boolean;
  match_kind: string;
};

async function findRequestedArea(message: string, history: ChatMessage[]) {
  // The database owns locality recognition. Unlike the retired regex and
  // stopword list, it can only return an official NSW alias and never turns an
  // arbitrary fragment of prose into a Places authorisation.
  //
  // Returns the whole resolved row rather than just the name: the suburb id is
  // what records demand and queues a sweep, and re-resolving the name later
  // would be a second database round trip for something already known.
  const messages = [message, ...history
    .filter((turn) => turn.role === 'user')
    .reverse()
    .map((turn) => turn.content)];
  for (const text of messages) {
    const { data, error } = await supabaseAdmin
      .rpc('resolve_nsw_suburb_in_text', { p_text: text })
      .maybeSingle();
    if (error) throw new Error(`Could not resolve requested suburb: ${error.message}`);
    const result = data as ResolvedSuburbText | null;
    if (result?.is_active) return result;
  }
  return null;
}

/// Queues a durable sweep for a suburb someone just asked about.
///
/// Free — it touches Postgres only, never Google — so it runs on every resolved
/// area question regardless of how well covered the suburb already is. What it
/// adds over the existing inline refresh is durability: the scheduled worker
/// drains this queue later, whereas an inline refresh that is rate-limited or
/// ineligible simply evaporates.
///
/// Demand is recorded as a side effect: `queue_nsw_suburb_sweep` calls
/// `record_nsw_suburb_coverage_demand` itself, so calling it here as well would
/// double-count the same question in the priority ordering.
///
/// Never throws. A failure here must not turn a working answer into an error —
/// the user asked about restaurants, not about coverage bookkeeping.
async function queueSuburbSweep(
  suburbId: string,
  canonicalName: string,
): Promise<CoverageStatus | null> {
  try {
    // 'assistant' is one of the four sources the database allows; anything else
    // raises 'Unknown suburb demand source'.
    const { data, error } = await supabaseAdmin
      .rpc('queue_nsw_suburb_sweep', { p_suburb_id: suburbId, p_source: 'assistant' })
      .maybeSingle();
    if (error) {
      console.error('Could not queue suburb sweep:', error.message);
      return null;
    }

    const result = data as { outcome: string; next_eligible_at: string | null } | null;
    if (!result) return null;

    // Outcomes come from queue_nsw_suburb_sweep: 'queued' (newly queued, or an
    // existing pending job), 'sweep_in_progress' (one is running), or an
    // ineligibility reason from suburb_sweep_eligibility — 'fresh' or
    // 'retired_or_unknown_suburb'.
    switch (result.outcome) {
      case 'queued':
        return { status: 'refresh_queued', suburb: canonicalName, nextEligibleAt: result.next_eligible_at };
      case 'sweep_in_progress':
        return { status: 'refresh_pending', suburb: canonicalName, nextEligibleAt: result.next_eligible_at };
      case 'fresh':
        // Genuinely swept recently. Claiming a refresh was queued would be a
        // lie, and the user would wait for something that is not coming.
        return { status: 'up_to_date', suburb: canonicalName };
      default:
        // 'retired_or_unknown_suburb' should be unreachable — the suburb was
        // just resolved as active — and anything the database adds later is
        // not ours to interpret. Say nothing rather than guess.
        return null;
    }
  } catch (error) {
    console.error('Could not queue suburb sweep:', error);
    return null;
  }
}

async function resolveNswSuburb(areaQuery: string): Promise<ResolvedSuburbText | null> {
  const { data, error } = await supabaseAdmin
    .rpc('resolve_nsw_suburb', { p_query: areaQuery })
    .maybeSingle();
  if (error) throw new Error(`Could not resolve requested suburb: ${error.message}`);
  return data as ResolvedSuburbText | null;
}

type VenueRequest = { name: string; suburb: string };
type VenueCandidate = {
  place_id: string;
  name: string;
  suburb: string | null;
  address: string | null;
  cuisine: string | null;
  google_rating: number | null;
  lat: number | null;
  lng: number | null;
};
type VenueDraft = {
  state: 'confirm_google_match' | 'ask_address' | 'confirm_manual';
  requested_name: string | null;
  requested_suburb: string | null;
  candidate: VenueCandidate | null;
  venue_name: string | null;
  suburb: string | null;
  address: string | null;
};

function normaliseName(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
}

function editDistance(left: string, right: string) {
  const previous = Array.from({ length: right.length + 1 }, (_, index) => index);
  for (let leftIndex = 1; leftIndex <= left.length; leftIndex++) {
    let diagonal = previous[0];
    previous[0] = leftIndex;
    for (let rightIndex = 1; rightIndex <= right.length; rightIndex++) {
      const saved = previous[rightIndex];
      previous[rightIndex] = Math.min(
        previous[rightIndex] + 1,
        previous[rightIndex - 1] + 1,
        diagonal + Number(left[leftIndex - 1] !== right[rightIndex - 1]),
      );
      diagonal = saved;
    }
  }
  return previous[right.length];
}

function isYes(value: string) {
  return /^(?:yes|yeah|yep|correct|right|that'?s right)$/i.test(value.trim());
}

function isNo(value: string) {
  return /^(?:no|nope|nah|wrong|not it)$/i.test(value.trim());
}

function isCancel(value: string) {
  return /^(?:cancel|stop|never mind|nevermind|start over)$/i.test(value.trim());
}

function extractVenueRequest(text: string): VenueRequest | null {
  const cleaned = text.trim().replace(/[?.!]+$/, '');
  let match = cleaned.match(/^(?:find|look for|search for|is there|do you know)?\s*(.+?)\s+(?:in|at|near)\s+([a-z][a-z' -]{1,60}?)$/i)
    ?? cleaned.match(/^(.+?)\s+(?:venue|restaurant|cafe|bar|pub)\s+(?:in\s+)?([a-z][a-z' -]{1,60}?)$/i);
  if (!match) {
    const reversed = cleaned.match(/^(?:in|at|near)\s+([a-z][a-z' -]{1,60}?)\s*[,\-:]\s*(.+)$/i);
    if (reversed) match = [reversed[0], reversed[2], reversed[1]];
  }
  if (!match) return null;
  const name = match[1].replace(/^(?:a |an |the )?(?:venue|restaurant|cafe|bar|pub)\s+(?:called |named )?/i, '').trim();
  const suburb = match[2].trim().replace(/\s+/g, ' ');
  if (name.length < 2 || suburb.length < 2 || /^(?:food|restaurants?|cafes?|places?)$/i.test(name)) return null;
  return { name, suburb };
}

async function loadVenueDraft(userId: string) {
  const { data, error } = await supabaseAdmin
    .from('assistant_venue_drafts')
    .select('state, requested_name, requested_suburb, candidate, venue_name, suburb, address')
    .eq('user_id', userId)
    .maybeSingle();
  if (error) throw new Error(`Could not load venue draft: ${error.message}`);
  return data as VenueDraft | null;
}

async function saveVenueDraft(userId: string, draft: Partial<VenueDraft> & { state: VenueDraft['state'] }) {
  const { error } = await supabaseAdmin.from('assistant_venue_drafts').upsert({
    user_id: userId,
    ...draft,
    updated_at: new Date().toISOString(),
  });
  if (error) throw new Error(`Could not save venue draft: ${error.message}`);
}

async function clearVenueDraft(userId: string) {
  const { error } = await supabaseAdmin.from('assistant_venue_drafts').delete().eq('user_id', userId);
  if (error) throw new Error(`Could not clear venue draft: ${error.message}`);
}

function rankVenueCandidates<T extends Pick<VenueCandidate, 'name'>>(name: string, venues: T[]) {
  const requested = normaliseName(name);
  const wanted = new Set(requested.split(' ').filter((word) => word.length > 2));
  return venues
    .map((venue) => ({
      venue,
      score: (() => {
        const candidate = normaliseName(venue.name);
        const sharedWords = candidate.split(' ').filter((word) => wanted.has(word)).length;
        const spellingSimilarity = 1 - editDistance(requested, candidate) / Math.max(requested.length, candidate.length, 1);
        return sharedWords * 2 + spellingSimilarity;
      })(),
    }))
    .filter(({ venue, score }) => score >= 0.55 || normaliseName(venue.name).includes(requested))
    .sort((a, b) => b.score - a.score || a.venue.name.length - b.venue.name.length)
    .slice(0, 5)
    .map(({ venue }) => venue);
}

async function findVenue(name: string, suburb: string) {
  const { data, error } = await supabaseAnon
    .from('restaurants')
    .select('place_id, name, suburb, address, cuisine, google_rating, lat, lng')
    .ilike('suburb', suburb)
    .limit(100);
  if (error) throw new Error(`Could not look up venue: ${error.message}`);
  return rankVenueCandidates(name, (data ?? []) as VenueCandidate[]);
}

function parseVenueCandidates(value: unknown): VenueCandidate[] {
  if (!value || typeof value !== 'object' || !Array.isArray((value as { candidates?: unknown }).candidates)) return [];
  return (value as { candidates: unknown[] }).candidates.flatMap((candidate) => {
    if (!candidate || typeof candidate !== 'object') return [];
    const value = candidate as Record<string, unknown>;
    if (typeof value.place_id !== 'string' || typeof value.name !== 'string') return [];
    const stringOrNull = (field: string) => typeof value[field] === 'string' ? value[field] : null;
    const numberOrNull = (field: string) => typeof value[field] === 'number' && Number.isFinite(value[field]) ? value[field] : null;
    return [{
      place_id: value.place_id,
      name: value.name,
      suburb: stringOrNull('suburb'),
      address: stringOrNull('address'),
      cuisine: stringOrNull('cuisine'),
      google_rating: numberOrNull('google_rating'),
      lat: numberOrNull('lat'),
      lng: numberOrNull('lng'),
    }];
  });
}

async function addGoogleVenue(candidate: VenueCandidate) {
  const { error } = await supabaseAdmin.from('restaurants').upsert({
    place_id: candidate.place_id,
    name: candidate.name,
    suburb: candidate.suburb,
    address: candidate.address,
    cuisine: candidate.cuisine,
    google_rating: candidate.google_rating,
    lat: candidate.lat,
    lng: candidate.lng,
  }, { onConflict: 'place_id', ignoreDuplicates: true });
  if (error) throw new Error(`Could not add Google venue: ${error.message}`);
}

async function addCommunityVenue(userId: string, draft: VenueDraft) {
  const name = draft.venue_name?.trim();
  const suburb = draft.suburb?.trim();
  if (!name || !suburb) throw new Error('Venue name and suburb are required');
  const duplicate = await findVenue(name, suburb);
  if (duplicate.some((venue) => normaliseName(venue.name) === normaliseName(name))) return false;
  const { error } = await supabaseAdmin.from('restaurants').insert({
    place_id: `community:${crypto.randomUUID()}`,
    name,
    suburb,
    address: draft.address?.trim() || null,
    source: 'community',
    community_submitted_by: userId,
    community_submitted_at: new Date().toISOString(),
    confidence: 'Low',
  });
  if (error) throw new Error(`Could not add community venue: ${error.message}`);
  return true;
}

async function continueVenueDraft(userId: string, message: string): Promise<string | null> {
  const draft = await loadVenueDraft(userId);
  if (!draft) return null;
  if (isCancel(message)) {
    await clearVenueDraft(userId);
    return 'Okay. I stopped.';
  }
  // A fresh venue request replaces an unfinished confirmation rather than
  // trapping the user in an old yes/no question.
  if (extractVenueRequest(message)) {
    await clearVenueDraft(userId);
    return null;
  }
  if (draft.state === 'confirm_google_match') {
    if (isYes(message) && draft.candidate) {
      await addGoogleVenue(draft.candidate);
      await clearVenueDraft(userId);
      return 'Okay! I added it.';
    }
    if (isNo(message)) {
      await saveVenueDraft(userId, { state: 'ask_address', venue_name: draft.requested_name, suburb: draft.requested_suburb, address: null });
      return 'Okay. What street is it on? You can say skip.';
    }
    return 'Is that the right place? Please say yes or no.';
  }
  if (draft.state === 'ask_address') {
    await saveVenueDraft(userId, { ...draft, state: 'confirm_manual', address: /^(?:skip|no|not sure)$/i.test(message.trim()) ? null : message.trim() });
    return `I have ${draft.venue_name} in ${draft.suburb}. Add it? Please say yes or no.`;
  }
  if (draft.state === 'confirm_manual') {
    if (isYes(message)) {
      const added = await addCommunityVenue(userId, draft);
      await clearVenueDraft(userId);
      return added ? 'Okay! I added it. It needs quietness readings now.' : 'That place is already here.';
    }
    if (isNo(message)) {
      await clearVenueDraft(userId);
      return 'Okay. I did not add it.';
    }
    return 'Should I add it? Please say yes or no.';
  }
  return null;
}

type CoverageRefresh = {
  succeeded: boolean;
  status?: number;
};

type AssistantBudgetClaim = {
  // 'rate_limited' is this account's own 5-hour window.
  // 'global_ceiling_reached' is the app's whole monthly Anthropic ceiling —
  // nothing the caller did, and nothing they can wait out today.
  outcome: 'granted' | 'rate_limited' | 'global_ceiling_reached';
  window_start: string;
  reserved_tokens: number;
  reset_at: string;
};

function sanitiseHistory(value: unknown): ChatMessage[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter(
      (turn): turn is ChatMessage =>
        Boolean(turn) &&
        typeof turn === 'object' &&
        ((turn as ChatMessage).role === 'user' || (turn as ChatMessage).role === 'assistant') &&
        typeof (turn as ChatMessage).content === 'string',
    )
    .slice(-MAX_HISTORY_TURNS)
    .map((turn) => ({ role: turn.role, content: turn.content.trim().slice(0, MAX_HISTORY_TURN_CHARS) }))
    .filter((turn) => turn.content.length > 0);
}

function estimatedAssistantTokens(message: string, history: ChatMessage[]) {
  const conversationChars = message.length + history.reduce((total, turn) => total + turn.content.length, 0);
  // The prompt, context lines and every user-controlled turn are explicitly
  // bounded above. Three characters/token is deliberately conservative for
  // this mostly-English payload, so the reservation remains safe until the
  // provider returns the exact total.
  const maximumPromptChars = 2_200 + MAX_CONTEXT_VENUES * MAX_CONTEXT_LINE_CHARS + conversationChars;
  return Math.min(TOKEN_LIMIT, Math.ceil(maximumPromptChars / 3) + MAX_OUTPUT_TOKENS);
}

async function claimAssistantBudget(userId: string, reservedTokens: number): Promise<AssistantBudgetClaim> {
  const { data, error } = await supabaseAdmin
    .rpc('claim_search_assistant_budget', {
      p_user_id: userId,
      p_reserved_tokens: reservedTokens,
    })
    .single();
  if (error || !data) throw new Error(`Could not reserve Assistant budget: ${error?.message ?? 'No result returned'}`);
  return data as AssistantBudgetClaim;
}

async function settleAssistantBudget(
  userId: string,
  claim: AssistantBudgetClaim,
  actualTokens: number,
) {
  const { error } = await supabaseAdmin.rpc('settle_search_assistant_budget', {
    p_user_id: userId,
    p_window_start: claim.window_start,
    p_reserved_tokens: claim.reserved_tokens,
    p_actual_tokens: actualTokens,
  });
  if (error) console.error('Failed to settle Assistant budget:', error.message);
}

/// Inline, billed coverage refresh for a GPS scope only.
///
/// Step 2b removed the equivalent path for *named suburbs*: those are queued as
/// durable sweeps instead, drained by the scheduled worker, so the assistant no
/// longer spends money mid-conversation for an area question.
///
/// Coordinates deliberately keep the inline path. There is no sweep to queue for
/// them: the sweep queue is keyed on gazetteer localities, and the gazetteer is
/// loaded with `returnGeometry=false`, so there are no boundary polygons and a
/// latitude/longitude cannot be resolved to a suburb. Removing this too would
/// leave GPS-based coverage with no way to grow at all. Its own 1 km checkpoint
/// and the shared monthly ledger remain the cost guards.
async function refreshNearbyCoverage(token: string, location: UserLocation): Promise<CoverageRefresh[]> {
  const refreshBodies = [
    { location, requestSource: 'assistant' },
    { location, coverageMode: 'nearby', requestSource: 'assistant' },
  ];

  const results: CoverageRefresh[] = [];
  for (const body of refreshBodies) {
    try {
      const response = await fetch(`${SUPABASE_URL}/functions/v1/ondemand-topup`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
          apikey: SUPABASE_ANON_KEY,
        },
        body: JSON.stringify(body),
      });
      if (!response.ok) {
        // The later database read can still answer from existing rows. Keep a
        // structured failure as well, so an empty requested suburb is never
        // misrepresented as a completed Google search.
        console.error(`ondemand-topup returned ${response.status}:`, await response.text());
        results.push({ succeeded: false, status: response.status });
      } else {
        results.push({ succeeded: true, status: response.status });
      }
    } catch (error) {
      // A coverage refresh must never turn a normal assistant question into a
      // total outage when local venues exist. An empty named suburb is handled
      // explicitly below rather than letting the model invent a reason.
      console.error('ondemand-topup request failed:', error);
      results.push({ succeeded: false });
    }
  }
  return results;
}

async function refreshVenueCoverage(token: string, name: string, suburb: string): Promise<VenueCandidate[]> {
  try {
    const response = await fetch(`${SUPABASE_URL}/functions/v1/ondemand-topup`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
        apikey: SUPABASE_ANON_KEY,
      },
      body: JSON.stringify({
        areaQuery: suburb,
        venueName: name,
        previewOnly: true,
        requestSource: 'assistant',
      }),
    });
    if (!response.ok) {
      console.error(`Venue lookup returned ${response.status}:`, await response.text());
      return [];
    }
    return parseVenueCandidates(await response.json());
  } catch (error) {
    console.error('Venue lookup request failed:', error);
    return [];
  }
}

function haversineMeters(a: UserLocation, latitude: number, longitude: number) {
  const radians = Math.PI / 180;
  const latitudeDelta = (latitude - a.latitude) * radians;
  const longitudeDelta = (longitude - a.longitude) * radians;
  const value =
    Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(a.latitude * radians) * Math.cos(latitude * radians) * Math.sin(longitudeDelta / 2) ** 2;
  return 2 * 6371000 * Math.asin(Math.sqrt(value));
}

async function loadRestaurantContext(scope: SearchScope) {
  const fields = 'name, cuisine, suburb, quietness_score, confidence, google_rating, lat, lng';
  let query = supabaseAnon.from('restaurants').select(fields).order('quietness_score', { ascending: false, nullsFirst: false });

  if (scope?.kind === 'area') {
    query = query.ilike('suburb', scope.areaQuery).limit(50);
  } else if (scope?.kind === 'location') {
    const latitudeDelta = LOCATION_RADIUS_METERS / 111000;
    const longitudeDelta = LOCATION_RADIUS_METERS / (111000 * Math.max(Math.cos((scope.location.latitude * Math.PI) / 180), 0.01));
    query = query
      .gte('lat', scope.location.latitude - latitudeDelta)
      .lte('lat', scope.location.latitude + latitudeDelta)
      .gte('lng', scope.location.longitude - longitudeDelta)
      .lte('lng', scope.location.longitude + longitudeDelta)
      .limit(100);
  } else {
    query = query.limit(50);
  }

  const { data, error } = await query;
  if (error) throw error;
  if (scope?.kind !== 'location') return data ?? [];

  return (data ?? [])
    .filter((restaurant) =>
      typeof restaurant.lat === 'number' &&
      typeof restaurant.lng === 'number' &&
      haversineMeters(scope.location, restaurant.lat, restaurant.lng) <= LOCATION_RADIUS_METERS,
    )
    .slice(0, 50);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (!ANTHROPIC_API_KEY) {
    // Fails loudly rather than pretending to work — this should only ever
    // happen if the secret hasn't been set yet.
    return jsonResponse({ error: 'ANTHROPIC_API_KEY is not configured' }, 500);
  }

  // Signed-in users only. supabase_flutter's functions.invoke() always
  // sends *some* bearer token (the session's access token if signed in,
  // otherwise the anon key) — auth.getUser rejects the anon key the same
  // way it rejects a missing/invalid token, so this one check covers both
  // "never signed in" and "session expired" without special-casing either.
  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '');
  const { data: userData, error: userError } = await supabaseAnon.auth.getUser(token);
  if (userError || !userData.user) {
    return jsonResponse({ error: 'auth_required', message: 'Sign in to use Search Assistant.' }, 401);
  }
  const userId = userData.user.id;

  // Beta gate, enforced server-side. Until 2026-08-24 this was checked only by
  // the Flutter router, so any signed-in account could reach this Function
  // directly regardless of whether it held a redeemed code — the UI was the
  // whole gate. Every other restriction in this app is enforced on the server
  // (mic-reading auth, vote cooldown, token budget); this one was not.
  //
  // Must run as the caller, not the service role: has_beta_access() is built on
  // auth.uid(), which is null for a service-role client and would therefore
  // deny everyone. Using the caller's JWT also means this follows whatever the
  // gate currently says, including a deliberate temporary bypass, instead of
  // reimplementing the beta_codes lookup and quietly diverging from it.
  const supabaseCaller = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: hasBetaAccess, error: betaAccessError } = await supabaseCaller.rpc('has_beta_access');
  if (betaAccessError) {
    // Fail closed. A gate that opens when its own check errors is not a gate.
    console.error('Could not check beta access:', betaAccessError.message);
    return jsonResponse({ error: 'beta_access_unavailable' }, 502);
  }
  if (hasBetaAccess !== true) {
    return jsonResponse({
      error: 'beta_access_required',
      message: 'Redeem your beta code to use Search Assistant.',
    }, 403);
  }

  let body: { message?: string; history?: unknown; location?: unknown };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: 'Invalid JSON body' }, 400);
  }

  const message = typeof body.message === 'string' ? body.message.trim() : '';
  if (!message) {
    return jsonResponse({ error: '"message" is required' }, 400);
  }
  if (message.length > MAX_MESSAGE_CHARS) {
    return jsonResponse({ error: `"message" must be at most ${MAX_MESSAGE_CHARS} characters` }, 400);
  }
  try {
    const draftReply = await continueVenueDraft(userId, message);
    if (draftReply) return jsonResponse({ reply: draftReply });
  } catch (error) {
    console.error('Could not continue venue draft:', error);
    return jsonResponse({ error: 'venue_draft_unavailable' }, 502);
  }
  const history = sanitiseHistory(body.history);

  // Reserve before any coverage refresh. A caller who is out of Assistant
  // budget must not be able to bypass that limit by making us spend Google
  // Places calls before Anthropic is reached.
  let budgetClaim: AssistantBudgetClaim;
  try {
    budgetClaim = await claimAssistantBudget(userId, estimatedAssistantTokens(message, history));
  } catch (error) {
    console.error('Assistant budget reservation failed:', error);
    return jsonResponse({ error: 'assistant_unavailable' }, 502);
  }
  if (budgetClaim.outcome === 'global_ceiling_reached') {
    // Deliberately NOT reported as 'rate_limited'. Telling someone they have
    // hit their limit when the app has hit its monthly ceiling is false, and
    // sends them to check usage they cannot influence. 503 rather than 429 for
    // the same reason: this is the service being unavailable, not the caller
    // being throttled. resetAt is the start of next month.
    return jsonResponse({
      error: 'assistant_budget_exhausted',
      resetAt: budgetClaim.reset_at,
    }, 503);
  }
  if (budgetClaim.outcome !== 'granted') {
    return jsonResponse({ error: 'rate_limited', resetAt: budgetClaim.reset_at }, 429);
  }

  let budgetSettled = false;
  let providerRequestAttempted = false;
  try {
    // Every assistant request can carry a fresh GPS fix. Store it behind the
    // authenticated backend (not the client Data API), then fall back to the
    // caller's recent fix for follow-up turns that do not need another device
    // lookup. Only the latest fix is retained, and only for six hours of use.
    const suppliedLocation = parseLocation(body.location);
    if (suppliedLocation) await storeCurrentLocation(userId, suppliedLocation);
    const currentLocation = suppliedLocation ?? (await loadRecentLocation(userId));
    const venueRequest = extractVenueRequest(message);
    if (venueRequest) {
      const resolvedVenueSuburb = await resolveNswSuburb(venueRequest.suburb);
      if (!resolvedVenueSuburb?.is_active) {
        return jsonResponse({ reply: 'I could not recognise that NSW suburb. Please check the name.' });
      }
      const canonicalVenueSuburb = resolvedVenueSuburb.canonical_name;
      const localMatches = await findVenue(venueRequest.name, canonicalVenueSuburb);
      const localExact = localMatches.find((venue) => normaliseName(venue.name) === normaliseName(venueRequest.name));
      if (localExact) {
        return jsonResponse({ reply: `I found ${localExact.name} in ${localExact.suburb}.` });
      }

      // A close database name is not proof that it is the venue the user
      // meant. Search Google for the requested name before offering a match.
      const googleMatches = rankVenueCandidates(
        venueRequest.name,
        await refreshVenueCoverage(token, venueRequest.name, canonicalVenueSuburb),
      );
      if (googleMatches.length > 0) {
        const exact = googleMatches.find((venue) => normaliseName(venue.name) === normaliseName(venueRequest.name));
        if (exact) {
          await addGoogleVenue(exact);
          return jsonResponse({ reply: `I found ${exact.name} in ${exact.suburb ?? canonicalVenueSuburb}.` });
        }
        const candidate = googleMatches[0];
        await saveVenueDraft(userId, {
          state: 'confirm_google_match',
          requested_name: venueRequest.name,
          requested_suburb: canonicalVenueSuburb,
          candidate,
        });
        return jsonResponse({
          reply: `I found ${candidate.name} in ${candidate.suburb ?? canonicalVenueSuburb}. Is that right? Say yes or no.`,
        });
      }
      await saveVenueDraft(userId, {
        state: 'ask_address',
        requested_name: venueRequest.name,
        requested_suburb: canonicalVenueSuburb,
        venue_name: venueRequest.name,
        suburb: canonicalVenueSuburb,
        address: null,
      });
      return jsonResponse({ reply: `I cannot find ${venueRequest.name}. What street is it on? You can say skip.` });
    }
    const requestedArea = await findRequestedArea(message, history);
    const scope: SearchScope = requestedArea
      ? { kind: 'area', areaQuery: requestedArea.canonical_name, suburbId: requestedArea.suburb_id }
      : currentLocation
        ? { kind: 'location', location: currentLocation }
        : null;

    // Queue a durable sweep before anything else. Free, no Google call, and it
    // records demand as a side effect so the scheduled worker's priority
    // ordering sees what people actually ask for. Deliberately unconditional: a
    // well-covered suburb still signals interest, and the call returns 'fresh'
    // rather than queueing anything.
    const coverage = requestedArea
      ? await queueSuburbSweep(requestedArea.suburb_id, requestedArea.canonical_name)
      : null;

    // This must happen before loading the assistant context. A named suburb
    // with zero stored venues therefore asks Google Places, inserts safe new
    // rows, then gives Haiku the refreshed rows in this same answer.
    //
    // Deliberately retained for now even though the sweep above is the intended
    // long-term path. `coverage_automation_config.enabled` is still false, so
    // nothing drains the queue — removing this would mean coverage could never
    // grow at all. Step 2b removes it once scheduled sweeps are switched on.
    // See execution-plan-2026-08-23.md.
    // Named suburbs no longer spend money here — queueSuburbSweep() above has
    // already queued a durable sweep the scheduled worker will drain. Only a
    // GPS scope still refreshes inline; see refreshNearbyCoverage().
    const coverageRefreshes = scope?.kind === 'location'
      ? await refreshNearbyCoverage(token, scope.location)
      : [];

    let restaurants: Awaited<ReturnType<typeof loadRestaurantContext>>;
    try {
      restaurants = await loadRestaurantContext(scope);
    } catch (error) {
      console.error('Could not load restaurant data:', error);
      return jsonResponse({ error: 'restaurant_data_unavailable' }, 502);
    }

    // If a Google-backed refresh actually failed and there are no local options,
    // be precise with the user. The old flow swallowed the 502 and left Haiku to
    // claim that it had no ability to call Google at all.
    // An empty named suburb. Since step 2b this is no longer a failed Google
    // call — nothing was attempted, because area coverage is queued rather than
    // bought inline. Say that plainly instead of letting Haiku guess from an
    // empty list, and only promise a look when one is genuinely queued.
    if (scope?.kind === 'area' && restaurants.length === 0) {
      const sweepComing = coverage?.status === 'refresh_queued' ||
        coverage?.status === 'refresh_pending';
      return jsonResponse({
        reply: sweepComing
          ? `I do not have any places in ${scope.areaQuery} yet. I have asked for a look. Please check back soon.`
          : `I do not have any places in ${scope.areaQuery} yet.`,
        ...(coverage ? { coverage } : {}),
      });
    }

    // A GPS scope can still fail a real Google call. Keep that precise rather
    // than letting Haiku claim it cannot search Google at all.
    if (
      scope?.kind === 'location' &&
      restaurants.length === 0 &&
      coverageRefreshes.some((refresh) => !refresh.succeeded)
    ) {
      return jsonResponse({
        reply: 'I could not check for places near you just now. Please try again in a moment.',
      });
    }

    const restaurantContext = restaurants
      .slice(0, MAX_CONTEXT_VENUES)
      .map((r) => {
        // confidence is only ever null when quietness_score is also null (see
        // combineScores() in scoring.js), so no fallback is needed here.
        const quietness = r.quietness_score == null ? 'no quietness data yet' : `quietness ${Math.round(r.quietness_score)}/100 (${r.confidence} confidence)`;
        const rating = r.google_rating == null ? 'unrated' : `${r.google_rating}★ on Google`;
        return `- ${r.name} — ${r.cuisine ?? 'cuisine unknown'}, ${r.suburb ?? 'suburb unknown'}, ${quietness}, ${rating}`
          .slice(0, MAX_CONTEXT_LINE_CHARS);
      })
      .join('\n');

    const systemPrompt = `You are the Search Assistant inside Quiet Restaurant Finder, an app that ranks Sydney restaurants by how quiet they are. Higher quietness_score means quieter/better.

Help the user find a restaurant that matches what they ask for. Use ONLY the restaurant data below. Never invent a restaurant. For a named suburb with venues, name two or three real options. If there are none, say so simply.

Do not claim to have just searched Google, and do not claim you cannot search at all. The app keeps its own venue list topped up in the background, so a thin suburb may gain more places later. If the list looks short, say what is there and that more may be added — never that you checked and this is everything.

Talk like you are helping a five-year-old: use little words, one or two short sentences, and no long explanations.

Reply in plain conversational text only — no markdown (no **bold**, no bullet/numbered lists, no headers). This is shown in a plain-text chat bubble that doesn't render markdown, so formatting characters would show up literally to the user. Use plain sentences or a simple dash-prefixed line if you need to list a couple of things.

Search scope: ${scope?.kind === 'area' ? scope.areaQuery : scope?.kind === 'location' ? `within ${LOCATION_RADIUS_METERS / 1000} km of the user's current location` : 'all loaded venues'}

Current restaurants:
${restaurantContext || '(none loaded yet)'}`;

    providerRequestAttempted = true;
    const anthropicRes = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: MAX_OUTPUT_TOKENS,
        system: systemPrompt,
        messages: [...history, { role: 'user', content: message }],
      }),
    });

    if (!anthropicRes.ok) {
      console.error('Anthropic API error:', anthropicRes.status, await anthropicRes.text());
      return jsonResponse({ error: 'assistant_unavailable' }, 502);
    }

    const data = await anthropicRes.json();
    const reply = data.content?.[0]?.text ?? '';

    const usage = data.usage ?? {};
    const inputTokens = typeof usage.input_tokens === 'number' ? usage.input_tokens : 0;
    const outputTokens = typeof usage.output_tokens === 'number' ? usage.output_tokens : 0;
    const tokensThisCall = inputTokens + outputTokens;

    await settleAssistantBudget(userId, budgetClaim, tokensThisCall);
    budgetSettled = true;

    // `coverage` is additive. An older app build reads only `reply` and is
    // unaffected, so this Function and the Flutter change can deploy in either
    // order without breaking anyone mid-release.
    return jsonResponse({ reply, ...(coverage ? { coverage } : {}) });
  } finally {
    if (!budgetSettled) {
      // Once a provider request is dispatched, retain the conservative
      // reservation if the provider fails before reporting exact usage.
      await settleAssistantBudget(
        userId,
        budgetClaim,
        providerRequestAttempted ? budgetClaim.reserved_tokens : 0,
      );
    }
  }
});
