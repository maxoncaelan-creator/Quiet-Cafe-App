// Standalone check for the open question in ranking-spec.md: how often does
// Outscraper's popular_times field actually show up for Sydney restaurants?
// Unlike the full pipeline, this only needs OUTSCRAPER_API_KEY — it doesn't
// require GOOGLE_PLACES_API_KEY, since Outscraper's own googleMapsSearch
// already returns name/address independent of the Places API.
//
// Usage: node scripts/check-outscraper-coverage.mjs

import { requireEnv } from '../src/env.js';
import { searchGoogleMapsPlaces } from '../src/outscraper.js';

async function main() {
  const apiKey = requireEnv('OUTSCRAPER_API_KEY');

  console.log('Querying Outscraper for restaurants in Sydney NSW...');
  const places = await searchGoogleMapsPlaces('restaurants in Sydney NSW', apiKey);

  const withPopularTimes = places.filter((p) => p.busynessPercent !== null);
  const pct = places.length ? Math.round((withPopularTimes.length / places.length) * 100) : 0;

  console.log(`\nTotal restaurants returned: ${places.length}`);
  console.log(`With a popular_times value: ${withPopularTimes.length} (${pct}%)`);
  console.log(`Without: ${places.length - withPopularTimes.length}`);

  if (withPopularTimes.length > 0) {
    console.log('\nExample with data:', withPopularTimes[0].name, '->', withPopularTimes[0].busynessPercent + '%');
  }
  const withoutExample = places.find((p) => p.busynessPercent === null);
  if (withoutExample) {
    console.log('Example without data:', withoutExample.name);
  }
}

main().catch((err) => {
  console.error('Check failed:', err.message);
  process.exitCode = 1;
});
