begin;

create extension if not exists pgtap with schema extensions;
select plan(41);

select is(
  public.normalise_nsw_suburb_name('  Crows   Nest '),
  'crowsnest',
  'normalisation removes casing and whitespace differences'
);

select is(
  public.normalise_nsw_suburb_name('Tést Town'),
  'testtown',
  'normalisation removes accents'
);

insert into public.nsw_suburb_gazetteer_syncs (id, source_url)
values ('10000000-0000-0000-0000-000000000001', 'https://official.example/nsw');

select lives_ok(
  $$
    select public.apply_nsw_suburb_gazetteer_snapshot(
      '10000000-0000-0000-0000-000000000001',
      jsonb_build_array(
        jsonb_build_object('cadid', '100', 'suburbname', 'Crows Nest', 'postcode', '2065', 'createdate', 806889600000),
        jsonb_build_object('cadid', '200', 'suburbname', 'Tést Town', 'postcode', '2000'),
        jsonb_build_object('cadid', '300', 'suburbname', 'Old Place', 'postcode', '2001')
      ),
      'fixture-one'
    )
  $$,
  'an official-style snapshot with millisecond dates applies'
);

select results_eq(
  $$ select canonical_name from public.resolve_nsw_suburb('Crows Nest') $$,
  array['Crows Nest'::text],
  'an exact official locality resolves'
);

select results_eq(
  $$ select canonical_name from public.resolve_nsw_suburb('crowsnest') $$,
  array['Crows Nest'::text],
  'a spacing-free locality resolves to the same canonical row'
);

select results_eq(
  $$ select canonical_name from public.resolve_nsw_suburb('test town') $$,
  array['Tést Town'::text],
  'an unaccented spelling resolves to an accented canonical locality'
);

select is_empty(
  $$ select * from public.resolve_nsw_suburb('louder the better') $$,
  'an unresolvable phrase cannot resolve to a locality'
);

select is_empty(
  $$ select * from public.resolve_nsw_suburb_in_text('I prefer it louder the better') $$,
  'unresolvable prose cannot resolve to a locality'
);

select results_eq(
  $$ select canonical_name from public.resolve_nsw_suburb_in_text('Find quiet places in Crows Nest tonight') $$,
  array['Crows Nest'::text],
  'an official locality embedded in Assistant text resolves'
);

insert into public.nsw_suburb_gazetteer_syncs (id, source_url)
values ('10000000-0000-0000-0000-000000000002', 'https://official.example/nsw');

select lives_ok(
  $$
    select public.apply_nsw_suburb_gazetteer_snapshot(
      '10000000-0000-0000-0000-000000000002',
      jsonb_build_array(
        jsonb_build_object('cadid', '100', 'suburbname', 'Crows Nest', 'postcode', '2065'),
        jsonb_build_object('cadid', '200', 'suburbname', 'Tést Town', 'postcode', '2000')
      ),
      'fixture-two'
    )
  $$,
  'a later full snapshot retires a missing locality without deleting it'
);

select is(
  (select is_active from public.resolve_nsw_suburb('Old Place')),
  false,
  'a retired locality remains an alias instead of being redirected or deleted'
);

update public.nsw_suburb_gazetteer_syncs
set completed_at = now() - interval '29 days', status = 'succeeded'
where status = 'succeeded';

select results_eq(
  $$ select outcome from public.claim_nsw_suburb_gazetteer_sync() $$,
  array['recently_synced'::text],
  'the monthly gazetteer guard refuses a 29-day re-sync'
);

update public.nsw_suburb_gazetteer_syncs
set completed_at = now() - interval '30 days'
where status = 'succeeded';

select results_eq(
  $$ select outcome from public.claim_nsw_suburb_gazetteer_sync() $$,
  array['granted'::text],
  'the monthly gazetteer guard permits a 30-day re-sync'
);

insert into public.restaurants (place_id, name, suburb)
select 'crows-nest-fixture-' || value, 'Fixture venue ' || value, 'Crows Nest'
from generate_series(1, 15) as value;

insert into public.nsw_suburb_sweep_state (suburb_id, last_swept_at)
select id, now() - interval '31 days'
from public.nsw_suburbs where canonical_name = 'Crows Nest';

select is(
  (select eligible from public.suburb_sweep_eligibility((select id from public.nsw_suburbs where canonical_name = 'Crows Nest'))),
  true,
  'a dense Crows Nest with fifteen stored venues is sweepable when stale'
);

update public.nsw_suburb_sweep_state
set last_swept_at = now()
where suburb_id = (select id from public.nsw_suburbs where canonical_name = 'Crows Nest');

select is(
  (select eligible from public.suburb_sweep_eligibility((select id from public.nsw_suburbs where canonical_name = 'Crows Nest'))),
  false,
  'a freshly swept locality is not immediately eligible'
);

update public.nsw_suburb_sweep_state
set last_swept_at = now() - interval '31 days'
where suburb_id = (select id from public.nsw_suburbs where canonical_name = 'Crows Nest');

select results_eq(
  $$
    select outcome from public.queue_nsw_suburb_sweep(
      (select id from public.nsw_suburbs where canonical_name = 'Tést Town'),
      'assistant'
    )
  $$,
  array['queued'::text],
  'a resolved stale locality is queued'
);

select results_eq(
  $$
    select outcome from public.queue_nsw_suburb_sweep(
      (select id from public.nsw_suburbs where canonical_name = 'Crows Nest'),
      'assistant'
    )
  $$,
  array['queued'::text],
  'a newly demanded stale locality is queued'
);

-- `now()` is stable for this test transaction, so make recency explicit
-- rather than relying on a sleep to break an otherwise deterministic tie.
update public.nsw_suburb_sweep_jobs
set last_demanded_at = clock_timestamp()
where suburb_id = (select id from public.nsw_suburbs where canonical_name = 'Crows Nest');

select results_eq(
  $$ select canonical_name from public.claim_next_nsw_suburb_sweep() $$,
  array['Crows Nest'::text],
  'recent demand wins queue priority over an older queued locality'
);

select ok(
  not public.complete_nsw_suburb_sweep(
    (select id from public.nsw_suburbs where canonical_name = 'Crows Nest'),
    gen_random_uuid(),
    'completed',
    0,
    true,
    0
  ),
  'a stale worker lease cannot mark a newer claim fresh'
);

select is(
  (select count(*) from public.nsw_suburb_coverage_demands where suburb_id = (select id from public.nsw_suburbs where canonical_name = 'Crows Nest')),
  1::bigint,
  'queueing stores canonical demand without raw user text'
);

insert into public.nsw_suburb_sweep_jobs (suburb_id, status, next_attempt_at)
select id, 'queued', now()
from public.nsw_suburbs
where canonical_name = 'Old Place';

select results_eq(
  $$ select canonical_name from public.claim_next_nsw_suburb_sweep() $$,
  array['Tést Town'::text],
  'a retired locality job is skipped instead of trapping the worker lease'
);

-- The dispatch marker is new in this migration. This fixture represents a
-- legacy pending row after the conservative migration backfill: it must remain
-- charged when a later budget claim runs stale-reservation cleanup.
update public.places_budget_config
set monthly_request_ceiling = 1;

insert into public.places_request_reservations (
  requested_count,
  purpose,
  reserved_at
)
values (
  1,
  'legacy-pending-dispatched',
  now() - interval '11 minutes'
);

select is(
  public.backfill_legacy_places_request_dispatches(clock_timestamp()),
  1,
  'the private rollout helper marks an unmarked legacy pending reservation dispatched'
);

select is(
  public.backfill_legacy_places_request_dispatches(clock_timestamp()),
  0,
  'the legacy dispatch backfill is idempotent'
);

select results_eq(
  $$
    select status || ':' || (dispatched_at = reserved_at)::text
    from public.places_request_reservations
    where purpose = 'legacy-pending-dispatched'
  $$,
  array['pending:true'::text],
  'the converted legacy reservation remains pending with its original dispatch time'
);

select results_eq(
  $$ select outcome from public.claim_places_request_budget(1, 'legacy-cleanup-check') $$,
  array['monthly_ceiling_reached'::text],
  'a legacy pending reservation backfilled as dispatched survives stale cleanup'
);

update public.places_request_reservations
set status = 'released', settled_count = 0, settled_at = now()
where purpose = 'legacy-pending-dispatched';

update public.places_budget_config
set monthly_request_ceiling = 3;

select results_eq(
  $$ select outcome from public.claim_places_request_budget(2, 'test') $$,
  array['granted'::text],
  'the monthly Places ledger grants capacity below the ceiling'
);

select is(
  (select remaining from public.claim_places_request_budget(2, 'test-denied')),
  1,
  'the monthly Places ledger exposes remaining capacity on a denial'
);

select results_eq(
  $$ select outcome from public.claim_places_request_budget(2, 'test-denied') $$,
  array['monthly_ceiling_reached'::text],
  'the monthly Places ledger blocks a request that would exceed the ceiling'
);

select is(
  public.places_budget_used(date_trunc('month', now() at time zone 'utc') at time zone 'utc'),
  2,
  'a pending reservation conservatively counts at its requested size'
);

select ok(
  public.mark_places_request_budget_dispatched(
    (select id from public.places_request_reservations where purpose = 'test' limit 1)
  ),
  'a service caller must durably mark a Places request before dispatch'
);

select ok(
  not public.release_places_request_budget(
    (select id from public.places_request_reservations where purpose = 'test' limit 1)
  ),
  'a dispatched request cannot be released back into the monthly budget'
);

update public.places_request_reservations
set reserved_at = now() - interval '11 minutes'
where purpose = 'test';

select results_eq(
  $$ select outcome from public.claim_places_request_budget(2, 'stale-dispatched') $$,
  array['monthly_ceiling_reached'::text],
  'an old dispatched reservation remains charged instead of being released'
);

-- Settle the original two-request claim to one actual provider attempt, which
-- frees exactly one request for a later caller.
select ok(
  public.settle_places_request_budget(
    (select id from public.places_request_reservations where purpose = 'test' limit 1),
    1
  ),
  'settling replaces a conservative reservation with actual use'
);

select results_eq(
  $$ select outcome from public.claim_places_request_budget(2, 'after-settlement') $$,
  array['granted'::text],
  'settlement frees capacity for a later reservation'
);

select ok(
  public.release_places_request_budget(
    (select id from public.places_request_reservations where purpose = 'after-settlement' limit 1)
  ),
  'releasing an unattempted request returns its capacity'
);

select results_eq(
  $$ select outcome from public.claim_places_request_budget(0, 'invalid') $$,
  array['invalid_count'::text],
  'zero request claims are rejected'
);

select ok(
  has_function_privilege('service_role', 'public.claim_places_request_budget(integer, text)', 'execute')
    and has_function_privilege('service_role', 'public.mark_places_request_budget_dispatched(uuid)', 'execute')
    and has_function_privilege('service_role', 'public.settle_places_request_budget(uuid, integer)', 'execute')
    and has_function_privilege('service_role', 'public.release_places_request_budget(uuid)', 'execute'),
  'service role can operate the Places request ledger'
);

select ok(
  not has_function_privilege('anon', 'public.claim_places_request_budget(integer, text)', 'execute')
    and not has_function_privilege('authenticated', 'public.claim_places_request_budget(integer, text)', 'execute')
    and not has_function_privilege('anon', 'public.mark_places_request_budget_dispatched(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.mark_places_request_budget_dispatched(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.settle_places_request_budget(uuid, integer)', 'execute')
    and not has_function_privilege('authenticated', 'public.settle_places_request_budget(uuid, integer)', 'execute')
    and not has_function_privilege('anon', 'public.release_places_request_budget(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.release_places_request_budget(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.places_budget_used(timestamptz)', 'execute')
    and not has_function_privilege('authenticated', 'public.places_budget_used(timestamptz)', 'execute'),
  'browser roles cannot operate the Places ledger or inspect its usage helper'
);

select ok(
  not has_function_privilege('anon', 'public.claim_nsw_suburb_gazetteer_sync()', 'execute')
    and not has_function_privilege('authenticated', 'public.claim_nsw_suburb_gazetteer_sync()', 'execute')
    and not has_function_privilege('anon', 'public.apply_nsw_suburb_gazetteer_snapshot(uuid, jsonb, text)', 'execute')
    and not has_function_privilege('authenticated', 'public.apply_nsw_suburb_gazetteer_snapshot(uuid, jsonb, text)', 'execute')
    and not has_function_privilege('anon', 'public.resolve_nsw_suburb(text)', 'execute')
    and not has_function_privilege('authenticated', 'public.resolve_nsw_suburb(text)', 'execute')
    and not has_function_privilege('anon', 'public.resolve_nsw_suburb_in_text(text)', 'execute')
    and not has_function_privilege('authenticated', 'public.resolve_nsw_suburb_in_text(text)', 'execute')
    and not has_function_privilege('anon', 'public.record_nsw_suburb_coverage_demand(uuid, text)', 'execute')
    and not has_function_privilege('authenticated', 'public.record_nsw_suburb_coverage_demand(uuid, text)', 'execute')
    and not has_function_privilege('anon', 'public.claim_nsw_suburb_sweep(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.claim_nsw_suburb_sweep(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.queue_nsw_suburb_sweep(uuid, text)', 'execute')
    and not has_function_privilege('authenticated', 'public.queue_nsw_suburb_sweep(uuid, text)', 'execute')
    and not has_function_privilege('anon', 'public.claim_next_nsw_suburb_sweep()', 'execute')
    and not has_function_privilege('authenticated', 'public.claim_next_nsw_suburb_sweep()', 'execute')
    and not has_function_privilege('anon', 'public.complete_nsw_suburb_sweep(uuid, uuid, text, integer, boolean, integer, text)', 'execute')
    and not has_function_privilege('authenticated', 'public.complete_nsw_suburb_sweep(uuid, uuid, text, integer, boolean, integer, text)', 'execute')
    and not has_function_privilege('anon', 'public.consume_nsw_suburb_sweep_wakeup()', 'execute')
    and not has_function_privilege('authenticated', 'public.consume_nsw_suburb_sweep_wakeup()', 'execute')
    and not has_function_privilege('anon', 'public.request_coverage_automation_worker(text)', 'execute')
    and not has_function_privilege('authenticated', 'public.request_coverage_automation_worker(text)', 'execute'),
  'browser roles cannot invoke private NSW coverage automation functions'
);

select ok(
  exists (select 1 from cron.job where jobname = 'run-nsw-suburb-sweep-worker'),
  'the worker cron job is registered'
);

select ok(
  to_regclass('pgmq.q_nsw_suburb_sweep_wakeups') is not null,
  'the private pgmq wake-up queue exists'
);

select * from finish();
rollback;
