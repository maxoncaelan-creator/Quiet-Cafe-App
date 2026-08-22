-- The functions below exist only as trigger implementation details. Trigger
-- execution does not require an API grant, so make each one uncallable through
-- PostgREST by every browser-facing role. This closes the advisory reported
-- after server-owned contribution scoring was deployed.

revoke all on function public.recompute_restaurant_score_after_contribution()
  from public, anon, authenticated;
revoke all on function public.set_current_loudness_from_mic()
  from public, anon, authenticated;
revoke all on function public.set_current_loudness_from_vote()
  from public, anon, authenticated;

-- This is intentionally a SECURITY INVOKER function, but it still needs a
-- fixed lookup path so its table references cannot be influenced by a caller.
alter function public.find_nearest_restaurant(double precision, double precision, double precision)
  set search_path = public, pg_temp;
