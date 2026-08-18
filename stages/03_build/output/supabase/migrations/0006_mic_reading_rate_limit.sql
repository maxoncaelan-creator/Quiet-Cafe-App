-- Per-account rate limiting on mic reading submissions, decided with Caelan
-- 2026-08-18: a 30-second cooldown between any two submissions from the same
-- account, regardless of restaurant. Enforced server-side (not just in the
-- Flutter app) so it can't be bypassed by a modified client.
--
-- `recorded_at` is client-supplied (the on-device capture time, used for
-- time-of-day filtering per ranking-spec.md) and so isn't trustworthy for
-- this. `submitted_at` is a separate, server-controlled timestamp the
-- trigger below always overwrites with `now()`.
alter table mic_readings
  add column submitted_at timestamptz not null default now();

create or replace function enforce_mic_reading_cooldown()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  last_submitted timestamptz;
  wait_seconds numeric;
begin
  -- Ignore whatever the client sent (if anything) for this column.
  new.submitted_at := now();

  -- Relies on the existing "Users can read their own mic readings" SELECT
  -- policy (0003_auth_required_for_mic_readings.sql) — this runs as the
  -- inserting user, not security definer, so it only ever sees their own
  -- rows, which is exactly the scope needed here.
  select max(submitted_at) into last_submitted
  from mic_readings
  where user_id = new.user_id;

  if last_submitted is not null and now() - last_submitted < interval '30 seconds' then
    wait_seconds := ceil(extract(epoch from (interval '30 seconds' - (now() - last_submitted))));
    raise exception 'rate_limited: wait % more second(s) before submitting another reading', wait_seconds;
  end if;

  return new;
end;
$$;

create trigger mic_readings_cooldown
  before insert on mic_readings
  for each row
  execute function enforce_mic_reading_cooldown();
