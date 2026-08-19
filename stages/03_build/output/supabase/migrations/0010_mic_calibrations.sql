-- Mic calibration, added 2026-08-19 per Caelan: an average human speaking
-- voice measures ~60 dBA. Every signed-in user is walked through a "say
-- something" screen once on their first sign-in and again every 3 months,
-- and the recorded level is compared against that 60 dBA reference to work
-- out how far off their specific device/browser mic reads relative to a
-- "true" scale — then that per-user offset corrects their future ambient
-- readings before they're weighted into micSubscore (see
-- scoring.js's calibrationOffset/applyCalibrationOffsets). Same shape as
-- mic_readings (0001_init.sql) and loudness_votes (0008) — real account
-- required, same RLS pattern, pipeline_service read-only.
create table if not exists mic_calibrations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  decibel_value numeric not null,
  platform text not null check (platform in ('ios', 'android', 'web')),
  recorded_at timestamptz not null default now()
);

create index if not exists mic_calibrations_user_id_idx on mic_calibrations (user_id);
create index if not exists mic_calibrations_user_id_recorded_at_idx on mic_calibrations (user_id, recorded_at desc);

alter table mic_calibrations enable row level security;

create policy "Users can submit their own calibration"
  on mic_calibrations for insert
  to authenticated
  with check (auth.uid() = user_id);

-- Same reasoning as mic_readings/loudness_votes: PostgREST's default insert
-- response does an implicit SELECT of the row just written.
create policy "Users can read their own calibrations"
  on mic_calibrations for select
  to authenticated
  using (auth.uid() = user_id);

-- Pipeline needs every user's latest calibration (not scoped to one venue's
-- place_ids the way mic_readings/loudness_votes fetches are) to correct
-- readings anywhere that user has submitted one.
grant select on mic_calibrations to pipeline_service;

create policy "pipeline_service can read mic_calibrations"
  on mic_calibrations for select
  to pipeline_service
  using (true);
