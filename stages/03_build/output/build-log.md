# Stage 03 — Active build log

Last compacted: 2026-08-21

## History archive

The complete session-by-session build record through this date is preserved
unchanged in [[quiet-restaurant-finder/stages/03_build/output/archive/build-log-2026-08-21|Build log archive — 2026-08-21]].
Its SHA-256 at archiving was
`fe5631165da4f9925127d2e26fc595cad102ffb69e72dd5a5053a40d59102f1e`.

This file is the handoff surface: update it with current state, a concise
record of material decisions or verification, and active blockers. Put long
session narratives in a new dated archive when this file needs another
compaction.

## Current product state

- **Product:** Quiet Restaurant Finder, a Flutter app ranking venues by how
  quiet they are.
- **Scope:** Seeded coverage is Greater Sydney, Newcastle, Dubbo, Moss Vale and
  Kiama. The search-area list is curated rather than exhaustive; GPS-based
  nearby checks deliberately allow demand-led expansion wherever users are.
- **Platforms:** Android, iOS and Web. The production web app is live at
  `https://app.cafequiet.com`.
- **Backend:** live Supabase project `quiet-restaurant-finder`
  (`aesorixtfasfuvcqrvem`, `ap-southeast-2`). Migrations through
  `20260822042954_assistant_venue_discovery.sql` are applied.
- **Repository:** [Quiet-Cafe-App](https://github.com/maxoncaelan-creator/Quiet-Cafe-App).
  The account-bound beta gate merged as [PR #26](https://github.com/maxoncaelan-creator/Quiet-Cafe-App/pull/26)
  on 2026-08-21 (`main` merge commit `07fa080`).
- **Data:** Google Places is the only live source. Yelp is deliberately paused;
  Popular Times was dropped after Outscraper returned no usable Sydney data.
  The latest verified pipeline table count was 4,596 restaurants, with later
  code written to avoid downloading all 5,300+ rows for location lookup.

## What the app does now

- Combines review-text mining, crowdsourced microphone readings and
  Quiet/Normal/Loud votes into a quietness score. The signal formula is in
  `data-pipeline/src/scoring.js`; the ranking spec remains authoritative for
  product meaning.
- Browsing, search, filters, favourites, venue detail, microphone capture,
  loudness votes, voice search, a Search Assistant, and a GPS venue guess are
  built. Search Assistant access and submissions are account-gated.
- During the closed beta, sign-in is the front door. A signed-in account
  without a redeemed code is sent to the beta gate; codes attach to the
  account, not a device. The standalone build without Supabase deliberately
  bypasses the gate.
- Beta request → approval → code email was live-tested, including real Resend
  delivery. A second device/browser using the same account is supported.
- The marketing site is built, but it is not deployed. Its copy is owned by
  the `quiet-restaurant-finder-marketing` workspace.

## Verification snapshot

| Area | Verified | Boundary still unverified |
|---|---|---|
| Flutter code | Live-Supabase Android debug APK built on 2026-08-21; `flutter test` 4/4 passed | A clean build is not a device/UI test. |
| Pipeline scoring and review mining | Unit-tested; sample pipeline run verified | Weights need real-usage tuning. |
| Google Places pipeline | Live-loaded real venues; regional/cuisine follow-up coverage checked | Search areas are not exhaustive. |
| Supabase roles and beta RPCs | RLS/roles smoke-tested; account-binding RPCs tested with real accounts and JWTs; the repaired native confirmation return now passed end to end. | Second-account `already_redeemed` handling and the no-Supabase demo build remain to test. |
| Email referral flow | Resend domain/secrets, a real request → approval → code delivery, and Supabase Auth custom SMTP confirmation delivery verified. | Password-recovery link click-through still needs its own focused pass. |
| Android core flow | 2026-08-21 live emulator pass: fresh email signup/confirmation, ordinary email sign-in, invalid code, valid UI code redemption, restart persistence, calibration reachability, and a rebuilt live-config APK after the session fix. The clean confirmation-return path is now included. | GPS, calibration submission and score refresh still need focused passes. |
| Location-aware Search Assistant | Latest-only backend location state, Google Nearby Search proxy, on-demand top-up and scoped Haiku context are deployed; Edge Functions type-check and Flutter tests pass. | A live Android/Google Places request has not yet established the complete GPS-to-answer path. |
| Web | Deployed, direct routes work, Google OAuth was click-tested | Responsive layout, web mic capture and recent UI changes lack a focused visual pass. |

## Latest verification — confirmation-return session smoke test passed

Resend is now configured as Supabase Auth's custom SMTP provider. On 2026-08-21
the current `fix/confirmation-return-session` Android debug APK was rebuilt
with live Supabase configuration, installed on a clean emulator, and driven
through the app's own email sign-up flow. The confirmation email arrived,
contained the expected `quietrestaurantfinder://login-callback` redirect, and
returned the app to `/beta-gate` with a usable session.

The first valid beta code was entered through the UI, redeemed for that newly
confirmed account, and the database recorded the account binding. The app then
opened its normal Search Assistant screen; Android immediately requested
location permission, which was deliberately left unanswered. This proves the
session-repair path without treating the later location feature as tested.

The temporary beta-code row was removed and the emulator app data was cleared.
Synthetic Supabase Auth accounts were retained (their deletion requires an
explicit decision); one disposable-mailbox endpoint rejected deletion, so that
mailbox is left to its provider expiry. The remaining beta-gate checks are a
second account using an already-redeemed code, the no-Supabase standalone
build, and the visual quality of `/checking-access` on a normal connection.

## Latest build — location-aware assistant and venue top-up

GPS now has a real hand-off to Search Assistant rather than feeding only the
empty-state “Are you at X?” prompt. The app sends its bounded current fix with
an assistant message; the authenticated Edge Function stores only that
account's latest fix in `user_location_state`, uses a recent fix for follow-up
turns, and never exposes raw coordinates through the client Data API.

For an explicit place phrase such as “restaurants in Leppington”, the function
refreshes thin coverage before building Haiku's restaurant context. Zero local
venues force a Google Places refresh; partial coverage keeps the existing
Haiku cost decision. “Around me” searches a strict 5 km circle through Google
Nearby Search and scopes the final assistant context to the same radius.
Refreshes are beta-account-only, capped at 20 paid Google searches per day,
and cooldowned for 24 hours per suburb or nearby cell. New venues are still
insert-only, so no user votes or microphone readings are overwritten.

The migration and all three affected Edge Functions are deployed live. Deno
type-checked the functions; `flutter test` passed 4/4, `flutter analyze`
reported no issues, and a debug Android APK built successfully. Those checks
would catch compilation and unit regressions, not live GPS permission, Google
billing or the full assistant response, so the device smoke test remains open.

## Latest implementation — current loudness + fixed in-place mic capture

- New on-site votes and completed microphone readings now immediately override
  the displayed historical score, then linearly blend back to the venue
  baseline over 21 days.
- The venue-detail screen now contains the entire 10-second microphone flow:
  “Listening” for the first five seconds, a Quiet/Normal/Loud assessment at
  five seconds, then the single 10-second average. Capture cannot be stopped
  or navigated away from while active.
- Migration `0016_current_loudness_decay.sql` rejects every new mic insert
  shorter than 10 seconds and writes fresh observations via database triggers.
- Flutter analysis and tests passed before the runner later became unresponsive
  in this worktree. The locked pipeline dependencies were installed and its
  Node suite passed 48/48.
- Do not apply the migration or deploy the recompute Edge Function until the
  matching app release is live: the already-deployed client does not send
  `capture_duration_ms` and would correctly be rejected by the new constraint.

## Latest implementation — list-search result recovery

- A List View search such as “Austral” now ends with useful recovery actions,
  whether it returns no rows or simply unsuitable rows: hand the area to a
  prefilled, user-submitted Search Assistant question, or deliberately ask
  the existing on-demand coverage backend for more venues.
- The refresh action asks the user to confirm that the typed text is a suburb,
  then reloads the list and reports the backend outcome. It does not create a
  client-side bypass of beta access, the daily Google Places cap, or the
  24-hour area cooldown.
- `flutter analyze --no-pub` completed with no issues and `flutter test
  --no-pub --reporter expanded` passed 11/11. A live configured-app check is
  still needed to observe the confirmation and real coverage-response states.

## Latest implementation — GPS coverage checkpoints

- The List View now offers **Check 1 km nearby** alongside the existing
  area-search recovery actions. It uses the app's bounded GPS service and calls
  `ondemand-topup` with coordinates, never a client-generated suburb name.
- For this List View coordinate request, the backend counts restaurants within
  1 km and calls Google Nearby Search whether or not that circle already has
  local venues. After a successful Google search and additive restaurant upsert,
  it records the coordinates, time, original result count, and Places result
  count in the private, RLS-protected `venue_coverage_checkpoints` table.
- The backend checks that table before the daily cap or Google call for this
  mode. Any point within 250 m of a completed check in the previous seven days
  receives a `nearby_recently_checked` result; it cannot spend another Google
  request. For a coordinate-based Assistant question, it performs this cached
  1 km check alongside its existing 5 km, thin-coverage path. Google receives
  the actual coordinates without a city restriction, so this deliberately grows
  coverage outside the seeded region where users search. The new migration and
  Edge Function source are in this branch only and have not been applied or
  deployed to production.
- **Rate-limit hardening in the same draft PR:** paid coverage refreshes now
  reserve capacity atomically in Postgres before Google is called. The existing
  20-refresh shared UTC-day budget remains, and each beta account may make five
  paid refreshes per UTC day. The reservation also prevents simultaneous 1 km
  checks in one 250 m circle from duplicating a Places call. Reservations are
  conservatively completed once a Google request is attempted, even if a later
  write fails. Loudness votes now have a server-enforced five-minute cooldown
  per account and venue; microphone readings retain their 30-second account
  cooldown.
- `npx --yes deno check supabase/functions/ondemand-topup/index.ts
  supabase/functions/search-assistant/index.ts` passed. Flutter analysis and
  tests could not be rerun in this session because the local Dart runtime itself
  hung without output, including for `dart --version`; the process was stopped
  rather than treated as a passing check.
- `npx --yes supabase db lint --local --fail-on error` could not run because
  this machine has neither Docker nor a local Supabase database (`127.0.0.1:54322`
  refused the connection). The new migration was not executed against production:
  this is a draft PR and no database deployment was requested.

## Latest draft fix — Assistant Google suburb refresh

- A real Assistant conversation for Austral exposed a production failure that
  source inspection had missed: every assistant-triggered `ondemand-topup`
  request returned 502 before Google Places ran. Postgres logs identified the
  cause as an ambiguous unqualified `reservation_id` reference in
  `claim_ondemand_topup_reservation()`.
- Draft PR #33 now adds a forward migration that qualifies the reservation
  ledger columns while preserving the atomic 20-per-day global and 5-per-user
  limits. An explicit-suburb request can therefore reserve capacity, call
  Google Places, insert newly found venues additively, and load those rows in
  the same Assistant response.
- The Assistant now tracks the refresh result. If a named suburb has no local
  rows and the coverage request fails, it says that Google could not be checked
  right now rather than quietly asking Haiku to claim it cannot use Google.
  Its prompt also requires two or three real named options whenever refreshed
  suburb context contains venues.
- This is source-only in the draft PR: the corrective migration and updated
  Edge Function still need deployment after merge, followed by a live signed-in
  Austral request that proves the Google call, inserted rows, and returned
  options together.

## Current draft implementation — backend architecture hardening

- Search Assistant now atomically reserves a bounded token budget in Postgres
  before it can request coverage or call Anthropic, then settles that
  reservation to the provider's actual usage. Concurrent requests therefore
  cannot all observe the same remaining allowance, and a rate-limited caller
  cannot spend Google Places capacity before being rejected.
- On-demand coverage is now deterministic: every eligible scope below the
  minimum venue threshold refreshes after its existing cooldown/cache rules;
  Haiku no longer decides whether a billed Google call should occur. The
  existing global/per-account reservation and the one-kilometre coordinate
  checkpoint remain the cost guardrails.
- A microphone reading or loudness vote now recomputes its venue aggregate in
  the same database transaction. The Flutter client no longer calls a
  best-effort, service-role score-recompute endpoint; that endpoint returns
  `410` until it is explicitly removed from deployed environments.
- Added a committed Supabase local-project configuration, pgTAP regression
  tests for budget and contribution-score triggers, and a GitHub verification
  workflow for Flutter, Node, Deno, local migrations and database tests. The
  Node scoring suite passed 48/48 locally. The local Flutter and Supabase CLI
  runners again produced no usable completion output on this workstation, so
  their clean CI run remains the verification boundary.
- CI follow-up: the first hosted run passed Flutter but exposed a quoted Node
  test glob that resolves to no files on GitHub's Linux runner, plus type
  errors in unreachable legacy code retained below the retired score endpoint.
  The test command now uses Node's built-in discovery and the endpoint is a
  true 410-only compatibility stub. The 48-test pipeline suite passes locally;
  the pushed hosted run is the remaining Deno/Supabase verification boundary.
## Latest verification — automated and deployed-web smoke test passed

On 2026-08-21, `flutter test --no-pub --reporter expanded` passed all four
tests and `flutter analyze --no-pub` reported no issues. The deployed web app
at `quiet-restaurant-finder.pages.dev` loaded to the sign-in screen; its
email-sign-in route opened successfully and the browser reported no console
errors. This verifies the automated suite and public initial auth navigation,
not an authenticated account flow, permissions, mic capture, GPS, or native
device behaviour.

## Active work queue

### Immediate defects — resolve before new feature work

- **Speech-to-text is unreliable across search inputs.** The source fix is in
  draft PR #38: one shared `speech_to_text` instance now owns initialisation
  and callbacks for the List and Search Assistant inputs, errors are actionable
  (permission, unavailable, network and timeout), and the Android release
  manifest declares the recognition service. It still requires successful live
  microphone transcription on web, Android and iOS before the defect is closed;
  do not log transcript content during that check. This validation is tracked
  in [GitHub issue #41](https://github.com/maxoncaelan-creator/Quiet-Cafe-App/issues/41).

  On 2026-08-22, `flutter analyze --no-pub` reported no issues and
  `flutter test --no-pub --reporter expanded` now passes 21 tests, including
  deterministic permission, network, no-speech and fallback voice-error
  guidance. A release web build also passed and is now required in PR CI.
  These checks verify Dart integration and compilation only; they do not
  exercise an OS/browser recognition service or microphone permission prompt.
- **Search Assistant 429 classification is fixed in source.** The Flutter
  service now catches Supabase's thrown HTTP-function error, maps the 429
  `resetAt` payload to the existing countdown UI, and leaves other failures as
  the generic fallback. Regression coverage includes 429, non-429 and malformed
  payloads; `flutter analyze --no-pub` and 21 tests passed. A live 429 check is
  blocked until the production migrations below are synchronised.
- **Production migrations are out of sync with `main` (blocked).** Evidence on
  2026-08-22 found production missing `20260822140000`, `20260822153000` and
  `20260822154500`, although the deployed Assistant calls the atomic-budget
  function from `20260822153000`. Do not patch migration history manually.
  Complete the linked Supabase deployment or run authenticated `supabase db
  push --linked` from clean `main`, then follow
  [`BACKEND_RELEASE_RUNBOOK.md`](supabase/BACKEND_RELEASE_RUNBOOK.md) and attach
  the resulting migration/function evidence to the PR. This is tracked in
  [GitHub issue #39](https://github.com/maxoncaelan-creator/Quiet-Cafe-App/issues/39).
- **Local Supabase database test is blocked by Podman tooling.** Podman Desktop
  has a running WSL machine, but its native `podman` CLI was not installed or
  on `PATH`; the official CLI installer completed without creating a native
  CLI. Repair or reinstall the Podman CLI, then open a fresh terminal. Until
  `podman info` and `supabase start` work, do not claim a local database test.
  If Windows host-port forwarding then fails, record that separately and use
  hosted CI as the test boundary. This is tracked in
  [GitHub issue #40](https://github.com/maxoncaelan-creator/Quiet-Cafe-App/issues/40).

### Needs a real device or browser

- GPS venue guess: near a loaded venue, confirm “Are you at X?” and its
  Yes/No behaviours against a real location fix.
- Location-aware and venue-discovery assistant: with a signed-in beta account,
  send a bare lower-case suburb, an exact venue-plus-suburb request, a close
  name and an unknown venue. Confirm the live backend checks coverage, waits
  for close-name confirmation before writing, supports cancel/replacement and
  labels a rate limit correctly. Then verify nearby GPS scope and the 24-hour
  cooldown do not re-spend.
- Mic calibration: fresh sign-in, cold launch, skip, submission and the
  calibration offset’s later effect on readings.
- Score refresh: submit a loudness vote and a mic reading, then confirm the
  detail view refreshes its noise bar and confidence indicators.
- List-search recovery: search for Austral, choose both recovery actions, and
  confirm Assistant hand-off stays unsent until the user submits it while the
  confirmed coverage refresh reports its real server-side outcome and reloads
  the List View.
- GPS coverage checkpoints: with or without venues already within 1 km, choose
  **Check 1 km nearby**, confirm Google adds any real nearby Places, then repeat
  from within 250 m and confirm no Google request runs for seven days. For a
  coordinate-based Assistant question, confirm it also performs the cached 1 km
  check while retaining its 5 km thin-coverage refresh. Also verify the
  unavailable-location message after turning location services off.
- Rate limits: from one beta account, complete five paid coverage refreshes in
  a UTC day and confirm the sixth returns the personal cap; exercise simultaneous
  nearby refreshes from two accounts and confirm only one makes a Places call.
  Submit a loudness vote, immediately submit another vote for that venue, and
  confirm the database returns the five-minute wait message.
- Web: validate responsive rail/drawer layout, download banner, max width and
  filter drawer in a real browser. Speech recognition has its own immediate
  defect above; do not reduce that investigation to a visual permission check.
- Password recovery: click a real recovery-email link and land on
  `ResetPasswordScreen`.

### Requires Caelan or a dashboard decision

- Deploy the marketing site to the apex `cafequiet.com`; check DNS records
  before attaching it because stale parking records previously appeared.
- `app.cafequiet.com` is live. Keep its Cloudflare Pages build configuration
  and public Supabase environment values verified when the web build changes;
  a successful static deployment does not deploy Supabase backend changes.
- Decide whether to add an admin view of outstanding/redeemed beta codes.
- Create iOS OAuth credentials and run an iOS build/device test. Facebook
  remains hidden until its Supabase provider is configured.
- Decide whether the now-web-capable “Get the app” banner remains useful.
- Stripe, push notifications, Privacy Policy/Terms, real store links,
  Universal Links/App Links and enforced GitHub branch protection remain
  launch work, not active implementation work.

### Needs product or technical design before implementation

- Consider replacing the on-demand top-up service-role credential with a
  narrower internal capability.
- Decide whether score breakdown values should be categorical throughout,
  and whether web-specific mic-reading counts are needed.
- Tune score constants (`DEFAULT_WEIGHTS`, platform weights and confidence
  tiers) against real usage data. `PLATFORM_WEIGHT.web = 0.35` is only a
  starting assumption.
- Consider extracting shared scoring constants: `recompute-restaurant-score`
  currently duplicates the Node pipeline formula in TypeScript.

### Low-priority cleanup / watch list

- A small number of old restaurant rows have no suburb.
- README/store wording still says “Sydney” despite the broader scope.
- Quietness scores will remain sparse/null until enough real review or
  microphone signals arrive; that cold-start behaviour is expected.
- The app’s Settings location toggle is not the same thing as the dedicated
  GPS venue-guess flow; do not silently conflate them.

## Non-negotiable implementation rules

- Never commit credentials. `data-pipeline/.env` is real and gitignored.
- Do not push directly to `main`; use a feature branch and PR.
- Keep marketing strings verbatim from the marketing workspace.
- For a provider integration, choose the correct flow for each platform and
  live-test it on that platform. Web Google auth uses Supabase OAuth redirect;
  native uses the vendor SDK path.
- A check only counts if it could have disproved the claim. Run one SQL
  statement per `execute_sql` call when each result matters.

## Concise milestone record

- **2026-08-15–18:** Flutter/Supabase foundation, ranking pipeline, real
  Places data, account-gated readings, native Google sign-in and Search
  Assistant established.
- **2026-08-18–19:** Web support, Cloudflare Pages deployment, responsive UI,
  Web Audio mic capture, calibration, loudness votes and wider NSW coverage
  added.
- **2026-08-20:** Marketing signup/referral service, regional pipeline
  top-ups, on-demand top-up backend, score-recompute fix and GPS venue-guess
  infrastructure completed.
- **2026-08-21:** Resend delivery verified; beta codes rebound from devices to
  signed-in accounts and merged as PR #26.
- **2026-08-21:** Search Assistant learned the latest account location and
  on-demand Google Places refresh path for nearby and explicit-suburb searches.

For the full reasoning, incident record and command history, use the dated
archive above rather than re-expanding this active handoff log.

## Latest implementation — venue coverage recording and Assistant discovery

On 2026-08-22, the List View gained the visible **Record venues near me**
action. It requests one bounded GPS fix and asks the authenticated
on-demand collector to run Google Nearby Search within 1 km. The same
collector has a hidden suburb-targeted mode used by Search Assistant before it
answers a request containing an explicit area, so a thin or empty suburb can
be refreshed in the background and read back in the same response.

The collector now treats the restaurant insert as the success boundary:
upsert, event-log, and coordinate-checkpoint failures return an error rather
than a 2xx partial success. It inserts additively only, returns the count of
new rows, and atomically reserves shared/per-user budget before any billed
Google call. The associated migrations add GPS check checkpoints, paid-refresh
reservations, account-held temporary Assistant location, and atomic Assistant
token budgeting. Flutter analysis and tests passed (7 tests) after the change.

PR #36 added bare-suburb recognition (including lower-case input), named
venue-plus-suburb lookup, a Google Places fallback, close-name confirmation,
and a community-venue draft flow. PR #37 documents that contract and makes a
named Google lookup preview-only: a close candidate is no longer written to
the public venue list until the user says yes. It also supports cancelling or
replacing an unfinished draft and adds a database regression test for the
private draft table.

PR #37 passed hosted Flutter, Node pipeline, Deno, and Supabase database CI on
2026-08-22. The local database suite requires a working Docker Desktop or
Podman command; a downloaded Podman installer alone is insufficient until the
CLI is available on `PATH` and its machine is running. Applying the database
migrations and deploying the affected Edge Functions are still required before
the latest Assistant changes reach the live app.

## Latest production sync and delivery retrospective

PR #37 was merged after its hosted checks passed. The Supabase GitHub
integration was enabled after that merge, so it did not backfill the already
merged release. Production was therefore still running the older Search
Assistant and coverage functions and did not have the assistant-venue-draft
migration. This was not a Cloudflare Pages issue: the static app was reaching
Supabase, but the backend release had not been synchronised.

On 2026-08-22 the reviewed `assistant_venue_discovery` migration was applied
manually, `search-assistant` was deployed as version 12, and
`ondemand-topup` as version 9. The private draft table exists with RLS and no
browser read access. Future backend-changing merges must be verified by
checking the production migration list and function versions, even with the
GitHub integration enabled.

The reported “couldn't reach the search assistant” screen was an HTTP 429
rate-limit response rendered as a generic connectivity failure. PR #38 now
maps that documented SDK error to its reset-time UI and has regression tests;
a real 429 still needs verification after production migration synchronisation.
Production is also missing three later source migrations despite the enabled
integration, so the backend release runbook is mandatory before another live
release claim. The complete record, including the PR #37 review, production
evidence, local-Podman limitation and speech-to-text entry gate, is in
[`delivery-retrospective-2026-08-22.md`](delivery-retrospective-2026-08-22.md).

## Production migration reconciliation — 2026-08-22

The initial GitHub integration did not deploy the intended database directory,
and correcting that configuration exposed older manual database changes that
had been recorded under generated timestamps rather than the repository
migration IDs. The automated deployment stopped safely; it did not partially
apply the new migration.

After an authenticated CLI comparison and schema check, the remote migration
*record* was repaired with the official `supabase migration repair` command.
The subsequent dry run listed exactly two absent source migrations:
`0016_current_loudness_decay.sql` and
`20260822154500_server_owned_contribution_scores.sql`. Both were then applied
with `supabase db push --include-all --skip-vault`. Production now reports a
one-to-one match for every repository migration. The new scoring function,
current-loudness fields and all expected triggers were verified directly.

The post-deploy security advisor found that three trigger-only security-definer
functions still had browser-role execution grants. PR #43 revokes those
grants, fixes the mutable search path on `find_nearest_restaurant`, and adds
pgTAP regression coverage. It must pass hosted Supabase database CI before
being merged. Local database tests remain blocked until a Podman or Docker CLI
is available on `PATH` (tracked in issue #40).
