begin;

create extension if not exists pgtap with schema extensions;
select plan(7);

insert into auth.users (id, email)
values ('00000000-0000-0000-0000-000000000101', 'architecture-guard@example.com');

-- The second reservation would exceed the five-hour 10,000-token budget only
-- if the first reservation is actually persisted under the same lock.
select results_eq(
  $$ select outcome from public.claim_search_assistant_budget('00000000-0000-0000-0000-000000000101', 6000) $$,
  array['granted'::text],
  'the Assistant budget atomically grants available capacity'
);

select results_eq(
  $$ select outcome from public.claim_search_assistant_budget('00000000-0000-0000-0000-000000000101', 5000) $$,
  array['rate_limited'::text],
  'the Assistant budget rejects a concurrent over-limit reservation'
);

select public.settle_search_assistant_budget(
  '00000000-0000-0000-0000-000000000101',
  (select window_start from public.search_assistant_usage where user_id = '00000000-0000-0000-0000-000000000101'),
  6000,
  1200
);

select is(
  (select tokens_used from public.search_assistant_usage where user_id = '00000000-0000-0000-0000-000000000101'),
  1200,
  'settling replaces the conservative reservation with actual token usage'
);

insert into public.restaurants (
  place_id,
  name,
  review_positive_count,
  review_negative_count,
  review_subscore
)
values ('architecture-guard-venue', 'Architecture Guard Venue', 1, 0, 100);

insert into public.mic_readings (
  place_id,
  user_id,
  decibel_value,
  platform,
  capture_duration_ms
)
values ('architecture-guard-venue', '00000000-0000-0000-0000-000000000101', 70, 'ios', 10000);

select is(
  (select mic_reading_count_ios from public.restaurants where place_id = 'architecture-guard-venue'),
  1,
  'a microphone insert recomputes the venue aggregate inside its transaction'
);

select cmp_ok(
  (select quietness_score from public.restaurants where place_id = 'architecture-guard-venue'),
  '>',
  69::numeric,
  'the contribution score combines the stored review and microphone signals'
);

insert into public.loudness_votes (place_id, user_id, vote)
values ('architecture-guard-venue', '00000000-0000-0000-0000-000000000101', 'normal');

select is(
  (select vote_count from public.restaurants where place_id = 'architecture-guard-venue'),
  0,
  'a same-user vote near a microphone reading is excluded by server-side scoring'
);

select is(
  (select current_loudness_source from public.restaurants where place_id = 'architecture-guard-venue'),
  'vote',
  'the fresh on-site observation remains independent of the historical aggregate'
);

select * from finish();
rollback;
