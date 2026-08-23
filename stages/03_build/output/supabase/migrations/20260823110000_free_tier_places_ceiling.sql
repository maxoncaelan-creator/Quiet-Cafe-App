-- Sets the monthly Google Places ceiling to the free-tier allowance.
--
-- Caelan's decision, 2026-08-23: stay inside Google's free tier until user
-- numbers justify paying for a higher ceiling. Reviewed at 50, 100, 300, 500,
-- 1000, 5000 active users, and every 10,000 thereafter.
--
-- Why 1,000. places-search requests `places.reviews`, which Google classifies
-- as Text Search **Enterprise + Atmosphere** — roughly 1,000 free requests per
-- month, then about $40 per 1,000. See PLACES_COST_PROPOSAL.md. So 1,000 is
-- the largest ceiling that stays free, and the previously recorded 8,000 would
-- have been roughly $280/month, against a stated budget of $10.
--
-- Why this is an UPDATE in a new migration rather than an edit to
-- 20260823091000_places_request_budget.sql. That migration had already been
-- applied to production when its literal was changed from 300 to 8,000 in
-- PR #46. Applied migrations do not re-run, and its insert carries
-- `on conflict (id) do nothing`, so that edit never reached the database:
-- production still held 300 while the repository claimed 8,000. Editing the
-- file again would be inert for exactly the same reason. An unconditional
-- UPDATE converges both — a fresh database (CI) that inserted 8,000 and the
-- production row that holds 300 both end at 1,000.
--
-- KNOWN LIMITATION, deliberately recorded rather than fixed here: this ledger
-- only governs Google traffic that flows through the places-search Edge
-- Function. `data-pipeline/src/places.js` calls Google directly and is not
-- counted. A pipeline run therefore consumes the same free allowance without
-- the ledger seeing it, and a full seed run is far larger than 1,000 requests.
-- Treat the ceiling as governing the *app's* automated spend, not total
-- project spend, until the pipeline is brought under the same ledger.

update public.places_budget_config
set monthly_request_ceiling = 1000,
    updated_at = now(),
    note = 'Free-tier ceiling confirmed 2026-08-23: 1,000 Text Search Enterprise + Atmosphere requests/month is Google''s free allowance. Raise only when active-user milestones justify paid calls. Does not cover data-pipeline traffic.'
where id = true;
