// Search Assistant backend — added 2026-08-17. Proxies chat messages to
// Anthropic's Claude Haiku, grounded in the real restaurants table so it
// can't invent a restaurant that isn't actually listed.
//
// The Anthropic API key lives only in this function's environment
// (Supabase Edge Function secrets — set via the dashboard, never in this
// file or in the Flutter client). See ui-design-decisions.md for why this
// has to be a server-side proxy rather than calling Anthropic directly
// from the app.

import { createClient } from 'npm:@supabase/supabase-js@2';

const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY');
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;

// Public data only (restaurants are publicly readable per 0001_init.sql's
// RLS policy) — the anon key is the right scope here, not service_role.
const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

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

  const { data: restaurants, error: dbError } = await supabase
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

  return jsonResponse({ reply });
});
