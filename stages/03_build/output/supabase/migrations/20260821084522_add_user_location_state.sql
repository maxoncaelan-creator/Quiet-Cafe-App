-- The assistant keeps only each signed-in user's latest GPS fix. This is
-- intentionally not a location history: it is enough to give a fresh answer
-- near the user without retaining a trail of where they have been.
create table public.user_location_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  accuracy_meters double precision check (accuracy_meters is null or accuracy_meters >= 0),
  captured_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_location_state enable row level security;

-- No client policy is intentional. The authenticated search-assistant Edge
-- Function validates the caller, then uses its server-side client to upsert
-- only that caller's latest fix. This keeps raw coordinates out of the public
-- Data API, even if the table becomes API-exposed later.
