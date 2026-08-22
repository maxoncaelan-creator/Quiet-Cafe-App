-- Reserve an Assistant request's worst-case token cost before calling the
-- provider.  The former read -> Anthropic call -> upsert sequence allowed
-- simultaneous requests for one account to all observe the same balance.
--
-- The caller supplies a bounded estimate based on its sanitised prompt. The
-- reservation is settled to actual provider usage when the request completes,
-- or released (actual = 0) if it fails before a provider response.

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
begin
  if p_user_id is null or p_reserved_tokens is null or p_reserved_tokens < 1 or p_reserved_tokens > v_token_limit then
    raise exception 'A valid user and token reservation are required';
  end if;

  perform pg_advisory_xact_lock(hashtext('search_assistant_budget:' || p_user_id::text));

  select usage.window_start, usage.tokens_used
    into v_window_start, v_tokens_used
    from public.search_assistant_usage as usage
   where usage.user_id = p_user_id;

  if not found or now() - v_window_start >= v_window_ms then
    v_window_start := now();
    v_tokens_used := 0;
  end if;
  v_reset_at := v_window_start + v_window_ms;

  if v_tokens_used + p_reserved_tokens > v_token_limit then
    return query select 'rate_limited'::text, v_window_start, 0, v_reset_at;
    return;
  end if;

  insert into public.search_assistant_usage as usage (user_id, window_start, tokens_used)
  values (p_user_id, v_window_start, v_tokens_used + p_reserved_tokens)
  on conflict (user_id) do update
    set window_start = excluded.window_start,
        tokens_used = excluded.tokens_used;

  return query select 'granted'::text, v_window_start, p_reserved_tokens, v_reset_at;
end;
$$;

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
begin
  if p_user_id is null or p_window_start is null or p_reserved_tokens < 0 or p_actual_tokens < 0 then
    raise exception 'Invalid Assistant budget settlement';
  end if;

  perform pg_advisory_xact_lock(hashtext('search_assistant_budget:' || p_user_id::text));

  update public.search_assistant_usage as usage
     set tokens_used = greatest(0, usage.tokens_used - p_reserved_tokens + p_actual_tokens)
   where usage.user_id = p_user_id
     and usage.window_start = p_window_start;
end;
$$;

revoke all on function public.claim_search_assistant_budget(uuid, integer) from public, anon, authenticated;
revoke all on function public.settle_search_assistant_budget(uuid, timestamptz, integer, integer) from public, anon, authenticated;
grant execute on function public.claim_search_assistant_budget(uuid, integer) to service_role;
grant execute on function public.settle_search_assistant_budget(uuid, timestamptz, integer, integer) to service_role;
