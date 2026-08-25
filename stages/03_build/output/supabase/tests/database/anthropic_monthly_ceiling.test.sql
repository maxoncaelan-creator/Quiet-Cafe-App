begin;

create extension if not exists pgtap with schema extensions;
select plan(11);

-- A ceiling that is only asserted is not a ceiling. These exercise the real
-- claim/settle functions against a deliberately tiny limit.

insert into auth.users (id, email)
values ('00000000-0000-0000-0000-0000000000a1', 'ceiling-a@example.test'),
       ('00000000-0000-0000-0000-0000000000a2', 'ceiling-b@example.test')
on conflict (id) do nothing;

select is(
  (select monthly_token_ceiling from public.anthropic_budget_config where id = true),
  5000000::bigint,
  'the settled monthly Anthropic ceiling is 5,000,000 tokens'
);

select is(
  (select count(*)::integer from public.anthropic_budget_config),
  1,
  'anthropic_budget_config holds exactly one ceiling row'
);

-- A ceiling anyone can raise is not a limit.
select ok(
  (select relrowsecurity from pg_class where oid = 'public.anthropic_budget_config'::regclass)
    and not exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = 'anthropic_budget_config'
    ),
  'anthropic_budget_config denies every browser role by default'
);

select ok(
  not has_function_privilege('anon', 'public.claim_search_assistant_budget(uuid, integer)', 'execute')
    and not has_function_privilege('authenticated', 'public.claim_search_assistant_budget(uuid, integer)', 'execute'),
  'no browser role can claim Assistant budget'
);

select ok(
  not has_function_privilege('anon', 'public.settle_search_assistant_budget(uuid, timestamptz, integer, integer)', 'execute')
    and not has_function_privilege('authenticated', 'public.settle_search_assistant_budget(uuid, timestamptz, integer, integer)', 'execute'),
  'no browser role can settle Assistant budget'
);

update public.anthropic_budget_config set monthly_token_ceiling = 5000 where id = true;

select is(
  (select outcome from public.claim_search_assistant_budget('00000000-0000-0000-0000-0000000000a1', 3000)),
  'granted',
  'a claim below the monthly ceiling is granted'
);

select is(
  (select tokens_used from public.anthropic_monthly_usage
    where month_start = date_trunc('month', now() at time zone 'utc') at time zone 'utc'),
  3000::bigint,
  'the reservation is charged to the month immediately'
);

-- A *different* account, so this can only be the global ceiling stopping it and
-- not the per-account window.
select is(
  (select outcome from public.claim_search_assistant_budget('00000000-0000-0000-0000-0000000000a2', 3000)),
  'global_ceiling_reached',
  'a second account is stopped by the global ceiling, not its own window'
);

-- The rejected claim must not have been charged: both limits are evaluated
-- before either is written.
select is(
  (select tokens_used from public.anthropic_monthly_usage
    where month_start = date_trunc('month', now() at time zone 'utc') at time zone 'utc'),
  3000::bigint,
  'a rejected claim charges the month nothing'
);

select lives_ok(
  $$ select public.settle_search_assistant_budget(
       '00000000-0000-0000-0000-0000000000a1',
       (select window_start from public.search_assistant_usage
         where user_id = '00000000-0000-0000-0000-0000000000a1'),
       3000, 400) $$,
  'settling a claim succeeds'
);

select is(
  (select tokens_used from public.anthropic_monthly_usage
    where month_start = date_trunc('month', now() at time zone 'utc') at time zone 'utc'),
  400::bigint,
  'settling replaces the reservation with actual usage in the monthly ledger'
);

select * from finish();
rollback;
