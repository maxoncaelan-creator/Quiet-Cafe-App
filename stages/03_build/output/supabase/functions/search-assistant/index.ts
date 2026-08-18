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

  let body: { message?: string; history?: ChatMessage[] };
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

  const { data: restaurants, error: dbError } = await supabaseAnon
    .from('restaurants')
    .select('name, cuisine, suburb, quietness_score, confidence, google_rating')
    .order('quietness_score', { ascending: false, nullsFirst: false })
    .limit(50);

  if (dbError) {
    return jsonResponse({ error: 'Could not load restaurant data', detail: dbError.message }, 502);
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

Help the user find a restaurant that matches what they're asking for — cuisine, suburb, how quiet they need it, price, whatever they mention. Use ONLY the restaurant data below. Never invent a restaurant that isn't listed here. If nothing in the list matches what they're after, say so plainly rather than guessing or making something up. Keep replies short and conversational, like a helpful local, not a formal report.

Reply in plain conversational text only — no markdown (no **bold**, no bullet/numbered lists, no headers). This is shown in a plain-text chat bubble that doesn't render markdown, so formatting characters would show up literally to the user. Use plain sentences or a simple dash-prefixed line if you need to list a couple of things.

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
