# Multi-model execution plan — coverage rebuild

Created 2026-08-23. Supersedes nothing; this is the execution contract for the
work described in the coverage remediation plan. The build log remains the
project's history. **This file is the running state of the rebuild** — each step
updates its own status block here when it finishes.

## Who does what

| Step | Owner | Scope | Status |
|---|---|---|---|
| 0 | Claude Opus 5 (Claude Code) | Instrumentation, extensions, budget guard, dependencies | **Done — PR open, awaiting review** |
| 1 | ChatGPT Terra 5.6 | Backend automation: gazetteer, sweep freshness, cron, queue | Not started |
| 2 | Claude Opus 5 (Claude Code) | Full-stack assistant rewire | Not started |
| 3 | Anthropic Sonnet 5 | Frontend: Riverpod migration, score refresh propagation | Not started |
| 4 | Claude Opus 5 (Claude Code) | Beta hardening, PostHog, launch work | Not started |

## The review gate — every step, without exception

No step begins until the previous step has cleared **both** gates.

```
model finishes step
  → opens PR, does NOT merge
  → Claude Opus 5 reviews the work and writes findings here
  → Caelan reviews and merges (or sends it back)
  → Claude Opus 5 updates this file + the build log
  → only then does the next model begin
```

Three rules that make the gate real:

1. **Stop at the PR.** No model merges its own work. No model pushes to `main`.
2. **State what your checks do not prove.** A green CI run is not a device test,
   and a successful deploy is not a verified feature.
3. **If a step's findings invalidate a later step's instructions, say so and
   stop.** Do not silently adapt the plan. The plan is a proposal, not a
   contract with reality — reality wins, but Caelan decides.

## Budget — the hard constraint

**$10 USD per month of Google Places spend.** To be reviewed as active users
reach 50, 100, 300, 500, 1000, 5000, and every 10,000 users thereafter.

Three things every model must understand before touching billed code:

- **The current caps do not enforce $10.** Today's limits are 20 shared paid
  refreshes per UTC day and 5 per account per day. One "refresh" is up to eight
  billed Places requests (two base pages plus three follow-up categories). At the
  cap that is roughly 3,000–4,800 requests per month — an order of magnitude over
  a $10 ceiling. The project is currently under budget only because usage is tiny
  (ten top-up events in its entire history).
- **The field mask is on the most expensive tier.** `places-search` requests
  `places.reviews` alongside `rating`, `priceLevel` and `userRatingCount`.
  Reviews are an Enterprise/Atmosphere-class field, so these are not cheap
  Essentials-tier calls. Any cost model built on basic-tier pricing will be wrong.
- **Therefore the budget must be denominated in requests, enforced server-side,
  and checked before the call, not after.** A per-user cap cannot enforce a global
  spend ceiling.

**Before Step 1 begins, Caelan must confirm the real number** by reading actual
Google Cloud billing for this project. Google replaced the flat $200 monthly
credit in March 2025 with per-SKU free allowances, so the true marginal cost of a
sweep can only be read from the billing console, not estimated from docs.

### Consequence Caelan should weigh

At $10/month, a one-off backfill of the 77 frozen suburbs (~600 requests) plausibly
consumes one to two months of the entire budget. Coverage will improve slowly.
If faster coverage matters more than the ceiling, the options are a temporary
higher budget for a single backfill, or a cheaper discovery pass — see Step 1.

## Non-negotiables for every model

- **Never push to `main`.** Feature branch and PR, always. Caelan merges.
- **Never commit credentials.** `data-pipeline/.env` is real and gitignored.
- **Never delete production rows without provenance.** See Step 0's finding on
  the `louder the better` venues.
- **After any backend-changing merge, follow
  [`BACKEND_RELEASE_RUNBOOK.md`](supabase/BACKEND_RELEASE_RUNBOOK.md).** Merging is
  not deploying. Verify the production migration list and function versions
  directly; this project has already drifted silently once with the GitHub
  integration enabled.
- **One SQL statement per call when each result matters.**
- **A check only counts if it could have disproved the claim.**

---

# Step 0 — Instrumentation and guardrails

**Owner: Claude Opus 5. Status: done, PR open, not merged.**

Nothing here changes user-visible behaviour. The point is to be able to see what
is happening, and to make Step 1 safe to build.

### 0.1 Sentry (Flutter)

Add `sentry_flutter`, initialise it behind a `--dart-define` DSN so the package is
inert when no DSN is supplied. This keeps the standalone no-Supabase build and CI
unaffected.

**Caelan must create the Sentry account and supply the DSN** — Claude cannot
create accounts or handle credentials. Instructions are in
[`SENTRY_SETUP.md`](SENTRY_SETUP.md).

### 0.2 Riverpod dependency only

Add `flutter_riverpod` and wrap the app in a `ProviderScope`. **No migration.**
Converting screens is Step 3 and belongs to Sonnet 5. Adding the dependency now
means Step 3 starts without a dependency-resolution detour.

### 0.3 Postgres extensions

One migration enabling `pg_cron`, `pg_net`, `pgmq`, `pg_trgm` and `unaccent`.
All five are available on this project and none were installed. Enabling them
changes no behaviour on its own; it makes Step 1 buildable.

### 0.4 Monthly Places budget ledger

A `places_request_budget` table plus a reserve-and-settle function, denominated in
**requests**, with the month's ceiling stored as a row Caelan can change without a
deploy. Step 1 wires the collector to it.

This lands in Step 0 rather than Step 1 deliberately: the current system has no
global spend ceiling at all, and Step 1's whole purpose is to increase Google
traffic. The guard must exist before the throttle is opened.

### 0.5 Venue provenance

Add `first_seen_at` and `discovered_via` to `restaurants`, populated going
forward.

**Finding that changed this task:** the plan originally said "delete the 19
phantom venues" from the `area:louder the better` sweep. That is **not safely
possible and has been dropped.** `restaurants` has no insertion timestamp, so
those rows cannot be identified. They may also be perfectly real venues that
Google fuzzy-matched to a nonsense query — deleting on suspicion would destroy
good data. Provenance columns make the *next* such incident traceable; the
existing rows stay.

### 0.6 What Step 0 deliberately does NOT do

**`MIN_COVERAGE` is not changed.** The stopgap in the original plan is dropped,
because unfreezing 77 dense suburbs before the budget ledger is enforced is
exactly how a $10 ceiling gets blown. The threshold is Step 1's to replace with
sweep-freshness logic, and Terra should delete the constant rather than tune it.

### Step 0 exit criteria

- [x] `flutter analyze` clean, `flutter test` 21/21 passing
- [ ] Migration applies cleanly in hosted Supabase CI — *pending CI*
- [x] Sentry inert with no DSN; no CI or standalone-build regression
- [x] `SENTRY_SETUP.md` written for a non-developer
- [x] PR opened, **not merged**
- [x] Findings written into this file

---

# Step 1 — Backend automation

**Owner: ChatGPT Terra 5.6. Begins only after Step 0 clears both gates.**

Backend only. No Flutter changes. This must ship without an app release.

### 1.1 Suburb gazetteer from the official NSW list

Build a `suburbs` table from the **official NSW gazetted suburb list** — the
authoritative source, not the 568 distinct values already in `restaurants`, which
inherit whatever Google returned.

**Refresh cadence: at most once per calendar month.** The gazetteer changes when
suburbs are created or subdivided, and that must be reflected, but it is not
volatile enough to justify more. Record `last_gazette_sync_at` and refuse to
re-sync inside 30 days.

Handle the case that matters: a suburb that is **subdivided** must not orphan the
venues already filed under its old name. Decide and document whether old names
become aliases or redirects — do not silently drop them.

### 1.2 Fuzzy resolution replacing the regex

Use `pg_trgm` and `unaccent` so "crows nest", "Crows Nest" and "crowsnest" all
resolve to one suburb id, and — critically — so an unresolvable string resolves to
**nothing**. This is the fix for the `louder the better` class of bug: a string
that is not a real suburb must never authorise a billed search.

Retire `extractAreaQuery()`'s regex and stopword list.

### 1.3 Freshness replaces sufficiency

Delete `MIN_COVERAGE` and the `currentResultCount >= MIN_COVERAGE` early return.
Replace with per-suburb `last_swept_at` and whether the last sweep exhausted its
pages. Eligibility becomes staleness, never count. **A dense suburb must be
sweepable.** This is the actual bug Caelan reported.

### 1.4 Background sweep

`pg_cron` schedules, `pg_net` invokes, `pgmq` queues with retries and priority
ordering. Order the queue by **recent demand first** — record every resolved
assistant query so the suburbs people ask about become the best covered. This
inverts the current behaviour, where popularity causes freezing.

### 1.5 Budget enforcement

Wire the collector to Step 0's ledger. Reserve before any billed call, settle
after. When the month's ceiling is reached the sweep stops cleanly and records
that it stopped — it must not fail silently or partially apply.

**Worth investigating and proposing, not assuming:** splitting discovery from
enrichment. A cheap field mask to discover place IDs, with the expensive
`reviews` fetch only for venues not already enriched, could cut sweep cost
substantially. Bring Caelan a costed proposal rather than implementing it
unasked — it changes the scoring pipeline's inputs.

### Step 1 exit criteria

- [ ] Gazetteer loaded from the official source, with sync-cadence guard
- [ ] Unresolvable strings provably cannot trigger a billed call
- [ ] A dense suburb (use Crows Nest, 15 venues) provably sweeps
- [ ] Ceiling provably stops the sweep — demonstrate it, don't assert it
- [ ] pgTAP coverage for resolution, freshness and budget
- [ ] Hosted Supabase CI green
- [ ] PR opened, **not merged**

---

# Step 2 — Assistant rewire

**Owner: Claude Opus 5. Begins only after Step 1 clears both gates.**

Full stack. App and backend must ship in the right order: **the app must
understand the new response states before the backend starts sending them**, or
older installs break.

- New assistant response states: answered, `stale_refresh_queued`,
  `not_found_searching`.
- The assistant stops making billed calls for area queries; it reads and enqueues.
- **One narrow exception is retained, per Caelan's decision:** a specific named
  venue may still trigger a single bounded Places lookup. This is the case where
  "check back later" is most annoying, and `refreshVenueCoverage` already exists.
  Everything else goes to the queue.
- Honest empty states in the UI — a missing venue must be distinguishable from a
  venue that does not exist.

---

# Step 3 — Frontend state

**Owner: Anthropic Sonnet 5. Begins only after Step 2 clears both gates.**

Flutter only.

- Incremental Riverpod migration. **Not a rewrite.** Order: auth and beta status
  first, then favourites, then venue scores.
- Close the score-refresh gap: the database trigger already recomputes on a vote
  or mic reading, but nothing propagates to a mounted detail screen. This is why
  "submit a vote, does the noise bar update?" is still unanswered.
- 16 screens and 11 services currently share state through `setState` alone.
  Migrating all of them is out of scope; migrating what genuinely crosses screens
  is the goal.

---

# Step 4 — Hardening and launch

**Owner: Claude Opus 5. Begins only after Step 3 clears both gates.**

- **PostHog wiring** — sequenced here deliberately, after Sentry. Crash data
  first, behavioural analytics second. The `quiet-cafe-posthog` workspace owns
  its configuration.
- Device validation batch: speech recognition (issue #41), GPS venue guess, mic
  calibration, live 429, rate limits, web responsive pass.
- Password hardening: send `currentPassword`, then enable the toggle — **but the
  recovery-flow question must be settled first** on a throwaway account. Supabase
  docs state no exemption for recovery sessions, and the reset screen never asks
  for the old password by design.
- Remaining launch list: store copy still says "Sydney", Stripe, policies, deep
  links, branch protection.

---

## Findings log

Each step appends here. Newest last.

### Step 0 — Claude Opus 5, 2026-08-23

**Done, PR open, not merged.** `flutter analyze --no-pub` clean and
`flutter test --no-pub` 21/21 passing after the change.

Three findings changed the work as planned. Terra should read these before
starting step 1.

**1. The "delete the 19 phantom venues" task was dropped as unsafe.**
`restaurants` had no insertion timestamp, so those rows cannot be identified at
all. And Google fuzzy-matches — the 19 places returned for "louder the better"
are probably real venues filed under a nonsense label, not fabrications.
Deleting on suspicion would have destroyed good data to tidy up a bad label.
Provenance columns were added instead so the next incident is traceable;
existing rows are untouched and deliberately not backfilled.

**2. The existing rate limits do not enforce a $10/month ceiling — they are out
by roughly an order of magnitude.** The caps are denominated in *refreshes*
(20 shared/day, 5 per account/day) but one refresh is up to eight billed Places
requests. At the cap that is ~3,000-4,800 requests/month. The project is under
budget today only because usage is tiny. This is why the budget ledger moved
into step 0: step 1's entire purpose is to increase Google traffic, so the
guard must pre-date the throttle.

**3. The field mask is on an expensive tier.** `places-search` requests
`places.reviews` alongside `rating`, `priceLevel` and `userRatingCount`.
Reviews are an Enterprise/Atmosphere-class field, so these are not cheap
Essentials-tier calls. **The 300/month ceiling in
`places_budget_config` is a placeholder, not a costed figure** — Caelan needs to
read real Google Cloud billing before step 1 opens the throttle. Terra should
treat splitting cheap discovery from expensive review-enrichment as a costed
proposal to bring back, not an assumption to build on.

**Also deliberately not done:** `MIN_COVERAGE` was left at 15. The original plan
had a step 0 stopgap; unfreezing 77 dense suburbs before the ledger is *enforced*
is precisely how a $10 ceiling gets blown. Terra should delete the constant as
part of the freshness redesign rather than tune it.

**Not wired yet:** nothing calls the budget functions. Wiring the collector to
`claim_places_request_budget` / `settle_places_request_budget` is a step 1 task,
and is on step 1's exit criteria as a demonstrated stop, not an asserted one.

**Still needed from Caelan:** the Sentry DSN (see
[`SENTRY_SETUP.md`](SENTRY_SETUP.md)) and a confirmed request ceiling from real
billing. Neither blocks the PR; both block Sentry actually reporting and step 1
respectively.

**Build log:** deliberately not edited in this step, because
[PR #44](https://github.com/maxoncaelan-creator/Quiet-Cafe-App/pull/44) has
uncommitted changes to the same file and a conflict would be pointless. Fold
step 0 into the build log after #44 merges.
