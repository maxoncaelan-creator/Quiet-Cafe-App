-- Backs the Search Assistant screen's "Are you at X?" GPS venue guess —
-- 2026-08-20. The feature was first built 2026-08-18 (stale, unmerged
-- feature/loudness-votes-and-venue-guess branch) fetching the *entire*
-- restaurants table client-side and computing distance in Dart. That was
-- fine at the table's size back then; at today's size (5,000+ rows, each
-- carrying review text and every signal column) downloading all of it just
-- to check "is anything within 100m" is real wasted bandwidth on a mobile
-- connection. This does the same nearest-neighbour check server-side
-- instead, returning only what the app actually needs (id, name, distance)
-- — the app already has a separate loader (_RestaurantByIdLoader in
-- router.dart) for fetching a restaurant's full detail by place_id, so
-- this function was kept deliberately narrow rather than duplicating that.
create or replace function find_nearest_restaurant(
  user_lat double precision,
  user_lng double precision,
  max_distance_meters double precision default 100
)
returns table (
  place_id text,
  name text,
  distance_meters double precision
)
language sql
stable
as $$
  select place_id, name, distance_meters
  from (
    select
      place_id,
      name,
      -- Haversine, meters (Earth radius ~6,371,000m).
      2 * 6371000 * asin(sqrt(
        sin(radians(lat - user_lat) / 2) ^ 2 +
        cos(radians(user_lat)) * cos(radians(lat)) *
        sin(radians(lng - user_lng) / 2) ^ 2
      )) as distance_meters
    from restaurants
    where lat is not null and lng is not null
      -- Cheap bounding-box pre-filter before the trig functions run on
      -- every row — 1 degree latitude is ~111km, so this box is generous
      -- (longitude degrees actually shrink at higher latitude, so it errs
      -- wider there, which is harmless; it's only a pre-filter, the real
      -- cutoff is the distance_meters <= max_distance_meters check below).
      and lat between user_lat - (max_distance_meters / 111000.0) and user_lat + (max_distance_meters / 111000.0)
      and lng between user_lng - (max_distance_meters / 111000.0) and user_lng + (max_distance_meters / 111000.0)
  ) nearby
  where distance_meters <= max_distance_meters
  order by distance_meters asc
  limit 1
$$;

-- Plain SQL function, no SECURITY DEFINER — runs as the calling role, so
-- this only ever sees what that role's RLS already permits. restaurants is
-- publicly readable (0001_init.sql), so anon/authenticated seeing this
-- function's output is no different from them reading the table directly.
grant execute on function find_nearest_restaurant(double precision, double precision, double precision) to anon, authenticated;
