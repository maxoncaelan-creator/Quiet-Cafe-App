-- Quiet Restaurant Finder — initial schema.
-- Mirrors stage 2's data-schema.md. Decided with Caelan on 2026-08-15 to use
-- Supabase as the backend, closing the "backend gap" flagged after the first
-- build pass (there was previously nowhere to send crowdsourced mic readings).

create table if not exists restaurants (
  place_id text primary key,
  yelp_id text,
  name text not null,
  cuisine text,
  price_level smallint,
  google_rating numeric,
  yelp_rating numeric,

  address text,
  suburb text,
  lat double precision,
  lng double precision,

  -- Review-text signal
  review_positive_count integer not null default 0,
  review_negative_count integer not null default 0,
  review_subscore numeric,
  review_signal_updated_at timestamptz,

  -- Popular Times signal (via Outscraper)
  popular_busyness_percent numeric,
  popular_subscore numeric,
  popular_signal_updated_at timestamptz,

  -- Microphone signal (aggregated; individual readings live in mic_readings)
  mic_reading_count_ios integer not null default 0,
  mic_reading_count_android integer not null default 0,
  mic_subscore numeric,
  mic_signal_updated_at timestamptz,

  -- Computed
  quietness_score numeric,
  confidence text check (confidence in ('low', 'medium', 'high')),
  score_updated_at timestamptz not null default now()
);

create index if not exists restaurants_suburb_idx on restaurants (suburb);
create index if not exists restaurants_cuisine_idx on restaurants (cuisine);
create index if not exists restaurants_quietness_score_idx on restaurants (quietness_score desc);

-- Individual crowdsourced decibel readings. Kept as raw rows (not just
-- aggregated onto `restaurants`) so the platform confidence weighting in
-- ranking-spec.md can be re-tuned later against real data.
create table if not exists mic_readings (
  id uuid primary key default gen_random_uuid(),
  place_id text not null references restaurants (place_id) on delete cascade,
  user_id uuid, -- Supabase auth uid if using anonymous/authenticated sign-in; nullable, no auth is specced yet — see README open item
  decibel_value numeric not null,
  platform text not null check (platform in ('ios', 'android')),
  device_model text,
  recorded_at timestamptz not null default now()
);

create index if not exists mic_readings_place_id_idx on mic_readings (place_id);

-- Row Level Security. Restaurants are public read data; only the pipeline
-- writes to it, via the scoped `pipeline_service` role added in
-- 0002_pipeline_role.sql (not a service-role bypass).
alter table restaurants enable row level security;

create policy "Restaurants are publicly readable"
  on restaurants for select
  using (true);

-- Mic readings: the app can insert a reading, but individual rows are not
-- publicly readable (only aggregates surfaced via `restaurants`), to avoid
-- exposing any one user's reading history. Only `pipeline_service`
-- (0002_pipeline_role.sql) can read raw rows for aggregation.
alter table mic_readings enable row level security;

create policy "Anyone can submit a mic reading"
  on mic_readings for insert
  with check (true);
