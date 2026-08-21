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
const WINDOW_MS = 5 * 60 * 60 * 1000; // 5 hours — keep in sync with search_assistant_screen.dart's client-side check

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
  | { kind: 'area'; areaQuery: string }
  | { kind: 'location'; location: UserLocation }
  | null;

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

function extractAreaQuery(text: string): string | null {
  // The assistant only needs an explicit place phrase, not a full natural-
  // language parser. This catches "in Leppington", "near Leppington" and
  // "around Leppington" deterministically before it decides whether to call
  // Places; any unknown name simply yields no Google results, never a made-up
  // venue. Conversation history is checked by the caller for follow-up turns.
  const match = text.match(
    /\b(?:in|near|around|at)\s+([a-z][a-z' -]{1,60}?)(?=\s+(?:for|with|that|which|tonight|today|tomorrow|please)\b|[?.!,]|$)/i,
  );
  if (!match) return null;
  const area = match[1].trim().replace(/\s+/g, ' ');
  if (!area || /^(?:me|here|my location|nearby)$/i.test(area)) return null;
  return area;
}

function findRequestedArea(message: string, history: ChatMessage[]) {
  return [message, ...history.filter((turn) => turn.role === 'user').reverse().map((turn) => turn.content)]
    .map(extractAreaQuery)
    .find((area): area is string => area != null);
}

async function refreshThinCoverage(token: string, scope: Exclude<SearchScope, null>) {
  const refreshBodies = scope.kind === 'area'
    ? [{ areaQuery: scope.areaQuery }]
    : [
        { location: scope.location },
        { location: scope.location, coverageMode: 'nearby' },
      ];

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
      if (!response.ok) console.error(`ondemand-topup returned ${response.status}:`, await response.text());
    } catch (error) {
      // A coverage refresh must never turn a normal assistant question into a
      // total outage. The following database read still answers from any local
      // venues already available.
      console.error('ondemand-topup request failed:', error);
    }
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
    query = query.ilike('suburb', `%${scope.areaQuery}%`).limit(50);
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

  let body: { message?: string; history?: ChatMessage[]; location?: unknown };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: 'Invalid JSON body' }, 400);
  }

  const message = body.message?.trim();
  if (!message) {
    return jsonResponse({ error: '"message" is required' }, 400);
  }
  const history = Array.isArray(body.history) ? body.history : [];

  // Fixed 5-hour window per account, not sliding — simplest to reason
  // about and to explain to the user ("available again in X"). A window
  // that's expired resets tokensUsed to 0 as part of this same check, so a
  // blocked response below can only ever mean the window is still active.
  const { data: usageRow } = await supabaseAdmin
    .from('search_assistant_usage')
    .select('window_start, tokens_used')
    .eq('user_id', userId)
    .maybeSingle();

  const now = new Date();
  let windowStart = usageRow ? new Date(usageRow.window_start) : now;
  let tokensUsed = usageRow?.tokens_used ?? 0;

  if (now.getTime() - windowStart.getTime() >= WINDOW_MS) {
    windowStart = now;
    tokensUsed = 0;
  }

  if (tokensUsed >= TOKEN_LIMIT) {
    const resetAt = new Date(windowStart.getTime() + WINDOW_MS);
    return jsonResponse({ error: 'rate_limited', resetAt: resetAt.toISOString() }, 429);
  }

  // Every assistant request can carry a fresh GPS fix. Store it behind the
  // authenticated backend (not the client Data API), then fall back to the
  // caller's recent fix for follow-up turns that do not need another device
  // lookup. Only the latest fix is retained, and only for six hours of use.
  const suppliedLocation = parseLocation(body.location);
  if (suppliedLocation) await storeCurrentLocation(userId, suppliedLocation);
  const currentLocation = suppliedLocation ?? (await loadRecentLocation(userId));
  const requestedArea = findRequestedArea(message, history);
  const scope: SearchScope = requestedArea
    ? { kind: 'area', areaQuery: requestedArea }
    : currentLocation
      ? { kind: 'location', location: currentLocation }
      : null;

  // This must happen before loading the assistant context. A named suburb
  // with zero stored venues therefore asks Google Places, inserts safe new
  // rows, then gives Haiku the refreshed rows in this same answer.
  if (scope) await refreshThinCoverage(token, scope);

  let restaurants: Awaited<ReturnType<typeof loadRestaurantContext>>;
  try {
    restaurants = await loadRestaurantContext(scope);
  } catch (error) {
    return jsonResponse({ error: 'Could not load restaurant data', detail: String(error) }, 502);
  }

  const restaurantContext = (restaurants ?? [])
    .map((r) => {
      // confidence is only ever null when quietness_score is also null (see
      // combineScores() in scoring.js), so no fallback is needed here.
      const quietness = r.quietness_score == null ? 'no quietness data yet' : `quietness ${Math.round(r.quietness_score)}/100 (${r.confidence} confidence)`;
      const rating = r.google_rating == null ? 'unrated' : `${r.google_rating}★ on Google`;
      return `- ${r.name} — ${r.cuisine ?? 'cuisine unknown'}, ${r.suburb ?? 'suburb unknown'}, ${quietness}, ${rating}`;
    })
    .join('\n');

  const systemPrompt = `You are the Search Assistant inside Quiet Restaurant Finder, an app that ranks Sydney restaurants by how quiet they are. Higher quietness_score means quieter/better.

Help the user find a restaurant that matches what they're asking for — cuisine, suburb, how quiet they need it, price, whatever they mention. Use ONLY the restaurant data below. Never invent a restaurant that isn't listed here. If the requested area still has no listed venues after a refresh, say that the app could not find a venue there yet and invite the user to try a nearby area; never tell them to Google it. Keep replies short and conversational, like a helpful local, not a formal report.

Reply in plain conversational text only — no markdown (no **bold**, no bullet/numbered lists, no headers). This is shown in a plain-text chat bubble that doesn't render markdown, so formatting characters would show up literally to the user. Use plain sentences or a simple dash-prefixed line if you need to list a couple of things.

Search scope: ${scope?.kind === 'area' ? scope.areaQuery : scope?.kind === 'location' ? `within ${LOCATION_RADIUS_METERS / 1000} km of the user's current location` : 'all loaded venues'}

Current restaurants:
${restaurantContext || '(none loaded yet)'}`;

  const anthropicRes = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 512,
      system: systemPrompt,
      messages: [...history, { role: 'user', content: message }],
    }),
  });

  if (!anthropicRes.ok) {
    const detail = await anthropicRes.text();
    return jsonResponse({ error: 'Anthropic API error', detail }, 502);
  }

  const data = await anthropicRes.json();
  const reply = data.content?.[0]?.text ?? '';

  const usage = data.usage ?? {};
  const tokensThisCall = (usage.input_tokens ?? 0) + (usage.output_tokens ?? 0);

  // Best-effort — an accounting write failing shouldn't block a reply the
  // user already paid a real Anthropic call for. Logged, not thrown.
  const { error: upsertError } = await supabaseAdmin.from('search_assistant_usage').upsert({
    user_id: userId,
    window_start: windowStart.toISOString(),
    tokens_used: tokensUsed + tokensThisCall,
  });
  if (upsertError) {
    console.error('Failed to record search assistant usage:', upsertError.message);
  }

  return jsonResponse({ reply });
});
