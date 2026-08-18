import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

import { optionalEnv } from './env.js'; // loads data-pipeline/.env as a side effect — see env.js
import { searchRestaurants } from './places.js';
import { mineNoiseMentions } from './reviewMining.js';
import { getDbPool, fetchMicReadingsByPlace, upsertScoredRestaurants } from './supabase.js';
import {
  reviewSubscore,
  popularSubscore,
  micSubscore,
  combineScores,
} from './scoring.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/**
 * Runs the full pipeline: restaurant records in -> quietness scores out.
 * Works the same whether the records came from live APIs or the bundled
 * sample dataset, since only the scoring stage matters for the output shape.
 * @param {Array<object>} restaurants raw restaurant records (see data-schema.md)
 */
export function computeScoredRestaurants(restaurants) {
  return restaurants.map((r) => {
    const { positiveCount, negativeCount } = mineNoiseMentions(r.reviewTexts);
    const review = reviewSubscore(positiveCount, negativeCount);
    const popular = popularSubscore(r.busynessPercent ?? null);
    const mic = micSubscore(r.micReadings);

    const { score, confidence, signalCount } = combineScores({
      review: { subscore: review, count: positiveCount + negativeCount },
      popular: { subscore: popular },
      mic: { subscore: mic, count: (r.micReadings || []).length },
    });

    return {
      placeId: r.placeId,
      yelpId: r.yelpId ?? null,
      name: r.name,
      cuisine: r.cuisine,
      priceLevel: r.priceLevel,
      address: r.address,
      suburb: r.suburb,
      lat: r.lat,
      lng: r.lng,
      googleRating: r.googleRating ?? null,
      yelpRating: r.yelpRating ?? null,
      signals: {
        review: { positiveCount, negativeCount, subscore: review },
        popular: { busynessPercent: r.busynessPercent ?? null, subscore: popular },
        mic: {
          readingCountIos: (r.micReadings || []).filter((x) => x.platform === 'ios').length,
          readingCountAndroid: (r.micReadings || []).filter((x) => x.platform === 'android').length,
          subscore: mic,
        },
      },
      quietnessScore: score,
      confidence,
      signalCount,
    };
  });
}

async function loadSampleInput() {
  const raw = await readFile(path.join(__dirname, '..', 'data', 'sample-input.json'), 'utf-8');
  return JSON.parse(raw);
}

async function main() {
  // GOOGLE_PLACES_API_KEY itself lives in Supabase's Function secrets now
  // (see places.js) — these three are what this pipeline needs locally to
  // call the places-search Edge Function instead.
  const supabaseUrl = optionalEnv('SUPABASE_URL');
  const supabaseAnonKey = optionalEnv('SUPABASE_ANON_KEY');
  const pipelineSharedSecret = optionalEnv('PIPELINE_SHARED_SECRET');
  const hasPlacesProxy = Boolean(supabaseUrl) && Boolean(supabaseAnonKey) && Boolean(pipelineSharedSecret);
  // Only touch the live database on the real-data path. Sample mode is meant
  // to be a self-contained local demo — it shouldn't write anything to
  // Supabase just because SUPABASE_DB_URL happens to be set in .env.
  const hasSupabase = hasPlacesProxy && Boolean(optionalEnv('SUPABASE_DB_URL'));
  let restaurants;

  if (hasPlacesProxy) {
    console.log('places-search config found — fetching live restaurant data for Sydney NSW.');
    restaurants = await searchRestaurants('restaurants in Sydney NSW', { supabaseUrl, supabaseAnonKey, pipelineSharedSecret });

    // Popular Times (via Outscraper) is not called here — dropped as a
    // signal on 2026-08-15 after confirming 0/100 Sydney restaurants had
    // popular_times data (see scripts/check-outscraper-coverage.mjs and
    // README "Outscraper vs. OpenSERP"). r.busynessPercent is left unset,
    // so popularSubscore() below naturally resolves to null and
    // combineScores() excludes it — the existing cold-start renormalization
    // logic handles a permanently-absent signal the same way it handles a
    // temporarily-absent one. outscraper.js and its tests are kept, dormant,
    // in case this gets revisited.

    if (hasSupabase) {
      console.log('SUPABASE_DB_URL found — fetching crowdsourced mic readings as pipeline_service.');
      const pool = getDbPool();
      try {
        const readingsByPlace = await fetchMicReadingsByPlace(pool, restaurants.map((r) => r.placeId));
        restaurants = restaurants.map((r) => ({ ...r, micReadings: readingsByPlace.get(r.placeId) ?? [] }));
      } finally {
        await pool.end();
      }
    } else {
      console.log('No SUPABASE_DB_URL set — mic signal will be empty for all venues.');
      restaurants = restaurants.map((r) => ({ ...r, micReadings: [] }));
    }
  } else {
    console.log('No places-search config set (SUPABASE_URL/SUPABASE_ANON_KEY/PIPELINE_SHARED_SECRET) — using bundled sample data instead (includes synthetic mic readings).');
    restaurants = await loadSampleInput();
  }

  const scored = computeScoredRestaurants(restaurants);
  const outPath = path.join(__dirname, '..', 'data', 'restaurants.json');
  await writeFile(outPath, JSON.stringify(scored, null, 2));
  console.log(`Wrote ${scored.length} scored restaurants to ${outPath}`);

  if (hasSupabase) {
    console.log('Upserting scored restaurants to Supabase as pipeline_service.');
    const pool = getDbPool();
    try {
      await upsertScoredRestaurants(pool, scored);
      console.log('Upsert complete.');
    } finally {
      await pool.end();
    }
  }
}

// Only run when executed directly (so tests can import computeScoredRestaurants
// without triggering a pipeline run). Uses pathToFileURL rather than raw
// string concatenation so this works on Windows, where process.argv[1] uses
// backslashes and doesn't literally match a file:// URL.
const isMainModule = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;

if (isMainModule) {
  main().catch((err) => {
    console.error(err);
    process.exitCode = 1;
  });
}
