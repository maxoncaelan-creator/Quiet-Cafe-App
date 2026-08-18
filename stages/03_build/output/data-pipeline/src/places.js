// Google Places API (New) client — restaurant identity/location + reviews.
// Calls Supabase's `places-search` Edge Function rather than Google
// directly, so GOOGLE_PLACES_API_KEY only ever lives in Supabase's Function
// secrets (added 2026-08-17), never in this pipeline's local .env. See
// supabase/functions/places-search/index.ts. Requires SUPABASE_URL,
// SUPABASE_ANON_KEY, and PIPELINE_SHARED_SECRET.

/**
 * Searches for restaurants in a given city via the places-search Edge Function.
 * @param {string} query e.g. "restaurants in Sydney NSW"
 * @param {{ supabaseUrl: string, supabaseAnonKey: string, pipelineSharedSecret: string }} config
 */
export async function searchRestaurants(query, { supabaseUrl, supabaseAnonKey, pipelineSharedSecret } = {}) {
  if (!supabaseUrl || !supabaseAnonKey || !pipelineSharedSecret) {
    throw new Error(
      'SUPABASE_URL, SUPABASE_ANON_KEY, and PIPELINE_SHARED_SECRET are all required to call places-search.'
    );
  }

  const res = await fetch(`${supabaseUrl}/functions/v1/places-search`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${supabaseAnonKey}`,
      apikey: supabaseAnonKey,
      'x-pipeline-secret': pipelineSharedSecret,
    },
    body: JSON.stringify({ query }),
  });

  if (!res.ok) {
    throw new Error(`places-search request failed: ${res.status} ${await res.text()}`);
  }

  const data = await res.json();
  return (data.places || []).map(normalizePlace);
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
    lat: place.location?.latitude,
    lng: place.location?.longitude,
    priceLevel: normalizePriceLevel(place.priceLevel),
    cuisine: place.primaryType,
    googleRating: place.rating,
    reviewTexts: (place.reviews || []).map((r) => r.text?.text).filter(Boolean),
  };
}
