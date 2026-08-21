-- A venue's historical aggregate is its baseline. A new on-site vote or
-- completed mic reading is stored separately so clients can show it at full
-- weight now, then blend it back to the baseline over 21 days.
alter table restaurants
  add column if not exists current_loudness_subscore numeric,
  add column if not exists current_loudness_observed_at timestamptz,
  add column if not exists current_loudness_source text;

alter table restaurants
  drop constraint if exists restaurants_current_loudness_subscore_check,
  drop constraint if exists restaurants_current_loudness_source_check;

alter table restaurants
  add constraint restaurants_current_loudness_subscore_check
    check (current_loudness_subscore is null or (current_loudness_subscore >= 0 and current_loudness_subscore <= 100)),
  add constraint restaurants_current_loudness_source_check
    check (current_loudness_source is null or current_loudness_source in ('mic', 'vote'));

-- Existing historical readings predate fixed-window capture and therefore
-- remain null. Every new insert must explicitly prove at least 10 seconds.
alter table mic_readings
  add column if not exists capture_duration_ms integer;

alter table mic_readings
  drop constraint if exists mic_readings_capture_duration_ms_min;

alter table mic_readings
  add constraint mic_readings_capture_duration_ms_min
    check (capture_duration_ms is null or capture_duration_ms >= 10000);

create or replace function require_complete_mic_capture()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.capture_duration_ms is null or new.capture_duration_ms < 10000 then
    raise exception 'capture_too_short: venue microphone readings require a complete 10-second capture';
  end if;
  return new;
end;
$$;

drop trigger if exists mic_readings_require_complete_capture on mic_readings;
create trigger mic_readings_require_complete_capture
  before insert on mic_readings
  for each row
  execute function require_complete_mic_capture();

-- The app has no UPDATE policy on restaurants, and it should not gain one.
-- These narrowly scoped trigger functions are the only path that updates the
-- fresh-observation fields. Direct execution is revoked; INSERT triggers do
-- not need callers to have EXECUTE on their backing function.
create or replace function set_current_loudness_from_mic()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update restaurants
     set current_loudness_subscore = greatest(0, least(100, 100 - ((new.decibel_value - 50) / 40) * 100)),
         current_loudness_observed_at = now(),
         current_loudness_source = 'mic'
   where place_id = new.place_id;
  return new;
end;
$$;

create or replace function set_current_loudness_from_vote()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update restaurants
     set current_loudness_subscore = case new.vote
           when 'quiet' then 100
           when 'normal' then 50
           when 'loud' then 0
         end,
         current_loudness_observed_at = now(),
         current_loudness_source = 'vote'
   where place_id = new.place_id;
  return new;
end;
$$;

revoke all on function set_current_loudness_from_mic() from public;
revoke all on function set_current_loudness_from_vote() from public;

drop trigger if exists mic_readings_set_current_loudness on mic_readings;
create trigger mic_readings_set_current_loudness
  before insert on mic_readings
  for each row
  execute function set_current_loudness_from_mic();

drop trigger if exists loudness_votes_set_current_loudness on loudness_votes;
create trigger loudness_votes_set_current_loudness
  before insert on loudness_votes
  for each row
  execute function set_current_loudness_from_vote();
