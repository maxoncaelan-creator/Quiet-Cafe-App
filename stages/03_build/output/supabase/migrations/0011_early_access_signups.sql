-- Early-access signups for the marketing site, added 2026-08-19. The site
-- (marketing-site/) is a static page with no backend of its own, so the
-- signup form posts straight to PostgREST with the public anon key. That
-- makes RLS the only thing standing between this table and the open
-- internet, so the policy below is deliberately narrow.
--
-- anon may INSERT and nothing else. No select policy exists on purpose:
-- without one, the anon key cannot read back a single address, so the
-- signup list can't be scraped by anyone who views source. Reading the list
-- is done from the Supabase dashboard or by a service-role connection, not
-- from the browser. Do not add a select policy here without rethinking that.
--
-- The unique index on lower(email) is load-bearing for the UI, not just
-- hygiene: the resulting 23505 is what lets signup.js tell "you're already
-- on the list" apart from a genuine failure. Addresses are lowercased by
-- the client too, but the index is what actually guarantees it.
create table if not exists early_access_signups (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  created_at timestamptz not null default now()
);

create unique index if not exists early_access_signups_email_key
  on early_access_signups (lower(email));

alter table early_access_signups enable row level security;

drop policy if exists "anon can request early access" on early_access_signups;
create policy "anon can request early access"
  on early_access_signups
  for insert
  to anon
  with check (
    -- Cheap sanity bound. Real validation is the client's job; this only
    -- stops the obviously junk rows an unauthenticated endpoint attracts.
    email is not null
    and length(email) between 3 and 320
    and position('@' in email) > 1
  );
