-- Dedicated, RLS-scoped role for the data pipeline, replacing the earlier
-- plan to use `service_role` (which has BYPASSRLS and can touch anything in
-- the database, not just these two tables). Decided with Caelan on
-- 2026-08-15 — see stage 3 README "Pipeline role vs. service_role".
--
-- No password is set here. That's done separately, out-of-band, and kept
-- only in data-pipeline/.env (gitignored, never committed):
--   ALTER ROLE pipeline_service WITH PASSWORD '...';

create role pipeline_service login;

grant usage on schema public to pipeline_service;

-- Pipeline writes computed scores onto restaurants. No delete needed.
grant select, insert, update on restaurants to pipeline_service;

-- Pipeline reads raw readings for aggregation. Writing readings is the
-- app's job via the anon role (see 0001_init.sql's insert policy), not the
-- pipeline's — pipeline_service is not granted insert on mic_readings.
grant select on mic_readings to pipeline_service;

create policy "pipeline_service can read and write restaurants"
  on restaurants for all
  to pipeline_service
  using (true)
  with check (true);

create policy "pipeline_service can read mic_readings"
  on mic_readings for select
  to pipeline_service
  using (true);
