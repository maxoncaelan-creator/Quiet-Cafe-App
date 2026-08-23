begin;

create extension if not exists pgtap with schema extensions;
select plan(3);

-- Guards the free-tier decision of 2026-08-23 and, more importantly, the
-- failure mode that produced it: migration 20260823091000 was edited after it
-- had already been applied, so production held 300 while the repository
-- claimed 8,000 and nothing detected the gap. This test asserts the *settled*
-- value after every migration has run, so a future edit to an already-applied
-- migration fails here instead of silently diverging again.
--
-- Deliberately in its own file: suburb_coverage_automation.test.sql mutates
-- the ceiling to exercise the ledger, and each pgTAP file runs in its own
-- rolled-back transaction.

select is(
  (select monthly_request_ceiling from public.places_budget_config where id = true),
  1000,
  'the settled monthly Places ceiling is the free-tier allowance of 1,000'
);

select is(
  (select count(*)::integer from public.places_budget_config),
  1,
  'places_budget_config holds exactly one ceiling row'
);

-- The ceiling is worthless if a browser role can raise it. beta_codes and
-- ondemand_topup_reservations take the same deny-all posture.
select ok(
  (select relrowsecurity from pg_class where oid = 'public.places_budget_config'::regclass)
    and not exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = 'places_budget_config'
    ),
  'places_budget_config denies every browser role by default'
);

select * from finish();
rollback;
