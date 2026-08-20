-- On-demand suburb top-up event log — 2026-08-20. Backs the ondemand-topup
-- Edge Function's daily cap and per-area "when did we last check" decision
-- input. Deliberately separate from restaurants' own timestamps: those
-- reflect data changes, this reflects deliberate top-up *attempts*
-- (including ones Haiku declined to run), which is what the cap and
-- recency check actually need — a restaurant row's own updated_at can't
-- tell you "we checked and decided not to spend the API call."
create table ondemand_topup_events (
  id bigint generated always as identity primary key,
  area_query text not null,
  triggered_at timestamptz not null default now(),
  haiku_decision text not null check (haiku_decision in ('yes', 'no')),
  haiku_reason text,
  result_count_before int not null,
  -- null exactly when haiku_decision = 'no' (no search ran, nothing to count)
  places_found int,
  constraint places_found_matches_decision check (
    (haiku_decision = 'yes' and places_found is not null) or
    (haiku_decision = 'no' and places_found is null)
  )
);

-- No public access — only the Edge Function's service-role client touches
-- this, same posture as search_assistant_usage (0007_search_assistant_rate_limit.sql).
alter table ondemand_topup_events enable row level security;

-- Per-area recency lookups ("when did we last check Orange?") and the
-- daily-cap count ("how many triggers today across all areas?").
create index ondemand_topup_events_area_query_idx on ondemand_topup_events (area_query, triggered_at desc);
create index ondemand_topup_events_triggered_at_idx on ondemand_topup_events (triggered_at);
