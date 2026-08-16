-- Requires a real account to submit a mic reading. Decided with Caelan on
-- 2026-08-15: mic readings need user identity (real accounts, not just an
-- anonymous device ID), but browsing the ranked list stays open to anyone —
-- see stage 3 README "Account-gated mic readings".
--
-- Supabase Auth's built-in `auth.users` table backs this; no separate users
-- table is needed. Email/password is enabled by default.

-- user_id was nullable in 0001_init.sql (identity was undecided at the
-- time). Now required, and auto-filled from the requester's JWT so a
-- client can't submit a reading under someone else's identity.
alter table mic_readings
  alter column user_id set default auth.uid(),
  alter column user_id set not null;

alter table mic_readings
  add constraint mic_readings_user_id_fkey
  foreign key (user_id) references auth.users (id) on delete cascade;

-- Replace the old "anyone can insert" policy: only signed-in users
-- (the `authenticated` role) can submit, and only under their own identity.
drop policy "Anyone can submit a mic reading" on mic_readings;

create policy "Authenticated users can submit their own mic reading"
  on mic_readings for insert
  to authenticated
  with check (auth.uid() = user_id);

-- Required for correctness, not just a nice-to-have: PostgREST's default
-- insert response (`Prefer: return=representation`, which most client
-- libraries use unless told otherwise) does an implicit SELECT of the row
-- it just wrote. Without a SELECT policy, that SELECT sees nothing, and
-- PostgREST reports the whole insert as an RLS violation — even though the
-- INSERT + WITH CHECK itself was fine. Found by testing an actual signed-up
-- user through the real REST API, not just eyeballing the policy. Scoped to
-- each user's own rows, not all rows, matching 0001_init.sql's original
-- intent: individual reading history stays private.
create policy "Users can read their own mic readings"
  on mic_readings for select
  to authenticated
  using (auth.uid() = user_id);
