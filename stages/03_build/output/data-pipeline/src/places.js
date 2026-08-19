// Google Places API (New) client — restaurant identity/location + reviews.
// Calls Supabase's `places-search` Edge Function rather than Google
// directly, so GOOGLE_PLACES_API_KEY only ever lives in Supabase's Function
// secrets (added 2026-08-17), never in this pipeline's local .env. See
// supabase/functions/places-search/index.ts. Requires SUPABASE_URL,
// SUPABASE_ANON_KEY, and PIPELINE_SHARED_SECRET.

/**
 * Searches for restaurants in a given area via the places-search Edge
 * Function, paginating up to `maxPages` pages (Google returns up to 20
 * results per page; a fresh nextPageToken needs a short delay before it's
 * valid, same as the legacy Places API). Bounded rather than exhaustive —
 * each extra page is a billed request, so this caps cost per area rather
 * than draining every result.
 * @param {string} query e.g. "restaurants in Newtown NSW"
 * @param {{ supabaseUrl: string, supabaseAnonKey: string, pipelineSharedSecret: string, maxPages?: number }} config
 */
export async function searchRestaurants(
  query,
  { supabaseUrl, supabaseAnonKey, pipelineSharedSecret, maxPages = 3 } = {}
) {
  if (!supabaseUrl || !supabaseAnonKey || !pipelineSharedSecret) {
    throw new Error(
      'SUPABASE_URL, SUPABASE_ANON_KEY, and PIPELINE_SHARED_SECRET are all required to call places-search.'
    );
  }

  const places = [];
  let pageToken;

  for (let page = 0; page < maxPages; page++) {
    const res = await fetch(`${supabaseUrl}/functions/v1/places-search`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${supabaseAnonKey}`,
        apikey: supabaseAnonKey,
        'x-pipeline-secret': pipelineSharedSecret,
      },
      body: JSON.stringify(pageToken ? { pageToken } : { query }),
    });

    if (!res.ok) {
      throw new Error(`places-search request failed: ${res.status} ${await res.text()}`);
    }

    const data = await res.json();
    places.push(...(data.places || []));

    if (!data.nextPageToken) break;
    pageToken = data.nextPageToken;
    // A brand-new page token isn't immediately usable server-side yet.
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }

  return places.map(normalizePlace);
}

// Places API (New) addressComponents types, in the order Australian
// addresses actually use them for "suburb" — a locality (e.g. "Newtown") is
// the normal case; sublocality only shows up for a handful of areas Google
// treats as a locality's subdivision instead.
const SUBURB_COMPONENT_TYPES = ['locality', 'sublocality', 'sublocality_level_1'];

export function extractSuburb(addressComponents) {
  for (const type of SUBURB_COMPONENT_TYPES) {
    const match = (addressComponents || []).find((c) => c.types?.includes(type));
    if (match?.longText) return match.longText;
  }
  return null;
}

// Places API (New) returns priceLevel as an enum string (e.g.
// "PRICE_LEVEL_EXPENSIVE"), but data-schema.md/0001_init.sql define
// price_level as `smallint` (integer 1-4, matching Yelp's $ / $$ / $$$
// convention). Found live 2026-08-17 on the first real run — the insert
// failed with "invalid input syntax for type smallint" until this mapping
// was added.
const PRICE_LEVEL_MAP = {
  PRICE_LEVEL_FREE: 1,
  PRICE_LEVEL_INEXPENSIVE: 1,
  PRICE_LEVEL_MODERATE: 2,
  PRICE_LEVEL_EXPENSIVE: 3,
  PRICE_LEVEL_VERY_EXPENSIVE: 4,
};

export function normalizePriceLevel(priceLevel) {
  return PRICE_LEVEL_MAP[priceLevel] ?? null;
}

function normalizePlace(place) {
  return {
    placeId: place.id,
    name: place.displayName?.text,
    address: place.formattedAddress,
    suburb: extractSuburb(place.addressComponents),
    lat: place.location?.latitude,
    lng: place.location?.longitude,
    priceLevel: normalizePriceLevel(place.priceLevel),
    cuisine: place.primaryType,
    googleRating: place.rating,
    reviewTexts: (place.reviews || []).map((r) => r.text?.text).filter(Boolean),
  };
}
