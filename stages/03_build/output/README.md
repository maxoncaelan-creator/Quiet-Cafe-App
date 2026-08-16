# Stage 3 — Build

Workspace: [[quiet-restaurant-finder/CONTEXT|Quiet Restaurant Finder]]
Inputs: [[quiet-restaurant-finder/stages/02_ranking-design/output/prd|PRD]], [[quiet-restaurant-finder/stages/02_ranking-design/output/ranking-spec|Ranking spec]], [[quiet-restaurant-finder/stages/02_ranking-design/output/data-schema|Data schema]]

**Code lives at [github.com/maxoncaelan-creator/Quiet-Cafe-App](https://github.com/maxoncaelan-creator/Quiet-Cafe-App) as of 2026-08-16** (pushed from this workspace — git history starts there, this ICM workspace is still the source of truth for the *decisions*, not necessarily every future code change). Session paused here after a real end-to-end pass: browsing, auth, and the mic-reading UI flow all exercised live against Supabase, two real bugs found and fixed in the process (see "Account-gated mic readings" below). Pick up from "Open items carried into further build work" at the bottom.

Tech stack: **Flutter** targeting iOS and Android — compiles clean and its unit tests pass as of 2026-08-16 (`flutter analyze`: 0 issues; `flutter test`: 2/2 passed). Backend: **Supabase** (live project `quiet-restaurant-finder`, ref `aesorixtfasfuvcqrvem`, `ap-southeast-2`). Active noise signals: **review-text mining + crowdsourced microphone readings**. Popular Times (Outscraper, revised from an initial OpenSERP plan) was built, then **dropped 2026-08-15** after live testing found 0/100 Sydney restaurants had the data — see "Outscraper vs. OpenSERP" below. Submitting a mic reading requires a **real account** (browsing doesn't) — see "Account-gated mic readings" below. All decided with Caelan on 2026-08-15.

## What's here

```
data-pipeline/           Node.js — fetches restaurant + noise-signal data, computes quietness scores, writes to Supabase
app/                     Flutter — the mobile app (list, detail, mic-reading capture)
supabase/migrations/     SQL schema shared by both: restaurants + mic_readings tables, RLS policies
```

## What's actually verified in this environment

This environment has Node.js and, as of 2026-08-16, Flutter (found at
`C:\Users\maxon\flutter`, not on PATH — v3.47.0) — but still no live
credentials for most external services (Places, Yelp). That shaped what
could be tested directly vs. what's written but unverified:

| Component | Status |
|---|---|
| Scoring engine (`data-pipeline/src/scoring.js`) | **Tested.** 21 unit tests, all passing (`npm test`), covering the ranking-spec.md formula: sub-score normalization, iOS/Android platform weighting, weight renormalization, and cold-start handling. |
| Review-text mining (`reviewMining.js`) | **Tested.** Unit tests for phrase matching. |
| Full pipeline run | **Run and verified.** `npm start` against the bundled sample dataset (`data/sample-input.json`) produced correct output for all four cases: a quiet high-confidence venue, a loud high-confidence venue, a low-confidence single-signal venue, and a zero-signal cold-start venue correctly excluded from ranking. |
| Outscraper client (`outscraper.js`) | **Live-tested with Caelan's own key — and the result changes the plan.** `googleMapsSearch()`'s request shape confirmed against the real SDK source; live queries against both `v2` and `v3` search endpoints for Sydney restaurants came back with `popular_times: null` on 100/100 and 3/3 results respectively. Confirmed this is a real absence, not a parsing bug, by inspecting raw response keys. See "Outscraper vs. OpenSERP" below — **Popular Times is currently not usable as a signal, decision needed.** |
| `.env` auto-loading (`src/env.js`) | **Tested live, not just assumed.** Ran `scripts/verify-pipeline-role.mjs` with `env -i` (a completely scrubbed shell — no env vars at all) and it still connected successfully, proving `dotenv` picks up `data-pipeline/.env` on its own. Also fixed a real bug this surfaced: sample-data mode was unconditionally checking for `SUPABASE_DB_URL` and would have upserted sample data into the live project just because the var was set — now gated on also having a real `GOOGLE_PLACES_API_KEY`, verified with the same scrubbed-shell run. |
| Google Places API client (`places.js`) | **Not exercised live.** No API key configured in this environment. |
| Yelp Fusion API client (`yelp.js`) | **Not exercised live.** Same as above. |
| Supabase project | **Live and fully exercised, including the pipeline_service role.** Project provisioned, both migrations applied, RLS confirmed enabled via `list_tables`, zero findings from `get_advisors`. Ran a live smoke test (`scripts/verify-pipeline-role.mjs`) connected as `pipeline_service`: upserting restaurants succeeded, reading `mic_readings` succeeded, inserting into `mic_readings` was blocked (`permission denied for table mic_readings`), deleting from `restaurants` was blocked (`permission denied for table restaurants`) — all four exactly as the grants in `0002_pipeline_role.sql` intend. See "Pipeline role vs. service_role" below. |
| Flutter app | **Compiled, statically clean, and running end-to-end against live Supabase as of 2026-08-16.** `flutter create .` generated native `android/`/`ios`/etc. folders without touching any hand-written `lib/` file (verified by diffing). Caelan enabled Windows Developer Mode, unblocking `flutter pub get` (all dependencies resolved). `flutter analyze` found two real issues on the first pass (unnecessary null-aware operator in `auth_screen.dart`; deprecated `anonKey` param, renamed to `publishableKey` by supabase_flutter) — both fixed, now 0 issues. `flutter run -d windows` failed on a real but unrelated problem: `permission_handler_windows`'s C++ hits a hard error under this MSVC version's deprecated coroutine headers — a native Windows-toolchain issue, not our code, and not worth chasing since Windows isn't a target platform (iOS/Android only, per the PRD). `flutter run -d edge` succeeded. Seeded the live `restaurants` table with the pipeline's known-good sample-output values (previously empty — 0 rows) so the run would be a meaningful test, not a blank screen; Caelan then confirmed by screenshot that the running app correctly rendered them **quietest-first from the real Supabase read** (75, 45, 8), with the zero-signal cold-start venue correctly separated under "Not enough data yet" showing a dash, not a fabricated score — exactly the ranking-spec.md behavior. Seeded demo rows need clearing before real pipeline data loads in. |
| Flutter unit test (`app/test/restaurant_test.dart`) | **Run for real — `flutter test`: 2/2 passed.** Both `Restaurant.fromJson` cases (fully-scored venue, cold-start venue with null score) verified against the actual compiled model, not just reasoned about. |
| Account-gated mic reading submission | **Auth gate, sign-up, and sign-in all clicked through for real in-browser, 2026-08-16 — mic capture itself confirmed *not* possible on this platform, and a real silent-failure bug fixed as a result.** Score breakdown, auth routing, and sign-up messaging all matched the code exactly (see "Account-gated mic readings" below for the confirmation-link quirk found along the way). Caelan then granted the browser's mic permission and reported a reading was submitted — checked `mic_readings` directly rather than trusting that: **0 rows**. Root cause confirmed via package docs: `audio_streamer`/`noise_meter` doesn't support web at all, so no reading was ever captured, and the previously-unwired `onError` callback (a self-flagged placeholder) swallowed the resulting stream failure with zero user-visible feedback. Fixed: `MicService.start()` now requires a real `onError` handler, wired to a visible error message; `_stopAndSave()` no longer silently no-ops on zero samples; a related latent bug (stale samples never cleared between attempts) fixed alongside it. `flutter analyze`: 0 issues after. Still unverified: actual mic capture succeeding, which needs a real iOS/Android device or emulator — not available in this environment. |
| Google/Apple sign-in (`AuthScreen`) | **Written against verified current Supabase docs (fetched, not assumed), not run.** Neither can work until Caelan sets up his own Google Cloud OAuth client and Apple Developer account — this agent can't create either. See "Google and Apple Sign-In" below and `app/PLATFORM_SETUP.md`. One real fix already made from spec-checking rather than guessing: the initial draft passed an async function directly to a `VoidCallback` parameter, which doesn't reliably typecheck in Dart — fixed to wrap it in a synchronous closure. |

## Outscraper vs. OpenSERP

Stage 1 originally proposed OpenSERP (self-hosted, free) for Popular Times.
Checking its actual API during the first build pass found it has **no
dedicated Google Maps endpoint at all** — just generic search-page scraping
and a content extractor, making Popular Times extraction a guess. Caelan
revised the decision to **Outscraper** the same day.

Outscraper is a real improvement here: its Google Maps Search API has a
**documented, purpose-built `popular_times` field**, confirmed by installing
the actual `outscraper` npm package and reading its source rather than
trusting a summary. That's a materially better starting point than OpenSERP.

One caveat carried forward, found in Outscraper's own community forum:
`popular_times` has been reported as intermittently **not returned for some
places**.

**Confirmed live on 2026-08-15, with Caelan's own key (added to `.env`,
never shared in chat):** `popular_times` was `null` for **100/100** Sydney
restaurants queried (`scripts/check-outscraper-coverage.mjs`). This wasn't
taken at face value — checked whether it was a parsing bug by inspecting
the raw API response directly: `popular_times` is a real field Outscraper
returns, present as a key on every result, but its value was `null` across
the board, on both the `v2` and `v3` search endpoints. So this isn't "some
places don't have it" as the community post suggested — for Sydney
restaurants right now, through this API, **none do**.

Practical effect: `outscraper.js`'s `parsePopularTimes()` correctly treats
this as "no popular-times signal for this venue," so nothing breaks — but
the Popular Times signal is currently non-functional in practice, not just
occasionally missing. This is a decision point for Caelan, not something
to route around silently: drop Popular Times as a signal for now (score on
review-text + microphone only), try an alternative source (the research
brief's original fallbacks — `populartimes` or `gosom/google-maps-scraper`,
open-source Maps-specific scrapers, unlike Outscraper's general search
product), or wait and re-check later in case Outscraper restores the field.

## Supabase — live

Project `quiet-restaurant-finder` was provisioned on 2026-08-15 (org
`maxoncaelan-creator's Org`, project ref `aesorixtfasfuvcqrvem`,
`ap-southeast-2` / Sydney region, free tier — $0/month). Both migrations
applied. Verified, not just assumed:
- `list_tables` confirms both `restaurants` and `mic_readings` exist with RLS enabled.
- `get_advisors` (security) came back with zero findings.
- A live REST call with the anon key successfully read `restaurants` (200 OK, empty array — no data loaded yet).
- The `pipeline_service` role's actual permission boundary was exercised live — see "Pipeline role vs. service_role" below.

`supabase/migrations/0001_init.sql` defines two tables per
[[quiet-restaurant-finder/stages/02_ranking-design/output/data-schema|data-schema.md]]:
- `restaurants` — one row per venue, public read access (RLS), written by the pipeline via the scoped `pipeline_service` role.
- `mic_readings` — one row per crowdsourced reading. Originally insert-only from the app's anon role; **revised 2026-08-15** to require a real account instead — see "Account-gated mic readings" below. Raw rows aren't publicly readable to everyone, only to the user who submitted them; aggregates are written back onto `restaurants` for the ranking to use.

This closes the "backend gap" from the first build pass: the app now has
somewhere real to send mic readings (`supabase_service.dart` →
`submitMicReading()`), and the pipeline now reads them back
(`fetchMicReadingsByPlace()` in `supabase.js`) to compute the mic sub-score
instead of only working from a static sample file.

## Pipeline role vs. service_role

Caelan asked what the alternative to bypassing RLS with the service_role
key would be. Implemented on 2026-08-15: `supabase/migrations/0002_pipeline_role.sql`
creates a dedicated Postgres role, `pipeline_service` — a normal role, not
`BYPASSRLS`, connected directly (not through PostgREST/supabase-js) via
`SUPABASE_DB_URL`. It's scoped by explicit `GRANT` + RLS policies to
exactly what the pipeline needs:
- `SELECT, INSERT, UPDATE` on `restaurants` (no delete)
- `SELECT` only on `mic_readings` (writing readings is the app's job via the anon role, not the pipeline's)

That's the whole point versus `service_role`: if this credential ever
leaked, it can upsert/read the two tables it's granted — it cannot delete a
restaurant, cannot insert a fake mic reading, and cannot touch any table
that isn't `restaurants` or `mic_readings` (there aren't any others yet,
but the scoping holds if more get added later without an explicit grant).

This isn't just asserted — `data-pipeline/scripts/verify-pipeline-role.mjs`
ran live against the project as `pipeline_service` and confirmed all four
boundaries: upsert restaurants ✅, read mic_readings ✅, insert mic_readings
❌ (`permission denied for table mic_readings`), delete restaurants ❌
(`permission denied for table restaurants`).

The role's password was generated and set via `ALTER ROLE ... WITH
PASSWORD` directly against the live project — not written into any
committed migration file. It lives only in `data-pipeline/.env`
(gitignored). `.env.example` shows the connection string shape without the
real credential.

**What's still needed to actually run against it:**
- App side: `app/PLATFORM_SETUP.md` has the real `SUPABASE_URL` and anon key ready to use as `--dart-define` flags — unaffected by this change, the app never used service_role.
- Both tables are still empty (the verification script's test row was inserted and cleaned up). Running the pipeline with real API keys (or even just the sample data path) will populate `restaurants`; real mic readings only appear once the app is actually run and used.

## Account-gated mic readings

Caelan decided (2026-08-15) that mic readings need real accounts — not
anonymous, not just a device ID — with browsing staying open to everyone.
`supabase/migrations/0003_auth_required_for_mic_readings.sql`, applied
live:
- `mic_readings.user_id` is now `not null`, defaults to `auth.uid()`, and has a foreign key to `auth.users`.
- The old "anyone can insert" policy was replaced with one scoped `to authenticated`, requiring `auth.uid() = user_id` — a signed-in user can only ever submit under their own identity, never someone else's.

App side: `AuthScreen` (email/password via Supabase Auth — the built-in
provider, no external app registration needed) only appears when someone
taps "Take a reading here" and isn't signed in. `RestaurantDetailScreen`
gates that one action; nothing else in the app requires an account.

**Walked through this for real in the browser on 2026-08-16** (Caelan,
against the running `flutter run -d edge` build): tapped a restaurant,
saw the score breakdown render correctly (73/83/65 sub-scores → 75
overall, matching the seeded data exactly), tapped "Take a reading here,"
correctly got routed to `AuthScreen` since not signed in, signed up with a
real email, got the "check your email" message exactly as coded (no false
"you're signed in" state). One real, reproducible quirk surfaced:
clicking the confirmation link showed `otp_expired` / "invalid or has
expired" — looked like a failure, but `auth.users` confirms the account
was actually confirmed 31 seconds after signup. The error came from a
second hit on the single-use confirmation token (most likely an email
client or security scanner pre-visiting the link before the real click,
a well-known category of issue with confirmation-link flows generally,
not specific to this app). Net effect: harmless, but the error page is
alarming enough that it's worth calling out — a user who saw that and
gave up would wrongly think sign-up failed. Signing in normally
afterward works, since the account was already confirmed. Not fixed in
code (there's nothing broken to fix), but worth deciding later whether to
show a clearer "your email may already be confirmed — try signing in"
hint on that error path instead of just surfacing Supabase's raw message.

**A second, more consequential gap surfaced right after: Caelan signed in,
tapped through to the mic-reading screen, granted the browser's real mic
permission prompt, and believed a reading was submitted for The Quiet
Fork — but `mic_readings` had 0 rows.** Checked before trusting the UI,
not after: `select count(*) from mic_readings` came back 0, both
project-wide and for that specific restaurant. Root cause, confirmed via
the actual package docs rather than assumed: **`audio_streamer` (which
`noise_meter` wraps) only supports iOS and Android — not web.** The
browser's mic permission prompt is real (a separate, genuinely
web-capable API that `permission_handler` exposes), but no platform
implementation exists to back `NoiseMeter().noise` on web, so the stream
never emits a reading.

That alone would just mean "the mic feature can't be tested on web" —
expected, not a bug, since web was never a target platform. What made it
worth fixing was *how* it failed: `mic_service.dart`'s `onError` callback
was a literal no-op placeholder (`// logged here as a placeholder`, doing
nothing) — a gap self-flagged in a comment when the file was first
written but never followed up on. So the stream's failure was silently
swallowed: no error state, no UI change, nothing — indistinguishable from
"I tapped the button and nothing happened." Fixed 2026-08-16:
- `MicService.start()` now takes a required `onError` callback instead of swallowing stream errors internally.
- `take_reading_screen.dart` wires it to a real error message ("Lost connection to the microphone: …") and resets `_listening`.
- `_stopAndSave()` no longer silently `return`s when zero samples were captured — shows "No sound level was captured — try again." instead.
- Also fixed while in there: `_samples` was never cleared after a successful submission, so a second reading taken in the same screen instance (without navigating away) would have silently averaged in stale samples from the first attempt.

`flutter analyze`: still 0 issues after these changes. This doesn't fix
mic capture on web (it can't — that needs a real iOS/Android
device/emulator), but it means a genuine platform failure now surfaces as
a clear, visible error instead of a confusing silent no-op — which
matters beyond web too, since the same `onError` path would previously
have swallowed *any* stream failure on real mobile hardware as well.

**A real bug was found and fixed while verifying this, and it's worth
understanding because it wasn't in the `WITH CHECK` logic at all.** Testing
methodology first, since it mattered: rather than trust the policy by
reading it, the actual Supabase Auth signup endpoint was used to create a
real test user, its email was confirmed directly in the database (Supabase
requires email confirmation before issuing a session — signUp alone
doesn't log you in, a detail the app's `AuthScreen` now handles explicitly
rather than assuming success means "signed in"), a real session token was
obtained through the real login endpoint, and that token was used to call
the real REST API.

That real test **failed** — "new row violates row-level security policy"
— even though the policy's `auth.uid() = user_id` check was correct
(confirmed independently via a debug RPC that showed `auth.uid()` resolving
correctly). Isolating it against a series of progressively simpler test
tables eventually found the actual cause: **the policy only covered
`INSERT`.** Supabase client libraries default to asking PostgREST to return
the row they just wrote (`Prefer: return=representation`), which requires
Postgres to `SELECT` that row back — and a `SELECT` is subject to RLS too.
With no `SELECT` policy for `authenticated` on `mic_readings`, that
implicit read-back saw nothing, and Postgres reported the *entire insert*
as an RLS violation, even though the write itself was fine. A plain
code-review of the `INSERT` policy would not have caught this — it only
showed up by exercising the real request path a real client makes.

Fixed by adding a second policy, scoped to each user's own rows so it
doesn't undo the original privacy intent (individual reading history stays
private, not visible to other users):

```sql
create policy "Users can read their own mic readings"
  on mic_readings for select
  to authenticated
  using (auth.uid() = user_id);
```

Re-verified end to end after the fix, through the same real signup → real
login → real REST call path:
1. Own identity, relying on the `auth.uid()` default, with representation requested → **201, row returned correctly.**
2. Attempting to submit under a different `user_id` (impersonation) → **403, blocked.**
3. Anonymous (no session) → **401, blocked.**
4. Reading back your own submitted row → **200, returns exactly that row.**

All debug objects (temp tables, temp functions, the test user, test rows)
were cleaned up afterward; `list_tables` and `get_advisors` confirm the
project is back to a clean state, and `pipeline_service`'s own permissions
were re-verified unaffected by any of this.

## Google and Apple Sign-In

Caelan asked for these as additional ways into `AuthScreen`, alongside
email/password. Both are coded (`_signInWithGoogle`, `_signInWithApple` in
`auth_screen.dart`), following Supabase's current documented Flutter
patterns — fetched and read directly rather than relied on from training
data, since these APIs (especially `google_sign_in`, which had a breaking
v7 rewrite) change often enough that a stale pattern would plausibly not
compile.

Neither can actually be exercised — by a human or this agent — until
Caelan sets up his own accounts:
- **Google:** free. A Google Cloud project + OAuth client IDs (Web + iOS). Button hidden until `GOOGLE_WEB_CLIENT_ID` is set.
- **Apple: skipped for now (decided 2026-08-15).** Genuinely unclear whether a free Xcode Personal Team even covers the capability — sources disagree, and it needs an actual Mac to answer (not available in this environment) — and shipping needs the paid $99/year Developer Program regardless, independent of Sign in with Apple specifically. Rather than chase that down now, the implementation stays as-is and the button is off by default behind `APPLE_SIGN_IN_ENABLED` (`bool.fromEnvironment`, defaults false) — flipping it on later needs a flag, not a code change. `app/PLATFORM_SETUP.md` keeps the free-first testing steps for whenever this gets picked back up.

Full step-by-step (with links) is in `app/PLATFORM_SETUP.md` — including
where Google's client IDs are genuinely not secret (they're meant to sit in
build commands and native config files), versus what stays out of chat and
this codebase entirely (anything from the Apple private-key / Team ID /
Services ID path, if the web OAuth flow ever gets added for Android). Until
configured, the Google button simply doesn't render (`_googleConfigured`
checks for a non-empty client ID) and the Apple button only ever shows on
iOS — nothing breaks by leaving both unconfigured.

**No object storage (AWS S3 or similar) is needed for this project.**
Nothing in scope produces files to store: no audio is recorded (mic
readings are just numbers), and restaurant photos are displayed directly
from Google Places'/Yelp's own hosting rather than downloaded and re-hosted.
If a future feature needs file uploads (e.g. user-submitted photos),
Supabase Storage — bundled with the same Supabase project, S3-compatible —
covers that without adding a separate AWS account.

## Running the data pipeline

Copy `.env.example` to `.env` and fill in whichever keys you have — it's
loaded automatically (`dotenv`, see `src/env.js`), so nothing needs to be
exported in your shell or pasted anywhere else. `.env` is gitignored.

```
cd data-pipeline
npm install
npm test                              # 21 scoring/mining/outscraper unit tests
npm start                             # writes data/restaurants.json — uses sample-input.json unless
                                       # GOOGLE_PLACES_API_KEY is set (see .env.example);
                                       # prints Popular Times coverage % if OUTSCRAPER_API_KEY is also set
node scripts/verify-pipeline-role.mjs # smoke-tests pipeline_service's permission boundary (needs SUPABASE_DB_URL)
```

## Running the app

See `app/PLATFORM_SETUP.md` — in short: `flutter create .`, add the
microphone permission entries and Supabase dart-defines it lists,
`flutter pub get`, `flutter run`. Without Supabase configured, the app
falls back to the bundled sample data and disables reading submission,
so it's still runnable/demoable standalone. Browsing the ranked list never
requires an account; tapping "Take a reading here" prompts sign-in/sign-up
first if not already signed in (`AuthScreen`).

## Open items carried into further build work
- ~~Decide what to do about Popular Times~~ — decided 2026-08-15: dropped for v1, code kept dormant.
- ~~Decide whether mic readings need a user identity~~ — decided 2026-08-15: real accounts, submission-gated only. See "Account-gated mic readings" above.
- ~~Whether to add Google/Apple Sign-In~~ — decided 2026-08-15: yes to both, but Apple deferred. Google: code written, waiting on Caelan's Google Cloud OAuth client IDs. Apple: implemented but hidden behind `APPLE_SIGN_IN_ENABLED` (off by default) — skipped for now per Caelan, see "Google and Apple Sign-In" above.
- Whether to add per-account rate limiting on readings, now that real identity exists.
- Exact score-weighting constants (`DEFAULT_WEIGHTS`, `PLATFORM_WEIGHT` in `scoring.js`) — starting values per ranking-spec.md, need tuning against real usage data.
- ~~Flutter app not yet compiled~~ — resolved 2026-08-16: `flutter pub get`/`analyze`/`test` all ran clean (0 issues, 2/2 tests passed), and `flutter run -d edge` confirmed the app renders live Supabase data correctly (ranked, cold-start venue handled right), and the auth gate/sign-up flow works end to end. Still needed: iOS build (needs a Mac — can't happen on Windows at all), Android build (needs Android Studio/SDK, not installed here), an actual Android/iOS device or emulator run (Edge/web isn't the target platform, just the closest thing available here), and completing sign-in + a real mic-reading submission through the UI.
- **Clear the 4 seeded demo rows from the live `restaurants` table** (`place_id` starting `sample-`) before real pipeline data loads in — they were inserted 2026-08-16 purely to make the `flutter run -d edge` test meaningful against an otherwise-empty table.
- Minor UX gap found while testing: if `restaurants` has zero rows at all (not just zero *ranked* rows), `home_screen.dart` renders just the filter bar with nothing below it — no "no restaurants yet" message. Only surfaced because the table was briefly empty during this test; not fixed, just noted.
- Minor UX gap found while testing: clicking an email confirmation link a second time (or having it pre-visited by an email client/security scanner) shows Supabase's raw `otp_expired` error page, even when the account was already successfully confirmed on the first hit. Worth a clearer in-app message ("this may already be confirmed — try signing in") instead of leaving users to see a scary, technical-looking error. Not fixed, just noted — see "Account-gated mic readings" above.
- Live Places/Yelp/Outscraper API calls have not been exercised — needs real API keys to confirm the coded request/response shapes still match.
