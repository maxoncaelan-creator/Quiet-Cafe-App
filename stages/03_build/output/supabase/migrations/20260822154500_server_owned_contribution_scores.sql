-- Contribution aggregates must not depend on a best-effort client call after
-- a vote or microphone insert. Keep the database as the authoritative path:
-- a successful contribution transaction always leaves its venue aggregate in
-- sync. The full batch pipeline remains responsible for review refreshes.

create or replace function public.recompute_restaurant_score_from_contributions(
  p_place_id text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_mic_count_ios integer := 0;
  v_mic_count_android integer := 0;
  v_mic_count_total integer := 0;
  v_mic_subscore numeric;
  v_vote_count integer := 0;
  v_vote_subscore numeric;
  v_review_subscore numeric;
  v_popular_subscore numeric;
  v_review_count integer := 0;
  v_quietness_score numeric;
  v_confidence text;
  v_weight_sum numeric := 0;
  v_weighted_score numeric := 0;
  v_confidence_points integer := 0;
begin
  if coalesce(btrim(p_place_id), '') = '' then
    raise exception 'A restaurant place id is required';
  end if;

  -- Apply the same per-user calibration and platform weighting as the batch
  -- scoring module, without reading microphone rows outside this restaurant.
  with venue_mic_users as (
    select distinct reading.user_id
    from public.mic_readings as reading
    where reading.place_id = p_place_id
  ), latest_calibration as (
    select distinct on (calibration.user_id)
      calibration.user_id,
      calibration.decibel_value
    from public.mic_calibrations as calibration
    inner join venue_mic_users as venue_user on venue_user.user_id = calibration.user_id
    order by calibration.user_id, calibration.recorded_at desc
  ), normalised_mics as (
    select
      reading.platform,
      reading.decibel_value - coalesce(calibration.decibel_value - 60, 0) as decibel_value
    from public.mic_readings as reading
    left join latest_calibration as calibration on calibration.user_id = reading.user_id
    where reading.place_id = p_place_id
  ), platform_averages as (
    select platform, avg(decibel_value) as avg_decibel
    from normalised_mics
    group by platform
  ), mic_counts as (
    select
      count(*) filter (where platform = 'ios')::integer as ios_count,
      count(*) filter (where platform = 'android')::integer as android_count,
      count(*)::integer as total_count
    from normalised_mics
  ), weighted_mic as (
    select
      sum(avg_decibel * case platform when 'ios' then 1.0 when 'android' then 0.5 when 'web' then 0.35 else 0 end) /
      nullif(sum(case platform when 'ios' then 1.0 when 'android' then 0.5 when 'web' then 0.35 else 0 end), 0) as weighted_decibel
    from platform_averages
  )
  select
    mic_counts.ios_count,
    mic_counts.android_count,
    mic_counts.total_count,
    case
      when weighted_mic.weighted_decibel is null then null
      else greatest(0, least(100, 100 - ((weighted_mic.weighted_decibel - 50) / 40) * 100))
    end
  into v_mic_count_ios, v_mic_count_android, v_mic_count_total, v_mic_subscore
  from mic_counts cross join weighted_mic;

  -- A same-user microphone reading within five minutes is more direct than a
  -- vote, so it excludes that vote from the historical aggregate.
  select
    count(*)::integer,
    avg(case vote.vote when 'quiet' then 100 when 'normal' then 50 when 'loud' then 0 end)
  into v_vote_count, v_vote_subscore
  from public.loudness_votes as vote
  where vote.place_id = p_place_id
    and not exists (
      select 1
      from public.mic_readings as reading
      where reading.place_id = vote.place_id
        and reading.user_id = vote.user_id
        and abs(extract(epoch from (reading.submitted_at - vote.submitted_at))) <= 300
    );

  select
    restaurant.review_subscore,
    restaurant.popular_subscore,
    coalesce(restaurant.review_positive_count, 0) + coalesce(restaurant.review_negative_count, 0)
  into v_review_subscore, v_popular_subscore, v_review_count
  from public.restaurants as restaurant
  where restaurant.place_id = p_place_id
  for update;

  if not found then
    raise exception 'Restaurant % does not exist', p_place_id;
  end if;

  if v_mic_subscore is not null then
    v_weight_sum := v_weight_sum + 0.4;
    v_weighted_score := v_weighted_score + v_mic_subscore * 0.4;
  end if;
  if v_review_subscore is not null then
    v_weight_sum := v_weight_sum + 0.25;
    v_weighted_score := v_weighted_score + v_review_subscore * 0.25;
  end if;
  if v_vote_subscore is not null then
    v_weight_sum := v_weight_sum + 0.2;
    v_weighted_score := v_weighted_score + v_vote_subscore * 0.2;
  end if;
  if v_popular_subscore is not null then
    v_weight_sum := v_weight_sum + 0.15;
    v_weighted_score := v_weighted_score + v_popular_subscore * 0.15;
  end if;

  if v_weight_sum > 0 then
    v_quietness_score := greatest(0, least(100, v_weighted_score / v_weight_sum));
    v_confidence_points :=
      case when v_review_count = 0 then 0 when v_review_count < 3 then 1 when v_review_count < 6 then 2 else 3 end +
      case when v_mic_count_total = 0 then 0 when v_mic_count_total < 3 then 1 when v_mic_count_total < 10 then 2 else 3 end +
      case when v_vote_count = 0 then 0 when v_vote_count < 3 then 1 when v_vote_count < 10 then 2 else 3 end +
      case when v_popular_subscore is null then 0 else 3 end;
    v_confidence := (array['Very Low', 'Low', 'Moderate', 'High', 'Very High', 'Certain'])[least(6, greatest(1, v_confidence_points))];
  else
    v_quietness_score := null;
    v_confidence := null;
  end if;

  update public.restaurants as restaurant
     set mic_reading_count_ios = v_mic_count_ios,
         mic_reading_count_android = v_mic_count_android,
         mic_subscore = v_mic_subscore,
         mic_signal_updated_at = now(),
         vote_count = v_vote_count,
         vote_subscore = v_vote_subscore,
         vote_signal_updated_at = now(),
         quietness_score = v_quietness_score,
         confidence = v_confidence,
         score_updated_at = now()
   where restaurant.place_id = p_place_id;
end;
$$;

create or replace function public.recompute_restaurant_score_after_contribution()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.recompute_restaurant_score_from_contributions(new.place_id);
  return new;
end;
$$;

revoke all on function public.recompute_restaurant_score_from_contributions(text) from public, anon, authenticated;
revoke all on function public.recompute_restaurant_score_after_contribution() from public;

drop trigger if exists mic_readings_recompute_restaurant_score on public.mic_readings;
create trigger mic_readings_recompute_restaurant_score
  after insert on public.mic_readings
  for each row
  execute function public.recompute_restaurant_score_after_contribution();

drop trigger if exists loudness_votes_recompute_restaurant_score on public.loudness_votes;
create trigger loudness_votes_recompute_restaurant_score
  after insert on public.loudness_votes
  for each row
  execute function public.recompute_restaurant_score_after_contribution();
