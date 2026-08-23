-- Venue provenance: where a restaurant row came from, and when.
--
-- Prompted by a real incident. On 2026-08-22 search-assistant's regex parsed
-- the phrase "louder the better" out of a sentence, treated it as a suburb,
-- ran a billed Places search and inserted 19 venues against a place that does
-- not exist (ondemand_topup_events, area_query 'area:louder the better',
-- result_count_before 0, places_found 19).
--
-- The remediation plan originally said to delete those 19 rows. That was
-- dropped as unsafe, for two reasons:
--
--   1. restaurants had no insertion timestamp, so the rows cannot be
--      identified. There is no way to tell them apart from any other venue.
--   2. Google fuzzy-matches. The 19 places it returned are probably real
--      venues somewhere; they were filed under a nonsense area, not invented.
--      Deleting on suspicion would destroy good data to tidy up a bad label.
--
-- So the existing rows stay, and this migration makes the *next* such incident
-- traceable instead. Backfilling is deliberately not attempted: a fabricated
-- first_seen_at would be worse than a null one.

alter table public.restaurants
  add column if not exists first_seen_at timestamptz;

alter table public.restaurants
  add column if not exists discovered_via text;

comment on column public.restaurants.first_seen_at is
  'When this row was first inserted. Null for every row predating 2026-08-23 — not backfilled, because the insertion time is genuinely unknown.';

comment on column public.restaurants.discovered_via is
  'How this venue was found: the seed pipeline, a suburb sweep, a GPS nearby check, or a named-venue lookup. Null for rows predating 2026-08-23.';

create index if not exists restaurants_first_seen_at_idx
  on public.restaurants (first_seen_at desc)
  where first_seen_at is not null;

-- Populate on insert only, so a later score update never rewrites the origin.
create or replace function public.set_restaurant_first_seen()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.first_seen_at is null then
    new.first_seen_at := now();
  end if;
  return new;
end;
$$;

create trigger restaurants_set_first_seen
  before insert on public.restaurants
  for each row
  execute function public.set_restaurant_first_seen();

-- Trigger-only implementation detail: no browser role needs to call this
-- through PostgREST. Revoked at creation rather than waiting for the security
-- advisor, per PR #43.
revoke all on function public.set_restaurant_first_seen() from public, anon, authenticated;
