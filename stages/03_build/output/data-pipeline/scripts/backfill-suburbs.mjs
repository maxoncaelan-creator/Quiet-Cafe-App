// One-off backfill for the 2026-08-19 live run that shipped 1,221 real
// restaurants with `suburb: null` on every one of them (the places-search
// Edge Function's addressComponents fix wasn't deployed yet at the time —
// see MISTAKES.md "edge-function-not-deployed"). Every row already has a
// real `formattedAddress` on file, which already contains the suburb — so
// this parses it out locally (extractSuburbFromAddress) instead of paying
// for another live Places API run just to re-fetch the same restaurants.
//
// Also surfaces (but does not delete) a small number of rows that turned
// out not to be in Australia at all — a handful of area queries matched an
// international namesake (e.g. "restaurants in Picton NSW" also matched
// Picton, NZ and Picton, Ontario). pipeline_service has no delete grant by
// design (see supabase.js), so removing those rows from the live table is
// left as a separate, explicit step.
//
// Usage: node scripts/backfill-suburbs.mjs [--dry-run]

import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

import { optionalEnv } from '../src/env.js';
import { extractSuburbFromAddress } from '../src/places.js';
import { getDbPool, upsertScoredRestaurants } from '../src/supabase.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const dataPath = path.join(__dirname, '..', 'data', 'restaurants.json');

async function main() {
  const dryRun = process.argv.includes('--dry-run');

  const restaurants = JSON.parse(await readFile(dataPath, 'utf-8'));
  console.log(`Loaded ${restaurants.length} restaurants from ${dataPath}`);

  const notAustralian = [];
  let filled = 0;
  let alreadyHadSuburb = 0;
  let unresolved = 0;

  const updated = restaurants.map((r) => {
    if (r.suburb) {
      alreadyHadSuburb++;
      return r;
    }
    const suburb = extractSuburbFromAddress(r.address);
    if (suburb) {
      filled++;
      return { ...r, suburb };
    }
    if (r.address && !r.address.includes('Australia')) {
      notAustralian.push({ placeId: r.placeId, name: r.name, address: r.address });
    } else {
      unresolved++;
    }
    return r;
  });

  console.log(`Already had a suburb: ${alreadyHadSuburb}`);
  console.log(`Filled from address: ${filled}`);
  console.log(`Not a recognisable Australian address (left as-is): ${notAustralian.length}`);
  console.log(`Address present but unparseable (left as-is): ${unresolved}`);

  if (notAustralian.length > 0) {
    console.log('\nOut-of-scope rows found (not deleted — flagged only):');
    for (const r of notAustralian) {
      console.log(`  ${r.placeId}  ${r.name}  —  ${r.address}`);
    }
  }

  if (dryRun) {
    console.log('\n--dry-run set — not writing the JSON file or touching Supabase.');
    return;
  }

  await writeFile(dataPath, JSON.stringify(updated, null, 2));
  console.log(`\nWrote ${dataPath}`);

  const supabaseDbUrl = optionalEnv('SUPABASE_DB_URL');
  if (!supabaseDbUrl) {
    console.log('No SUPABASE_DB_URL set — skipping the Supabase upsert.');
    return;
  }

  console.log('Upserting corrected rows to Supabase as pipeline_service (no Places API calls made).');
  const pool = getDbPool();
  try {
    await upsertScoredRestaurants(pool, updated);
    console.log('Upsert complete.');
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
