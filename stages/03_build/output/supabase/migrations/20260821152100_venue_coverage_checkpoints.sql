-- GPS coverage checks back the List View's "Check 1 km nearby" recovery
-- action. A check is recorded only after Google Nearby Search and the
-- additive restaurant upsert both complete, including a legitimate zero-place
-- result. This is a shared coverage cache, not user location history.
create table public.venue_coverage_checkpoints (
  id bigint generated always as identity primary key,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  checked_at timestamptz not null default now(),
  result_count_before integer not null check (result_count_before >= 0),
  places_found integer not null check (places_found >= 0)
);

-- The Edge Function's service-role client is the only reader and writer.
-- There are intentionally no browser-facing Data API policies.
alter table public.venue_coverage_checkpoints enable row level security;
revoke all on table public.venue_coverage_checkpoints from anon, authenticated;

-- The function first limits to the one-week window and then applies a
-- coordinate bounding box before calculating exact Haversine distance.
create index venue_coverage_checkpoints_checked_at_idx
  on public.venue_coverage_checkpoints (checked_at desc);
create index venue_coverage_checkpoints_coordinates_idx
  on public.venue_coverage_checkpoints (latitude, longitude);
