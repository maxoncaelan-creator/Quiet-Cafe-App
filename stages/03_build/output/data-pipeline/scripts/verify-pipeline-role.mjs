// Smoke test for pipeline_service's scoped permissions (see
// supabase/migrations/0002_pipeline_role.sql). Confirms it can do what it
// should and is blocked from what it shouldn't, against the live database —
// not just trusting the migration's intent. Run after any change to the
// role's grants/policies.
//
// Usage: node scripts/verify-pipeline-role.mjs
// (reads SUPABASE_DB_URL from data-pipeline/.env automatically — see ../src/env.js)

import '../src/env.js';
import { getDbPool, upsertScoredRestaurants, fetchMicReadingsByPlace } from '../src/supabase.js';

const TEST_PLACE_ID = 'role-verification-test';

const testRestaurant = {
  placeId: TEST_PLACE_ID,
  yelpId: null,
  name: 'Role Verification Test',
  cuisine: 'Test',
  priceLevel: null,
  address: null,
  suburb: null,
  lat: null,
  lng: null,
  googleRating: null,
  yelpRating: null,
  signals: {
    review: { positiveCount: 0, negativeCount: 0, subscore: null },
    popular: { busynessPercent: null, subscore: null },
    mic: { readingCountIos: 0, readingCountAndroid: 0, subscore: null },
  },
  quietnessScore: null,
  confidence: null,
};

async function main() {
  const pool = getDbPool();
  const results = {};

  try {
    await upsertScoredRestaurants(pool, [testRestaurant]);
    results.upsertRestaurant = 'OK (allowed, as expected)';
  } catch (err) {
    results.upsertRestaurant = `UNEXPECTED FAILURE: ${err.message}`;
  }

  try {
    const readings = await fetchMicReadingsByPlace(pool, [TEST_PLACE_ID]);
    results.selectMicReadings = `OK (allowed, as expected) — ${readings.size} place(s) with readings`;
  } catch (err) {
    results.selectMicReadings = `UNEXPECTED FAILURE: ${err.message}`;
  }

  try {
    await pool.query("insert into mic_readings (place_id, decibel_value, platform) values ($1, 60, 'ios')", [
      TEST_PLACE_ID,
    ]);
    results.insertMicReading = 'ALLOWED — should have been blocked! Check the grants in 0002_pipeline_role.sql.';
  } catch (err) {
    results.insertMicReading = `Blocked, as expected: ${err.message}`;
  }

  try {
    await pool.query('delete from restaurants where place_id = $1', [TEST_PLACE_ID]);
    results.deleteRestaurant = 'ALLOWED — should have been blocked! Check the grants in 0002_pipeline_role.sql.';
  } catch (err) {
    results.deleteRestaurant = `Blocked, as expected: ${err.message}`;
  }

  console.log(JSON.stringify(results, null, 2));
  await pool.end();
}

main().catch((err) => {
  console.error('Verification script crashed:', err);
  process.exitCode = 1;
});
