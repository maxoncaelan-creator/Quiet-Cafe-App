-- Confidence went from 3 signal-count buckets (low/medium/high) to 6
-- data-volume-aware tiers, decided with Caelan 2026-08-17 alongside
-- lowering MIN_REVIEW_MENTIONS to 1 — see ranking-spec.md "Cold start
-- handling" and data-pipeline/src/scoring.js. Safe to swap the constraint
-- outright: confirmed via `select distinct confidence from restaurants`
-- that every row is still null (no venue has cleared even the old, higher
-- threshold yet), so there's no existing data to migrate.
alter table restaurants drop constraint restaurants_confidence_check;
alter table restaurants add constraint restaurants_confidence_check
  check (confidence in ('Very Low', 'Low', 'Moderate', 'High', 'Very High', 'Certain'));
