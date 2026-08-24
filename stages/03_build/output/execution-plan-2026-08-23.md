# Multi-model execution plan — coverage rebuild

Created 2026-08-23. Supersedes nothing; this is the execution contract for the
work described in the coverage remediation plan. The build log remains the
project's history. **This file is the running state of the rebuild** — each step
updates its own status block here when it finishes.

## Who does what

| Step | Owner | Scope | Status |
|---|---|---|---|
| 0 | Claude Opus 5 (Claude Code) | Instrumentation, extensions, budget guard, dependencies | **Done — merged PRs #45 and #46** |
| 1 | ChatGPT Terra 5.6 | Backend automation: gazetteer, sweep freshness, cron, queue | **Live and verified 2026-08-24 — Crows Nest 15 → 39 venues** |
| 2 | Claude Opus 5 (Claude Code) | Full-stack assistant rewire | **2a in progress; 2b blocked on scheduled sweeps being enabled** |
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

**Confirmed 2026-08-23: the operational ceiling is 8,000 Google Places calls per
UTC month.** The Step 0 migration seeds that value in the server-enforced ledger.
Google replaced the flat $200 monthly credit in March 2025 with per-SKU free
allowances, so reassess the request-to-dollar relationship from the billing
console whenever the ceiling is changed.

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

**Owner: Claude Opus 5. Re-scoped 2026-08-23 against what Step 1 actually
shipped, rather than what this plan assumed before it existed.**

### What Step 1 already did, so Step 2 does not

Terra replaced the assistant's *resolution* layer: `extractAreaQuery()`'s regex
and stopword list are gone, and `findRequestedArea()` now calls
`resolve_nsw_suburb_in_text`. The `louder the better` class of bug is already
fixed at the source, and `search-assistant` v14 is live with it.

### What Step 1 did NOT do, and Step 2 must

Reading the merged code rather than the plan:

- **The assistant still makes the billed call inline.** `refreshThinCoverage()`
  still `fetch`es `ondemand-topup` synchronously inside the user's request. The
  queue, worker and cron all exist and nothing in the assistant touches them.
- **Nothing durably queues a sweep from the assistant.** Demand *is* already
  recorded — `ondemand-topup` calls `record_nsw_suburb_coverage_demand`, and
  `queue_nsw_suburb_sweep` records it internally too (an earlier draft of this
  section claimed demand had no callers at all; that was wrong). What is missing
  is the durable queue entry: an inline refresh that is rate-limited or
  ineligible simply evaporates, leaving nothing for the scheduled worker to pick
  up later.
- **The app contract is unchanged.** The Function returns `{ reply }` and
  `askSearchAssistant` returns a bare `String`. A missing venue is still
  indistinguishable from a venue that does not exist.

### Step 2a — this PR

- Thread the resolved `suburb_id` through instead of discarding it for the name.
- Call `queue_nsw_suburb_sweep` on every resolved area question. Free, no
  Google, and it records demand as a side effect — calling
  `record_nsw_suburb_coverage_demand` separately would double-count the same
  question in the priority ordering. Source must be `'assistant'`; the database
  raises `Unknown suburb demand source` for anything outside its four-value
  allowlist.
- Add an **additive** `coverage` object to the response —
  `refresh_queued` / `refresh_pending` / `up_to_date`. `reply` is always still
  present, so this Function and the app can deploy in either order without
  breaking an in-flight build. Parsing is total: an unknown status yields null
  rather than throwing.
- Show it in the chat as a quiet line under the answer, held in a `note` field
  that is deliberately excluded from the history sent back to the model.
- Keep the named-venue narrow case exactly as is, per Caelan's decision.

### Step 2a deliberately KEEPS the inline refresh

Removing `refreshThinCoverage()` is the obvious reading of the original plan and
it would be wrong right now. `coverage_automation_config.enabled` is `false`, so
nothing drains the queue. Deleting the inline path today would mean coverage
could never grow at all — strictly worse than the bug we set out to fix.

### Step 2b — blocked on enabling scheduled sweeps

Remove the inline billed refresh, leaving the assistant a pure reader. **Do not
start this until `enabled = true` and a sweep has demonstrably run.** Until
then the queue is write-only.

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
Essentials-tier calls. **Caelan confirmed an 8,000-call-per-UTC-month operational
ceiling on 2026-08-23.** The ledger enforces that number, but Terra should still
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
[`SENTRY_SETUP.md`](SENTRY_SETUP.md)). It does not block the PR or Step 1; it
only blocks Sentry actually reporting.

**Build log:** deliberately not edited in this step, because
[PR #44](https://github.com/maxoncaelan-creator/Quiet-Cafe-App/pull/44) has
uncommitted changes to the same file and a conflict would be pointless. Fold
step 0 into the build log after #44 merges.

### Step 1 — ChatGPT Terra 5.6, reviewed by Claude Opus 5, 2026-08-23

**Reviewed, accepted, merged.** All seven exit criteria met, hosted CI green.

Verified rather than taken on trust: the gazetteer source is the official NSW
Spatial Services boundaries endpoint; the once-a-month sync cadence is enforced
by a `CHECK (gazetteer_sync_min_interval >= interval '30 days')` rather than by
convention; `resolve_nsw_suburb('louder the better')` is regression-tested to
resolve to nothing, bare and embedded in prose; and a dense Crows Nest at
fifteen venues is tested as sweepable when stale — the exact case that started
this work. 42 pgTAP tests.

**Three things the implementation did better than the brief.** Budget is
claimed per *request* rather than per sweep, so the ledger counts real billed
calls. `verifyPlacesDispatchBoundary()` fails closed when the Edge Function
deploys ahead of its migration. And `coverage_automation_config.enabled`
defaults to `false`, so merging started nothing.

**Security passed.** 20 new functions, all with `set search_path`, 17 explicitly
revoked. The four without are the step-0 budget functions being redefined with
byte-identical signatures, so `CREATE OR REPLACE` preserves their grants — no
repeat of #43. That invariant is unwritten though: if a future edit changes one
of those argument lists the revoke silently disappears and the function becomes
`PUBLIC`-executable. Worth a comment at those definitions.

**One real defect found, and it was not in the diff.** Production held a ceiling
of 300 while the repository claimed 8,000. PR #46 had edited migration
`20260823091000` *after* it was applied; applied migrations do not re-run and
its insert carries `on conflict do nothing`, so the change never reached the
database. Same class of repo-versus-production divergence as the earlier
migration-repair incident, and nothing would have caught it.

**Resolved before merge.** Caelan chose to stay inside the free tier until user
numbers justify paying. `20260823110000_free_tier_places_ceiling.sql` uses an
unconditional `update` so a fresh database and production both converge on
1,000 — the largest ceiling with zero expected marginal cost, given the
`places.reviews` field mask bills as Text Search Enterprise + Atmosphere.
`places_budget_ceiling.test.sql` now asserts the settled value, so the same
divergence fails a test rather than going unnoticed. Recorded in
`_config/decisions.md` under "Google Places spend".

**Known limitation, recorded not fixed:** the ledger only sees Google traffic
through the `places-search` Edge Function. `data-pipeline/src/places.js` calls
Google directly and is uncounted, and a full seed run far exceeds 1,000
requests. "Free" describes the app's automated sweeps, not total project spend.

**Not yet done:** the automation is merged but `enabled = false`. Turning it on
needs the worker URL and vault secret configured — see
`COVERAGE_AUTOMATION_SETUP.md`. Nothing has swept, and no live Google request
has been made through the new path.

### Step 1 — enabled and verified live, 2026-08-24

Scheduled sweeps are on. A real sweep ran: Crows Nest `completed`, 24 places
found, **15 → 39 venues**, 5 billed Places requests, 16 of 1,000 used this month.

Two things were changed before enabling, and both matter to anyone reading this
later. The default cron would have spent the entire monthly budget in about a
day, because it was written against the 8,000 ceiling rather than the free-tier
1,000 — it is now 4 sweeps/day. And `pg_net`'s 5-second timeout is shorter than a
sweep, so the cron records a timeout even on success; sweep state is the
monitoring surface, not `net._http_response`.

**Step 2b is now unblocked.** Scheduled sweeps are enabled and one has
demonstrably run, which was the stated precondition for removing the assistant's
inline billed refresh.

