// Direct Postgres connection to Supabase, authenticated as the dedicated
// `pipeline_service` role (see supabase/migrations/0002_pipeline_role.sql) —
// not the `service_role` key. service_role has BYPASSRLS and can touch
// anything in the database; pipeline_service is a normal role, scoped by
// GRANT + RLS policies to exactly what the pipeline needs: read/write on
// restaurants, read-only on mic_readings. No delete anywhere, no insert on
// mic_readings (that's the app's job via the anon role).

import pg from 'pg';

import { requireEnv } from './env.js';

const { Pool } = pg;

export function getDbPool() {
  const connectionString = requireEnv('SUPABASE_DB_URL');
  return new Pool({ connectionString, ssl: { rejectUnauthorized: false } });
}

/** Fetches all mic readings for a set of place IDs, grouped by place_id. */
export async function fetchMicReadingsByPlace(pool, placeIds) {
  if (placeIds.length === 0) return new Map();

  const { rows } = await pool.query(
    'select place_id, decibel_value, platform from mic_readings where place_id = any($1)',
    [placeIds]
  );

  const byPlace = new Map();
  for (const row of rows) {
    const list = byPlace.get(row.place_id) ?? [];
    list.push({ decibel: Number(row.decibel_value), platform: row.platform });
    byPlace.set(row.place_id, list);
  }
  return byPlace;
}

const UPSERT_QUERY = `
  insert into restaurants (
    place_id, yelp_id, name, cuisine, price_level, google_rating, yelp_rating,
    address, suburb, lat, lng,
    review_positive_count, review_negative_count, review_subscore, review_signal_updated_at,
    popular_busyness_percent, popular_subscore, popular_signal_updated_at,
    mic_reading_count_ios, mic_reading_count_android, mic_subscore, mic_signal_updated_at,
    quietness_score, confidence, score_updated_at
  ) values (
    $1, $2, $3, $4, $5, $6, $7,
    $8, $9, $10, $11,
    $12, $13, $14, now(),
    $15, $16, now(),
    $17, $18, $19, now(),
    $20, $21, now()
  )
  on conflict (place_id) do update set
    yelp_id = excluded.yelp_id,
    name = excluded.name,
    cuisine = excluded.cuisine,
    price_level = excluded.price_level,
    google_rating = excluded.google_rating,
    yelp_rating = excluded.yelp_rating,
    address = excluded.address,
    suburb = excluded.suburb,
    lat = excluded.lat,
    lng = excluded.lng,
    review_positive_count = excluded.review_positive_count,
    review_negative_count = excluded.review_negative_count,
    review_subscore = excluded.review_subscore,
    review_signal_updated_at = excluded.review_signal_updated_at,
    popular_busyness_percent = excluded.popular_busyness_percent,
    popular_subscore = excluded.popular_subscore,
    popular_signal_updated_at = excluded.popular_signal_updated_at,
    mic_reading_count_ios = excluded.mic_reading_count_ios,
    mic_reading_count_android = excluded.mic_reading_count_android,
    mic_subscore = excluded.mic_subscore,
    mic_signal_updated_at = excluded.mic_signal_updated_at,
    quietness_score = excluded.quietness_score,
    confidence = excluded.confidence,
    score_updated_at = excluded.score_updated_at
`;

/** Upserts scored restaurant rows. Requires pipeline_service's insert+update grant (no delete). */
export async function upsertScoredRestaurants(pool, scoredRestaurants) {
  for (const r of scoredRestaurants) {
    await pool.query(UPSERT_QUERY, [
      r.placeId,
      r.yelpId,
      r.name,
      r.cuisine,
      r.priceLevel,
      r.googleRating,
      r.yelpRating,
      r.address,
      r.suburb,
      r.lat,
      r.lng,
      r.signals.review.positiveCount,
      r.signals.review.negativeCount,
      r.signals.review.subscore,
      r.signals.popular.busynessPercent,
      r.signals.popular.subscore,
      r.signals.mic.readingCountIos,
      r.signals.mic.readingCountAndroid,
      r.signals.mic.subscore,
      r.quietnessScore,
      r.confidence,
    ]);
  }
}
