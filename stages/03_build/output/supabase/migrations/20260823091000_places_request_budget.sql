-- A global, month-denominated ceiling on billed Google Places requests.
--
-- Why this exists, and why it lands before the step 1 automation rather than
-- with it: the project currently has NO global spend ceiling. The existing
-- guards are 20 shared paid refreshes per UTC day and 5 per account per day
-- (20260821155524_on_demand_topup_reservations.sql). Those are denominated in
-- *refreshes*, and one refresh is up to eight billed Places requests — two base
-- pages plus three follow-up categories. At the cap that is roughly 3,000-4,800
-- requests a month, an order of magnitude above the $10/month ceiling Caelan
-- set on 2026-08-23. The project is under budget today only because usage is
-- tiny: ten top-up events in its entire history.
--
-- Step 1 exists to increase Google traffic. The guard must therefore exist
-- first. Nothing calls these functions yet; wiring the collector to them is a
-- step 1 task.
--
-- Denominated in requests, not dollars, deliberately. Google's per-SKU pricing
-- changed in March 2025 (per-SKU free allowances replaced the flat $200
-- credit), and places-search asks for `places.reviews`, which is an
-- Enterprise/Atmosphere-class field rather than a cheap Essentials one. The
-- dollar value of a request can only be read from the billing console, so the
-- ceiling is a request count that Caelan maps to his own budget.

create table public.places_budget_config (
  -- Single-row table: the check constraint makes a second row impossible.
  id boolean primary key default true check (id),
  monthly_request_ceiling integer not null check (monthly_request_ceiling >= 0),
  updated_at timestamptz not null default now(),
  note text
);

comment on table public.places_budget_config is
  'Single-row ceiling for billed Google Places requests per UTC month. Caelan can change monthly_request_ceiling without a deploy.';

-- PROVISIONAL. 300 requests/month is a placeholder chosen against a $10 ceiling
-- and an assumed high-tier per-request cost. It has NOT been reconciled against
-- real Google Cloud billing for this project. Confirm it from the billing
-- console before step 1 opens the throttle, and change this row rather than
-- editing this migration.
insert into public.places_budget_config (id, monthly_request_ceiling, note)
values (true, 300, 'Provisional against $10/month. Confirm against real Google Cloud billing before step 1 raises Places traffic.')
on conflict (id) do nothing;

create table public.places_request_reservations (
  id uuid primary key default gen_random_uuid(),
  reserved_at timestamptz not null default now(),
  requested_count integer not null check (requested_count > 0),
  settled_count integer check (settled_count >= 0),
  status text not null default 'pending' check (status in ('pending', 'completed', 'released')),
  purpose text
);

create index places_request_reservations_month_idx
  on public.places_request_reservations (reserved_at desc)
  where status <> 'released';

comment on table public.places_request_reservations is
  'Reserve-then-settle ledger for billed Places requests. A pending row counts against the ceiling at its reserved size so concurrent callers cannot both observe the same headroom.';

-- Usage for the current UTC month: pending reservations count at their
-- requested size, completed ones at what they actually spent, released ones
-- not at all.
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
  where reserved_at >= p_month_start;
$$;

-- Claims headroom before any billed call. Serialised on a transaction-scoped
-- advisory lock so two concurrent sweeps cannot both read the same remaining
-- allowance, matching claim_ondemand_topup_reservation()'s approach.
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

-- Settles a claim to what was actually spent. Called after the Places calls
-- complete, whether or not they all succeeded.
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
      settled_count = greatest(coalesce(p_actual_count, 0), 0)
  where id = p_reservation_id and status = 'pending';
  get diagnostics v_updated = row_count;
  return v_updated > 0;
end;
$$;

-- Releases a claim that never spent anything, so an aborted sweep does not
-- hold budget for the rest of the month.
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
  set status = 'released', settled_count = 0
  where id = p_reservation_id and status = 'pending';
  get diagnostics v_updated = row_count;
  return v_updated > 0;
end;
$$;

-- These are internal, called by service-role Edge Functions. No browser role
-- may reach them through PostgREST. Revoking here rather than waiting for the
-- security advisor to flag it, per PR #43's finding.
revoke all on function public.claim_places_request_budget(integer, text) from public, anon, authenticated;
revoke all on function public.settle_places_request_budget(uuid, integer) from public, anon, authenticated;
revoke all on function public.release_places_request_budget(uuid) from public, anon, authenticated;
revoke all on function public.places_budget_used(timestamptz) from public, anon, authenticated;

alter table public.places_budget_config enable row level security;
alter table public.places_request_reservations enable row level security;
-- No policies: deny-all to every browser role, reachable only via the service
-- role. Same deliberate posture as beta_codes and ondemand_topup_reservations.
