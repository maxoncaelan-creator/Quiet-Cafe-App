-- Step 1: canonical NSW suburb coverage automation.
--
-- This migration replaces the area-only MIN_COVERAGE policy with an official
-- gazetteer, conservative resolver, freshness state and a durable worker queue.
-- It deliberately does not change Flutter's existing response contracts; Step 2
-- owns the Assistant's eventual queued-refresh states.
--
-- See ADR-001-suburb-coverage-automation.md and
-- execution-plan-2026-08-23.md for the decision record.

-- The Step 0 ledger correctly removed browser execution but omitted the
-- service-role grants that Edge Functions need to call it. Keep the helper
-- private: claim_places_request_budget() invokes it under SECURITY DEFINER.
grant execute on function public.claim_places_request_budget(integer, text) to service_role;
grant execute on function public.settle_places_request_budget(uuid, integer) to service_role;
grant execute on function public.release_places_request_budget(uuid) to service_role;

-- Safe crash recovery can release only a reservation that has not been marked
-- dispatched. Once a function has durably marked the request before calling
-- Google, an invocation/settlement failure must remain charged for the month:
-- under-counting a real provider call would weaken the hard global ceiling.
alter table public.places_request_reservations
  add column if not exists dispatched_at timestamptz,
  add column if not exists settled_at timestamptz;

-- Kept private and idempotent so the rollout conversion is directly testable.
-- The migration passes its live cutoff so any Step 0 invocation that began
-- before the Step 1 boundary is conservatively treated as potentially paid.
create or replace function public.backfill_legacy_places_request_dispatches(
  p_before timestamptz
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_updated integer;
begin
  update public.places_request_reservations
  set dispatched_at = reserved_at
  where status = 'pending'
    and dispatched_at is null
    and reserved_at < p_before;
  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

update public.places_request_reservations
set dispatched_at = coalesce(dispatched_at, settled_at, reserved_at),
    settled_at = coalesce(settled_at, reserved_at)
where status = 'completed' and (dispatched_at is null or settled_at is null);

-- This is the first migration that records a dispatch marker. Existing pending
-- rows predate that marker, so their prior dispatch state is unknowable. Treat
-- them conservatively as already dispatched: a crashed legacy invocation may
-- have reached Google before it could settle its reservation.
select public.backfill_legacy_places_request_dispatches(clock_timestamp());

create or replace function public.places_budget_used(p_month_start timestamptz)
returns integer
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select coalesce(sum(
    case status
      when 'pending' then requested_count
      when 'completed' then coalesce(settled_count, requested_count)
      else 0
    end
  ), 0)::integer
  from public.places_request_reservations
  where case
    when status = 'completed' then coalesce(dispatched_at, settled_at, reserved_at)
    else coalesce(dispatched_at, reserved_at)
  end >= p_month_start;
$$;

create or replace function public.claim_places_request_budget(
  p_count integer,
  p_purpose text default null
)
returns table (reservation_id uuid, outcome text, remaining integer)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_month_start timestamptz := date_trunc('month', now() at time zone 'utc') at time zone 'utc';
  v_ceiling integer;
  v_used integer;
  v_reservation_id uuid;
begin
  if p_count is null or p_count <= 0 then
    return query select null::uuid, 'invalid_count'::text, null::integer;
    return;
  end if;

  perform pg_advisory_xact_lock(hashtext('places_request_budget'));

  update public.places_request_reservations
  set status = 'released', settled_count = 0, settled_at = now()
  where status = 'pending'
    and dispatched_at is null
    and reserved_at < now() - interval '10 minutes';

  select monthly_request_ceiling into v_ceiling
  from public.places_budget_config where id = true;

  if v_ceiling is null then
    return query select null::uuid, 'no_ceiling_configured'::text, null::integer;
    return;
  end if;

  v_used := public.places_budget_used(v_month_start);

  if v_used + p_count > v_ceiling then
    return query select null::uuid, 'monthly_ceiling_reached'::text, greatest(v_ceiling - v_used, 0);
    return;
  end if;

  insert into public.places_request_reservations (requested_count, purpose)
  values (p_count, p_purpose)
  returning id into v_reservation_id;

  return query select v_reservation_id, 'granted'::text, v_ceiling - v_used - p_count;
end;
$$;

-- This is the durable boundary immediately before a provider request. A caller
-- must successfully mark the reservation before it can call Google. If it dies
-- after this point, the pending row keeps consuming capacity until a successful
-- settlement or deliberate operator reconciliation.
create or replace function public.mark_places_request_budget_dispatched(p_reservation_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_updated integer;
begin
  update public.places_request_reservations
  set dispatched_at = now()
  where id = p_reservation_id
    and status = 'pending'
    and dispatched_at is null;
  get diagnostics v_updated = row_count;
  return v_updated > 0;
end;
$$;

create or replace function public.settle_places_request_budget(
  p_reservation_id uuid,
  p_actual_count integer
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_updated integer;
begin
  update public.places_request_reservations
  set status = 'completed',
      settled_count = greatest(coalesce(p_actual_count, 0), 0),
      settled_at = now()
  where id = p_reservation_id and status = 'pending';
  get diagnostics v_updated = row_count;
  return v_updated > 0;
end;
$$;

create or replace function public.release_places_request_budget(p_reservation_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_updated integer;
begin
  update public.places_request_reservations
  set status = 'released', settled_count = 0, settled_at = now()
  where id = p_reservation_id
    and status = 'pending'
    and dispatched_at is null;
  get diagnostics v_updated = row_count;
  return v_updated > 0;
end;
$$;

-- Operator-owned configuration. Automation starts disabled so deploying source
-- cannot start paid traffic before the Vault secret and worker URL exist.
create table public.coverage_automation_config (
  id boolean primary key default true check (id),
  enabled boolean not null default false,
  gazetteer_source_url text not null,
  gazetteer_sync_min_interval interval not null default interval '30 days'
    check (gazetteer_sync_min_interval >= interval '30 days'),
  suburb_sweep_fresh_after interval not null default interval '30 days'
    check (suburb_sweep_fresh_after >= interval '1 day'),
  worker_url text,
  worker_secret_vault_name text not null default 'coverage_automation_secret',
  updated_at timestamptz not null default now()
);

insert into public.coverage_automation_config (
  id,
  gazetteer_source_url,
  enabled,
  worker_url,
  worker_secret_vault_name
)
values (
  true,
  'https://portal.spatial.nsw.gov.au/server/rest/services/NSW_Administrative_Boundaries_Theme_multiCRS/FeatureServer/2/query',
  false,
  null,
  'coverage_automation_secret'
)
on conflict (id) do nothing;

-- `cadid` is the Spatial Services source identity. It is kept separate from
-- the immutable application UUID because a source change can split or rename a
-- locality. Existing Google-derived restaurant.suburb text stays nullable and
-- untouched: GPS expansion outside NSW must remain possible.
create table public.nsw_suburbs (
  id uuid primary key default gen_random_uuid(),
  source_cadid text not null unique,
  canonical_name text not null,
  normalised_name text not null,
  postcode text,
  source_shape_uuid text,
  source_created_at timestamptz,
  source_modified_at timestamptz,
  source_start_at timestamptz,
  source_end_at timestamptz,
  source_last_updated_at timestamptz,
  is_active boolean not null default true,
  first_seen_at timestamptz not null default now(),
  retired_at timestamptz,
  updated_at timestamptz not null default now(),
  check (length(btrim(canonical_name)) > 0),
  check (length(btrim(normalised_name)) > 0)
);

create table public.nsw_suburb_aliases (
  id bigint generated always as identity primary key,
  suburb_id uuid not null references public.nsw_suburbs (id) on delete cascade,
  alias_name text not null,
  normalised_name text not null,
  source text not null check (source in ('canonical', 'source_rename', 'retired_name', 'operator')),
  created_at timestamptz not null default now(),
  unique (suburb_id, normalised_name),
  check (length(btrim(alias_name)) > 0),
  check (length(btrim(normalised_name)) > 0)
);

create index nsw_suburbs_normalised_name_idx
  on public.nsw_suburbs (normalised_name);
create index nsw_suburb_aliases_normalised_name_idx
  on public.nsw_suburb_aliases (normalised_name);
create index nsw_suburb_aliases_trgm_idx
  on public.nsw_suburb_aliases using gin (normalised_name extensions.gin_trgm_ops);

create table public.nsw_suburb_gazetteer_syncs (
  id uuid primary key default gen_random_uuid(),
  source_url text not null,
  checksum text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  status text not null default 'running'
    check (status in ('running', 'succeeded', 'failed', 'skipped_recent')),
  records_received integer,
  error_message text
);

create index nsw_suburb_gazetteer_syncs_completed_idx
  on public.nsw_suburb_gazetteer_syncs (completed_at desc)
  where status = 'succeeded';

-- Historical demand is intentionally small and private. It turns real user
-- interest into queue ordering without retaining raw Assistant text.
create table public.nsw_suburb_coverage_demands (
  id bigint generated always as identity primary key,
  suburb_id uuid not null references public.nsw_suburbs (id) on delete cascade,
  source text not null check (source in ('assistant', 'list', 'named_venue', 'system')),
  demanded_at timestamptz not null default now()
);

create index nsw_suburb_coverage_demands_priority_idx
  on public.nsw_suburb_coverage_demands (suburb_id, demanded_at desc);

-- A job row carries priority, lease and retry state. pgmq supplies durable
-- wake-ups; this table lets the worker choose the most recently demanded
-- eligible locality rather than FIFO arrival order.
create table public.nsw_suburb_sweep_jobs (
  suburb_id uuid primary key references public.nsw_suburbs (id) on delete cascade,
  status text not null default 'queued'
    check (status in ('queued', 'running', 'completed', 'blocked_budget', 'failed')),
  last_demanded_at timestamptz,
  enqueued_at timestamptz not null default now(),
  claimed_at timestamptz,
  lease_expires_at timestamptz,
  lease_token uuid,
  next_attempt_at timestamptz not null default now(),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  last_error text,
  updated_at timestamptz not null default now()
);

create index nsw_suburb_sweep_jobs_claim_idx
  on public.nsw_suburb_sweep_jobs (status, next_attempt_at, last_demanded_at desc, enqueued_at);

-- Completion data is distinct from a job lease. A budget denial or transport
-- failure is not a successful fresh sweep and must never update last_swept_at.
create table public.nsw_suburb_sweep_state (
  suburb_id uuid primary key references public.nsw_suburbs (id) on delete cascade,
  last_swept_at timestamptz,
  last_attempt_at timestamptz,
  last_outcome text check (last_outcome in ('completed', 'failed', 'blocked_budget')),
  last_pages_attempted integer not null default 0 check (last_pages_attempted >= 0),
  last_pages_exhausted boolean,
  last_places_found integer not null default 0 check (last_places_found >= 0),
  last_error text,
  updated_at timestamptz not null default now()
);

-- pgmq is private to the worker. New messages do not expose a PostgREST table
-- to the browser; all queue access remains behind security-definer helpers.
select pgmq.create('nsw_suburb_sweep_wakeups');

-- Fixed extension schema is intentional: unaccent and trigram functions are
-- installed by Step 0 in Supabase's extensions schema.
create or replace function public.normalise_nsw_suburb_name(p_value text)
returns text
language sql
stable
strict
set search_path = public, extensions, pg_temp
as $$
  select nullif(
    regexp_replace(lower(unaccent(btrim(p_value))), '[^a-z0-9]+', '', 'g'),
    ''
  );
$$;

-- Claims a monthly sync slot before the Edge Function fetches the official
-- source. A stale running slot is marked failed so a crashed invocation cannot
-- block next month's update forever.
create or replace function public.claim_nsw_suburb_gazetteer_sync()
returns table (sync_id uuid, outcome text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_source_url text;
  v_interval interval;
  v_last_completed timestamptz;
  v_running_id uuid;
  v_sync_id uuid;
begin
  perform pg_advisory_xact_lock(hashtext('nsw_suburb_gazetteer_sync'));

  select gazetteer_source_url, gazetteer_sync_min_interval
    into v_source_url, v_interval
    from public.coverage_automation_config where id = true;

  update public.nsw_suburb_gazetteer_syncs
  set status = 'failed', completed_at = now(), error_message = 'worker lease expired'
  where status = 'running' and started_at < now() - interval '30 minutes';

  select id into v_running_id
  from public.nsw_suburb_gazetteer_syncs
  where status = 'running'
  order by started_at desc
  limit 1;
  if v_running_id is not null then
    return query select v_running_id, 'sync_in_progress'::text;
    return;
  end if;

  select completed_at into v_last_completed
  from public.nsw_suburb_gazetteer_syncs
  where status = 'succeeded'
  order by completed_at desc
  limit 1;
  if v_last_completed is not null and v_last_completed > now() - v_interval then
    return query select null::uuid, 'recently_synced'::text;
    return;
  end if;

  insert into public.nsw_suburb_gazetteer_syncs (source_url)
  values (v_source_url)
  returning id into v_sync_id;
  return query select v_sync_id, 'granted'::text;
end;
$$;

-- Atomically applies a full official snapshot. The source is current-state
-- only, so missing CadIDs are retired aliases rather than redirected to an
-- inferred successor. Existing restaurant rows retain their raw suburb text.
create or replace function public.apply_nsw_suburb_gazetteer_snapshot(
  p_sync_id uuid,
  p_records jsonb,
  p_checksum text
)
returns table (inserted_count integer, updated_count integer, retired_count integer)
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_inserted integer := 0;
  v_updated integer := 0;
  v_retired integer := 0;
begin
  if p_sync_id is null or jsonb_typeof(p_records) <> 'array' then
    raise exception 'A sync id and an array of official suburb records are required';
  end if;

  if not exists (
    select 1 from public.nsw_suburb_gazetteer_syncs
    where id = p_sync_id and status = 'running'
  ) then
    raise exception 'Gazetteer sync is not running';
  end if;

  drop table if exists incoming_nsw_suburbs;
  create temporary table incoming_nsw_suburbs on commit drop as
  select distinct on (source_cadid)
    source_cadid,
    canonical_name,
    public.normalise_nsw_suburb_name(canonical_name) as normalised_name,
    nullif(btrim(record ->> 'postcode'), '') as postcode,
    nullif(btrim(record ->> 'shapeuuid'), '') as source_shape_uuid,
    case when nullif(record ->> 'createdate', '') is null then null
      when record ->> 'createdate' ~ '^[-]?[0-9]{11,}$' then to_timestamp((record ->> 'createdate')::numeric / 1000)
      else (record ->> 'createdate')::timestamptz end as source_created_at,
    case when nullif(record ->> 'modifieddate', '') is null then null
      when record ->> 'modifieddate' ~ '^[-]?[0-9]{11,}$' then to_timestamp((record ->> 'modifieddate')::numeric / 1000)
      else (record ->> 'modifieddate')::timestamptz end as source_modified_at,
    case when nullif(record ->> 'startdate', '') is null then null
      when record ->> 'startdate' ~ '^[-]?[0-9]{11,}$' then to_timestamp((record ->> 'startdate')::numeric / 1000)
      else (record ->> 'startdate')::timestamptz end as source_start_at,
    case when nullif(record ->> 'enddate', '') is null then null
      when record ->> 'enddate' ~ '^[-]?[0-9]{11,}$' then to_timestamp((record ->> 'enddate')::numeric / 1000)
      else (record ->> 'enddate')::timestamptz end as source_end_at,
    case when nullif(record ->> 'lastupdate', '') is null then null
      when record ->> 'lastupdate' ~ '^[-]?[0-9]{11,}$' then to_timestamp((record ->> 'lastupdate')::numeric / 1000)
      else (record ->> 'lastupdate')::timestamptz end as source_last_updated_at
  from jsonb_array_elements(p_records) as value(record)
  cross join lateral (
    select nullif(btrim(record ->> 'cadid'), '') as source_cadid,
           nullif(btrim(record ->> 'suburbname'), '') as canonical_name
  ) fields
  where source_cadid is not null and canonical_name is not null
  order by source_cadid, canonical_name;

  if not exists (select 1 from incoming_nsw_suburbs) then
    raise exception 'Official snapshot did not contain a valid CadID/suburbname record';
  end if;

  -- Retain a previous name as an alias before changing an existing CadID.
  insert into public.nsw_suburb_aliases (suburb_id, alias_name, normalised_name, source)
  select existing.id, existing.canonical_name, existing.normalised_name, 'source_rename'
  from public.nsw_suburbs as existing
  join incoming_nsw_suburbs as incoming using (source_cadid)
  where existing.normalised_name <> incoming.normalised_name
  on conflict (suburb_id, normalised_name) do nothing;

  select count(*) into v_inserted
  from incoming_nsw_suburbs as incoming
  where not exists (
    select 1 from public.nsw_suburbs as existing
    where existing.source_cadid = incoming.source_cadid
  );

  select count(*) into v_updated
  from incoming_nsw_suburbs as incoming
  join public.nsw_suburbs as existing using (source_cadid)
  where row(
    existing.canonical_name,
    existing.postcode,
    existing.source_shape_uuid,
    existing.source_modified_at,
    existing.source_last_updated_at,
    existing.is_active
  ) is distinct from row(
    incoming.canonical_name,
    incoming.postcode,
    incoming.source_shape_uuid,
    incoming.source_modified_at,
    incoming.source_last_updated_at,
    true
  );

  insert into public.nsw_suburbs (
    source_cadid, canonical_name, normalised_name, postcode, source_shape_uuid,
    source_created_at, source_modified_at, source_start_at, source_end_at,
    source_last_updated_at, is_active, retired_at, updated_at
  )
  select
    source_cadid, canonical_name, normalised_name, postcode, source_shape_uuid,
    source_created_at, source_modified_at, source_start_at, source_end_at,
    source_last_updated_at, true, null, now()
  from incoming_nsw_suburbs
  on conflict (source_cadid) do update set
    canonical_name = excluded.canonical_name,
    normalised_name = excluded.normalised_name,
    postcode = excluded.postcode,
    source_shape_uuid = excluded.source_shape_uuid,
    source_created_at = excluded.source_created_at,
    source_modified_at = excluded.source_modified_at,
    source_start_at = excluded.source_start_at,
    source_end_at = excluded.source_end_at,
    source_last_updated_at = excluded.source_last_updated_at,
    is_active = true,
    retired_at = null,
    updated_at = now();

  -- The canonical label is always an alias too, making resolver reads one
  -- indexed source and allowing old/active names to be distinguished by state.
  insert into public.nsw_suburb_aliases (suburb_id, alias_name, normalised_name, source)
  select id, canonical_name, normalised_name, 'canonical'
  from public.nsw_suburbs
  where source_cadid in (select source_cadid from incoming_nsw_suburbs)
  on conflict (suburb_id, normalised_name) do nothing;

  update public.nsw_suburbs as existing
  set is_active = false, retired_at = coalesce(retired_at, now()), updated_at = now()
  where existing.is_active
    and not exists (
      select 1 from incoming_nsw_suburbs as incoming
      where incoming.source_cadid = existing.source_cadid
    );
  get diagnostics v_retired = row_count;

  insert into public.nsw_suburb_aliases (suburb_id, alias_name, normalised_name, source)
  select id, canonical_name, normalised_name, 'retired_name'
  from public.nsw_suburbs
  where not is_active
  on conflict (suburb_id, normalised_name) do nothing;

  update public.nsw_suburb_gazetteer_syncs
  set status = 'succeeded',
      completed_at = now(),
      checksum = p_checksum,
      records_received = (select count(*) from incoming_nsw_suburbs),
      error_message = null
  where id = p_sync_id;

  return query select v_inserted, v_updated, v_retired;
exception when others then
  update public.nsw_suburb_gazetteer_syncs
  set status = 'failed', completed_at = now(), error_message = left(sqlerrm, 500)
  where id = p_sync_id and status = 'running';
  raise;
end;
$$;

-- Exact matches take precedence. Fuzzy matches are intentionally conservative:
-- one clearly-best active locality is required; ambiguous and weak strings are
-- indistinguishable from no match, so neither can authorise paid work.
create or replace function public.resolve_nsw_suburb(p_query text)
returns table (
  suburb_id uuid,
  canonical_name text,
  is_active boolean,
  match_kind text
)
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_normalised text := public.normalise_nsw_suburb_name(p_query);
  v_exact_count integer;
  v_best record;
  v_next_score real;
begin
  if v_normalised is null or length(v_normalised) < 3 then
    return;
  end if;

  select count(*) into v_exact_count
  from (
    select distinct alias.suburb_id
    from public.nsw_suburb_aliases as alias
    where alias.normalised_name = v_normalised
  ) exact;

  if v_exact_count = 1 then
    return query
    select locality.id, locality.canonical_name, locality.is_active, 'exact'::text
    from public.nsw_suburbs as locality
    join public.nsw_suburb_aliases as alias on alias.suburb_id = locality.id
    where alias.normalised_name = v_normalised
    limit 1;
    return;
  end if;

  if v_exact_count > 1 then
    return;
  end if;

  select
    locality.id,
    locality.canonical_name,
    greatest(
      similarity(v_normalised, alias.normalised_name),
      word_similarity(v_normalised, alias.normalised_name)
    )::real as score
  into v_best
  from public.nsw_suburb_aliases as alias
  join public.nsw_suburbs as locality on locality.id = alias.suburb_id
  where locality.is_active
    and greatest(
      similarity(v_normalised, alias.normalised_name),
      word_similarity(v_normalised, alias.normalised_name)
    ) >= 0.72
  order by score desc, locality.canonical_name
  limit 1;

  if v_best is null then
    return;
  end if;

  select max(score) into v_next_score
  from (
    select greatest(
      similarity(v_normalised, alias.normalised_name),
      word_similarity(v_normalised, alias.normalised_name)
    )::real as score
    from public.nsw_suburb_aliases as alias
    join public.nsw_suburbs as locality on locality.id = alias.suburb_id
    where locality.is_active
      and locality.id <> v_best.id
  ) candidates;

  if v_best.score < 0.82 or coalesce(v_best.score - v_next_score, v_best.score) < 0.10 then
    return;
  end if;

  return query select v_best.id, v_best.canonical_name, true, 'fuzzy'::text;
end;
$$;

-- Assistant messages are natural language, not an area-only input field. This
-- extracts only whole official aliases from text ("quiet dinner in Crows
-- Nest"), then delegates a sole bare phrase to the conservative resolver. It
-- replaces the old application regex/stopword list, which was not a gazetteer
-- and once treated prose as a billable locality.
create or replace function public.resolve_nsw_suburb_in_text(p_text text)
returns table (
  suburb_id uuid,
  canonical_name text,
  is_active boolean,
  match_kind text
)
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_phrase text;
  v_match_count integer;
  v_bare boolean;
begin
  if p_text is null or length(btrim(p_text)) < 3 then return; end if;
  v_phrase := regexp_replace(lower(unaccent(p_text)), '[^a-z0-9]+', ' ', 'g');
  v_phrase := btrim(regexp_replace(v_phrase, '[[:space:]]+', ' ', 'g'));
  if v_phrase = '' then return; end if;

  select count(*) into v_match_count
  from (
    select distinct alias.suburb_id
    from public.nsw_suburb_aliases as alias
    where (' ' || v_phrase || ' ') like
      ('% ' || regexp_replace(lower(unaccent(alias.alias_name)), '[^a-z0-9]+', ' ', 'g') || ' %')
  ) matches;

  if v_match_count = 1 then
    return query
    select locality.id, locality.canonical_name, locality.is_active, 'text_exact'::text
    from public.nsw_suburbs as locality
    join public.nsw_suburb_aliases as alias on alias.suburb_id = locality.id
    where (' ' || v_phrase || ' ') like
      ('% ' || regexp_replace(lower(unaccent(alias.alias_name)), '[^a-z0-9]+', ' ', 'g') || ' %')
    limit 1;
    return;
  end if;

  -- Fuzzy matching is appropriate only when the whole user turn is a short,
  -- bare area phrase; allowing it over prose would reintroduce false positives.
  v_bare := array_length(regexp_split_to_array(v_phrase, ' '), 1) <= 4;
  if v_bare then
    return query select * from public.resolve_nsw_suburb(v_phrase);
  end if;
end;
$$;

create or replace function public.suburb_sweep_eligibility(p_suburb_id uuid)
returns table (eligible boolean, reason text, next_eligible_at timestamptz)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_active boolean;
  v_last_swept_at timestamptz;
  v_fresh_after interval;
begin
  select is_active into v_active from public.nsw_suburbs where id = p_suburb_id;
  if v_active is distinct from true then
    return query select false, 'retired_or_unknown_suburb'::text, null::timestamptz;
    return;
  end if;

  select suburb_sweep_fresh_after into v_fresh_after
  from public.coverage_automation_config where id = true;
  select last_swept_at into v_last_swept_at
  from public.nsw_suburb_sweep_state where suburb_id = p_suburb_id;

  if v_last_swept_at is null then
    return query select true, 'never_swept'::text, now();
    return;
  end if;
  if v_last_swept_at <= now() - v_fresh_after then
    return query select true, 'stale'::text, v_last_swept_at + v_fresh_after;
    return;
  end if;

  return query select false, 'fresh'::text, v_last_swept_at + v_fresh_after;
end;
$$;

create or replace function public.record_nsw_suburb_coverage_demand(
  p_suburb_id uuid,
  p_source text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_source not in ('assistant', 'list', 'named_venue', 'system') then
    raise exception 'Unknown suburb demand source';
  end if;
  if not exists (select 1 from public.nsw_suburbs where id = p_suburb_id) then
    raise exception 'Unknown NSW suburb';
  end if;
  insert into public.nsw_suburb_coverage_demands (suburb_id, source)
  values (p_suburb_id, p_source);
end;
$$;

-- An authenticated on-demand caller can run a stale locality immediately
-- during Step 1, while the background worker uses claim_next_... below. Both
-- paths share one lease so they cannot duplicate a paid sweep.
create or replace function public.claim_nsw_suburb_sweep(p_suburb_id uuid)
returns table (outcome text, lease_token uuid)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_eligible boolean;
  v_reason text;
  v_next_eligible_at timestamptz;
  v_existing_status text;
  v_lease_token uuid := gen_random_uuid();
begin
  perform pg_advisory_xact_lock(hashtext('nsw_suburb_sweep:' || p_suburb_id::text));
  update public.nsw_suburb_sweep_jobs
  set status = 'queued', lease_token = null, next_attempt_at = now(), updated_at = now(),
      last_error = coalesce(last_error, 'worker lease expired')
  where suburb_id = p_suburb_id
    and status = 'running'
    and lease_expires_at < now();

  select status into v_existing_status
  from public.nsw_suburb_sweep_jobs
  where suburb_id = p_suburb_id
  for update;

  -- Re-check under the per-suburb coordination lock. A worker might have
  -- completed this locality after the caller first decided to refresh it.
  select eligibility.eligible, eligibility.reason, eligibility.next_eligible_at
    into v_eligible, v_reason, v_next_eligible_at
    from public.suburb_sweep_eligibility(p_suburb_id) as eligibility;
  if not v_eligible then
    return query select v_reason, null::uuid;
    return;
  end if;
  if v_existing_status = 'running' then
    return query select 'sweep_in_progress'::text, null::uuid;
    return;
  end if;

  insert into public.nsw_suburb_sweep_jobs (
    suburb_id, status, claimed_at, lease_expires_at, lease_token, attempt_count, updated_at
  )
  values (p_suburb_id, 'running', now(), now() + interval '15 minutes', v_lease_token, 1, now())
  on conflict (suburb_id) do update set
    status = 'running',
    claimed_at = now(),
    lease_expires_at = now() + interval '15 minutes',
    lease_token = v_lease_token,
    attempt_count = public.nsw_suburb_sweep_jobs.attempt_count + 1,
    updated_at = now();

  insert into public.nsw_suburb_sweep_state (suburb_id, last_attempt_at, updated_at)
  values (p_suburb_id, now(), now())
  on conflict (suburb_id) do update
  set last_attempt_at = excluded.last_attempt_at, updated_at = excluded.updated_at;

  return query select 'granted'::text, v_lease_token;
end;
$$;

-- Records a resolved demand before deciding whether it is stale. No raw user
-- phrase is retained; only the canonical locality and caller type are stored.
create or replace function public.queue_nsw_suburb_sweep(
  p_suburb_id uuid,
  p_source text
)
returns table (outcome text, next_eligible_at timestamptz)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_eligible boolean;
  v_reason text;
  v_next_eligible_at timestamptz;
  v_existing_status text;
begin
  if p_source not in ('assistant', 'list', 'named_venue', 'system') then
    raise exception 'Unknown suburb demand source';
  end if;

  perform public.record_nsw_suburb_coverage_demand(p_suburb_id, p_source);

  select eligibility.eligible, eligibility.reason, eligibility.next_eligible_at
    into v_eligible, v_reason, v_next_eligible_at
    from public.suburb_sweep_eligibility(p_suburb_id) as eligibility;
  if not v_eligible then
    return query select v_reason, v_next_eligible_at;
    return;
  end if;

  perform pg_advisory_xact_lock(hashtext('nsw_suburb_sweep:' || p_suburb_id::text));
  select status into v_existing_status
  from public.nsw_suburb_sweep_jobs
  where suburb_id = p_suburb_id
  for update;

  if v_existing_status is null then
    insert into public.nsw_suburb_sweep_jobs (suburb_id, status, last_demanded_at)
    values (p_suburb_id, 'queued', now());
    perform pgmq.send('nsw_suburb_sweep_wakeups', jsonb_build_object('suburb_id', p_suburb_id), 0);
    return query select 'queued'::text, v_next_eligible_at;
    return;
  end if;

  update public.nsw_suburb_sweep_jobs
  set last_demanded_at = now(),
      status = case when status = 'running' then 'running' else 'queued' end,
      next_attempt_at = case when status = 'running' then next_attempt_at else now() end,
      updated_at = now()
  where suburb_id = p_suburb_id;

  if v_existing_status not in ('queued', 'running') then
    perform pgmq.send('nsw_suburb_sweep_wakeups', jsonb_build_object('suburb_id', p_suburb_id), 0);
  end if;
  return query select case when v_existing_status = 'running' then 'sweep_in_progress' else 'queued' end, v_next_eligible_at;
end;
$$;

-- Cron uses this to seed any stale locality. It is intentionally no-op until
-- an operator sets enabled=true after configuring the private worker secret.
create or replace function public.enqueue_stale_nsw_suburb_sweeps(p_limit integer default 25)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_enabled boolean;
  v_suburb_id uuid;
  v_count integer := 0;
begin
  if p_limit is null or p_limit < 1 then
    raise exception 'p_limit must be positive';
  end if;
  select enabled into v_enabled from public.coverage_automation_config where id = true;
  if not v_enabled then return 0; end if;

  for v_suburb_id in
    select locality.id
    from public.nsw_suburbs as locality
    left join public.nsw_suburb_sweep_state as state on state.suburb_id = locality.id
    left join lateral (
      select max(demanded_at) as last_demanded_at
      from public.nsw_suburb_coverage_demands as demand
      where demand.suburb_id = locality.id
    ) demand on true
    cross join public.coverage_automation_config as config
    where config.id = true
      and locality.is_active
      and (state.last_swept_at is null or state.last_swept_at <= now() - config.suburb_sweep_fresh_after)
      and not exists (
        select 1 from public.nsw_suburb_sweep_jobs as job
        where job.suburb_id = locality.id
          and job.status = 'running'
          and job.lease_expires_at > now()
      )
    order by demand.last_demanded_at desc nulls last, locality.canonical_name
    limit p_limit
  loop
    perform public.queue_nsw_suburb_sweep(v_suburb_id, 'system');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- Atomically claims the highest-demand available job. Expired leases are made
-- retryable before selection. The worker does not need a user id and never
-- consumes the separate beta-user on-demand reservation pool.
create or replace function public.claim_next_nsw_suburb_sweep()
returns table (suburb_id uuid, canonical_name text, attempt_count integer, lease_token uuid)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_job public.nsw_suburb_sweep_jobs%rowtype;
  v_lease_token uuid := gen_random_uuid();
begin
  perform pg_advisory_xact_lock(hashtext('claim_next_nsw_suburb_sweep'));

  update public.nsw_suburb_sweep_jobs
  set status = 'queued',
      lease_token = null,
      next_attempt_at = now(),
      last_error = coalesce(last_error, 'worker lease expired'),
      updated_at = now()
  where status = 'running' and lease_expires_at < now();

  select job.* into v_job
  from public.nsw_suburb_sweep_jobs as job
  join public.nsw_suburbs as locality on locality.id = job.suburb_id
  where job.status = 'queued'
    and job.next_attempt_at <= now()
    and locality.is_active
  order by job.last_demanded_at desc nulls last, job.enqueued_at
  limit 1
  for update skip locked;
  if not found then return; end if;

  update public.nsw_suburb_sweep_jobs as job
  set status = 'running',
      claimed_at = now(),
      lease_expires_at = now() + interval '15 minutes',
      lease_token = v_lease_token,
      attempt_count = job.attempt_count + 1,
      updated_at = now()
  where job.suburb_id = v_job.suburb_id;

  insert into public.nsw_suburb_sweep_state (suburb_id, last_attempt_at, updated_at)
  values (v_job.suburb_id, now(), now())
  on conflict on constraint nsw_suburb_sweep_state_pkey do update
  set last_attempt_at = excluded.last_attempt_at, updated_at = excluded.updated_at;

  return query
  select locality.id, locality.canonical_name, v_job.attempt_count + 1, v_lease_token
  from public.nsw_suburbs as locality
  where locality.id = v_job.suburb_id and locality.is_active;
end;
$$;

create or replace function public.complete_nsw_suburb_sweep(
  p_suburb_id uuid,
  p_lease_token uuid,
  p_outcome text,
  p_pages_attempted integer,
  p_pages_exhausted boolean,
  p_places_found integer,
  p_error text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_attempt_count integer;
  v_next_attempt_at timestamptz;
begin
  if p_lease_token is null then
    raise exception 'A suburb sweep lease token is required';
  end if;
  if p_outcome not in ('completed', 'failed', 'blocked_budget') then
    raise exception 'Unknown suburb sweep outcome';
  end if;
  if p_pages_attempted is null or p_pages_attempted < 0
    or p_pages_exhausted is null
    or p_places_found is null or p_places_found < 0 then
    raise exception 'Sweep totals must be non-negative';
  end if;

  select attempt_count into v_attempt_count
  from public.nsw_suburb_sweep_jobs
  where suburb_id = p_suburb_id
    and status = 'running'
    and lease_token = p_lease_token
  for update;
  if not found then return false; end if;

  if p_outcome = 'completed' then
    update public.nsw_suburb_sweep_jobs
    set status = 'completed', lease_expires_at = null, lease_token = null, last_error = null, updated_at = now()
    where suburb_id = p_suburb_id;
  elsif p_outcome = 'blocked_budget' then
    v_next_attempt_at := date_trunc('month', now() at time zone 'utc') at time zone 'utc' + interval '1 month';
    update public.nsw_suburb_sweep_jobs
    set status = 'blocked_budget', lease_expires_at = null, lease_token = null, next_attempt_at = v_next_attempt_at,
        last_error = coalesce(p_error, 'monthly Places request ceiling reached'), updated_at = now()
    where suburb_id = p_suburb_id;
  else
    v_next_attempt_at := now() + make_interval(mins => least(60, greatest(5, 5 * power(2, least(v_attempt_count, 4))::integer)));
    update public.nsw_suburb_sweep_jobs
    set status = 'queued', lease_expires_at = null, lease_token = null, next_attempt_at = v_next_attempt_at,
        last_error = coalesce(p_error, 'worker failed'), updated_at = now()
    where suburb_id = p_suburb_id;
    perform pgmq.send('nsw_suburb_sweep_wakeups', jsonb_build_object('suburb_id', p_suburb_id), 0);
  end if;

  insert into public.nsw_suburb_sweep_state (
    suburb_id, last_swept_at, last_attempt_at, last_outcome, last_pages_attempted,
    last_pages_exhausted, last_places_found, last_error, updated_at
  )
  values (
    p_suburb_id,
    case when p_outcome = 'completed' then now() else null end,
    now(), p_outcome, p_pages_attempted, p_pages_exhausted, p_places_found,
    p_error, now()
  )
  on conflict (suburb_id) do update set
    last_swept_at = case when excluded.last_outcome = 'completed' then excluded.last_swept_at else public.nsw_suburb_sweep_state.last_swept_at end,
    last_attempt_at = excluded.last_attempt_at,
    last_outcome = excluded.last_outcome,
    last_pages_attempted = excluded.last_pages_attempted,
    last_pages_exhausted = excluded.last_pages_exhausted,
    last_places_found = excluded.last_places_found,
    last_error = excluded.last_error,
    updated_at = excluded.updated_at;
  return true;
end;
$$;

-- Consumes a wake-up without exposing pgmq through the Data API. The worker
-- still claims priority from nsw_suburb_sweep_jobs, so FIFO message order never
-- defeats recent-demand ordering.
create or replace function public.consume_nsw_suburb_sweep_wakeup()
returns boolean
language sql
security definer
set search_path = public, pgmq, pg_temp
as $$
  select exists (select 1 from pgmq.pop('nsw_suburb_sweep_wakeups'));
$$;

-- pg_cron must not contain a secret. This function reads a named Vault secret
-- only at run time; when the operator has not configured it, the scheduled job
-- safely no-ops rather than exposing a public worker endpoint.
create or replace function public.request_coverage_automation_worker(p_action text)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_enabled boolean;
  v_url text;
  v_secret_name text;
  v_secret text;
begin
  if p_action not in ('sweep', 'sync_gazetteer') then
    raise exception 'Unknown coverage worker action';
  end if;
  select enabled, worker_url, worker_secret_vault_name
    into v_enabled, v_url, v_secret_name
    from public.coverage_automation_config where id = true;
  if not v_enabled then return 'disabled'; end if;
  if v_url is null or btrim(v_url) = '' then return 'worker_url_not_configured'; end if;
  if to_regclass('vault.decrypted_secrets') is null then return 'vault_unavailable'; end if;

  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1'
    into v_secret using v_secret_name;
  if v_secret is null or v_secret = '' then return 'worker_secret_not_configured'; end if;

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-coverage-automation-secret', v_secret
    ),
    body := jsonb_build_object('action', p_action)
  );
  return 'requested';
end;
$$;

-- The queue scan runs hourly; the worker tick runs every fifteen minutes.
-- Both are inert until coverage_automation_config.enabled is explicitly set.
do $$
begin
  if not exists (select 1 from cron.job where jobname = 'enqueue-stale-nsw-suburb-sweeps') then
    perform cron.schedule(
      'enqueue-stale-nsw-suburb-sweeps',
      '7 * * * *',
      'select public.enqueue_stale_nsw_suburb_sweeps(25); select public.request_coverage_automation_worker(''sweep'');'
    );
  end if;
  if not exists (select 1 from cron.job where jobname = 'run-nsw-suburb-sweep-worker') then
    perform cron.schedule(
      'run-nsw-suburb-sweep-worker',
      '*/15 * * * *',
      'select public.request_coverage_automation_worker(''sweep'');'
    );
  end if;
  if not exists (select 1 from cron.job where jobname = 'sync-nsw-suburb-gazetteer') then
    perform cron.schedule(
      'sync-nsw-suburb-gazetteer',
      '23 3 * * *',
      'select public.request_coverage_automation_worker(''sync_gazetteer'');'
    );
  end if;
end;
$$;

-- Everything is private to service-role Edge Functions or database cron jobs.
alter table public.coverage_automation_config enable row level security;
alter table public.nsw_suburbs enable row level security;
alter table public.nsw_suburb_aliases enable row level security;
alter table public.nsw_suburb_gazetteer_syncs enable row level security;
alter table public.nsw_suburb_coverage_demands enable row level security;
alter table public.nsw_suburb_sweep_jobs enable row level security;
alter table public.nsw_suburb_sweep_state enable row level security;

revoke all on table public.coverage_automation_config,
  public.nsw_suburbs,
  public.nsw_suburb_aliases,
  public.nsw_suburb_gazetteer_syncs,
  public.nsw_suburb_coverage_demands,
  public.nsw_suburb_sweep_jobs,
  public.nsw_suburb_sweep_state
  from anon, authenticated;

revoke all on function public.normalise_nsw_suburb_name(text) from public, anon, authenticated;
revoke all on function public.backfill_legacy_places_request_dispatches(timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.mark_places_request_budget_dispatched(uuid) from public, anon, authenticated;
revoke all on function public.claim_nsw_suburb_gazetteer_sync() from public, anon, authenticated;
revoke all on function public.apply_nsw_suburb_gazetteer_snapshot(uuid, jsonb, text) from public, anon, authenticated;
revoke all on function public.resolve_nsw_suburb(text) from public, anon, authenticated;
revoke all on function public.resolve_nsw_suburb_in_text(text) from public, anon, authenticated;
revoke all on function public.suburb_sweep_eligibility(uuid) from public, anon, authenticated;
revoke all on function public.record_nsw_suburb_coverage_demand(uuid, text) from public, anon, authenticated;
revoke all on function public.claim_nsw_suburb_sweep(uuid) from public, anon, authenticated;
revoke all on function public.queue_nsw_suburb_sweep(uuid, text) from public, anon, authenticated;
revoke all on function public.enqueue_stale_nsw_suburb_sweeps(integer) from public, anon, authenticated;
revoke all on function public.claim_next_nsw_suburb_sweep() from public, anon, authenticated;
revoke all on function public.complete_nsw_suburb_sweep(uuid, uuid, text, integer, boolean, integer, text) from public, anon, authenticated;
revoke all on function public.consume_nsw_suburb_sweep_wakeup() from public, anon, authenticated;
revoke all on function public.request_coverage_automation_worker(text) from public, anon, authenticated;

grant execute on function public.claim_nsw_suburb_gazetteer_sync() to service_role;
grant execute on function public.apply_nsw_suburb_gazetteer_snapshot(uuid, jsonb, text) to service_role;
grant execute on function public.resolve_nsw_suburb(text) to service_role;
grant execute on function public.resolve_nsw_suburb_in_text(text) to service_role;
grant execute on function public.suburb_sweep_eligibility(uuid) to service_role;
grant execute on function public.record_nsw_suburb_coverage_demand(uuid, text) to service_role;
grant execute on function public.claim_nsw_suburb_sweep(uuid) to service_role;
grant execute on function public.queue_nsw_suburb_sweep(uuid, text) to service_role;
grant execute on function public.claim_next_nsw_suburb_sweep() to service_role;
grant execute on function public.complete_nsw_suburb_sweep(uuid, uuid, text, integer, boolean, integer, text) to service_role;
grant execute on function public.consume_nsw_suburb_sweep_wakeup() to service_role;
grant execute on function public.mark_places_request_budget_dispatched(uuid) to service_role;
