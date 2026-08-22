begin;

create extension if not exists pgtap with schema extensions;
select plan(4);

select ok(
  to_regclass('public.assistant_venue_drafts') is not null,
  'assistant venue drafts are stored in a dedicated table'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.assistant_venue_drafts'::regclass),
  'assistant venue drafts have row-level security enabled'
);

select ok(
  not has_table_privilege('anon', 'public.assistant_venue_drafts', 'select')
    and not has_table_privilege('authenticated', 'public.assistant_venue_drafts', 'select'),
  'browser roles cannot read a user''s assistant draft'
);

insert into public.restaurants (place_id, name)
values ('assistant-discovery-default-source', 'Assistant Discovery Default Source');

select is(
  (select source from public.restaurants where place_id = 'assistant-discovery-default-source'),
  'google',
  'existing ingestion paths retain the Google source by default'
);

select * from finish();
rollback;
