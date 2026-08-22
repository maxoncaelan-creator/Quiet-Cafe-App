-- The reservation function's RETURNS TABLE output parameter
-- `reservation_id` shares its name with the event table column. PostgreSQL
-- treats an unqualified reference as ambiguous in PL/pgSQL, so every paid
-- top-up failed before Google Places was reached. Qualify every table column
-- in the accounting queries; this retains the existing atomic limits.

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

  delete from public.ondemand_topup_reservations as stale_reservation
  where stale_reservation.status = 'pending'
    and stale_reservation.reserved_at < now() - v_reservation_ttl;

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
    from public.ondemand_topup_reservations as pending_reservation
    where pending_reservation.scope_key = p_scope_key
      and pending_reservation.status = 'pending'
  ) then
    return query select null::uuid, 'topup_in_progress'::text, null::timestamptz;
    return;
  end if;

  select
    (select count(*) from public.ondemand_topup_events as event
      where event.reservation_id is null
        and event.haiku_decision = 'yes'
        and event.triggered_at >= v_today_start) +
    (select count(*) from public.ondemand_topup_reservations as reservation
      where reservation.reserved_at >= v_today_start)
    into v_global_used;

  if v_global_used >= v_global_daily_cap then
    return query select null::uuid, 'daily_cap_reached'::text, null::timestamptz;
    return;
  end if;

  select
    (select count(*) from public.ondemand_topup_events as event
      where event.reservation_id is null
        and event.user_id = p_user_id
        and event.haiku_decision = 'yes'
        and event.triggered_at >= v_today_start) +
    (select count(*) from public.ondemand_topup_reservations as reservation
      where reservation.user_id = p_user_id
        and reservation.reserved_at >= v_today_start)
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

revoke all on function public.claim_ondemand_topup_reservation(uuid, text, double precision, double precision)
  from public, anon, authenticated;
grant execute on function public.claim_ondemand_topup_reservation(uuid, text, double precision, double precision)
  to service_role;
