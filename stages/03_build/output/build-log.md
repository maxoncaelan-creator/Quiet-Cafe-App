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
- **Scope:** Greater Sydney, Newcastle, Dubbo, Moss Vale and Kiama. The
  search-area list is curated rather than exhaustive.
- **Platforms:** Android, iOS and Web. Web is live at
  `https://quiet-restaurant-finder.pages.dev`; its custom domain is not yet
  attached.
- **Backend:** live Supabase project `quiet-restaurant-finder`
  (`aesorixtfasfuvcqrvem`, `ap-southeast-2`). Migrations through
  `0015_beta_code_account_binding.sql` are applied.
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
| Flutter code | `flutter analyze` clean; `flutter test` 4/4 passed on 2026-08-21 | A clean build is not a device/UI test. |
| Pipeline scoring and review mining | Unit-tested; sample pipeline run verified | Weights need real-usage tuning. |
| Google Places pipeline | Live-loaded real venues; regional/cuisine follow-up coverage checked | Search areas are not exhaustive. |
| Supabase roles and beta RPCs | RLS/roles smoke-tested; account-binding RPCs tested with real accounts and JWTs | App-side beta flow has not been driven by a human. |
| Email referral flow | Resend domain/secrets and a real request → approval → code delivery verified | Device code-entry UI still needs testing. |
| Android core flow | Account, Google sign-in, mic reading and rate-limit UX have earlier real-emulator verification | Recent gate, GPS, calibration and score-refresh changes need a fresh pass. |
| Web | Deployed, direct routes work, Google OAuth was click-tested | Responsive layout, web mic capture and recent UI changes lack a focused visual pass. |

## Immediate blocker — real-device beta smoke test

Run an installed/current build against the live backend and verify:

1. Signed out → `/sign-in`; sign in with an account that has no code.
2. `/checking-access` is brief and transitions to `/beta-gate`.
3. Enter a valid code, reach the app, then restart/revisit with the same
   account and confirm it remains unlocked.
4. Confirm a code redeemed by another account reports the correct hard block.
5. Confirm the no-Supabase standalone/demo build bypasses the gate.
6. Ensure the post-sign-in mic-calibration prompt is not lost when the gate
   first redirects the user.

## Active work queue

### Needs a real device or browser

- Beta gate smoke test above.
- GPS venue guess: near a loaded venue, confirm “Are you at X?” and its
  Yes/No behaviours against a real location fix.
- Mic calibration: fresh sign-in, cold launch, skip, submission and the
  calibration offset’s later effect on readings.
- Score refresh: submit a loudness vote and a mic reading, then confirm the
  detail view refreshes its noise bar and confidence indicators.
- Web: validate responsive rail/drawer layout, download banner, max width,
  filter drawer and web mic permission/levels in a real browser.
- Password recovery: click a real recovery-email link and land on
  `ResetPasswordScreen`.

### Requires Caelan or a dashboard decision

- Deploy the marketing site to the apex `cafequiet.com`; check DNS records
  before attaching it because stale parking records previously appeared.
- Attach `app.cafequiet.com` to Cloudflare Pages.
- Decide whether to add an admin view of outstanding/redeemed beta codes.
- Create iOS OAuth credentials and run an iOS build/device test. Facebook
  remains hidden until its Supabase provider is configured.
- Decide whether the now-web-capable “Get the app” banner remains useful.
- Stripe, push notifications, Privacy Policy/Terms, real store links,
  Universal Links/App Links and enforced GitHub branch protection remain
  launch work, not active implementation work.

### Needs product or technical design before implementation

- Geolocation: define how distance should affect Search Assistant suggestions
  and whether auto-top-up should reverse-geocode / trigger near the user.
- On-demand top-up: wire it from thin search results and/or Search Assistant
  candidate exhaustion; add automated tests; consider replacing its
  service-role secret with a scoped role.
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

For the full reasoning, incident record and command history, use the dated
archive above rather than re-expanding this active handoff log.
