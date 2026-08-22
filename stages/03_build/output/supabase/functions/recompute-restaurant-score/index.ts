// Retired score-recompute endpoint. Score aggregation now runs in database
// triggers (migration 20260822154500), atomically with every contribution.
// Keep this compatibility endpoint deployed until it is explicitly removed
// from each Supabase environment; it intentionally performs no work.

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve((req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  return new Response(JSON.stringify({ error: 'recompute_endpoint_retired' }), {
    status: 410,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
});
