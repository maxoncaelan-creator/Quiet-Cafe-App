// Yelp Fusion API client — supplementary identity data + review excerpts.
// Requires YELP_API_KEY. Never wired into pipeline.js (only places.js is
// called there) — kept dormant, same pattern as outscraper.js. Paused
// 2026-08-17: Yelp Fusion dropped its permanent free tier (30-day trial
// then paid per-call plans), so Caelan decided to run v1 on Google Places
// only. Revisit if the cost becomes worth it later.

const BASE_URL = 'https://api.yelp.com/v3';

/**
 * Searches Yelp businesses near a location.
 * @param {{location: string, categories?: string}} params
 * @param {string} apiKey
 */
export async function searchBusinesses(params, apiKey) {
  if (!apiKey) throw new Error('YELP_API_KEY is required to call the Yelp Fusion API.');

  const url = new URL(`${BASE_URL}/businesses/search`);
  url.searchParams.set('location', params.location);
  url.searchParams.set('categories', params.categories || 'restaurants');
  url.searchParams.set('limit', String(params.limit || 50));

  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${apiKey}` },
  });

  if (!res.ok) {
    throw new Error(`Yelp Fusion API request failed: ${res.status} ${await res.text()}`);
  }

  const data = await res.json();
  return (data.businesses || []).map(normalizeBusiness);
}

/** Yelp's review endpoint returns at most 3 excerpts per business (free tier). */
export async function fetchReviewExcerpts(yelpBusinessId, apiKey) {
  if (!apiKey) throw new Error('YELP_API_KEY is required to call the Yelp Fusion API.');

  const res = await fetch(`${BASE_URL}/businesses/${yelpBusinessId}/reviews`, {
    headers: { Authorization: `Bearer ${apiKey}` },
  });

  if (!res.ok) {
    throw new Error(`Yelp reviews request failed: ${res.status} ${await res.text()}`);
  }

  const data = await res.json();
  return (data.reviews || []).map((r) => r.text).filter(Boolean);
}

function normalizeBusiness(business) {
  return {
    yelpId: business.id,
    name: business.name,
    address: business.location?.display_address?.join(', '),
    lat: business.coordinates?.latitude,
    lng: business.coordinates?.longitude,
    priceLevel: business.price ? business.price.length : undefined,
    yelpRating: business.rating,
  };
}
