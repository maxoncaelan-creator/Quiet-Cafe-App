# Stage 3 — Build

Workspace: [[quiet-restaurant-finder/CONTEXT|Quiet Restaurant Finder]]
Inputs: [[quiet-restaurant-finder/stages/02_ranking-design/output/prd|PRD]], [[quiet-restaurant-finder/stages/02_ranking-design/output/ranking-spec|Ranking spec]], [[quiet-restaurant-finder/stages/02_ranking-design/output/data-schema|Data schema]]

**Code lives at [github.com/maxoncaelan-creator/Quiet-Cafe-App](https://github.com/maxoncaelan-creator/Quiet-Cafe-App) as of 2026-08-16** (pushed from this workspace — git history starts there, this ICM workspace is still the source of truth for the *decisions*, not necessarily every future code change). Session paused here after a real end-to-end pass: browsing, auth, and the mic-reading UI flow all exercised live against Supabase, two real bugs found and fixed in the process (see "Account-gated mic readings" below). Pick up from "Open items carried into further build work" at the bottom.

Tech stack: **Flutter** targeting iOS and Android — compiles clean and its unit tests pass as of 2026-08-16 (`flutter analyze`: 0 issues; `flutter test`: 2/2 passed). Backend: **Supabase** (live project `quiet-restaurant-finder`, ref `aesorixtfasfuvcqrvem`, `ap-southeast-2`). Active noise signals as of 2026-08-16: **review-text mining + crowdsourced microphone readings** (a third, **loudness votes**, was added 2026-08-18 — see that session's entry and `ranking-spec.md` "Signals" for the current, up-to-date list). Popular Times (Outscraper, revised from an initial OpenSERP plan) was built, then **dropped 2026-08-15** after live testing found 0/100 Sydney restaurants had the data — see "Outscraper vs. OpenSERP" below. Submitting a mic reading requires a **real account** (browsing doesn't) — see "Account-gated mic readings" below. All decided with Caelan on 2026-08-15.

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

## Session — 2026-08-16 (continued, after ICM import)

Picked up after this workspace was imported into current ICM conventions
(see the workspace's `AGENTS.md`/`CONTEXT.md`). Re-verified the environment
first rather than assuming anything still worked:

- **Supabase project still healthy** (`aesorixtfasfuvcqrvem`, `ACTIVE_HEALTHY`). Confirmed via `list_projects`/`list_tables` before touching anything.
- **Cleared the 4 seeded demo rows.** Checked `restaurants` first (`select place_id, name, quietness_score, confidence`) and confirmed all 4 rows were exactly the known `sample-*` set with no `mic_readings` referencing them, then deleted (`delete from restaurants where place_id like 'sample-%'`). Table is now genuinely empty (0 rows) — real pipeline data can load in without stepping on demo rows.
- **Fixed the empty-state UX gap** (`home_screen.dart`): the table being truly empty right after clearing demo rows made this the actual live state, not just a hypothetical — added an `_EmptyState` widget ("No restaurants yet — check back soon") shown when `_all.isEmpty`, instead of a bare filter bar with nothing below it. `flutter analyze`: 0 issues. `flutter test`: 2/2 passed.
- **Investigated the `otp_expired` confirmation-link message — turned out to be a bigger item than "minor UX gap" suggested.** There is no email-confirmation redirect/deep-link handling anywhere in the app (checked `auth_screen.dart` and `PLATFORM_SETUP.md` — no `redirect`, deep-link package, or custom Site URL setup). The raw Supabase error page shown on re-clicking a confirmation link is Supabase's own hosted page, not something this app renders or can currently intercept. A real fix needs: a decision on a custom redirect scheme/URL, Supabase Auth "Site URL"/redirect config, and a deep-link handler in the app to catch `error=access_denied&error_code=otp_expired` and show a friendly message. That's new infrastructure and a config decision, not a one-line message change — left undone, moved back into open items below with this context attached so it isn't mistaken for a small fix next time.
- **Re-ran the full verification chain, not just trusted it still worked:** `npm install` (data-pipeline's `node_modules` isn't committed, per `.gitignore` — reinstalled clean, 16 packages, 0 vulnerabilities), `npm test` (21/21 passed, same suite as 2026-08-16 build), and `scripts/verify-pipeline-role.mjs` live against Supabase — all four `pipeline_service` boundaries confirmed unchanged (upsert restaurants ✅, read mic_readings ✅ — 0 places with readings, insert mic_readings ❌, delete restaurants ❌).

## Session — 2026-08-16 (continued again: sign-in persistence + Facebook)

Caelan reported the app doesn't stay signed in, and asked for Facebook (and
other) social logins. Investigated rather than assumed:

- **The persistence code was already correct** — `Supabase.initialize()` runs before `runApp()`, nothing calls `signOut()`, no storage override. But there was **no visible sign-in indicator anywhere in the app** (checked `home_screen.dart` — confirmed nothing). A working session with no on-screen confirmation of it is very easy to mistake for "not staying signed in." Fixed: `home_screen.dart`'s app bar now shows a live account icon (via a new `authStateChanges` stream on `SupabaseService`) with a tap-to-see-email / sign-out dialog. `flutter analyze`: 0 issues, `flutter test`: 2/2 passed.
- **Second likely factor, not fixed (nothing to fix):** all testing so far has been via `flutter run -d edge`, which serves on a new random port each launch — a different origin each time, so web storage looks empty on the next run. Not a bug; doesn't affect a real installed mobile build. Worth knowing if the "not staying signed in" impression continues once the account indicator is in place.
- **Added Facebook sign-in**, via Supabase's redirect-based `signInWithOAuth` (no native-SDK ID-token equivalent exists for Facebook the way Google/Apple have one) — hidden behind `FACEBOOK_SIGN_IN_ENABLED` until Caelan configures the Facebook provider in Supabase's dashboard. See `PLATFORM_SETUP.md`.
- **Activated Apple sign-in** (was deferred 2026-08-15, decided this session to activate alongside Google/Facebook) — `APPLE_SIGN_IN_ENABLED` now defaults to `true`. The two original caveats (needs a real device to test; paid Developer Program still required for App Store shipping regardless of the free-Personal-Team path) are unchanged.
- **Built the deep-link redirect infrastructure this needed** (`quietrestaurantfinder://login-callback` — AndroidManifest.xml intent-filter, iOS Info.plist CFBundleURLTypes), since Facebook's OAuth flow requires it. Wired the **same redirect into email confirmation** (`emailRedirectTo` on `signUp()`), which directly targets the `otp_expired` issue flagged two sessions ago — confirmation links now route back into the app instead of Supabase's generic hosted page, *once Caelan registers the redirect URL in Supabase's dashboard* (not yet done — see "Still needed from you" in `PLATFORM_SETUP.md`).
- **None of this is verified live** — same limitation as Google/Apple before it: needs a real installed build on a device to confirm the OS actually hands the redirect back to the app. Documented as such, not claimed as working.

## Session — 2026-08-17: UI/UX redesign (Figma) → backend prep

A multi-session Figma design pass produced a full M3 redesign (color/type
foundations, all core screens, dark mode, a Search Assistant chat concept,
favorites, and a full Settings section). Full record, including exactly
what each piece needs on the backend, what's already ready to build, and
what's blocked on Caelan's own credentials:
[[quiet-restaurant-finder/stages/03_build/output/ui-design-decisions|UI/UX redesign — decisions and backend implications]].

The one concrete backend change made this session: **`favorites` table**
added (`supabase/migrations/0004_favorites.sql`), applied live and
verified via `list_tables` + `get_advisors` (clean). RLS-scoped to the
signed-in user, same shape as `mic_readings`. See
[[quiet-restaurant-finder/stages/02_ranking-design/output/data-schema|data-schema.md]]
for the field-level record.

Also cleaned up a stray `role-verification-test` row in `restaurants` left
over from an earlier session's `verify-pipeline-role.mjs` run — table is
back to 0 rows.

Everything else from the design pass (dark mode theming, noise-score
display flip, Google rating rendering, Settings screens, drawer-as-overlay)
is Flutter implementation work with no further backend prerequisites.
Search Assistant (Haiku) and Donate (Stripe) are the two pieces still
blocked — both need a secret that can't live client-side, so both need a
small Supabase Edge Function plus Caelan's own API credentials before
they can do anything real.

## Session — 2026-08-17 (continued): Flutter implementation of the redesign

Built straight through the "Ready to build" list from `ui-design-decisions.md`,
in order. `flutter analyze`: 0 issues throughout (fixed 2 lint infos along
the way — missing `const`, missing braces). `flutter test`: 2/2 still
passing. Not yet run on a device — same standing limitation as everything
else in this app (no emulator/device in this environment).

- **Theme**: `ColorScheme.fromSeed(seedColor: 0xFF006874)`, light + dark, replacing the placeholder indigo seed. `ThemeService` (new) persists the choice via `shared_preferences`.
- **Noise score display**: new `QuietnessGauge` widget (`widgets/quietness_gauge.dart`, `CustomPainter`-based semicircle) — shows `100 - quietnessScore`, fill color still keyed off the true quietness value. `quietness_score` itself and `rankedByQuietness()` are untouched. Used on both the List rows (compact) and Detail screen (large hero, replacing the old plain number).
- **Google rating**: now rendered under the name on List/Favourites rows (`widgets/restaurant_tile.dart`, extracted from `home_screen.dart` so List and Favourites share one implementation instead of two).
- **Favorites**: full round trip — `SupabaseService.fetchFavoritePlaceIds/addFavorite/removeFavorite`, wired into the star toggle on List rows and the Detail app bar, backed by the real `favorites` table from earlier this session. Same sign-in-at-point-of-need pattern as "Take a reading." Optimistic UI with rollback on failure.
- **Search bar with voice input**: `widgets/voice_search_bar.dart`, new `speech_to_text` dependency. Filters the List by name/cuisine/suburb. iOS needs `NSSpeechRecognitionUsageDescription` — added to Info.plist.
- **Navigation drawer**: `widgets/app_drawer.dart`. All five destinations (Search Assistant, List, Favourites, Login/Signup, Settings) plus Report a problem (`mailto:`, via `url_launcher`) and a live version number (`package_info_plus`). The "overlay with a scrim, don't lose context" requirement turned out to need zero custom code — `Scaffold.drawer` already renders exactly that.
- **Settings**: full shell (`screens/settings/`) — Display (dark-mode toggle, wired to `ThemeService`), Location (UI only, honestly — v1 is Sydney-only, no geo backend exists), Permissions (both toggles wired to real OS permission state via `permission_handler`, not just UI — added `POST_NOTIFICATIONS` to AndroidManifest.xml), Log out (confirms, then calls the existing `signOut()`), Privacy Policy (Privacy Policy/Terms rows honestly disabled — content doesn't exist yet; Open Source Licenses is real, uses Flutter's built-in `showLicensePage`), Donate (honest "not connected yet" — blocked on Caelan's Stripe account).
- **Search Assistant**: now the app's actual entry point (`main.dart`), matching the design intent. Empty-state UI only — composer is real and functional as a text field, but sending shows "isn't connected yet" rather than pretending to answer. Blocked on Caelan's Anthropic API key + an Edge Function, as scoped in `ui-design-decisions.md`.

## Session — 2026-08-17 (continued again): Search Assistant is real now

Caelan added `ANTHROPIC_API_KEY` to Supabase's Edge Function secrets
(dashboard, not CLI — never shared in chat, per the pattern established
for every other secret in this project).

- **Deployed `search-assistant`** (`supabase/functions/search-assistant/index.ts`), status `ACTIVE`. Proxies chat messages to Claude Haiku (`claude-haiku-4-5-20251001`), grounded in a live query of the `restaurants` table so it can't invent a restaurant that isn't actually listed — the system prompt explicitly instructs it to say so rather than guess. `verify_jwt: true` — callers need a valid Supabase key (the app's anon key qualifies; browsing the assistant doesn't need a signed-in account, matching every other browsing feature).
- **Verified live, not just deployed**: curled the function directly with the anon key and a real question ("Where can I get a quiet coffee?"). It correctly reported no restaurants are loaded yet (table is genuinely empty right now, cleared earlier this session) instead of fabricating one — confirms both the Anthropic key is being read correctly and the grounding instruction is working as intended.
- **Wired the Flutter side for real**: `SupabaseService.askSearchAssistant()` calls the function via `client.functions.invoke()`. `SearchAssistantScreen` is now a real chat thread — user bubbles, assistant messages, a typing indicator while waiting, and a visible error message (not a crash) if the call fails. Voice input via `speech_to_text`, same pattern as the List screen's search bar.
- **Not yet run on a device** — same standing limitation as the rest of the app. `flutter analyze` is the only verification available in this environment.

Donate/Stripe is the one piece from `ui-design-decisions.md` still blocked — needs Caelan's Stripe account the same way this needed his Anthropic key.

## Session — 2026-08-17 (continued again): first real run, on a real emulator

Caelan had Android Studio installed already. Set up the rest of the Android
toolchain in this environment from scratch:

- Downloaded the Android command-line tools (Google's official `dl.google.com` host — the `edgedl.me.gvt1.com` link Google's own docs page resolves to turned out to be a session-specific redirect that 404'd on a fresh request), verified its SHA-256 against the checksum Google publishes before extracting it — asked Caelan first, since downloading a file wasn't something to do without confirmation. Placed at `cmdline-tools/latest` (the location Android tooling expects; a bare `cmdline-tools/bin` doesn't get picked up).
- Accepted all SDK licenses (`flutter doctor --android-licenses`, piped non-interactively).
- Installed a system image (`system-images;android-36;google_apis;x86_64`) and created an AVD. The legacy `avdmanager` tool errored (`Could not load devices from ...devices.xml`) on modern device profiles like `pixel_10` — worked fine once repointed at the plain `pixel` profile, and separately via the newer `android` CLI tool's `emulator create medium_phone`, which also (harmlessly) downloaded its own preferred system image. Ended up with three working AVDs from three different attempts; deleted two, kept one (`Pixel_API_36`).
- `flutter doctor`: Android toolchain now fully green.

**First real build and run, on the emulator** — the actual milestone this
was all for. First release build took ~15 minutes (first-ever Gradle run:
downloading the NDK, multiple SDK platform versions for different plugins'
`compileSdk` requirements). Rebuilds after that: ~65 seconds. The emulator
got closed accidentally partway through the first build; relaunching it
picked up on a quick-boot snapshot in under 30 seconds and the in-flight
Gradle build (which doesn't need the device until the final install step)
completed against it without needing to restart from scratch.

**Verified visually, not just by reading logs** — used `adb shell input`
and `adb exec-out screencap` to actually drive the app and see it:
- Search Assistant (empty state), the navigation drawer (confirmed the
  scrim-overlay behavior works exactly as intended — the screen behind is
  genuinely visible and dimmed, not just conceptually), and the List screen
  (correctly showing the "No restaurants yet" empty state, because the
  table genuinely is empty right now) all render correctly against the
  live M3 theme.
- **Sent real messages to the Search Assistant and got real Claude Haiku
  responses on-device** — end-to-end confirmation that the whole chain
  (Flutter → Edge Function → Anthropic, grounded in a live Supabase query)
  works outside of a curl test.

**Two real bugs found this way — neither was visible from reading the code:**
1. **Microphone permission was requested the instant the Search Assistant or List screen loaded**, before any user interaction — `speech_to_text`'s `initialize()` triggers the OS permission prompt as a side effect, and it was being called from `initState()`. Fixed in both `widgets/voice_search_bar.dart` and `screens/search_assistant_screen.dart`'s `_ComposerState`: `initialize()` is now lazy, only called the first time the mic button is actually tapped. Reverified on-device — no dialog on load.
2. **Assistant replies showed literal `**asterisks**`** instead of bold — Claude's default output uses markdown, and the chat UI just renders plain `Text`, so the formatting characters showed up raw. Fixed by adding an explicit instruction to the Edge Function's system prompt ("plain conversational text only, no markdown") and redeploying (`search-assistant`, now version 2). Reverified on-device with a second real question — clean plain text.

Also noticed, not yet investigated: on the rebuild-and-rerun, the app
resumed on the Settings screen (not the Search Assistant home route) and
rendered in dark mode, despite `ThemeService` defaulting to light and dark
mode never having been toggled. Likely Android restoring a cached
activity/task state across the reinstall rather than a real app bug — the
theme system itself demonstrably works correctly (dark mode rendered
properly once seen) — but flagged here in case it recurs and turns out to
be something else.

**Current real status**: the app now runs, for real, on a real Android
emulator, connected to the live Supabase backend and the live Search
Assistant Edge Function. Everything in `ui-design-decisions.md`'s "Ready to
build" list has been both built and now live-verified, not just
compiled-and-assumed. Remaining known gaps: iOS still needs a Mac (unrelated,
unchanged); Donate still blocked on Caelan's Stripe account; the
dark-mode-on-resume curiosity above.

## Session — 2026-08-17 (continued again): Yelp paused, wiring up real data

Picked back up on getting real Sydney restaurant data into the pipeline
instead of the bundled sample set. `GOOGLE_PLACES_API_KEY` and
`YELP_API_KEY` were both unset in `.env` — the actual reason the pipeline
was still running on sample data.

Caelan reported Yelp Fusion has dropped its permanent free tier (now a
30-day trial then paid per-call plans) and decided to run v1 on Google
Places only, pausing Yelp. Checked before changing anything: `yelp.js` was
never actually imported by `pipeline.js` (only `places.js` is called), so
there was no live wiring to remove — same already-dormant pattern as
`outscraper.js`. Updated `.env.example`, `yelp.js`'s header comment, and
`_config/decisions.md` to record the decision and reasoning. No code
behavior changed.

Next: waiting on Caelan's `GOOGLE_PLACES_API_KEY` to actually run the
pipeline against live Sydney data.

## Session — 2026-08-17 (continued): Places key proxied through a new Edge Function, real data loaded

Caelan had already put a Google Places key in Supabase's Function secrets,
expecting it to just work. It didn't — checked rather than assumed why:
Supabase Function secrets are **write-only**, readable only from inside a
running Edge Function via `Deno.env.get()` (confirmed via `search_docs`,
not guessed). The data pipeline is a local Node script, not an Edge
Function, so it could never have read that secret regardless of naming.

Built the fix rather than falling back to a local `.env` key: a new
**`places-search` Edge Function**
(`supabase/functions/places-search/index.ts`, deployed, `ACTIVE`), same
proxy pattern as `search-assistant`. Deliberately **not** a public
endpoint the app calls — nothing in the Flutter app does, and Places Text
Search costs real money per call, unlike Haiku. `verify_jwt: true` alone
isn't real protection here since the anon key is meant to be public and is
already embedded in the app; added a second gate, a **shared secret**
(`PIPELINE_SHARED_SECRET`, generated locally, written to
`data-pipeline/.env`, never printed in chat, matched as a second Supabase
Function secret) checked via a custom `x-pipeline-secret` header before any
Google call is made. `places.js` now calls this function instead of Google
directly; `pipeline.js`'s gating switched from `GOOGLE_PLACES_API_KEY` to
`SUPABASE_URL` + `SUPABASE_ANON_KEY` + `PIPELINE_SHARED_SECRET` all being
present locally.

Two real naming/config gaps found only by testing live, not by reading the
code:
- Caelan's secret was actually named `GOOGLE_PLACES_KEY`, not
  `GOOGLE_PLACES_API_KEY` — function returned a clear 500 rather than
  silently failing, so this was a one-line fix once surfaced.
- Google's **Places API (New) wasn't enabled** on the Cloud project the key
  belongs to — a 403 from Google itself, passed through the function's
  error response rather than swallowed, so it was immediately diagnosable
  without digging into logs. Caelan enabled it in Cloud Console.

**A real data bug found on the actual first live run, not caught by any
test or code review**: Places API (New) returns `priceLevel` as an enum
string (`PRICE_LEVEL_EXPENSIVE`), but `price_level` is `smallint` per
`data-schema.md`/`0001_init.sql` — the upsert failed outright
(`invalid input syntax for type smallint`) on the very first real row.
Fixed with an explicit enum→1-4 map (`normalizePriceLevel` in `places.js`,
matching Yelp's existing `$`-count convention), covered by two new tests
(`test/places.test.js`) rather than just patched and trusted. `npm test`:
23/23 passing (was 21).

**Verified live end to end, not just deployed**: curled `places-search`
directly — 20 real Sydney restaurants back, correct shape. Ran
`npm start` for real: `places-search config found`, upsert succeeded, 0
errors. Queried `restaurants` directly rather than trusting the log line —
20 real venues (Grana, Bennelong, Mr. Wong, etc.), correct `price_level`
integers, real `google_rating` values.

**Every `quietness_score` is currently `null` — checked this is correct
cold-start behavior, not a bug.** A few venues got exactly one
noise-mention review (`review_positive_count: 1`); `reviewSubscore`
deliberately returns `null` below its minimum mention threshold rather
than trusting a single data point — exactly the "low-confidence
single-signal venue" case the pipeline's unit tests and original sample-data
run already covered. Popular Times stays dropped (see above); mic readings
are naturally empty for these newly-loaded place IDs. Worth flagging to
Caelan directly: the app will now show all 20 restaurants (the empty-state
fix from an earlier session won't trigger anymore) but every one under
"Not enough data yet," which is correct given real signal volume right
now, not a regression — easy to mistake for something broken if seen
without this context.

Yelp remains paused (see above) — `yelpId`/`yelpRating` are `null` on
every row, as expected.

## Session — 2026-08-17 (continued again): Popular Times re-checked, graduated confidence levels

Caelan asked three things: whether Popular Times could come back via Google
Places directly, to lower the minimum-signal threshold, and to add a real
confidence indicator to the UI with six named levels (Very Low, Low,
Moderate, High, Very High, Certain), anchored on "any noise-mention review
is at least Very Low confidence."

**Popular Times: checked live via web search rather than assumed — not
possible.** Google's Places API, old or new, has never exposed a
popular-times/busyness field. That's the same reason the project reached
for Outscraper (a third-party scraper) back on 2026-08-15, and that route
already came back empty for Sydney. Nothing changed; the only paths back to
this signal are third-party scrapers, not an official API. `ranking-spec.md`
updated to record this explicitly rather than leaving it an open question.

**Lowered `MIN_REVIEW_MENTIONS` from 3 to 1** — any noise mention now
produces a score instead of being excluded outright.

**Replaced the three-bucket confidence model (low/medium/high, purely
signal-count based) with six graduated levels** that also weigh data
volume: each present signal contributes 1-3 points based on how much data
backs it (`REVIEW_MENTION_TIERS`/`MIC_READING_TIERS` in `scoring.js`),
points sum and clamp to 1-6, mapping directly onto Very Low → Certain.
`combineScores()`'s signature changed to take `{ subscore, count }` per
signal rather than a bare subscore, so it has the volume data to work with;
`pipeline.js` updated to pass mention/reading totals through. 26/26 tests
passing (was 21), including new cases pinned to Caelan's exact rule (1
review mention → 'Very Low').

**DB migration applied live**: `0005_confidence_levels.sql` swaps
`restaurants_confidence_check` to the six new values. Checked first that
this was safe to do as a straight replacement rather than needing a data
migration — `select distinct confidence` showed every row was still null,
confirmed via `pg_get_constraintdef` before and after.

**Re-ran the pipeline against the live 20 Sydney restaurants to apply the
new model**, not just left the old scores in place: the three venues with
exactly 1 review mention (Cafe Sydney Restaurant, MuMu, Bouillon
L'Entrecôte) now score 100 at 'Very Low' confidence — verified directly in
the database, matching Caelan's rule exactly.

**Flutter**: new `ConfidenceIndicator` widget
(`widgets/confidence_indicator.dart`) — six dots, filled to the current
level, with an optional text label and a `Semantics` label for
accessibility. Added wherever a restaurant's quietness score appears:
compact (dots only) on List/Favourites tiles, full (dots + label) on the
detail screen's score header, replacing the old plain
`"{label} · {confidence} confidence"` text. Also regenerated the bundled
demo dataset (`app/assets/data/restaurants.json`) through the actual
scoring code rather than hand-editing its stale `"confidence": "high"`
values — the four demo cases now read Certain / Certain / Moderate / null,
consistent with the new model. `flutter analyze`: 0 issues. `flutter test`:
2/2 passed (fixture updated from `'high'` to `'Certain'`).

One design note worth flagging: Popular Times, when present, is treated as
inherently high-confidence (3 points, same as each signal's strongest
volume tier) rather than scaled by a count, since it doesn't have a
"volume" concept the way mention/reading counts do — a single Popular
Times read is itself already an aggregate across many real visits. This
only matters once Popular Times is revived (see above); it's inert today.

Confidence tier thresholds (`REVIEW_MENTION_TIERS`, `MIC_READING_TIERS`)
are a starting point, same status as `DEFAULT_WEIGHTS` — open to tuning
against real usage, not a final calibration.

## Session — 2026-08-17 (continued again): Universal Links planned ahead of the domain

Caelan is buying a domain for the app's marketing site (see the new
`quiet-restaurant-finder-marketing` workspace) and asked to use it in the
app too, to get off the `localhost` Site URL fallback and the bare
`quietrestaurantfinder://` custom scheme. He confirmed he wants to go all
the way to real Universal Links (iOS) / App Links (Android), not just patch
the Supabase Site URL field.

Domain isn't purchased yet, so no code or config changed this session —
writing placeholder domain values now would just need rewriting later.
Instead, researched the exact requirements live (Supabase's current docs,
fetched directly rather than recalled) and wrote them into
`app/PLATFORM_SETUP.md` under "Universal Links / App Links — planned,
blocked on the domain" so the real implementation is fast and accurate once
unblocked. Key findings, checked rather than assumed:
- Supabase does not host the iOS `apple-app-site-association` file — it has
  to live on Caelan's own infrastructure, which will naturally be the
  marketing site once that exists.
- Supabase's own Flutter deep-linking docs only cover the *basic, unverified*
  custom-scheme setup for Android — no `assetlinks.json`/`autoVerify`
  walkthrough. Real Android App Links is a platform-level Android feature
  independent of Supabase's docs.
- This isn't blocked on the domain alone: iOS needs a real Apple Developer
  Team ID (paid enrollment, still not done — see "Apple" above), and Android
  needs a release signing certificate's SHA-256 fingerprint (no release
  keystore generated yet in this project).

The existing `quietrestaurantfinder://login-callback` scheme keeps working
in the meantime — this is a planned upgrade, not a fix for something broken.

## Session — 2026-08-17 (continued again): domain confirmed — cafequiet.com

Caelan confirmed the domain: **`cafequiet.com`**, already purchased.
Checked directly rather than taking his word for what it currently does:
fetching it hits a certificate mismatch against `*.crazydomains.com` — it's
registered, but nothing is hosted there yet (still sitting on the
registrar's default). Recorded in `_config/decisions.md` and
`PLATFORM_SETUP.md` with the real domain name in place of the earlier
`yourdomain.com` placeholders.

This unblocks exactly one thing now: Supabase Auth's **Site URL** should
move from `http://localhost:3000` to `https://cafequiet.com` — no other
blocker applies to just that field, unlike the fuller Universal Links work
(still blocked on real hosting existing on the domain, the paid Apple
Developer Program, and an Android signing key — unchanged from the note
above). This is a dashboard-only change, same category as the redirect URL
registration earlier this session — **Caelan's to do, not something this
agent can do via API.**

## Session — 2026-08-17 (continued again): real sign-in + mic-reading verified on-device, one real bug found and fixed

While Caelan waits on domain nameserver propagation, used the still-running
`Pixel_API_36` emulator to close out the biggest standing gap: "completing
a real sign-in + mic-reading submission through the UI on-device" — flagged
unverified in every session since the app first ran.

**Caught a real mistake before it became a false report**: the emulator was
still running a build from before this session's Flutter changes (confidence
indicator, dropdown fixes) — the detail screen showed "Quiet · Very Low
confidence" as plain text, which looked like the old UI happening to read
new data, not the new `ConfidenceIndicator` widget. Checked instead of
assuming — rebuilt (`flutter build apk --debug`) and reinstalled before
trusting anything else on screen. `flutter analyze`: 0 issues throughout.

**A real bug found on real data, not caught by analyze/test**: the List
screen's Cuisine filter dropdown overflowed ("RIGHT OVERFLOWED BY 34
PIXELS"), reproducible on every load. Root cause: `DropdownButtonFormField`
without `isExpanded: true` sizes itself to its *widest* menu item, not the
current selection — invisible with the old short sample cuisines
("Steakhouse", "Seafood"), but real Google Places data has long raw type
strings (`asian_fusion_restaurant`, `middle_eastern_restaurant`). Fixed
(`isExpanded: true` + `TextOverflow.ellipsis` on both Suburb and Cuisine
dropdowns, `home_screen.dart`), rebuilt, reverified clean on-device —
overflow gone, menu still displays every long cuisine name correctly when
opened.

**Confidence indicator confirmed live**: List rows show the compact 6-dot
version, detail screen shows dots + label ("Very Low"), both matching the
real database values exactly.

**Full account-gated flow, verified for real, not assumed**:
1. Tapped "Take a reading here" on a real venue → correctly routed to
   `AuthScreen` (not signed in).
2. Signed up with a real disposable email
   (`qrf-device-test-...@mailinator.com`) through the actual UI — got the
   coded "check your email" message, no false success state.
3. **Confirmed the redirect fix from earlier this session actually works**:
   read the real confirmation email — `redirect_to=quietrestaurantfinder://login-callback`,
   not the `localhost` fallback from before Caelan's dashboard fix. This is
   the app's own real signup flow confirming it, not a synthetic API test.
4. Clicked the confirmation link; browser couldn't follow the custom
   scheme (expected, harmless) — verified server-side instead:
   `auth.users.email_confirmed_at` set, for real.
5. Signed in through the real UI with the confirmed account — succeeded,
   routed straight to the reading screen.
6. **Mic capture works on this emulator** — not previously known; every
   prior session's standing note was "needs a real iOS/Android
   device/emulator." Got live dBA readings (flat ~18dB — no ambient audio
   source feeding the emulator's virtual mic, expected, not a bug — but a
   real reading from the real native plugin, not a stub).
7. Tapped "Stop and save" — UI reported "Thanks! Reading of 18 dB
   submitted." **Did not trust it** (the whole reason `mic_service.dart`
   got fixed two sessions ago was a UI success message with zero rows
   underneath) — queried `mic_readings` directly: a real row, correct
   user, correct `place_id`, `platform: android`, real timestamp.
8. Re-ran the pipeline to confirm the reading actually feeds the score:
   `mic_reading_count_android` → 1, `mic_subscore` → 100, confidence moved
   from `Very Low` to `Low` — exactly matching the tiered model (1 review
   mention + 1 mic reading = 2 points).

Cleaned up afterward: deleted the test user (cascade-deleted the mic
reading with it — confirmed via a follow-up count query), re-ran the
pipeline once more so the restaurant's aggregate returned to its real,
untested state.

## Session — 2026-08-17 (continued again): numbers replaced with a categorical noise bar

Caelan's call: the semicircle-gauge-with-a-number wasn't landing with
users. Replaced it entirely with a named category on a colored spectrum
bar — no numbers shown in the primary display anywhere.

**New widget**: `widgets/noise_level_bar.dart` (`NoiseLevelBar`), replacing
`widgets/quietness_gauge.dart` (deleted — confirmed nothing else referenced
it before removing). Seven categories, quietest to loudest: Silent, Very
Quiet, Quiet, Moderate, Loud, Very Loud, Earsplitting. `quietness_score`
(0-100, 100=quietest) splits into seven even bands — a starting point, same
status as `DEFAULT_WEIGHTS`/the confidence tiers, open to tuning. Rendered
as seven colored segments in a row; the current category's segment is full
opacity, the rest dimmed to ~28%, so the bar reads as a spectrum with a
clear "you are here." Colors reuse the exact same red→amber→teal ramp
`QuietnessGauge` used (sampled once per category's band midpoint) rather
than inventing a new palette, so the noise language stays consistent with
the rest of the app.

Two modes, same pattern as `ConfidenceIndicator`: `compact` (list/favourites
tiles — small bar, short label, width-constrained so a long name like
"Earsplitting" can't push the tile layout around) and full (detail screen —
category name as a large bold heading, bar below it). No-data state: grey
bar, "—" (compact) or "Not enough data yet" (full) — same convention the
old gauge used.

`flutter analyze`: 0 issues. `flutter test`: 2/2 passed. **Rebuilt and
verified live on the emulator, not just reasoned about** — compact bars
render correctly in the List screen (including the null-data grey state),
and the detail screen shows exactly the intended layout: "Silent" as a
large heading, the seven-segment bar with the current category highlighted,
confidence dots below.

Deliberately out of scope for this pass: the "Score breakdown" section's
per-signal numbers (Microphone readings, Review mentions, Popular times)
still show raw 0-100 subscores. Caelan's ask was specifically about how
overall loudness is displayed, not the detail breakdown — flagged as an
open question below rather than changed without being asked.

## Session — 2026-08-18: Google Sign-In verified end to end; real Account screen replaces a live-found bug

Picked up from the Android OAuth client blocker. Caelan created the Web
client ID, enabled Google in Supabase, then hit `[16] Account reauth
failed` on-device — diagnosed as the missing **Android**-type OAuth client
(package name + SHA-1), not a code issue. Generated the debug keystore's
SHA-1 myself (`cd android && ./gradlew signingReport`, needed `JAVA_HOME`
pointed at Android Studio's bundled JBR — not on PATH here) and gave Caelan
the exact values to register. Documented all of this in `PLATFORM_SETUP.md`
so it doesn't need re-deriving.

**Google Sign-In confirmed working end to end on-device**: real account
picker scoped to the app, real Google credential entry (Caelan's own, not
something this agent touched), successful sign-in. Declined to enter any
Google credentials at any point, including backing out of an Android
system passkey/screen-lock detour that account-adding triggered — stayed
within bounds throughout.

**Testing this surfaced a real bug, not a new feature request**: signed in
for real, tapped "Account" in the drawer, and it took Caelan back to the
sign-in form — dead end for a signed-in user. Checked the code rather than
guessing: `app_drawer.dart`'s login/account item had the label correctly
switching to "Account" when signed in, but the `onTap` always pushed
`AuthScreen` regardless of sign-in state. Real bug, not a design gap.

Fixed by building the account management screen that should have been
there — `screens/account_screen.dart`, scoped to what this app actually
stores about a user (no invented profile fields):
- **Personal details**: email, editable via `supabase.auth.updateUser()`.
- **Security**: change password, same API.
- **Your activity**: the signed-in user's own submitted mic readings,
  newest first, joined with the restaurant name
  (`SupabaseService.fetchMyReadings()`, new — relies on the existing RLS
  policy scoping `mic_readings` reads to the caller's own rows, verified
  live two sessions ago).
- **Log out**: moved here from Settings, per Caelan's request.

Wired into both entry points: the drawer's Account item (was the bug) and
`home_screen.dart`'s app bar account icon (previously just a bare
email+sign-out dialog — replaced for consistency, since leaving two
different "signed in" affordances with different capabilities would have
been its own confusing gap).

**Donate moved from Settings into the drawer directly**, per Caelan's
request — new `AppRoute.donate`, `DonateScreen` now carries its own
`AppDrawer` like the other top-level destinations rather than being a
Settings sub-page.

`flutter analyze`: 0 issues (after fixing 3 `prefer_const_constructors`
infos). `flutter test`: 2/2 passed. **Verified live on-device, not just
compiled**: Account screen renders with the real signed-in email
(`maxon.caelan@gmail.com`), the activity query resolves cleanly against
live Supabase with the correct empty state, Log out is present, and Donate
now shows its own hamburger menu confirming it's a real top-level route.

## Session — 2026-08-18 (continued): per-account rate limiting on mic readings

Caelan's call, per this workspace's own rules (rate limiting was explicitly
flagged as not something to decide silently). Asked directly: a 30-second
cooldown between any two submissions from the same account, regardless of
which restaurant.

Also surfaced first: the direct-push-to-main incident from the previous
session. No GitHub branch-protection rule got set up — the session had no
authenticated path to github.com (Claude-in-Chrome extension needed
re-auth and didn't come back up, no `gh` CLI installed, no token in env).
Caelan chose to skip the GitHub settings change for now and rely on a
standing rule instead: always branch + PR, never push straight to `main`.
This and every session's work from here on happens on a feature branch
(`feature/mic-reading-rate-limit` for this session).

Also checked before touching `DEFAULT_WEIGHTS`/tier thresholds in
`scoring.js` (the other open item, also flagged Caelan's call): queried the
live `restaurants`/`mic_readings` tables first rather than assuming. Real
signal is still too thin to tune against — 0 mic readings across all 23
restaurants, and only 3 restaurants have any review-mention signal at all,
each with exactly 1 mention. Flagged to Caelan rather than tuning against
noise; he chose to hold off entirely rather than set new judgment-call
values now. Weight tuning stays an open item.

**New migration**: `supabase/migrations/0006_mic_reading_rate_limit.sql`.
Enforced server-side via a `before insert` trigger on `mic_readings`
(`enforce_mic_reading_cooldown`), not just client-side, so it can't be
bypassed by a modified client. Added a new `submitted_at timestamptz`
column, distinct from the existing `recorded_at` — `recorded_at` is
client-supplied (the on-device capture time ranking-spec.md's time-of-day
filtering needs) and so isn't trustworthy for a rate-limit check; the
trigger unconditionally overwrites `submitted_at` with `now()` regardless
of what the client sends. The check itself: look up the caller's own most
recent `submitted_at` (covered by the existing "Users can read their own
mic readings" RLS policy from `0003_auth_required_for_mic_readings.sql` —
no `security definer` needed) and reject with a `rate_limited: ...` message
if under 30 seconds have passed.

Ran `get_advisors` (security) after applying the migration, per standard
practice for any DDL change — caught `function_search_path_mutable` on the
new trigger function immediately, fixed with a follow-up
`alter function ... set search_path = public`, then re-ran advisors and
confirmed clean (only the pre-existing, unrelated leaked-password-protection
warning remains).

**Verified live against the real database, not just reasoned about**: ran an
actual insert/insert/rollback test against the live `mic_readings` table
(inside a transaction, rolled back after) confirming a second insert from
the same `user_id` within 30 seconds is rejected with the expected message,
then confirmed the rollback left 0 rows behind.

**Flutter side**: `take_reading_screen.dart` now catches `PostgrestException`
specifically and shows the trigger's message (stripped of the
`rate_limited:` prefix) in the snackbar instead of the raw error, so a
throttled user sees "wait N more second(s)..." rather than a Postgres error
string. `flutter analyze`: 0 issues. `flutter test`: 2/2 passed. Not yet
verified live on-device (no real second reading was submitted within 30s
through the actual UI this session) — the server-side behavior is proven,
the client-side message path is reasoned-through from the code but not
click-tested end to end.

## Session — 2026-08-18 (continued again): email is now immutable; forgot-password flow added

Two bugs Caelan caught in the just-shipped Account screen.

**Email can no longer be changed from the app.** Caelan's reasoning: needing
a different email is effectively wanting a new account, not an edit to this
one — so the capability shouldn't exist. Removed `_changeEmail()` and its
dialog from `account_screen.dart` entirely; the Email row is now a plain
`ListTile` with no `onTap`/chevron, display-only. Removed the now-unused
`SupabaseService.updateEmail()` too rather than leave dead code.

**Forgot password, added.** Nothing existed for a user who's locked out —
`account_screen.dart`'s change-password only works for someone already
signed in. Built as Supabase Auth's standard email-based recovery, not a
custom token scheme:
- `auth_screen.dart`: new "Forgot password?" link under the password field
  (sign-in mode only — a fresh signup has no password yet to reset), a
  dialog for the email (pre-filled from the field above if already typed),
  calling `_client.auth.resetPasswordForEmail(email, redirectTo: ...)`
  directly against the Supabase client — matching this file's existing
  pattern of talking to `_client.auth` directly for every other auth action
  here, rather than adding a pass-through wrapper to `SupabaseService` that
  nothing else would call. Reuses `_oauthRedirectUrl`
  (`quietrestaurantfinder://login-callback`), the same deep link already
  wired for OAuth and email confirmation — no new native/dashboard config
  needed beyond what's already pending (see the still-open "Register
  `quietrestaurantfinder://login-callback`..." item below). Deliberately
  doesn't reveal whether the address has an account, since Supabase's own
  API doesn't either — the confirmation message reads "if this address has
  an account..." either way.
- New `screens/reset_password_screen.dart`: shown after the user taps the
  emailed link. Supabase exchanges that link for a temporary recovery
  session and fires `AuthChangeEvent.passwordRecovery` — the old password is
  never asked for, by design (the link itself is the proof of ownership).
  Just a new-password + confirm form calling the existing
  `SupabaseService.updatePassword()`.
- **Wired at the app level, not screen level**: `main.dart`'s
  `QuietRestaurantFinderApp` converted from `StatelessWidget` to
  `StatefulWidget` specifically to hold a `GlobalKey<NavigatorState>` and a
  top-level `authStateChanges` subscription. The recovery link can cold-launch
  the app or land while any arbitrary screen is on top — home_screen.dart's
  existing auth listener is scoped to that one screen and wouldn't fire
  reliably here, so this needed to live above all of them, pushing
  `ResetPasswordScreen` via the navigator key from wherever the app happens
  to be.

`flutter analyze`: 0 issues. `flutter test`: 2/2 passed. **Not yet verified
live on-device** — sending a real reset email and completing the link-tap →
recovery-session → new-password flow through the actual UI hasn't been done
this session; the code path is reasoned-through, not click-tested.

Still on `feature/mic-reading-rate-limit` — Caelan asked not to push the
branch yet, more changes to land on it first.

## Session — 2026-08-18 (continued once more): the two Account fixes verified live on the emulator

Caelan flagged that a screenshot of his still showed the old "Change email"
dialog. Checked the source first rather than assuming a bug — confirmed
`account_screen.dart` already had no `onTap`/`_changeEmail` and grepped the
whole app for "Change email" (zero hits) — the source was already correct.
The screenshot was from a stale install; the emulator hadn't been rebuilt
since that commit landed.

Rebuilt and ran for real: `flutter run -d emulator-5554` with the real
Supabase project's URL/anon key (same values `PLATFORM_SETUP.md` already
documents as safe to use in plain text). Drove it via `adb shell input`
taps and `adb shell screencap` pulled screenshots (adb wasn't on PATH —
found at the standard `Sdk/platform-tools/adb.exe` location; needed
`MSYS2_ARG_CONV_EXCL="*"` on each call, otherwise Git Bash was rewriting
`/sdcard/...` remote paths into a local Windows path and breaking every
pull), not just re-reading the code.

Confirmed both fixes live, signed in as Caelan's real account
(`maxon.caelan@gmail.com`):
- Account screen's Email row: plain `ListTile`, no chevron, not tappable.
- Signed out, opened the sign-in screen: "Forgot password?" renders under
  the password field. Tapped it, entered the real email, hit "Send link" —
  got Supabase's actual response back in the UI: "If
  maxon.caelan@gmail.com has an account, a password reset link is on its
  way." A real reset email went out to that address.

**Not fully click-tested**: the emulator can confirm the send succeeded,
but can't complete the other half of the loop — tapping the link in a real
inbox and landing on `ResetPasswordScreen` via the
`quietrestaurantfinder://login-callback` deep link. That needs Caelan to
check his own email and confirm it lands cleanly.

## Session — 2026-08-18 (continued yet again): Google button false alarm, intro copy removed, forgot-password moved to its own page

Three things from Caelan after checking the previous session's screenshots.

**Google sign-in button "missing" — not a code regression.** Caelan's
screenshot showed no Google button on Sign in/Create account. Checked before
touching anything: `git diff` against `auth_screen.dart` for this whole
branch shows only additions (the forgot-password work) — `_signInWithGoogle`
and its button's `if (_googleConfigured)` gate were never touched. The
button was correctly hiding itself because the *previous* session's
`flutter run` verification only passed `SUPABASE_URL`/`SUPABASE_ANON_KEY`,
not `--dart-define=GOOGLE_WEB_CLIENT_ID=...` — so `_googleConfigured`
evaluated false, exactly as designed (hide rather than show a button that
would error). Not a bug; just a verification run that didn't pass every
flag the app supports. Confirmed by rebuilding with the Google web client
ID from `PLATFORM_SETUP.md` added back to the run command.

**Removed the "An account is only needed..." intro line** from
`auth_screen.dart` — shown above the form on both Sign in and Create
account, per Caelan (not needed).

**Forgot password moved from a dialog to its own screen**, per Caelan (it
was a `showDialog` on top of `AuthScreen`; he wants a real page). New
`screens/forgot_password_screen.dart`, reached via
`Navigator.push` from the "Forgot password?" link (was `showDialog`) —
`_forgotPassword()`'s dialog-and-network-call method removed from
`auth_screen.dart` entirely, logic moved onto the new screen's own state.
Pre-fills from whatever was already typed in the sign-in email field, same
as the dialog did.

**Skeleton loader added deliberately as a transition**, per Caelan's
specific ask ("separated from the sign in page by a skeleton loader") —
`_ForgotPasswordSkeleton`: pulsing placeholder blocks shaped like the real
form (description, email field, button), shown for a flat 500ms on
navigation before swapping to the real interactive form. No dependency
added — a plain `AnimationController` + `FadeTransition`, not a shimmer
package, kept in this one file since nothing else in the app needs it yet.
Worth being clear this is cosmetic pacing, not real loading: there's no
actual async fetch happening underneath, the screen has nothing to wait
on — the delay exists only because Caelan asked for the visual separation.

`flutter analyze`: 0 issues (one miss along the way — forgot the `kIsWeb`
import in the new file, caught immediately by analyze, fixed). `flutter
test`: 2/2 passed. **Verified live on the emulator**, rebuilt with the full
set of dart-defines this time (including Google's client ID): the Google
button is back on Sign in, the intro line is gone, and tapping "Forgot
password?" opens a distinct full page with its own back arrow — caught the
skeleton mid-pulse in a screenshot taken immediately on navigation (grey
placeholder bars matching the real form's shape), confirmed it swaps to the
real interactive form shortly after, and confirmed the empty-email
validation message ("Enter your account email first.") on the new page.
Apple's button is unaffected by any of this (iOS-only, `Platform.isIOS`
gate untouched) but wasn't itself re-verified this run — Android emulator,
same as every other session, never shows it.

## Session — 2026-08-18 (yet another continuation): keyboard overflow fixed; sign-up split into email → password steps

Caelan hit a real bug live: a yellow/black "BOTTOM OVERFLOWED BY 109 PIXELS"
banner on the Create account screen once the keyboard opened. Root cause,
same across every auth screen: `Scaffold.body` was a bare
`Padding(child: Column(mainAxisAlignment: center, ...))` — fine until the
keyboard shrinks the viewport (`viewInsets.bottom`), at which point the
vertically-centered fixed-height content has nowhere to go. Fixed by
wrapping every auth screen's form in `SingleChildScrollView` (dropping
`mainAxisAlignment: center`, which stops mattering once content can
scroll): `auth_screen.dart`, `forgot_password_screen.dart`,
`reset_password_screen.dart`, and the two new screens below. Verified live
by forcing the emulator's soft keyboard on
(`settings put secure show_ime_with_hard_keyboard 1` — this emulator has a
hardware-keyboard passthrough that normally suppresses the on-screen IME,
which is why the bug wasn't caught in earlier sessions' verification) and
screenshotting the password screen with the keyboard up: form fits cleanly
above it, no overflow.

**Sign-up restructured into two screens**, per Caelan: create-account used
to be `AuthScreen` toggled into a second mode sharing one email+password
pair with sign-in. Now:
- `AuthScreen` is sign-in only — no more `_isSignUp` toggle, title is
  always "Sign in". "Don't have an account? Create one" now navigates
  instead of toggling.
- New `screens/create_account_screen.dart` — email field only, plus the
  OAuth buttons (Google/Apple/Facebook create an account and sign in with
  the same call, so they don't need a second step). "Continue" does a
  minimal `contains('@')` check (Supabase is the real authority on email
  validity, proven below) and pushes the new password screen.
- New `screens/create_account_password_screen.dart` — password + confirm
  password, checked for a 6-char minimum and that they match before
  calling `signUp`.

**Extracted `services/oauth_service.dart`** rather than duplicate the
Google/Apple/Facebook sign-in mechanics (nonce generation, idToken
exchange, the config flags) across both AuthScreen and the new
CreateAccountScreen — each screen now just calls
`OAuthService.signInWithGoogle()` etc. and owns its own
submitting/error/navigation handling. `forgot_password_screen.dart` also
switched to this file's shared `oauthRedirectUrl` constant instead of its
own duplicate.

**Navigation contract**: all three call sites that push `AuthScreen`
(`home_screen.dart` ×2, `restaurant_detail_screen.dart` ×2,
`app_drawer.dart` ×1) use `Navigator.push<bool>`, so `AuthScreen` may only
ever pop with `true`/`false`/`null` — checked this before designing the
3-screen cascade. `CreateAccountPasswordScreen` pops `true` (session
established — cascades all the way up through `CreateAccountScreen` and
`AuthScreen`) or `false` (needs email confirmation — the message reaches
`AuthScreen` via an `onPendingConfirmation` callback threaded through both
new screens, decoupled from the pop value itself, then cascades back only
as far as `AuthScreen` so it can display that message).

`flutter analyze`: 0 issues (two misses along the way, both caught
immediately by analyze: a nonexistent `SignInWithAppleButtonIfIOS` widget
name invented while drafting, and `LaunchMode` incorrectly imported from
`material.dart` instead of `supabase_flutter.dart` in the new service
file). `flutter test`: 2/2 passed.

**Verified live on the emulator**, extensively:
- Overflow fix, confirmed above.
- Create account screen: email-only, no password field, matches Caelan's
  ask exactly.
- Continue → Set a password screen, back arrow → returns to Create account
  with the email preserved (natural `Navigator` pop, no special handling
  needed).
- Three real Supabase-side errors surfaced correctly through the new
  screens' error text, each proving the real API call path works, not just
  the UI: a password-complexity policy on this project ("should contain at
  least one character of each: lowercase, uppercase, digit, symbol"), an
  invalid-domain rejection (`@example.com`), and — after several test
  emails this session — a real `email rate limit exceeded` from Supabase's
  own SMTP limits.
- **Not completed**: the actual success path (immediate session, or the
  "check your email" pending-confirmation message reaching AuthScreen) —
  blocked by that same rate limit before a signup could succeed. No test
  account was created by any attempt (confirmed via
  `select ... from auth.users` — zero rows), so nothing needed cleaning up.
  The pop-cascade logic is code-reviewed and reasoned-through, not
  click-tested end to end. **Heads up for Caelan**: if you try signing up
  for real soon and get "email rate limit exceeded," that's Supabase's
  default free-tier SMTP limit (temporary, resets on its own), not a bug —
  don't spend time debugging it.

## Session — 2026-08-18 (yet another continuation): auth screens split into choosers, matching cal.com reference

Caelan gave a screenshot of cal.com's sign-in/sign-up pages as the reference
and asked for four things: a more prominent Google button, sign-up's email
field moved off the main screen and behind a button, sign-in's email+password
moved the same way, and every Google button using the real logo.

**`widgets/google_sign_in_button.dart`** (new) — solid near-black pill,
white bold text, Google's actual four-color "G" mark rather than a generic
Material icon. Deliberately a literal style match to the reference rather
than derived from the app's teal theme — the point is contrast against the
other buttons on the same screen. The logo itself: added
`assets/icons/google_logo.svg` (Google's standard four-path "G" logomark)
and the `flutter_svg` package (`^2.0.10+1`, resolved to `2.3.0` — wasn't a
dependency before, added just for this) to render it.

**`widgets/email_option_button.dart`** (new) — the "Sign in/up with email >"
secondary button replacing the inline fields on both chooser screens.

**Both `auth_screen.dart` and `create_account_screen.dart` became pure
choosers** — just the provider buttons (Google now via the new widget,
Apple/Facebook unchanged) and an email-option button, no text fields of
their own anymore. The actual fields moved to two new screens:
- `screens/sign_in_email_screen.dart` — email, password, "Forgot
  password?", Sign in button. Basically `auth_screen.dart`'s old form,
  relocated.
- `screens/create_account_email_screen.dart` — email field + Continue.
  `create_account_screen.dart`'s old form, relocated.

**Cascade got one hop deeper** on the sign-up side: all 5 sites that push
`AuthScreen` still expect `Navigator.push<bool>`, so the pop contract
(`true`/`false`/`null`, same meaning as before) now relays through one more
screen — `CreateAccountPasswordScreen` → `CreateAccountEmailScreen` →
`CreateAccountScreen` (chooser) → `AuthScreen` (chooser) → original caller.
Each hop is the same `if (result != null) Navigator.of(context).pop(result)`
pattern already established two sessions ago, just threaded one level
further. Sign-in gained one hop too:
`SignInEmailScreen` → `AuthScreen` (chooser) → original caller.
`onPendingConfirmation` (the "check your email" message callback) threads
through the same chain unchanged.

`flutter analyze`: 0 issues (one miss along the way, caught immediately:
`create_account_email_screen.dart`'s `_submitting` field was declared but
never actually set `true` during the push-and-await, same latent gap the
pre-refactor file had — analyze flagged it as "could be final" once
isolated in its own file; fixed properly by setting it during the
navigation instead of just silencing the lint). `flutter test`: 2/2 passed.

**Verified live on the emulator**: both chooser screens screenshot
pixel-matches the ask — solid black Google button with the real logo,
"Sign in with email >" / "Sign up with email >" as the only other visible
option beside Apple/Facebook. Confirmed tapping the email-option button on
both screens opens the dedicated page with the actual fields, title
reflecting which flow ("Sign in with email" / "Create account").
Deeper cascade behavior (the extra hop) is reasoned-through/code-reviewed,
not independently re-verified this pass beyond what the visual check above
covers — no reason to expect it broke given it's the same pop pattern used
one level up, but flagging the distinction honestly.

## Session — 2026-08-18 (yet another continuation): auth screens' content vertically centered

Caelan: "move all of that more to the centre of the screens" — the chooser
and email/password screens from the last two sessions all had their content
packed at the top with a lot of empty space below, a side effect of the
keyboard-overflow fix (`SingleChildScrollView` sizes its child to content,
so `mainAxisAlignment: center` on the inner `Column` was already dead —
removed when that fix landed, silently leaving everything top-aligned).

**New `widgets/centered_scroll_form.dart`** — the same
`LayoutBuilder → SingleChildScrollView → ConstrainedBox(minHeight) →
IntrinsicHeight → Column(mainAxisAlignment: center)` recipe was about to be
copy-pasted into all 7 screens with this shape, so extracted once instead.
The `minHeight` comes from the `LayoutBuilder`'s own reported constraints,
which the `Scaffold` already shrinks when the keyboard opens — so this
centers content only when there's slack, and still scrolls normally when
there isn't (the keyboard-overflow fix from two sessions ago stays intact,
not re-broken by this).

Applied to all 7: `auth_screen.dart`, `create_account_screen.dart`,
`sign_in_email_screen.dart`, `create_account_email_screen.dart`,
`create_account_password_screen.dart`, `forgot_password_screen.dart` (only
the real-form branch — the skeleton placeholder already centered correctly
on its own, since it's outside the scroll view), `reset_password_screen.dart`.

`flutter analyze`: 0 issues. `flutter test`: 2/2 passed. **Verified live on
the emulator**: rebuilt, screenshotted the Sign in chooser and the "Sign in
with email" page — both now show content centered in the available space
rather than pinned to the top.

## Session — 2026-08-18 (yet another continuation): Search Assistant gated to signed-in users, per-account 10,000-token/5-hour rate limit

Two asks from Caelan: Search Assistant only usable by signed-in accounts
(signed-out sees an explanatory message instead), and a 10,000-token/5-hour
budget per account to prevent misuse, with "on a break, available again in
X" messaging once hit. Explicitly told not to test by actually burning
10,000 tokens — see the testing section below for what was done instead.

**Enforced server-side, not just in the Flutter UI** — same principle as
every other gate in this app (mic reading auth, mic reading cooldown): the
UI gate is the normal path, but `search-assistant`'s Edge Function has to
reject an unauthenticated or over-limit caller on its own, since a client
can always call the function directly.

**New migration**: `0007_search_assistant_rate_limit.sql` —
`search_assistant_usage` (user_id, window_start, tokens_used). Only a
SELECT policy for `authenticated` (own row) — deliberately no
insert/update policy, since only the Edge Function's service-role client
should ever write to it; a user directly resetting their own tokens_used
would defeat the whole point. The SELECT policy exists so the app can show
current status via a plain table read, no round trip through the assistant
or any token cost.

**`search-assistant/index.ts` rewritten**: extracts the caller's JWT from
the Authorization header and validates it via `auth.getUser()` — rejects
with 401 `auth_required` if that fails (covers both "never signed in" and
"session expired" the same way, since `functions.invoke` always sends
*some* bearer token — the anon key if signed out — and `auth.getUser`
rejects that the same as a missing one). Added a service-role client
(`SUPABASE_SERVICE_ROLE_KEY` — auto-injected by the Edge Runtime, not a
secret that needed setting) for the usage table, separate from the existing
anon client that reads public restaurant data. Fixed 5-hour window per
account, not sliding — simplest to reason about and to explain to the user.
A blocked request never touches Anthropic; a request that goes through
gets its real `usage.input_tokens + usage.output_tokens` from Anthropic's
response added to the running total afterward (upsert, best-effort — a
failed accounting write doesn't discard a reply already paid for). Deployed
as version 6, `verify_jwt: true` kept as-is (already true; compatible since
the anon key is itself a validly-signed JWT that passes the platform check
before my own `auth.getUser` check correctly rejects it as not a real
user).

**Flutter side**: `SupabaseService` gained `SearchAssistantUsage` (+
`isRateLimited`/`resetAt` helpers), `SearchAssistantRateLimited` (thrown by
`askSearchAssistant` on a 429), and `fetchSearchAssistantUsage()` (the
token-free status read). `TOKEN_LIMIT`/`WINDOW_MS` constants duplicated
client-side (Dart) and server-side (Deno/TS) — no way to literally share a
constant across those runtimes, flagged clearly in comments on both sides;
the Edge Function's copy is the actual source of truth, the client's is
only for showing status without spending a call.

`search_assistant_screen.dart`: checks sign-in state and current usage on
load (via `authStateChanges`, same subscription pattern `home_screen.dart`
already uses) and shows one of three states in place of the normal
chat — not configured (dev-only), signed out ("Search Assistant needs you
to sign up or log in to work." + a Sign in button), or rate-limited
("Search Assistant is on a break, it will be available again in
[X hours and] Y minutes.", hours dropped under 1h per Caelan, "0 minutes"
also dropped when remainder lands exactly on the hour). A 30-second
`Timer.periodic` keeps the countdown accurate and clears the gate on its
own once time's up, rather than leaving a stale "2 hours" on screen
indefinitely. Also caught: a message that comes back 429 mid-conversation
switches into the same gated state.

**Testing — deliberately not by spending 10,000 tokens**, per Caelan's
explicit instruction. What was done instead:
- `curl`'d the deployed function directly with the anon key as the bearer
  token (no real user) — confirmed 401 `auth_required`, zero tokens spent,
  proves the server-side auth gate works independent of the Flutter UI.
- Simulated the rate-limited state via direct SQL on
  `search_assistant_usage` for the real account (`tokens_used: 10000`,
  `window_start` backdated by a chosen amount) rather than actually
  reaching the limit through real usage. Verified live on the emulator:
  signed-out gate shows correctly with the exact requested wording;
  signed in via Google, backdated the window by 2h30m → screen correctly
  showed "available again in 2 hours and 29 minutes"; backdated by 4h15m
  (45m remaining) → correctly showed "available again in 45 minutes" with
  the hours part dropped, exactly per spec; deleted the row → composer
  correctly reappeared.
- Sent exactly one real message ("hi") to confirm the parts no SQL
  simulation could prove on its own: that a real signed-in JWT actually
  passes the function's `auth.getUser` check, and that a real Anthropic
  response's actual token usage gets correctly parsed and upserted. Cost:
  973 tokens (mostly the system prompt's restaurant context) — under 10% of
  one account's 5-hour budget, nowhere near the 10,000-token ceiling this
  session was told not to spend testing. Confirmed via SQL that the row
  recorded exactly that, then deleted the test row to leave the real
  account's usage clean.

`flutter analyze`: 0 issues. `flutter test`: 2/2 passed.

## Session — 2026-08-18 (yet another continuation): password visibility toggle, friendly policy-error message, Change password rebuilt as its own re-verified screen

Three related asks from Caelan, arriving in sequence as the conversation
clarified itself.

**Password visibility toggle.** New `widgets/password_field.dart` — a
`TextField` wrapping its own `obscureText` bool with an eye
`IconButton` suffix, so every password field in the app gets the same
toggle without each screen managing the bool itself. Applied everywhere a
password is typed: `sign_in_email_screen.dart`,
`create_account_password_screen.dart` (both fields),
`reset_password_screen.dart` (both fields), and the (now-replaced, see
below) change-password dialog.

**The confusing password-policy error, not the policy itself.** Caelan's
first framing made it sound like the strict Supabase password-complexity
requirement (upper+lower+digit+symbol, from the "password should contain
at least one character of each: abcdefg...!@#$%..." error two sessions
ago) was a mistake to relax. He then corrected that: the policy is
intentional and correct — what actually needed fixing was that the app was
displaying Supabase's raw rejection message verbatim, dumping the entire
allowed-character-set string instead of stating the requirement plainly.
New `utils/friendly_auth_error.dart` —
`friendlyPasswordPolicyError(Object error)` detects that specific
Supabase message (matches on `'password should contain'`, case-
insensitive) and returns "Password must contain at least one uppercase
letter, one lowercase letter, one number, and one special character."
instead; returns null for any other error so callers keep their own normal
fallback formatting. Wired into every place a password-setting call can
fail: `create_account_password_screen.dart`, `reset_password_screen.dart`,
and the change-password flow. Also added a matching hint line under the
new-password field on all three password-*setting* screens (not
sign-in, which doesn't set a password) — "Must include an uppercase
letter, a lowercase letter, a number, and a symbol." — so the requirement
is visible upfront instead of only discovered after a rejected attempt.

Also flagged plainly to Caelan: the policy itself lives in Supabase's Auth
project settings (Dashboard → Authentication → Providers → Email →
"Password Requirements"), not in this app's code or migrations — none of
the Supabase MCP tools available in this session can read or change that
setting remotely, so confirming exactly what's configured there was Caelan's
own check, not something done from here.

**Change password rebuilt as its own screen**, per Caelan, replacing the
original `showDialog` version — and now asks for the *current* password
too, not just the new one. New `screens/change_password_screen.dart`:
Current password + New password (both via the new `PasswordField`, both
with the policy hint), reached from `account_screen.dart`'s "Change
password" row via `Navigator.push` instead of `showDialog`. Two-step
submit, not one: Supabase's `updateUser()` changes the password based on
the current session alone — it never checks the old password — so this
screen re-verifies it explicitly first via a real
`signInWithPassword(email, currentPassword)` call before touching the
actual update. A wrong current password fails right there with "Current
password is incorrect." and never reaches the update step. This matters
for a real, not hypothetical, gap: without it, anyone with the device
unlocked and this app already signed in could change the password without
ever knowing the original — re-verification is what makes "change
password" actually mean the account holder authorized it.
`account_screen.dart` lost its `_changePassword` method and the
now-unused `PasswordField`/`friendly_auth_error` imports that moved with
it.

`flutter analyze`: 0 issues throughout (checked after each of the three
sub-changes). `flutter test`: 2/2 passed.

**Verified live on the emulator**, all three: (1) opened the change-
password screen, typed a password, tapped the eye icon — text visibly
un-masked, icon switched to the crossed-out variant. (2) Entered a
deliberately wrong current password with a policy-valid new password,
submitted — got exactly "Current password is incorrect.", confirming the
re-verify-before-update ordering actually works, not just compiles. Hit
one unrelated hiccup mid-session: the emulator rendered a solid black
frame after closing the Google account picker (engine/surface glitch, no
error in the Flutter run log, unaffected by any code in this session) —
resolved with a force-stop + relaunch, unrelated to and not caused by any
of these changes.

## Session — 2026-08-18 (yet another continuation): full-conversation mistake review

Caelan asked for a review of the whole conversation for mistakes that should
have been logged, noting that failing to log a mistake is itself a mistake.
Went through the session and recorded six in
`workspaces/quiet-restaurant-finder/MISTAKES.md` via `bin/icm mistake`:
`keyboard-overflow-unhandled`, `incomplete-verification-build-flags`,
`raw-backend-error-shown-to-user` (all caught by Caelan), plus two smaller
self-caught ones (`unscoped-filesystem-search`,
`unintended-tool-call-not-disclosed`) and the meta one Caelan's framing
pointed at directly — `mistakes-not-logged-contemporaneously`: none of the
above were written down when they actually happened, despite this
workspace's own `AGENTS.md` saying to. Recompiled `MasterMistakes.md` and
ran `bin/icm doctor` clean afterward. Full detail lives in `MISTAKES.md`
itself, not duplicated here — none of these are at the 3+ "approaching"
threshold yet, so no `AGENTS.md` guard is required.

## Session — 2026-08-18 (yet another continuation): documentation pass

Caelan asked for all documentation in the vault to be brought up to date,
separately from the pending PR (still blocked on GitHub connector repo
access — see below). Went through every doc in the workspace and updated
what this session's work had made stale:

- `_config/decisions.md` — three new confirmed-decisions sections: "Account
  & Search Assistant access" (sign-in required, 10k-token/5h limit),
  "Password policy" (intentional, only the display was wrong), "Git
  workflow" (never push directly to `main`).
- `AGENTS.md` — the "per-account rate limiting" open item was stale (marked
  as still-open; it's resolved twice over now, mic readings and Search
  Assistant both). Added the branch+PR rule to "Rules specific to this
  workspace" so it's not only in this agent's memory file.
- `ui-design-decisions.md` — updated the Search Assistant entry (gating +
  rate limit) and added a summary-table row for the cal.com-style
  sign-in/sign-up rework, noting it's a separate later pass from the
  original Figma-driven redesign this doc otherwise documents.
- `app/PLATFORM_SETUP.md` — updated the "AuthScreen has the buttons" note
  now that the OAuth mechanics live in `oauth_service.dart` shared across
  two screens; added a password-policy dashboard note so a future session
  (or Caelan) knows where that setting lives and that the app's own copy
  (hint text, friendly error message) won't update itself if it changes.
- `app/README.md` — was still Flutter's unedited scaffold boilerplate
  ("A new Flutter project") this whole time, on the actual GitHub repo.
  Replaced with a real project README: what the app is, the stack,
  features, how to run it, and a pointer back to this workspace as the
  source of truth for the decisions behind the code.

Left `data-schema.md`, `ranking-spec.md`, `prd.md`, `research-brief.md`,
`CONTEXT.md`, `workspace.md` unchanged — checked each, none went stale from
this session's work (data-schema.md deliberately delegates exact columns
to the migration files rather than duplicating them, so new tables/columns
don't require an edit there).

**Still open**: the PR itself. Pushed `feature/mic-reading-rate-limit` to
origin, but had no authenticated path to create/merge it — `gh` CLI isn't
installed, Claude-in-Chrome needed re-auth then turned out to not apply to
Edge (Chrome-only extension), and the connected GitHub App's installation
was initially scoped to two unrelated repos, not this one. Caelan is
updating the installation's repository access; retrying once that's
confirmed.

## Session — 2026-08-18 (continuation): mic crash found and fixed, rate-limit UX click-tested

Picked up the rate-limit cooldown open item — verifying the `take_reading_screen.dart`
snackbar path live, not just reasoned from code. Confirmed `emulator-5554`
(`Pixel_API_36`) already running with the app installed and signed in as
`maxon.caelan@gmail.com`.

**Found a real crash, not an emulator quirk.** Tapping "Start listening" on
MuMu's reading screen red-screened immediately: `Unsupported operation:
Infinity or NaN toInt`. Traced via `adb logcat`: the emulator's virtual mic
was failing to deliver frames (`pcm_readi failed ... I/O error`, inserting
silence). `noise_meter`'s `meanDecibel` is `20*log10(amplitude)`, so true
zero amplitude is `-Infinity`, not a small number — that flowed unguarded
into `take_reading_screen.dart`'s `Text('${_currentDb!.round()} dB')` and
crashed on the `.round()` call. This isn't emulator-specific: a genuinely
silent room — exactly the case this app exists to detect — hits the same
zero-amplitude math on a real device.

**Fixed at the source**, `lib/services/mic_service.dart`'s `start()`: the
`onReading` callback now checks `value.isFinite` and substitutes `0` for
any non-finite sample, instead of passing `-Infinity`/`NaN` through
untouched. `flutter analyze`: 0 issues. Rebuilt (`flutter run -d
emulator-5554` with the full `SUPABASE_URL`/`SUPABASE_ANON_KEY`/
`GOOGLE_WEB_CLIENT_ID` dart-define set) and reinstalled.

**Re-verified live end to end**, both halves: (1) "Start listening" no
longer crashes — showed a real ticking dB value, then `0 dB` on a later
sample where the mic again produced silence, confirming the clamp path
itself gets exercised, not just the happy path. (2) Submitted a reading
(got "Thanks! Reading of 18 dB submitted."), then immediately started and
submitted a second one on the same account — got back exactly "wait 14
more second(s) before submitting another reading", the plain-language
message from `friendly`-style handling of the `rate_limited:`-prefixed
`PostgrestException` in `take_reading_screen.dart`. Confirms the server
trigger (`enforce_mic_reading_cooldown`, `0006_mic_reading_rate_limit.sql`)
and the Flutter-side message parsing both work correctly together, live —
this was previously only reasoned-through from code.

Not yet committed — working on `feature/mic-reading-rate-limit`, still
blocked on the GitHub connector's repo access (see PR blocker below);
Caelan chose to skip resolving that this session and defer the PR.

## Session — 2026-08-18 (yet another continuation): sign-up pending-confirmation path verified live

Picked up the one remaining open item that was actually actionable this
session (everything else is blocked on Caelan — dashboard settings,
Stripe, a Mac, checking his own inbox, or the still-unresolved GitHub App
repo access for `Quiet-Cafe-App`, re-checked and still 404 via the GitHub
connector).

Started the `Pixel_API_36` emulator, ran the app with the full
`SUPABASE_URL`/`SUPABASE_ANON_KEY`/`GOOGLE_WEB_CLIENT_ID` dart-defines, and
drove it via `adb` screenshots + `input tap`/`input text` (no direct-attach
UI tool available in this environment). Logged out of the real
`maxon.caelan@gmail.com` session first (confirmed via the Account screen),
then went through Create account → Sign up with email using
`maxon.caelan+quiettest1@gmail.com` (a plus-addressed alias of Caelan's own
inbox, not a new external address) and a policy-valid password.

No rate limit hit this time. Got back exactly "Check
maxon.caelan+quiettest1@gmail.com for a confirmation link, then sign in."
and landed back on the Sign in screen — the `false` +
`onPendingConfirmation` leg of `CreateAccountPasswordScreen`'s pop-cascade,
previously only reasoned-through from code. Confirmed via SQL against
`auth.users` that the row exists with `email_confirmed_at: null`, matching
the UI message exactly. Deleted the test user (`auth.identities` then
`auth.users`) afterward to leave no residue, same pattern as prior
sessions' test cleanup.

Not exercised: the other leg of the pop-cascade (`true`, immediate
session — happens when email confirmation is off, which it isn't for this
project).

**Update, same session: the click-through half is now resolved too.**
Caelan pointed at [10minutemail.com](https://10minutemail.com) as a
disposable inbox this agent *can* actually reach (via the browser tool),
which removes the "needs Caelan's own inbox" blocker entirely. Repeated
the signup with a fresh 10minutemail address
(`pjtfpehbjtxlqnzmrk@vtmpj.net`), got the same "check your email" screen,
then read the real confirmation email in the browser and pulled the actual
link Supabase sent: `.../auth/v1/verify?token=pkce_...&type=signup&redirect_to=quietrestaurantfinder://login-callback`.

Opened it via `adb shell am start -a android.intent.action.VIEW -d '<url>'`
on the emulator, not the desktop browser — the point was to exercise the
real deep-link handoff (Supabase verify → 302 redirect →
`quietrestaurantfinder://login-callback` → Android routes it to the
installed app), which a desktop browser can't do. First attempt hit
`{"code":400,"error_code":"validation_failed","msg":"Verify requires a
verification type"}` — not an app bug, an `adb shell` quoting bug: passing
the URL in double quotes let the device's remote shell treat the bare `&`
characters as its own job-control operator, truncating the command at the
first `&` and dropping `type=signup` before it ever reached Supabase.
Fixed by wrapping the URL in single quotes for the remote shell
(`adb shell "am start ... -d '$URL'"`). Retried and the app came back to
the foreground on its own — confirmed via SQL that `email_confirmed_at`
flipped from `null` to a real timestamp. Then signed in with that same
account through the UI and landed on an unlocked Search Assistant,
verifying signup → email confirmation → deep link → sign-in as one
continuous, real chain for the first time. Deleted the test user
afterward, same cleanup pattern as before.

Left the emulator logged out at the end of this session (both the real
account and the final test account were signed out; nothing was left
signed in).

**Attempted the same session to extend this to the forgot-password
click-through** (the sibling open item below), reusing the same
10minutemail address. Hit `email rate limit exceeded` on the second
signup attempt with that address — Supabase's built-in email sender
shares one low per-hour rate limit across every auth email type (signup
confirmation, password recovery, etc.), and the two confirmation emails
already sent this session used most or all of it. Confirmed no partial
user row was left in `auth.users` for that attempt — Supabase rejected the
whole signup, not just the email send, so nothing needed cleanup. The
forgot-password click-through is unblocked in principle (same proven
mechanism) but still needs an actual run once the rate limit window
resets.

## Session — 2026-08-18 (yet another continuation): web support — routing, responsive shell, mic gating, Cloudflare Pages deploy

Caelan asked for the app to work as a web app too, reachable through a URL,
with device/OS-aware behavior. Established up front that CSS media queries
can't do device/OS detection (they read viewport/rendering capabilities,
not identity) — the actual mechanism is `kIsWeb` + `defaultTargetPlatform`
from `package:flutter/foundation.dart`, which Flutter web already derives
from the browser's own UA. Scoped to three goals: adaptive layout, an
OS-aware "get the app" prompt, and gating off the in-app mic reading
(native-only). Planned in plan mode; Caelan explicitly asked for the full
persistent-shell + router rewrite rather than a scoped-down per-screen
patch, and for Cloudflare Pages deployment to be part of this work, not a
follow-up. Full plan and reasoning: `~/.claude/plans/deep-stargazing-fairy.md`
(outside this repo, session-local).

**Router migration.** The app had no router before this — plain
`MaterialApp`, imperative `Navigator.push`/`pushReplacement` across 11
files. Moved to `go_router` (`lib/router.dart`), giving every one of the
20 screens a real, bookmarkable URL (`/list`, `/restaurant/:placeId`,
`/settings/permissions`, etc.) — this is also literally what "web app
through the URL" requires, not a separate concern from the shell work.
`/restaurant/:placeId` fetches by id (new
`SupabaseService.fetchRestaurantByPlaceId`, mirroring the existing
`fetchRankedRestaurants` pattern) when opened directly with no in-memory
`Restaurant` available — otherwise a URL paste or browser refresh would
silently break, which would have made the URLs cosmetic rather than real.
All 13 files with `Navigator` calls were migrated (`context.push`/`.pop`/
`.go`, preserving every `push<bool>`/`pop(result)` chain exactly — the
multi-screen sign-up flow's `onPendingConfirmation` callback and email
threading through `/sign-up` → `/sign-up/email` → `/sign-up/password`
now travels via go_router's `extra`, including a Dart record type for the
two-value case). `usePathUrlStrategy()` (`flutter_web_plugins`) keeps URLs
as plain paths, not hash-prefixed.

**Persistent shell — the point Caelan corrected mid-plan.** First draft
scoped the wide-screen `NavigationRail` to only the 5 nav-bearing
screens, matching where the existing `Drawer` shows today. Caelan said
that was out of scope and wanted the real thing: a root `ShellRoute`
(`lib/widgets/app_shell.dart`) wraps *every* route, so the rail is
visible on wide layouts even during auth flows, restaurant detail, or
settings sub-screens — not just the 5. Below `kWideLayoutBreakpoint`
(840, `lib/utils/breakpoints.dart`), each screen keeps its own `Drawer`
exactly as before — confirmed live on the Android emulator afterward
that mobile visuals and navigation are byte-for-byte unchanged (drawer
order, detail screen layout, mic button all identical to pre-change
screenshots). `lib/widgets/app_nav_destinations.dart` is now the single
source of truth for the 5 top-level destinations, shared by `AppDrawer`
and the new `AppNavRail` so they can't drift apart — `AppDrawer` itself
shrank from 5 hardcoded items to a loop, with `AppRoute` re-exported from
it (moved to `app_nav_destinations.dart`) so the 5 screens that only
imported `app_drawer.dart` for that enum didn't all need new imports.

**Mic gating.** `restaurant_detail_screen.dart`'s single "Take a reading
here" call site got a `kIsWeb` branch — web shows "Take a reading in the
app" leading to a new shared `showGetAppPrompt` bottom sheet instead of
dead-ending. `permissions_settings_screen.dart`'s Microphone toggle is
hidden (not disabled) on web — a greyed toggle would have implied an
OS-permission state that doesn't exist there. `mic_reading.dart`'s
previously-unconditional `dart:io Platform` import (the actual web-compile
blocker) was replaced with `kIsWeb`/`defaultTargetPlatform`, adding a
`'web'` platform value that's normally unreachable now that capture
itself is gated. Voice search (`speech_to_text`) was deliberately left
alone — it already has real web support, a different feature from mic
decibel metering.

**"Get the app" banner.** New `download_app_banner.dart` (OS detection,
no new package), `download_banner_service.dart` (dismissal persisted via
`SharedPreferences`, mirroring `theme_service.dart`'s pattern), and
`store_links.dart` — the store URLs are explicit placeholders (`idTODO`),
since the app isn't published to either store yet. Shown globally via
`MaterialApp.router`'s `builder:` slot, not per-screen.

**Cloudflare Pages deploy.** New `.github/workflows/deploy-web.yml` —
this repo's first CI pipeline — builds `flutter build web --release` and
deploys via `wrangler pages deploy`. `web/_redirects`
(`/* /index.html 200`) added for SPA fallback so direct-URL loads don't
404 at the CDN. None of the account-side setup is done — no Cloudflare
API token, no GitHub secrets, no Pages project — all documented as
ordered steps in `PLATFORM_SETUP.md`'s new "Web" section, explicitly
Caelan's to do. Flagged, not resolved: the existing "Site URL should
become `https://cafequiet.com`" open item conflicts with this work's
`https://app.cafequiet.com` redirect need — one Supabase field, two
different asks — left as an open decision for Caelan once the marketing
site's own hosting is real.

**Verification.** `flutter analyze`: 0 issues (one round-trip fixing 5
files that referenced `AppRoute` only via `app_drawer.dart`'s now-moved
definition). `flutter build web --release`: succeeded — the strongest
single signal here, since Dart's type system would reject almost any
mistake in the 20-route table, the record-typed `extra`s, or the
`fetchRestaurantByPlaceId` wiring. Ran `flutter run -d web-server` and
drove it via the browser tool: confirmed a clean boot (Supabase init
completes, zero console errors) on both `/` and a direct
`/restaurant/<real-id>` load, and confirmed `usePathUrlStrategy` actually
keeps the address bar on the plain path with no redirect or 404. **Could
not get full pixel/semantics-level confirmation of the web UI in this
session** — the browser tool's own screenshot action failed with "the
page is not compositing frames," and CanvasKit (Flutter web's renderer)
never painted a canvas element despite a clean, error-free boot; a manual
`fetch()` to Supabase and to `gstatic.com` (CanvasKit's CDN) both
succeeded from the page, so this reads as a WebGL/compositing limitation
of this specific sandboxed browser tool, not a code defect — but it means
the web UI's actual visual layout (rail/drawer swap, banner rendering,
max-width constraints) is unverified beyond code review and the
successful compile. Worth a real visual pass (a normal desktop browser,
or once deployed) before calling the web UI itself done, separate from
"does it build and boot," which is confirmed. Mobile regression check was
thorough and fully visual (Android emulator, `Pixel_API_36`): drawer,
sign-in chain (push → nested push → back), and a full restaurant-tile →
detail-screen navigation with the mic button intact, all screenshotted
and matching pre-change behavior exactly.

Work is on `feature/web-support`, branched from `docs/session-mistakes-and-updates`
(itself already pushed). Not yet pushed or PR'd — see below.

## Session — 2026-08-19: Cloudflare Pages deploy — live, after three real fixes

Caelan carried out the GitHub-secrets and Cloudflare setup from the prior
session's "Web" section himself and ran the deploy live, pasting the
actual GitHub Actions error logs back each time something broke. Three
real bugs, not user error, found and fixed this way — none of them were
verifiable without a real deploy attempt:

1. **`deploy-web.yml` was at the wrong path entirely.** Placed inside
   `app/.github/workflows/` in the prior session, but this repo's true
   root is the ICM workspace (`app/` is a subdirectory several levels
   down) — GitHub Actions only ever reads workflow files from the actual
   repo root, so it silently never saw the workflow at all; the Actions
   tab showed the "Get started" onboarding page instead. Fixed on
   `fix/workflow-location` (PR #3, merged): moved the file to the real
   root `.github/workflows/`, added a job-level `working-directory`
   default (`stages/03_build/output/app`) for the `run:` steps, kept the
   wrangler deploy path as a full path from root since `uses:` steps
   don't inherit that default. Logged as mistake
   `workflow-file-placed-in-wrong-repo-root`.
2. **Cloudflare API token permissions were incomplete.** Documented (and
   Caelan created the token) with only `Pages: Edit`. First real deploy
   failed with `Authentication error [code: 10000]` / "Unable to
   retrieve email for this user" — Wrangler's own login check also needs
   `User → User Details → Read`, undocumented in Cloudflare's own token
   template gallery (there's no dedicated Pages template there at all;
   has to be a Custom Token). Caelan added the permission to the
   existing token without regenerating it. Logged as mistake
   `cloudflare-token-permission-incomplete`.
3. **`wrangler pages deploy` doesn't auto-create the Pages project.**
   PLATFORM_SETUP.md's "Web" section assumed it would; second real
   deploy attempt failed with `Project not found ... [code: 8000007]`.
   Fixed on `fix/deploy-create-pages-project` (PR merged): added a
   `continue-on-error` `wrangler pages project create` step before the
   deploy step, so the project is created explicitly on first run and
   the step is a harmless no-op every run after. Logged as mistake
   `cloudflare-pages-project-assumed-auto-created`.

**Verified live afterward** (this was also the first real visual
confirmation of the web build — the prior session's sandboxed browser
tool couldn't composite/screenshot at all): navigated to
`https://quiet-restaurant-finder.pages.dev` (Cloudflare's default
`.pages.dev` URL, live before any custom domain is attached) — clean
boot, `flutter-view` present, no console errors. Also loaded
`https://quiet-restaurant-finder.pages.dev/list` directly (not via
in-app navigation) and got the app, not a 404 — confirms `web/_redirects`
(`/* /index.html 200`) actually works on Cloudflare Pages, so direct
URLs/bookmarks/shares will work for real users, not just in principle.

**Still open, both Caelan's**: attach the `app.cafequiet.com` custom
domain in the Cloudflare Pages project (Custom domains tab), and add
`https://app.cafequiet.com` to Supabase's Redirect URLs — see the Site
URL conflict item below, unresolved until the marketing site's hosting
is also real.

## Session — 2026-08-19 (continued): cafequiet.com parking-page incident, Supabase Site URL set, Greater NSW scope expansion + cuisine display formatting

**cafequiet.com briefly served an unrelated ad-tech/parking page.**
Investigated live: DNS had fully delegated to Cloudflare as intended, but
the zone's `A` records for `cafequiet.com`/`www.cafequiet.com` pointed at
`27.124.125.171` — a leftover Crazy Domains default-parking record that got
auto-imported during the 2026-08-17 "Scan DNS Records" nameserver
migration and was never replaced once real hosting was planned. Cloudflare
audit log checked directly, not assumed: every action traced to
`maxon.caelan@gmail.com` or `system`, ruling out account compromise. Caelan
deleted the stale proxied `A` records and separately turned on Domain Lock
at the registrar (found off, an unrelated but real transfer-risk exposure).
DNS resolution confirmed clean afterward (`nslookup` returns no addresses,
correct until real hosting is pointed at the apex).

**Supabase Auth's Site URL set to `https://cafequiet.com`**, closing the
open item from two sessions ago. Resolved as "no real conflict" rather than
picking a winner under duress: Site URL is the fallback/email-template
variable, Redirect URLs is the separate explicit allow-list —
`https://app.cafequiet.com` and `quietrestaurantfinder://login-callback`
both stay in Redirect URLs untouched. Confirmed saved live (value survived
a page reload).

**Two real product issues found by Caelan using the live web build,
became this session's main focus:**

1. **Suburb filter always showed only "All suburbs."** Root cause: Google
   Places' `normalizePlace()` in `data-pipeline/src/places.js` never set
   `suburb` at all for live-fetched data — the field existed in the schema
   and the Flutter model, but nothing ever populated it outside the sample
   dataset. `whereType<String>()` in `home_screen.dart`'s suburb-options
   derivation silently dropped every null, leaving only the built-in "All
   suburbs" option. Fixed by adding `places.addressComponents` to the
   `places-search` Edge Function's field mask (no SKU-tier cost increase —
   already at Enterprise+Atmosphere for reviews) and extracting the
   `locality`/`sublocality` component as `suburb` in `places.js`
   (`extractSuburb()`, tested).

2. **Cuisine values rendered raw** (`french_restaurant`, not "French
   Restaurant") in the list tile and the cuisine filter dropdown. Per
   Caelan, explicitly **not** a backend/Supabase data change — added
   `humanizeSnakeCase()` (`app/lib/utils/text_format.dart`, tested) and
   applied it only at render time in `restaurant_tile.dart` and
   `home_screen.dart`'s `_FilterBar`; the underlying `cuisine` value used
   for filtering/comparison is untouched.

**Scope expanded from "Sydney only" to Greater Sydney + Dubbo + Newcastle +
Moss Vale + Kiama/Illawarra**, confirmed with Caelan this session — see
`_config/decisions.md` "Scope." The pipeline previously ran a single Text
Search query (`"restaurants in Sydney NSW"`, one page, ~20 results max) —
nowhere near this footprint even before the expansion was requested.
Replaced with `data-pipeline/src/searchAreas.js`, a curated list of 63
area queries spanning inner Sydney, the eastern suburbs, inner west, north
shore/northern beaches, the Hills District, western and south-western
Sydney, Sutherland Shire, the Blue Mountains, Central Coast/Newcastle,
west to Dubbo (via Lithgow/Bathurst/Orange), and south to the Southern
Highlands/Illawarra. `searchRestaurants()` in `places.js` now paginates up
to 3 pages per area (Google's `nextPageToken`, with the same short delay
the legacy Places API needed before a fresh token is valid) and
`pipeline.js`'s new `searchAllAreas()` runs the full list, deduping by
`placeId` across areas (a venue near a suburb boundary can legitimately
turn up under more than one query).

**Not run live this session.** 63 areas × up to 3 pages each is a real
range of billed Google Places requests (worst case ~1,900, realistically
far fewer since most areas won't fill 3 pages) — this hits Caelan's Google
Cloud billing directly, so the actual pipeline run against production is
being left for Caelan to kick off (or explicitly greenlight) rather than
run unattended. Once run, expect the `restaurants` table to grow
substantially past the current handful of Sydney-CBD rows, and expect the
suburb filter to populate for real for the first time.

**Verification**: `flutter analyze` — 0 issues. `flutter test` — all pass,
including two new suites (`text_format_test.dart`,
`places.test.js` suburb-extraction cases). `npm test` in `data-pipeline` —
29/29 pass. `node --check` on the three touched pipeline files. Nothing
requiring the live Places API or a real device was exercised — the
addressComponents field-mask change and the pagination loop are unverified
against the real API until the first live run.

**Explicitly not done, both flagged for Caelan rather than decided
silently**: the app's AppBar title ("Quietest in Sydney") and README/store
copy still say "Sydney" only, now inconsistent with the wider data
footprint — a branding call, not folded into this data-scope change. The
curated area list is a representative regional spread, not exhaustive
suburb-level coverage; treat gaps found in testing as expected, not bugs.

Work is on `feature/greater-nsw-scope-and-cuisine-display`, branched from
`docs/web-deploy-live` (which itself picked up one more commit this session
closing out the Site URL item, and is still not yet PR'd/merged — see its
open item above). Pushed; not yet PR'd/merged.

## Session — 2026-08-19 (continued again): live pipeline run — real bug found (Edge Function never deployed), fixed, awaiting a clean re-run

Caelan approved the live run, capped at 200 total Places requests (added
`createRequestBudget()` in `places.js` — a shared counter across all areas,
not per-area, so the cap is a real hard ceiling regardless of how many
areas/pages that spans). Ran `npm start` in `data-pipeline/`.

**It ran clean (exit 0) but produced the wrong result.** 1,221 restaurants
were written and upserted to Supabase, but **0 of them had a `suburb`** —
the exact bug this session was supposed to fix. Root cause, found by
comparing the live Edge Function's deployed code
(`get_edge_function` via the Supabase MCP tool) against the local source:
**the `addressComponents`/pagination change to
`supabase/functions/places-search/index.ts` was only ever edited locally,
never actually deployed.** The live function Google was hit through was
still the pre-session version — no `addressComponents` in the field mask
(nothing to extract a suburb from) and no `nextPageToken` in its response
(so `places.js`'s new pagination loop always saw `undefined` and stopped
after page 1 every time, regardless of the `maxPages`/budget logic being
correct). That's also why only 63 of the 200-request budget got used — one
request per area, no pagination ever engaged. Logged as mistake
`edge-function-not-deployed` in `MISTAKES.md`.

The ~63 real Places API requests this run made were still billed for real
— not recoverable, but small (well under the ~$7-8 worst-case estimate
given to Caelan beforehand, likely closer to $2-3 for 63 single-page
requests).

**Fixed**: deployed the corrected function via the Supabase MCP
`deploy_edge_function` tool (now version 5) — confirmed the field mask
includes `addressComponents` and the response includes `nextPageToken`.
Not yet re-run against the live API — holding for Caelan given this is a
second real-money request against his billing, caused by this session's
own deployment miss rather than something new he asked for.

## Session — 2026-08-19 (continued again): suburb backfilled for free from the existing address text, no re-run needed

Caelan pointed out (from a live screenshot of "The Botanist", 17 Willoughby
St, **Kirribilli** NSW) that the suburb is already sitting in plain text
inside `address` on every one of the 1,221 rows from the flawed run — no
need to spend more Places API money re-fetching data already on file just
to get `addressComponents`. Right call, acted on it instead of the planned
paid re-run.

Added `extractSuburbFromAddress()` in `places.js` (tested against the real
shapes found in the dataset, not guessed): the normal
`"<street>, <suburb> <STATE> <postcode>, Australia"` form (1,214 rows) and
a reversed form a handful of Google listings return,
`"Australia, New South Wales, <suburb>, <street>, ..."` (3 rows —
Hornsby, Castle Hill, Narellan). Deliberately returns `null` for anything
that isn't a recognisable Australian address rather than guessing, which is
what caught the next finding.

**4 rows turned out not to be in Australia at all**: the "Picton NSW" area
query also matched restaurants in Picton, New Zealand and Picton, Ontario,
Canada — real namesake towns, not a parser bug (`extractSuburbFromAddress`
correctly returned `null` for all four rather than mis-suburbing them).
Tightened that one query to `"restaurants in Picton, New South Wales,
Australia"` in `searchAreas.js` for future runs. The 4 existing bad rows
are flagged (by `scripts/backfill-suburbs.mjs`'s output) but **not
deleted** — `pipeline_service` has no delete grant by design (see
`supabase.js`), so removing them needs an explicit higher-privilege step;
left for Caelan to confirm before doing that.

New `scripts/backfill-suburbs.mjs`: loads `data/restaurants.json`, fills
`suburb` via `extractSuburbFromAddress()` for every row missing one, writes
the file back, then re-upserts through the existing
`upsertScoredRestaurants()` path (same UPSERT the pipeline always uses —
no schema or query changes needed, no Places API calls made). Run live:
**1,217 of 1,221 rows filled, 119 distinct suburbs**, confirmed directly
against Supabase afterward (`select count(*), count(suburb), count(distinct
suburb) from restaurants` → 1229 total / 1217 with suburb / 119 distinct —
the 1,229 vs. 1,221 gap is pre-existing leftover rows from an earlier,
much smaller demo dataset that this run's area list never touched, harmless
given no-delete).

**Cost of this fix: $0** — zero Places API requests, just local string
parsing and a normal DB write.

**The 4 non-Australian rows were then confirmed and deleted.** Caelan
double-checked the reasoning first (right call, given cascading deletes
aren't reversible) — verified none of the four addresses contain the word
"Australia" anywhere (`New Zealand` × 2, `Canada` × 2, and the postcodes
themselves are non-Australian formats: NZ's `7220`, Canada's `K0K 2T0`, not
a 4-digit AU postcode). Deleted via the Supabase MCP `execute_sql` tool
(`pipeline_service` still has no delete grant — this went through a
higher-privileged path deliberately, as a one-off, not by changing the
pipeline's normal access). `mic_readings` and `favorites` both have
`on delete cascade` on `place_id`, so no orphaned rows either. Confirmed by
the delete's own `returning` clause: all 4 rows gone
(`ChIJddN3Nlc5OW0RdTI0-TxF3G0`, `ChIJIxOnYWw5OW0RJDC2CTu3q_Q`,
`ChIJhehZb03K14kRuAjwco4Vhd4`, `ChIJbWsJDlTK14kRQ5AMXem65-Y`). Local
`data/restaurants.json` filtered to match (1,221 → 1,217 rows).

## Open items carried into further build work
- **~8 old leftover demo rows with no suburb** — added 2026-08-19, low priority. Pre-date this session's area-list run entirely; harmless, just slightly stale given the no-delete design. Worth a one-time cleanup pass if it's ever worth Caelan's time, not urgent.
- **App branding still says "Sydney" only** — added 2026-08-19. AppBar title (`home_screen.dart`) and README/store copy weren't touched when scope expanded to Greater NSW; Caelan's call on whether/how to rename.
- **Search area list is a curated regional spread, not exhaustive** — added 2026-08-19. 63 queries across Greater Sydney/Newcastle/Dubbo/Moss Vale/Kiama, each only pulled page 1 (~20 results) since no area actually needed pagination yet; extend `searchAreas.js` (or swap in a real suburb dataset) if live testing finds a gap.
- **Web UI's actual rendered layout still not visually confirmed** — the live `.pages.dev` boot/routing check above confirms the app *works*, but didn't specifically re-check the rail/drawer swap at different widths, the download banner, or the max-width constraints now that a real browser is available. Worth a specific pass, not just "does it load."
- ~~Cloudflare Pages deployment not set up~~ — resolved 2026-08-19: live at `https://quiet-restaurant-finder.pages.dev`, see session above. Still open: attach `app.cafequiet.com` as a custom domain (Cloudflare dashboard, Caelan's).
- ~~Supabase Site URL conflict~~ — resolved 2026-08-19: Caelan set Site URL to `https://cafequiet.com` (confirmed saved after a page reload); `https://app.cafequiet.com` stays as an explicit Redirect URL alongside the `quietrestaurantfinder://login-callback` scheme. No real conflict — Site URL is the fallback/email-template variable, Redirect URLs is the separate explicit allow-list, so both domains do their own job.
- **Store links are placeholders** — `lib/utils/store_links.dart` has `idTODO`/`id=TODO` App Store/Play Store URLs. Replace once the app is actually published; not something to chase speculatively.
- **`feature/web-support` not yet pushed or PR'd** — same GitHub App repo-access issue as prior sessions (still 404 on this repo via the GitHub connector as of this session). Push happens this session regardless, per the established branch-first pattern; opening the PR is blocked the same way `docs/session-mistakes-and-updates` was.
- ~~Decide what to do about Popular Times~~ — decided 2026-08-15: dropped for v1, code kept dormant.
- ~~Decide whether mic readings need a user identity~~ — decided 2026-08-15: real accounts, submission-gated only. See "Account-gated mic readings" above.
- ~~Whether to add Google/Apple Sign-In~~ — decided 2026-08-15: yes to both. ~~Google~~ — resolved 2026-08-18: Web + Android OAuth clients created, confirmed working end to end on the emulator (real account picker, real credential entry, successful sign-in). iOS client ID still not created — Apple sign-in still waiting on a real device to test.
- ~~Whether to add Facebook (and other) social logins~~ — decided 2026-08-16: Facebook, via `signInWithOAuth`, hidden behind `FACEBOOK_SIGN_IN_ENABLED` until Caelan configures the Facebook provider in Supabase. See "Facebook — free, added 2026-08-16" in `PLATFORM_SETUP.md`.
- ~~Register `quietrestaurantfinder://login-callback` as an Additional Redirect URL in Supabase's Auth → URL Configuration.~~ — confirmed already done as of 2026-08-18 (yet another continuation): a real signup confirmation link's `redirect_to=quietrestaurantfinder://login-callback` was followed live (Supabase verify → 302 → deep link → app foregrounded), which only works if this redirect URL is registered. Still needed for Facebook sign-in specifically once that provider is configured (separate, still open below).
- ~~Whether to add per-account rate limiting on readings, now that real identity exists~~ — resolved 2026-08-18: 30-second cooldown between submissions from the same account, enforced server-side. See "per-account rate limiting on mic readings" above.
- **GitHub branch protection on `main` still not set up as an actual repo setting** — no authenticated path to github.com in the 2026-08-18 session (Claude-in-Chrome needed re-auth, no `gh` CLI, no token). Caelan chose a standing behavioral rule (branch + PR, never push to `main` directly) instead for now; revisit setting the real GitHub setting when there's an authenticated path available.
- ~~Rate-limit cooldown message not click-tested end to end on-device~~ — resolved 2026-08-18 (continuation): triggered live by submitting two readings within 30s on-device, got back the exact expected message. See "mic crash found and fixed, rate-limit UX click-tested" above. Found and fixed an unrelated but real crash along the way (silent/invalid mic samples producing `-Infinity` → uncaught `.round()`), same session.
- ~~New sign-up success path not click-tested~~ — resolved 2026-08-18 (yet another continuation): rate limit had cleared, retested live. See "sign-up pending-confirmation path verified live" below.
- ~~Email can be changed from the Account screen~~ — resolved 2026-08-18: removed entirely, per Caelan (a new email is effectively a new account). See "email is now immutable" above.
- ~~No way to reset a forgotten password~~ — resolved 2026-08-18: standard Supabase email-recovery flow added. See "forgot-password flow added" above. **Partially click-tested on-device** — rebuilt and ran on the Android emulator (`Pixel_API_36`), verified live: the Email row on Account is no longer tappable, the "Forgot password?" link renders and opens the dialog, and submitting a real address gets Supabase's actual "check your email" confirmation back. **Still open**: the click-through half — tapping the real emailed link and landing on `ResetPasswordScreen` via the deep link. No longer blocked on Caelan's inbox specifically (2026-08-18, yet another continuation, proved the same `quietrestaurantfinder://login-callback` deep-link mechanism works end to end using a 10minutemail.com disposable address + `adb shell am start ... -d '<url>'` for the signup-confirmation link — see "sign-up pending-confirmation path verified live" below); the password-reset link just hasn't been re-tested the same way yet.
- **Move Supabase Auth off its built-in email sender to Resend (custom SMTP), waiting on Cloudflare DNS propagation.** Decided 2026-08-18 (yet another continuation) after Supabase's shared per-hour email rate limit blocked the forgot-password click-through test twice in one session — see the `email rate limit exceeded` note above. Caelan created a Resend account and generated an API key. Two steps remain, both Caelan's: (1) verify `cafequiet.com` as a sending domain in Resend by adding the SPF/DKIM records Resend provides to Cloudflare DNS — required, since Resend won't deliver to real recipients from an unverified domain, only back to the account owner's own address; currently waiting on that DNS propagation. (2) Once verified, take the SMTP credentials (`smtp.resend.com`, port 465, username `resend`, password = the API key) into Supabase Dashboard → Authentication → Emails → SMTP Settings and enable Custom SMTP with a sender address on the verified domain (e.g. `noreply@cafequiet.com`). Neither step is doable from this session — SMTP settings and DNS records are both dashboard-only, same pattern as the password-policy setting. Once done, retry the forgot-password click-through test (still separately open above) to confirm delivery actually works end to end.
- Exact score-weighting constants (`DEFAULT_WEIGHTS`, `PLATFORM_WEIGHT`, and now `REVIEW_MENTION_TIERS`/`MIC_READING_TIERS` in `scoring.js`) — starting values per ranking-spec.md, need tuning against real usage data.
- ~~Flutter app not yet compiled~~ — resolved 2026-08-16: `flutter pub get`/`analyze`/`test` all ran clean, and `flutter run -d edge` confirmed the app renders live Supabase data correctly. ~~Android build/device run~~ — resolved 2026-08-17: full Android toolchain set up, real emulator created, app built and run on it, verified visually (see "first real run" above). Still needed: iOS build (needs a Mac — no workaround, unrelated to the Android work). ~~Completing a real sign-in + mic-reading submission through the UI on-device~~ — resolved 2026-08-17: full flow verified for real (signup → email confirmation → sign-in → mic capture → submission → pipeline aggregation), see "real sign-in + mic-reading verified on-device" above.
- ~~Clear the 4 seeded demo rows from the live `restaurants` table~~ — done this session (2026-08-16, continued): confirmed the 4 rows were exactly the known sample set, then deleted. Table is at 0 rows now — needs real pipeline data before the app has anything to show.
- ~~Minor UX gap: no "no restaurants yet" message when `restaurants` has zero rows~~ — fixed this session: `home_screen.dart` now shows an empty state instead of a bare filter bar.
- ~~Confirmation-link `otp_expired` error~~ — the redirect infrastructure it needed is now built (2026-08-16, continued again), reusing the same deep link set up for Facebook sign-in. Not fully resolved yet: needs Caelan to register the redirect URL in Supabase's dashboard (see item above), and needs live device verification either way.
- ~~Live Places/Yelp/Outscraper API calls have not been exercised~~ — Places resolved 2026-08-17: real key wired through the new `places-search` Edge Function, live-tested, 20 real Sydney restaurants loaded into `restaurants`. Yelp: paused (see "Yelp paused" above), not exercised by design. Outscraper: stays dropped, not exercised by design.
- **Real signal volume is thin right now** — every currently-loaded restaurant has `quietness_score: null` because real review-mention counts and mic readings haven't reached the minimum threshold yet, not because of a bug (verified 2026-08-17). Expected to resolve naturally as mic readings and richer review data accumulate; nothing to fix.
- ~~Android SDK/Android Studio not installed~~ — resolved 2026-08-17: Caelan installed Android Studio; cmdline-tools, licenses, a system image, and one AVD (`Pixel_API_36`) set up in this environment. See "first real run" above.
- ~~Anthropic API key needed from Caelan~~ — resolved 2026-08-17: added to Supabase Function Secrets (dashboard, not shared in chat). `search-assistant` Edge Function deployed, live-tested via curl and on-device.
- **Stripe account needed from Caelan** — blocks Donate from doing anything real. Explicitly paused by Caelan for closer to launch. See `ui-design-decisions.md`.
- Push notifications — no infrastructure exists yet; the Settings toggle is UI only until this is built as its own feature.
- Privacy Policy / Terms of Service — content doesn't exist yet; not something to draft speculatively. (Open Source Licenses is real now — wired to Flutter's built-in `showLicensePage`, no content gap there.)
- ~~"Report a problem" destination undecided~~ — resolved: defaults to a `mailto:` link via `url_launcher`, implemented in `widgets/app_drawer.dart`.
- ~~The Supabase redirect-URL registration was unverified live~~ — resolved 2026-08-17: confirmed via a real signup's actual confirmation email (`redirect_to=quietrestaurantfinder://login-callback`), not a synthetic test. ~~Google sign-in unverified~~ — resolved 2026-08-18, see above. Facebook sign-in remains unverified — provider not configured in Supabase yet, button doesn't render.
- The dark-mode-on-resume curiosity noted above — not investigated, low priority, theme system itself works correctly.
- Whether to also replace the "Score breakdown" section's raw 0-100 subscore numbers (Microphone readings, Review mentions, Popular times) with categories, now that the main quietness display no longer shows numbers — deliberately not done without being asked; Caelan's call.
- **Check `cafequiet.com` again later** — DNS delegation to Cloudflare confirmed (Google's public resolver sees the new nameservers/IPs already), but propagation isn't complete everywhere yet: this machine's local resolver was still returning the old Crazy Domains IP as of 2026-08-17. Normal — can take up to ~48 hours. Also worth Caelan confirming the domain shows "Active" under the Cloudflare Pages project's Custom domains tab, which is a separate check from propagation.
- **Update Supabase Auth's Site URL from `http://localhost:3000` to `https://cafequiet.com`** — the domain is confirmed and purchased, this is now fully unblocked, dashboard-only, Caelan's to do. Nothing else needed for just this field.
- **Universal Links (iOS) / App Links (Android)** — planned, see "Universal Links planned ahead of the domain" / "domain confirmed — cafequiet.com" above and `PLATFORM_SETUP.md`. Domain itself is no longer the blocker; still needs real hosting pointed at `cafequiet.com` (currently sits on the registrar), the paid Apple Developer Program (for a Team ID), and an Android release signing key (for the SHA-256 fingerprint).
