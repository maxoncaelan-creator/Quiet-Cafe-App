// Popular Times via Outscraper's Google Maps Search API, replacing the
// earlier OpenSERP approach (decided with Caelan on 2026-08-15 — see
// README "Outscraper vs. OpenSERP").
//
// Uses the official `outscraper` npm package (SDK verified against the
// installed source: googleMapsSearch() calls POST /maps/search-v2 with an
// X-API-KEY header). Requires OUTSCRAPER_API_KEY.
//
// Field-name caveat: Outscraper's Google Maps product is documented to
// return a `popular_times` field with per-place busyness data, but this
// has not been confirmed against a live response in this environment (no
// API key configured here), and there are user reports in Outscraper's own
// community forum of `popular_times` intermittently not being returned for
// some places. parsePopularTimes() below is defensive — it returns null
// rather than throwing when the field is missing or in an unexpected shape,
// so a venue without popular-times data falls back to the other two
// signals per ranking-spec.md's cold-start handling, exactly as a venue
// with genuinely no Popular Times data would.

import Outscraper from 'outscraper';

/**
 * Searches Google Maps via Outscraper for restaurants matching a query.
 * @param {string} query e.g. "restaurants in Sydney NSW"
 * @param {string} apiKey
 */
export async function searchGoogleMapsPlaces(query, apiKey) {
  if (!apiKey) throw new Error('OUTSCRAPER_API_KEY is required to call Outscraper.');

  const client = new Outscraper(apiKey);
  // asyncRequest=false waits for the result inline rather than polling a
  // request-archive endpoint, which keeps the pipeline's control flow simple
  // at the cost of a longer-lived HTTP request for large queries.
  const results = await client.googleMapsSearch(query, 100, 'en', 'AU', 0, true, null, false);
  // The SDK returns an array of arrays (one array per input query); we only
  // ever pass a single query string here.
  const places = Array.isArray(results?.[0]) ? results[0] : results || [];
  return places.map(normalizePlace);
}

function normalizePlace(place) {
  return {
    placeId: place.place_id ?? place.google_id,
    name: place.name,
    address: place.full_address ?? place.address,
    lat: place.latitude,
    lng: place.longitude,
    googleRating: place.rating,
    busynessPercent: parsePopularTimes(place),
  };
}

/**
 * Best-effort extraction of a single "current busyness" percent (0-100)
 * from Outscraper's place record. Returns null if popular_times is absent
 * or not in the expected shape — see the module-level caveat above.
 * Exported so it can be unit tested against sample records without a live
 * API key.
 */
export function parsePopularTimes(place) {
  const popularTimes = place?.popular_times;
  if (!popularTimes || typeof popularTimes !== 'object') return null;

  // Outscraper's documented shape is an array of {day, hours: [{hour, percentage}]}
  // objects. Take the current day/hour if present, otherwise the day's peak,
  // as a stand-in "how busy does this place tend to be" figure.
  const now = new Date();
  const dayEntries = Array.isArray(popularTimes) ? popularTimes : Object.values(popularTimes);
  const today = dayEntries.find((d) => d?.day_int === now.getDay() || d?.day === now.getDay());
  const hours = today?.popular_times ?? today?.hours;
  if (!Array.isArray(hours) || hours.length === 0) return null;

  const currentHour = hours.find((h) => h?.hour === now.getHours());
  const percentage = currentHour?.percentage ?? Math.max(...hours.map((h) => h?.percentage ?? 0));

  return typeof percentage === 'number' ? Math.min(100, Math.max(0, percentage)) : null;
}
