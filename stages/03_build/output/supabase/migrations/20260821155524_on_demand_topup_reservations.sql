-- Atomic reservation ledger for paid on-demand coverage refreshes.
--
-- The old count-then-call flow could allow concurrent requests to observe the
-- same remaining daily capacity (or missing nearby checkpoint) and each spend
-- a Google request. This table retains both in-flight and completed claims;
-- ondemand_topup_events remains the durable audit record and references each
-- new reservation so the two accounting sources never double-count a call.
--
-- Limits confirmed for this implementation:
--   * 20 paid refreshes shared by all beta users per UTC day (existing cap)
--   * 5 paid refreshes per account per UTC day
--   * one in-flight nearby request in each 250 m circle

alter table public.ondemand_topup_events
  add column if not exists user_id uuid references auth.users (id) on delete set null;

alter table public.ondemand_topup_events
  add column if not exists reservation_id uuid;

create index if not exists ondemand_topup_events_user_triggered_at_idx
  on public.ondemand_topup_events (user_id, triggered_at desc);

create table public.ondemand_topup_reservations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  scope_key text not null,
  latitude double precision,
  longitude double precision,
  reserved_at timestamptz not null default now(),
  status text not null default 'pending' check (status in ('pending', 'completed')),
  completed_at timestamptz,
  check (
    (latitude is null and longitude is null) or
    (latitude between -90 and 90 and longitude between -180 and 180)
  )
);

alter table public.ondemand_topup_events
  add constraint ondemand_topup_events_reservation_id_fkey
  foreign key (reservation_id)
  references public.ondemand_topup_reservations (id)
  on delete set null;

create unique index ondemand_topup_events_reservation_id_key
  on public.ondemand_topup_events (reservation_id)
  where reservation_id is not null;

alter table public.ondemand_topup_reservations enable row level security;
revoke all on table public.ondemand_topup_reservations from anon, authenticated;

create index ondemand_topup_reservations_reserved_at_idx
  on public.ondemand_topup_reservations (reserved_at);
create index ondemand_topup_reservations_user_reserved_at_idx
  on public.ondemand_topup_reservations (user_id, reserved_at desc);
create index ondemand_topup_reservations_coordinates_idx
  on public.ondemand_topup_reservations (latitude, longitude)
  where latitude is not null;

-- The function is service-role-only. It serializes the tiny claim section
-- with a transaction-scoped advisory lock, then counts old event rows plus
-- every reservation created today. Stale pending reservations are only a crash
-- recovery path; completed reservations remain as the authoritative daily
-- budget ledger even if a later event-log write has a transient failure.
create or replace function public.claim_ondemand_topup_reservation(
  p_user_id uuid,
  p_scope_key text,
  p_latitude double precision default null,
  p_longitude double precision default null
)
returns table (
  reservation_id uuid,
  outcome text,
  checked_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_today_start timestamptz := date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';
  v_global_daily_cap constant integer := 20;
  v_user_daily_cap constant integer := 5;
  v_nearby_radius_meters constant double precision := 250;
  v_reservation_ttl constant interval := interval '10 minutes';
  v_latitude_delta double precision;
  v_longitude_delta double precision;
  v_checked_at timestamptz;
  v_reservation_id uuid;
  v_global_used integer;
  v_user_used integer;
begin
  if p_user_id is null or coalesce(btrim(p_scope_key), '') = '' then
    raise exception 'A user and scope key are required for a coverage reservation';
  end if;

  if (p_latitude is null) <> (p_longitude is null) then
    raise exception 'Latitude and longitude must be supplied together';
  end if;

  if p_latitude is not null and (
    p_latitude < -90 or p_latitude > 90 or
    p_longitude < -180 or p_longitude > 180
  ) then
    raise exception 'Invalid reservation coordinates';
  end if;

  perform pg_advisory_xact_lock(hashtext('ondemand_topup_reservations'));

  delete from public.ondemand_topup_reservations
  where status = 'pending' and reserved_at < now() - v_reservation_ttl;

  if p_latitude is not null then
    v_latitude_delta := v_nearby_radius_meters / 111000.0;
    v_longitude_delta := v_nearby_radius_meters /
      (111000.0 * greatest(cos(radians(p_latitude)), 0.01));

    select checkpoint.checked_at
      into v_checked_at
      from public.venue_coverage_checkpoints as checkpoint
      where checkpoint.checked_at >= now() - interval '7 days'
        and checkpoint.latitude between p_latitude - v_latitude_delta and p_latitude + v_latitude_delta
        and checkpoint.longitude between p_longitude - v_longitude_delta and p_longitude + v_longitude_delta
        and 2 * 6371000 * asin(sqrt(
          power(sin(radians(checkpoint.latitude - p_latitude) / 2), 2) +
          cos(radians(p_latitude)) * cos(radians(checkpoint.latitude)) *
          power(sin(radians(checkpoint.longitude - p_longitude) / 2), 2)
        )) <= v_nearby_radius_meters
      order by checkpoint.checked_at desc
      limit 1;

    if found then
      return query select null::uuid, 'nearby_recently_checked'::text, v_checked_at;
      return;
    end if;

    select reservation.reserved_at
      into v_checked_at
      from public.ondemand_topup_reservations as reservation
      where reservation.status = 'pending'
        and reservation.latitude between p_latitude - v_latitude_delta and p_latitude + v_latitude_delta
        and reservation.longitude between p_longitude - v_longitude_delta and p_longitude + v_longitude_delta
        and 2 * 6371000 * asin(sqrt(
          power(sin(radians(reservation.latitude - p_latitude) / 2), 2) +
          cos(radians(p_latitude)) * cos(radians(reservation.latitude)) *
          power(sin(radians(reservation.longitude - p_longitude) / 2), 2)
        )) <= v_nearby_radius_meters
      order by reservation.reserved_at desc
      limit 1;

    if found then
      return query select null::uuid, 'nearby_check_in_progress'::text, v_checked_at;
      return;
    end if;
  elsif exists (
    select 1
    from public.ondemand_topup_reservations
    where scope_key = p_scope_key and status = 'pending'
  ) then
    return query select null::uuid, 'topup_in_progress'::text, null::timestamptz;
    return;
  end if;

  select
    (select count(*) from public.ondemand_topup_events
      where reservation_id is null and haiku_decision = 'yes' and triggered_at >= v_today_start) +
    (select count(*) from public.ondemand_topup_reservations
      where reserved_at >= v_today_start)
    into v_global_used;

  if v_global_used >= v_global_daily_cap then
    return query select null::uuid, 'daily_cap_reached'::text, null::timestamptz;
    return;
  end if;

  select
    (select count(*) from public.ondemand_topup_events
      where reservation_id is null and user_id = p_user_id and haiku_decision = 'yes' and triggered_at >= v_today_start) +
    (select count(*) from public.ondemand_topup_reservations
      where user_id = p_user_id and reserved_at >= v_today_start)
    into v_user_used;

  if v_user_used >= v_user_daily_cap then
    return query select null::uuid, 'user_daily_cap_reached'::text, null::timestamptz;
    return;
  end if;

  insert into public.ondemand_topup_reservations (user_id, scope_key, latitude, longitude)
  values (p_user_id, p_scope_key, p_latitude, p_longitude)
  returning id into v_reservation_id;

  return query select v_reservation_id, 'granted'::text, null::timestamptz;
end;
$$;

create or replace function public.release_ondemand_topup_reservation(
  p_reservation_id uuid
)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  delete from public.ondemand_topup_reservations
  where id = p_reservation_id and status = 'pending';
$$;

create or replace function public.complete_ondemand_topup_reservation(
  p_reservation_id uuid
)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  update public.ondemand_topup_reservations
  set status = 'completed', completed_at = now()
  where id = p_reservation_id and status = 'pending';
$$;

revoke all on function public.claim_ondemand_topup_reservation(uuid, text, double precision, double precision)
  from public, anon, authenticated;
revoke all on function public.release_ondemand_topup_reservation(uuid)
  from public, anon, authenticated;
revoke all on function public.complete_ondemand_topup_reservation(uuid)
  from public, anon, authenticated;
grant execute on function public.claim_ondemand_topup_reservation(uuid, text, double precision, double precision)
  to service_role;
grant execute on function public.release_ondemand_topup_reservation(uuid)
  to service_role;
grant execute on function public.complete_ondemand_topup_reservation(uuid)
  to service_role;

-- Votes are cheap but directly affect a venue's fresh current-loudness value.
-- Serialize a user's votes for one venue, overwrite the client timestamp, and
-- refuse repeats for five minutes. Mic readings keep their separate 30-second
-- account-wide trigger because the two signals have different flows.
create or replace function public.enforce_loudness_vote_cooldown()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_last_submitted timestamptz;
  v_wait_seconds numeric;
begin
  perform pg_advisory_xact_lock(hashtext('loudness_vote:' || new.user_id::text || ':' || new.place_id));
  new.submitted_at := now();

  select max(submitted_at)
    into v_last_submitted
    from public.loudness_votes
    where user_id = new.user_id and place_id = new.place_id;

  if v_last_submitted is not null and now() - v_last_submitted < interval '5 minutes' then
    v_wait_seconds := ceil(extract(epoch from (interval '5 minutes' - (now() - v_last_submitted))));
    raise exception 'rate_limited: wait % more second(s) before submitting another vote for this venue', v_wait_seconds;
  end if;

  return new;
end;
$$;

drop trigger if exists loudness_votes_cooldown on public.loudness_votes;
create trigger loudness_votes_cooldown
  before insert on public.loudness_votes
  for each row
  execute function public.enforce_loudness_vote_cooldown();
