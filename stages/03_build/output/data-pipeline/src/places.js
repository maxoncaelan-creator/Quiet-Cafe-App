// Google Places API (New) client — restaurant identity/location + reviews.
// Calls Supabase's `places-search` Edge Function rather than Google
// directly, so GOOGLE_PLACES_API_KEY only ever lives in Supabase's Function
// secrets (added 2026-08-17), never in this pipeline's local .env. See
// supabase/functions/places-search/index.ts. Requires SUPABASE_URL,
// SUPABASE_ANON_KEY, and PIPELINE_SHARED_SECRET.

/**
 * A shared, mutable cap on total billed places-search requests across an
 * entire run (not per-area) — created once by the caller and passed into
 * every searchRestaurants() call so areas late in the list stop cleanly
 * once the total is spent, rather than each area getting its own budget.
 * @param {number} limit
 */
export function createRequestBudget(limit) {
  let remaining = limit;
  return {
    take() {
      if (remaining <= 0) return false;
      remaining--;
      return true;
    },
    get remaining() {
      return remaining;
    },
  };
}

/**
 * Searches for restaurants in a given area via the places-search Edge
 * Function, paginating up to `maxPages` pages (Google returns up to 20
 * results per page; a fresh nextPageToken needs a short delay before it's
 * valid, same as the legacy Places API). Bounded rather than exhaustive —
 * each extra page is a billed request. Pass `budget` (see
 * createRequestBudget) to cap total requests across an entire multi-area
 * run rather than just per-area.
 * @param {string} query e.g. "restaurants in Newtown NSW"
 * @param {{ supabaseUrl: string, supabaseAnonKey: string, pipelineSharedSecret: string, maxPages?: number, budget?: ReturnType<typeof createRequestBudget> }} config
 */
export async function searchRestaurants(
  query,
  { supabaseUrl, supabaseAnonKey, pipelineSharedSecret, maxPages = 3, budget } = {}
) {
  if (!supabaseUrl || !supabaseAnonKey || !pipelineSharedSecret) {
    throw new Error(
      'SUPABASE_URL, SUPABASE_ANON_KEY, and PIPELINE_SHARED_SECRET are all required to call places-search.'
    );
  }

  const places = [];
  let pageToken;

  for (let page = 0; page < maxPages; page++) {
    if (budget && !budget.take()) break;

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

const AU_STATES = ['NSW', 'ACT', 'VIC', 'QLD', 'SA', 'WA', 'TAS', 'NT'];
const AU_STATE_NAMES = [
  'New South Wales',
  'Australian Capital Territory',
  'Victoria',
  'Queensland',
  'South Australia',
  'Western Australia',
  'Tasmania',
  'Northern Territory',
];
const TRAILING_STATE_POSTCODE = new RegExp(`\\s+(${AU_STATES.join('|')})\\s+\\d{4}$`, 'i');

/**
 * Backfill path for rows that already have `formattedAddress` but no
 * addressComponents on file (e.g. fetched before that field mask change) —
 * parses the suburb straight out of the address string instead of spending
 * another Places API request. Handles the two shapes actually seen in this
 * dataset:
 *  - Normal: "17 Willoughby St, Kirribilli NSW 2061, Australia"
 *  - Reversed (a handful of Google listings return it this way):
 *    "Australia, New South Wales, Hornsby, Pacific Hwy, FC8"
 * Returns null for anything that isn't a recognisable Australian address at
 * all (a few interstate-namesake false positives — e.g. Picton, NZ/Canada —
 * turned up in the area-query results and shouldn't get a suburb guessed
 * for them).
 */
export function extractSuburbFromAddress(address) {
  if (!address) return null;
  if (!address.includes('Australia')) return null;

  const parts = address.split(',').map((p) => p.trim()).filter(Boolean);
  if (parts.length === 0) return null;

  if (parts[0] === 'Australia') {
    // Reversed shape: Australia, <state name>, <suburb>, <street>, ...
    const stateIndex = parts.findIndex((p) => AU_STATE_NAMES.includes(p));
    const suburb = stateIndex >= 0 ? parts[stateIndex + 1] : parts[2];
    return suburb || null;
  }

  // Normal shape: the segment right before ", Australia" is "<suburb> <STATE> <postcode>".
  const withoutCountry = parts[parts.length - 1] === 'Australia' ? parts.slice(0, -1) : parts;
  const last = withoutCountry[withoutCountry.length - 1];
  if (!last) return null;
  const suburb = last.replace(TRAILING_STATE_POSTCODE, '').trim();
  return suburb || null;
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
