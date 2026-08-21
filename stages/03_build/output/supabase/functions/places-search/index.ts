// Google Places API (New) proxy — added 2026-08-17. The data pipeline is a
// local Node script, not an Edge Function, so it can never read Supabase's
// Function secrets directly. This function exists purely so
// GOOGLE_PLACES_KEY only ever lives in Supabase's Function secrets, not
// in data-pipeline/.env. See "Wiring up real restaurant data" in
// build-log.md.
//
// Unlike search-assistant, this is NOT meant to be a public endpoint the
// Flutter app calls — nothing in the app does, and Google Places Text
// Search costs real money per call. The anon/publishable key alone isn't
// enough gating here, since that key is meant to be public and is already
// embedded in the app. So on top of verify_jwt, every request must also
// present a shared secret (PIPELINE_SHARED_SECRET) known only to this
// function and data-pipeline/.env — anyone with just the app's anon key
// still gets rejected.

// Named GOOGLE_PLACES_KEY (not _API_KEY) in Supabase's Function secrets —
// matches what Caelan actually set, confirmed 2026-08-17.
const GOOGLE_PLACES_API_KEY = Deno.env.get('GOOGLE_PLACES_KEY');
const PIPELINE_SHARED_SECRET = Deno.env.get('PIPELINE_SHARED_SECRET');

const FIELD_MASK = [
  'places.id',
  'places.displayName',
  'places.formattedAddress',
  'places.addressComponents',
  'places.location',
  'places.priceLevel',
  'places.primaryType',
  'places.rating',
  'places.userRatingCount',
  'places.reviews',
].join(',');

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-pipeline-secret',
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (!GOOGLE_PLACES_API_KEY) {
    // Fails loudly rather than pretending to work — this should only ever
    // happen if the secret hasn't been set yet.
    return jsonResponse({ error: 'GOOGLE_PLACES_KEY is not configured' }, 500);
  }
  if (!PIPELINE_SHARED_SECRET) {
    return jsonResponse({ error: 'PIPELINE_SHARED_SECRET is not configured' }, 500);
  }

  if (req.headers.get('x-pipeline-secret') !== PIPELINE_SHARED_SECRET) {
    return jsonResponse({ error: 'Unauthorized' }, 401);
  }

  let body: {
    query?: string;
    pageToken?: string;
    nearby?: { latitude?: number; longitude?: number; radiusMeters?: number };
  };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: 'Invalid JSON body' }, 400);
  }

  const pageToken = body.pageToken?.trim();
  const query = body.query?.trim();
  const nearby = body.nearby;

  const latitude = nearby?.latitude;
  const longitude = nearby?.longitude;
  const radiusMeters = nearby?.radiusMeters;
  const hasNearbySearch =
    Number.isFinite(latitude) &&
    Number.isFinite(longitude) &&
    Number.isFinite(radiusMeters) &&
    latitude! >= -90 &&
    latitude! <= 90 &&
    longitude! >= -180 &&
    longitude! <= 180 &&
    radiusMeters! > 0 &&
    radiusMeters! <= 50000;

  if (nearby && !hasNearbySearch) {
    return jsonResponse({ error: '"nearby" must contain valid latitude, longitude and radiusMeters (1-50000)' }, 400);
  }
  // Google requires textQuery repeated identically on a page-token
  // follow-up — "All parameters other than maxResultCount, pageSize, and
  // pageToken must be the same as the previous request. Otherwise, the API
  // returns an INVALID_ARGUMENT error." (confirmed against Google's own
  // docs 2026-08-20, after a live run hit exactly that error trying to
  // send pageToken alone). So query is always required, page 1 or not.
  if (!query && !hasNearbySearch) {
    return jsonResponse({ error: '"query" is required' }, 400);
  }

  if (hasNearbySearch && pageToken) {
    // Nearby Search has no text-search page tokens. Rejecting this avoids a
    // caller accidentally treating two incompatible Google endpoints alike.
    return jsonResponse({ error: '"pageToken" is not supported for nearby searches' }, 400);
  }

  const requestUrl = hasNearbySearch
    ? 'https://places.googleapis.com/v1/places:searchNearby'
    : 'https://places.googleapis.com/v1/places:searchText';
  // Nearby Search returns one page only; nextPageToken is a Text Search
  // response field and would make a Nearby request fail its field-mask
  // validation rather than quietly returning the same venue data.
  const fieldMask = hasNearbySearch ? FIELD_MASK : `${FIELD_MASK},nextPageToken`;
  const requestBody = hasNearbySearch
    ? {
        // These are Place types, not free-form user input. Nearby Search keeps
        // the returned venues inside the requested circle and ranks them by
        // distance, which is stronger than Text Search's optional location
        // bias for the "around me" assistant path.
        includedTypes: ['restaurant', 'cafe', 'bar', 'pub'],
        maxResultCount: 20,
        rankPreference: 'DISTANCE',
        locationRestriction: {
          circle: {
            center: { latitude, longitude },
            radius: radiusMeters,
          },
        },
      }
    : { textQuery: query, ...(pageToken ? { pageToken } : {}) };

  const placesRes = await fetch(requestUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': GOOGLE_PLACES_API_KEY,
      'X-Goog-FieldMask': fieldMask,
    },
    body: JSON.stringify(requestBody),
  });

  if (!placesRes.ok) {
    const detail = await placesRes.text();
    return jsonResponse({ error: 'Places API request failed', detail }, 502);
  }

  const data = await placesRes.json();
  return jsonResponse({ places: data.places ?? [], nextPageToken: data.nextPageToken ?? null });
});
