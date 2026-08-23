-- Enables the Postgres extensions the step 1 coverage automation is built on.
-- Enabling them changes no behaviour by itself; it makes that work buildable.
-- See execution-plan-2026-08-23.md.
--
--   pg_cron   schedules the background suburb sweep
--   pg_net    lets the scheduled job invoke an Edge Function
--   pgmq      queues sweeps with retries and demand-priority ordering
--   pg_trgm   fuzzy suburb resolution, replacing extractAreaQuery()'s regex
--   unaccent  normalises accented suburb names before that match
--
-- pg_trgm and unaccent together are what stop a string like "louder the
-- better" resolving to a suburb at all, which is how a nonsense phrase came
-- to authorise a billed Google search on 2026-08-22.

-- Supabase installs pg_cron into pg_catalog; it is only available in the
-- postgres database.
create extension if not exists pg_cron;

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists unaccent with schema extensions;

-- pgmq manages its own schema.
create extension if not exists pgmq;
