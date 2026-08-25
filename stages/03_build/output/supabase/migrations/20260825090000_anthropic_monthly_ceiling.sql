-- A global ceiling on Anthropic token spend, above the existing per-account
-- limit. See ANTHROPIC_BUDGET_PROPOSAL.md.
--
-- Search Assistant spend was capped per account (10,000 tokens per rolling
-- 5-hour window) but had no ceiling across accounts. Sign-up is open, so total
-- Anthropic spend was bounded only by how many accounts existed. It was the one
-- genuinely unbounded cost in the project; Google Places has been capped at
-- 1,000 requests per UTC month since 20260823110000.
--
-- Deliberately mirrors places_budget_config: proven in production, already
-- understood, already has a test precedent.

create table public.anthropic_budget_config (
  -- Single-row table; the check constraint makes a second row impossible.
  id boolean primary key default true check (id),
  monthly_token_ceiling bigint not null check (monthly_token_ceiling >= 0),
  updated_at timestamptz not null default now(),
  note text
);

comment on table public.anthropic_budget_config is
  'Single-row ceiling for Anthropic tokens per UTC month, above the per-account window limit. Editable without a deploy.';

-- 5,000,000 tokens/month. Grounded in measured usage rather than guessed:
--
--   * Only two accounts have ever used the assistant, and the busiest single
--     5-hour window was 6,864 tokens (measured 2026-08-25).
--   * estimatedAssistantTokens() reserves roughly 2,200 tokens per question, so
--     this ceiling is about 2,250 questions a month, ~75 a day across all users.
--     Comfortable for a closed beta while still bounding a runaway.
--   * Seven accounts each abusing the per-account cap could otherwise reach
--     ~10,000,000 tokens a month. This caps that at half, and an unlimited
--     number of new accounts at the same figure.
--
-- Caelan should confirm the dollar value in the Anthropic console and change
-- this row, not this migration — editing an applied migration does nothing,
-- which is exactly how production came to hold a Places ceiling of 300 while
-- the repository claimed 8,000.
insert into public.anthropic_budget_config (id, monthly_token_ceiling, note)
values (true, 5000000, 'Set 2026-08-25 from measured usage: ~2,250 assistant questions/month. Confirm the dollar value in the Anthropic console; change this row, never this migration.')
on conflict (id) do nothing;

create table public.anthropic_monthly_usage (
  month_start timestamptz primary key,
  tokens_used bigint not null default 0 check (tokens_used >= 0),
  updated_at timestamptz not null default now()
);

comment on table public.anthropic_monthly_usage is
  'Reserved-then-settled Anthropic token usage per UTC month. A reservation counts immediately so concurrent callers cannot both observe the same headroom.';

alter table public.anthropic_budget_config enable row level security;
alter table public.anthropic_monthly_usage enable row level security;
-- No policies: deny-all to every browser role, reachable only via the service
-- role. Same posture as places_budget_config and beta_codes.

-- Claim: now checks the global ceiling as well as the per-account window.
--
-- Signature is unchanged on purpose. CREATE OR REPLACE preserves grants only
-- when the signature matches, and this function is deliberately revoked from
-- every browser role — see the grants at the bottom of
-- 20260822153000_atomic_assistant_budget.sql.
--
-- Both limits are evaluated BEFORE either is written. Reserving globally and
-- then failing the per-account check would charge the month for a request that
-- never ran, and the same in reverse; there is no partial reservation here.
--
-- Lock order is global-then-per-user everywhere, so this cannot deadlock
-- against settle_search_assistant_budget.
create or replace function public.claim_search_assistant_budget(
  p_user_id uuid,
  p_reserved_tokens integer
)
returns table (
  outcome text,
  window_start timestamptz,
  reserved_tokens integer,
  reset_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_window_ms constant interval := interval '5 hours';
  v_token_limit constant integer := 10000;
  v_window_start timestamptz;
  v_tokens_used integer;
  v_reset_at timestamptz;
  v_month_start timestamptz;
  v_month_end timestamptz;
  v_month_used bigint;
  v_ceiling bigint;
begin
  if p_user_id is null or p_reserved_tokens is null or p_reserved_tokens < 1 or p_reserved_tokens > v_token_limit then
    raise exception 'A valid user and token reservation are required';
  end if;

  perform pg_advisory_xact_lock(hashtext('anthropic_monthly_budget'));
  perform pg_advisory_xact_lock(hashtext('search_assistant_budget:' || p_user_id::text));

  v_month_start := date_trunc('month', now() at time zone 'utc') at time zone 'utc';
  v_month_end := (date_trunc('month', now() at time zone 'utc') + interval '1 month') at time zone 'utc';

  select config.monthly_token_ceiling into v_ceiling
    from public.anthropic_budget_config as config where config.id = true;

  if v_ceiling is null then
    -- Fail closed. A ceiling that vanishes must not become "no ceiling".
    return query select 'global_ceiling_reached'::text, v_month_start, 0, v_month_end;
    return;
  end if;

  select coalesce(usage.tokens_used, 0) into v_month_used
    from public.anthropic_monthly_usage as usage
   where usage.month_start = v_month_start;
  v_month_used := coalesce(v_month_used, 0);

  -- Read the per-account window before writing anything, so neither limit can
  -- be charged for a request the other one rejects.
  select usage.window_start, usage.tokens_used
    into v_window_start, v_tokens_used
    from public.search_assistant_usage as usage
   where usage.user_id = p_user_id;

  if not found or now() - v_window_start >= v_window_ms then
    v_window_start := now();
    v_tokens_used := 0;
  end if;
  v_reset_at := v_window_start + v_window_ms;

  if v_month_used + p_reserved_tokens > v_ceiling then
    -- reset_at is the start of next month: there is no personal reset here, and
    -- the caller must be told something different from a per-account limit.
    return query select 'global_ceiling_reached'::text, v_month_start, 0, v_month_end;
    return;
  end if;

  if v_tokens_used + p_reserved_tokens > v_token_limit then
    return query select 'rate_limited'::text, v_window_start, 0, v_reset_at;
    return;
  end if;

  insert into public.anthropic_monthly_usage as usage (month_start, tokens_used)
  values (v_month_start, p_reserved_tokens)
  on conflict (month_start) do update
    set tokens_used = usage.tokens_used + excluded.tokens_used,
        updated_at = now();

  insert into public.search_assistant_usage as usage (user_id, window_start, tokens_used)
  values (p_user_id, v_window_start, v_tokens_used + p_reserved_tokens)
  on conflict (user_id) do update
    set window_start = excluded.window_start,
        tokens_used = excluded.tokens_used;

  return query select 'granted'::text, v_window_start, p_reserved_tokens, v_reset_at;
end;
$$;

-- Settle: replaces the reservation with actual usage in both ledgers.
--
-- Signature unchanged, for the same grant-preservation reason as above. The
-- month is derived from p_window_start rather than now(), so a request that
-- straddles midnight on the 1st settles against the month it reserved from.
create or replace function public.settle_search_assistant_budget(
  p_user_id uuid,
  p_window_start timestamptz,
  p_reserved_tokens integer,
  p_actual_tokens integer
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_month_start timestamptz;
begin
  if p_user_id is null or p_window_start is null or p_reserved_tokens < 0 or p_actual_tokens < 0 then
    raise exception 'Invalid Assistant budget settlement';
  end if;

  perform pg_advisory_xact_lock(hashtext('anthropic_monthly_budget'));
  perform pg_advisory_xact_lock(hashtext('search_assistant_budget:' || p_user_id::text));

  v_month_start := date_trunc('month', p_window_start at time zone 'utc') at time zone 'utc';

  update public.anthropic_monthly_usage as usage
     set tokens_used = greatest(0, usage.tokens_used - p_reserved_tokens + p_actual_tokens),
         updated_at = now()
   where usage.month_start = v_month_start;

  update public.search_assistant_usage as usage
     set tokens_used = greatest(0, usage.tokens_used - p_reserved_tokens + p_actual_tokens)
   where usage.user_id = p_user_id
     and usage.window_start = p_window_start;
end;
$$;

-- Re-assert the grants. CREATE OR REPLACE preserves them for an unchanged
-- signature, but stating them here means a future signature change cannot
-- silently make these PUBLIC-executable — the failure mode PR #43 fixed.
revoke all on function public.claim_search_assistant_budget(uuid, integer) from public, anon, authenticated;
revoke all on function public.settle_search_assistant_budget(uuid, timestamptz, integer, integer) from public, anon, authenticated;
grant execute on function public.claim_search_assistant_budget(uuid, integer) to service_role;
grant execute on function public.settle_search_assistant_budget(uuid, timestamptz, integer, integer) to service_role;
