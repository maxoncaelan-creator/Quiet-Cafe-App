// Google Places API (New) client — restaurant identity/location + reviews.
// Requires GOOGLE_PLACES_API_KEY. Not exercised against the live API in this
// environment (no key configured here) — see README for how to verify it.

const FIELD_MASK = [
  'places.id',
  'places.displayName',
  'places.formattedAddress',
  'places.location',
  'places.priceLevel',
  'places.primaryType',
  'places.rating',
  'places.userRatingCount',
  'places.reviews',
].join(',');

/**
 * Searches for restaurants in a given city using Places API (New) Text Search.
 * @param {string} query e.g. "restaurants in Sydney NSW"
 * @param {string} apiKey
 */
export async function searchRestaurants(query, apiKey) {
  if (!apiKey) throw new Error('GOOGLE_PLACES_API_KEY is required to call the Places API.');

  const res = await fetch('https://places.googleapis.com/v1/places:searchText', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': apiKey,
      'X-Goog-FieldMask': FIELD_MASK,
    },
    body: JSON.stringify({ textQuery: query }),
  });

  if (!res.ok) {
    throw new Error(`Places API request failed: ${res.status} ${await res.text()}`);
  }

  const data = await res.json();
  return (data.places || []).map(normalizePlace);
}

function normalizePlace(place) {
  return {
    placeId: place.id,
    name: place.displayName?.text,
    address: place.formattedAddress,
    lat: place.location?.latitude,
    lng: place.location?.longitude,
    priceLevel: place.priceLevel,
    cuisine: place.primaryType,
    googleRating: place.rating,
    reviewTexts: (place.reviews || []).map((r) => r.text?.text).filter(Boolean),
  };
}
