-- Loudness votes — added 2026-08-18, per Caelan: a lightweight "Quiet /
-- Normal / Loud" vote alongside the mic reading, feeding into the same
-- quietness score. Requires a real account, same gate as mic_readings
-- (0003) and favorites (0004) — a vote needs a user identity so the
-- pipeline can tell whether it should defer to a mic reading (see below).
--
-- Note: this migration was already applied directly to the live database
-- back on 2026-08-18, from a feature branch that never got merged to main
-- (feature/loudness-votes-and-venue-guess) — the app-side UI just never
-- shipped until 2026-08-19. Added here now purely so the migrations folder
-- matches what's actually live; running this against a fresh database
-- (`if not exists`/`if not exists` throughout) is safe either way.
create table if not exists loudness_votes (
  id uuid primary key default gen_random_uuid(),
  place_id text not null references restaurants (place_id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  vote text not null check (vote in ('quiet', 'normal', 'loud')),
  -- Server-set, not client-supplied — same reasoning as mic_readings'
  -- submitted_at (0006_mic_reading_rate_limit.sql): this is what the
  -- pipeline compares against a mic reading's own submitted_at to decide
  -- precedence, so it has to be trustworthy.
  submitted_at timestamptz not null default now()
);

create index if not exists loudness_votes_place_id_idx on loudness_votes (place_id);
create index if not exists loudness_votes_user_id_idx on loudness_votes (user_id);

alter table loudness_votes enable row level security;

create policy "Authenticated users can submit their own vote"
  on loudness_votes for insert
  to authenticated
  with check (auth.uid() = user_id);

-- Same reasoning as mic_readings' matching policy: PostgREST's default
-- insert response does an implicit SELECT of the row just written, which
-- needs its own policy or every insert reports as an RLS violation.
create policy "Users can read their own votes"
  on loudness_votes for select
  to authenticated
  using (auth.uid() = user_id);

-- Pipeline aggregates votes the same way it aggregates mic_readings — raw
-- rows, not just a count, since it needs each vote's user_id and
-- submitted_at to apply the "a mic reading within 5 minutes wins" rule
-- (see data-pipeline/src/scoring.js).
grant select on loudness_votes to pipeline_service;

create policy "pipeline_service can read loudness_votes"
  on loudness_votes for select
  to pipeline_service
  using (true);

-- Per-venue vote signal, mirroring review_*/popular_*/mic_* in 0001_init.sql
-- — stored on restaurants even though only vote_subscore feeds the combined
-- score, same transparency/debugging rationale as the existing signals.
alter table restaurants
  add column if not exists vote_count integer not null default 0,
  add column if not exists vote_subscore numeric,
  add column if not exists vote_signal_updated_at timestamptz;
