-- Favoriting, added from the UI redesign (2026-08-17). No favorites table
-- existed before this — the star toggle on the List/Favourites/Detail
-- screens had nothing to write to.
--
-- Requires a real account, same gate as mic_readings (0003): a favorite is
-- a per-user list, so it can't mean anything for an anonymous session.
-- Browsing and the ranked list stay open to everyone, same as before —
-- only the star toggle itself needs sign-in, matching how "Take a reading"
-- prompts sign-in at the point of need rather than gating the whole app.

create table if not exists favorites (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  place_id text not null references restaurants (place_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, place_id)
);

create index if not exists favorites_user_id_idx on favorites (user_id);

-- RLS: a user can only ever see, add, or remove their own favorites — same
-- privacy shape as mic_readings' own reading history.
alter table favorites enable row level security;

create policy "Users can view their own favorites"
  on favorites for select
  to authenticated
  using (auth.uid() = user_id);

create policy "Users can add their own favorites"
  on favorites for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "Users can remove their own favorites"
  on favorites for delete
  to authenticated
  using (auth.uid() = user_id);
