-- Per-account rate limiting on the Search Assistant, decided with Caelan
-- 2026-08-18: 10,000 tokens per account per fixed 5-hour window (not a
-- sliding window — see the search-assistant Edge Function, which is the
-- only writer here and where the actual limit/reset logic lives). This
-- table is pure accounting; only the Edge Function's service-role client
-- ever writes to it. Users can read their own row so the app can show
-- current rate-limit status without a round trip through the assistant
-- itself (and so this session's testing could simulate "already at the
-- limit" by writing a row directly, without spending real tokens).
create table search_assistant_usage (
  user_id uuid primary key references auth.users (id) on delete cascade,
  window_start timestamptz not null default now(),
  tokens_used integer not null default 0
);

alter table search_assistant_usage enable row level security;

-- No insert/update/delete policy for `authenticated` — deliberate. Writes
-- only ever happen via the Edge Function's service-role client, which
-- bypasses RLS entirely; a user should never be able to reset their own
-- usage by writing to this table directly.
create policy "Users can read their own search assistant usage"
  on search_assistant_usage for select
  to authenticated
  using (auth.uid() = user_id);
