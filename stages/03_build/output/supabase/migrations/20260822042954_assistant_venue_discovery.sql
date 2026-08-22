-- Search Assistant venue discovery. These rows are private working state for
-- the authenticated Edge Function; they must never become a client-readable
-- chat or location history.
alter table public.restaurants
  add column if not exists source text not null default 'google',
  add column if not exists community_submitted_at timestamptz,
  add column if not exists community_submitted_by uuid references auth.users(id);

alter table public.restaurants
  drop constraint if exists restaurants_source_check,
  add constraint restaurants_source_check check (source in ('google', 'community'));

create index if not exists restaurants_community_name_suburb_idx
  on public.restaurants (lower(name), lower(coalesce(suburb, '')))
  where source = 'community';

create table public.assistant_venue_drafts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  state text not null check (state in ('confirm_google_match', 'ask_address', 'confirm_manual')),
  requested_name text,
  requested_suburb text,
  candidate jsonb,
  venue_name text,
  suburb text,
  address text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.assistant_venue_drafts enable row level security;
revoke all on public.assistant_venue_drafts from anon, authenticated;
grant all on public.assistant_venue_drafts to service_role;
