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
| Flutter code | Live-Supabase Android debug APK built on 2026-08-21; `flutter test` 4/4 passed | A clean build is not a device/UI test. |
| Pipeline scoring and review mining | Unit-tested; sample pipeline run verified | Weights need real-usage tuning. |
| Google Places pipeline | Live-loaded real venues; regional/cuisine follow-up coverage checked | Search areas are not exhaustive. |
| Supabase roles and beta RPCs | RLS/roles smoke-tested; account-binding RPCs tested with real accounts and JWTs | The confirmation-return session fix is implemented; a clean native callback retest is blocked only by the live email rate limit. |
| Email referral flow | Resend domain/secrets and a real request → approval → code delivery verified | Retest the app's own confirmation link once Supabase permits another email; do not substitute a non-app redirect. |
| Android core flow | 2026-08-21 live emulator pass: fresh email signup/confirmation, ordinary email sign-in, invalid code, valid UI code redemption, restart persistence, calibration reachability, and a rebuilt live-config APK after the session fix. | GPS, calibration submission, score refresh, and the clean confirmation-return rerun still need focused passes. |
| Web | Deployed, direct routes work, Google OAuth was click-tested | Responsive layout, web mic capture and recent UI changes lack a focused visual pass. |

## Immediate blocker — confirmation-return session retest

The 2026-08-21 live Android emulator smoke test found a narrow but real
beta-gate defect. A fresh disposable account followed the confirmation-email
deep link back into the app and reached `/beta-gate`, but entering a known,
unexpired and unredeemed code returned “That code isn't valid.” The exact code
was in the field; the same account could redeem it through an authenticated
direct RPC call (`ok`).

The normal path works: after a clean ordinary email/password sign-in, the same
unbound account reached `/beta-gate`, redeemed the code through the actual UI,
entered the app, and remained unlocked after restart. Android location
permission appeared before mic calibration; after denying it, the calibration
screen appeared, so the gate redirect did not lose that prompt.

This points to the confirmation-return hand-off, not the code, schema or
normal sign-in flow. The RPC itself returns `invalid` when `auth.uid()` is
null, exactly matching the failed app result. The repair is on
`fix/confirmation-return-session`: account-gated paths now require
`currentSession`, the beta gate stays on `/checking-access` while that session
is checked, stale access checks cannot overwrite a newer auth event, and a
confirmed ordinary sign-in can leave the auth routes while recovery remains
exempt.

The changed app compiled in a live-Supabase Android debug APK and its existing
Flutter tests passed 4/4. A real account confirmation was also checked
server-side, but that fallback did not specify the app's custom redirect and
therefore cannot establish or disprove the native callback behaviour. The
proper clean retry (app `signUp` with
`quietrestaurantfinder://login-callback`, clear app data, confirmation link,
then first valid-code UI redemption) is currently blocked by Supabase Auth's
email send rate limit. The temporary beta-code row and reachable test session
were removed afterward.

Once the rate limit lifts, run that exact clean native callback path. A pass is
only: confirmation returns through the custom scheme, `/checking-access` then
`/beta-gate` appears with a usable session, the first valid code unlocks, and
the database records it bound to that account. A direct server confirmation
without the app redirect is not evidence either way.

Still to smoke-test: a second account attempting an already-redeemed code,
the no-Supabase standalone build, and whether `/checking-access` is visually
acceptable on a normal connection.

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

## Active work queue

### Needs a real device or browser

- Retest the confirmation-return session hand-off after its fix; see the
  immediate blocker above.
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
