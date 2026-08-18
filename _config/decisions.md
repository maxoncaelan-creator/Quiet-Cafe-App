# Confirmed decisions — Quiet Restaurant Finder

Layer 3. Product-level decisions that hold across every stage, updated as
they change. Stage contracts read this rather than restating it.

## Scope

One city: Sydney, NSW. Confirmed with Caelan.
Platform: iOS and Android. Confirmed with Caelan.

## Noise signals

Active for v1:
- Review text mining (reviews that mention noise)
- Decibel data — measured first-party via the phone's microphone inside the
  app, crowdsourced from users. Submitting a reading requires a real
  (email/password) account; browsing the ranked list never does. Decided
  2026-08-15.
- Loudness votes (Quiet/Normal/Loud) — decided with Caelan 2026-08-18. A
  lighter-weight alternative to a mic reading, same account gate. If the
  same user submits a mic reading within 5 minutes of a vote at the same
  venue, the mic reading wins for scoring purposes, but the vote is still
  recorded either way. Replaced the detail screen's "Score breakdown"
  section entirely. See [[quiet-restaurant-finder/stages/02_ranking-design/output/ranking-spec|ranking spec]]
  "Signals" and [[quiet-restaurant-finder/stages/02_ranking-design/output/data-schema|data schema]]
  "Loudness votes."

Not active:
- SoundPrint (third-party decibel data) — considered and skipped 2026-08-15
  in favor of first-party in-app microphone measurement.
- Google Popular Times — built against Outscraper (revised 2026-08-15 from
  an initial OpenSERP plan), then dropped the same day after confirming live
  that 0/100 Sydney restaurants had `popular_times` data. Code kept dormant.
  See [[quiet-restaurant-finder/stages/01_research/output/research-brief|research brief]]
  and [[quiet-restaurant-finder/stages/03_build/output/build-log|build log]].

## Data sources

Active for v1: Google Places API (New) — restaurant identity, location, and
reviews. This is the pipeline's only live data source.

Not active:
- Yelp Fusion API — paused 2026-08-17. Yelp dropped its permanent free tier
  (now a 30-day trial then paid per-call plans); Caelan decided v1 runs on
  Google Places only. `data-pipeline/src/yelp.js` is kept dormant (was never
  wired into `pipeline.js` in the first place) in case this gets revisited.

## Domain

`cafequiet.com` — purchased by Caelan, confirmed 2026-08-17. No hosting
pointed at it yet (currently resolves to the registrar, Crazy Domains).
Planned uses: the marketing site (see the `quiet-restaurant-finder-marketing`
workspace), Supabase Auth's Site URL (still `http://localhost:3000`, needs
updating — dashboard-only change, not yet done), and eventually Universal
Links (iOS) / App Links (Android) once real hosting + an Apple Developer
Team ID + an Android signing key all exist — see `PLATFORM_SETUP.md`
"Universal Links / App Links."

## Account & Search Assistant access

**Search Assistant requires sign-in**, decided with Caelan 2026-08-18 — same
account gate as mic readings and favorites. A signed-out user sees an
explanatory message and a Sign in button instead of the chat composer.
Enforced server-side in the `search-assistant` Edge Function (rejects an
unauthenticated caller with 401), not just in the Flutter UI.

**Per-account rate limit: 10,000 tokens per fixed 5-hour window**, decided
with Caelan 2026-08-18, to prevent misuse. Enforced in the Edge Function
against `search_assistant_usage` (a Postgres table, service-role-only
writes). Once hit, the screen shows "Search Assistant is on a break, it
will be available again in [X hours and] Y minutes" instead of the
composer, with the hours part dropped under an hour. See
[[quiet-restaurant-finder/stages/03_build/output/build-log|build log]] for
the implementation and how it was tested without spending the budget.

Mic readings carry their own separate limit, decided the same day: a
30-second cooldown between submissions from the same account, enforced via
a Postgres trigger.

## Password policy

Supabase Auth's password policy requires at least one uppercase letter, one
lowercase letter, one number, and one special character — an intentional,
confirmed setting in the Supabase dashboard (Authentication → Providers →
Email → Password Requirements), not something set by this workspace's code
or migrations. Confirmed with Caelan 2026-08-18 after an initial mix-up:
Supabase's own rejection message dumped the full allowed-character-set
string verbatim, which read as confusing enough that the policy itself
looked wrong. The policy stays as-is; only the *display* was fixed — see
`utils/friendly_auth_error.dart` in the Flutter app and the build log's
"raw-backend-error-shown-to-user" mistake entry.

## Account security

**Google-only accounts can't change a password in the app**, decided with
Caelan 2026-08-18. Supabase actually supports an OAuth-only account adding
a password (`updateUser({password: ...})`), but Caelan chose the simpler
of two options: hide password management entirely for accounts with no
password identity, rather than offer a "set a password" flow. The Account
screen shows "Signed in with Google — manage your password in your Google
Account" instead of "Change password" for these accounts
(`SupabaseService.hasPasswordIdentity`, checking the signed-in user's
`identities` for an `email` provider).

Separately confirmed the same session: Supabase automatically links a
Google identity to an existing password account sharing the same verified
email (checked directly against `auth.identities` for a real test
account) — so an email already used with Google can't end up with a
second, duplicate password account. No code change was needed for that
half; the app's existing "check your email" handling for an ambiguous
`signUp()` response already covers it correctly.

## Location

**The app uses real device GPS location**, added 2026-08-18, for one
specific purpose: guessing which restaurant the user is currently at, on
the Search Assistant screen's empty state ("Are you at X?", within 100m of
a loaded restaurant; declining sets a 30-minute cooldown before asking
again). This is not proximity filtering of the list and does not wire up
the existing Settings → Location GPS toggle — see `ui-design-decisions.md`
"Location" for how these relate. Requires `ACCESS_FINE_LOCATION`/
`ACCESS_COARSE_LOCATION` (Android) and `NSLocationWhenInUseUsageDescription`
(iOS), added to the platform config the same session.

## Git workflow

**Never push directly to `main`.** Decided with Caelan 2026-08-18, after a
commit was accidentally pushed straight to `main` in an earlier session.
Every change goes through a feature branch and a pull request that Caelan
reviews and merges himself (or explicitly asks this agent to merge). A real
GitHub branch-protection rule enforcing this hasn't been set up yet — no
session so far has had an authenticated path to github.com to configure it
— so this is currently a behavioral rule, not a platform-enforced one. See
`AGENTS.md`'s "Rules specific to this workspace."

## Git tracking

**Found and fixed 2026-08-18**: this workspace folder had no `.git` at all,
and no other clone of the repo existed anywhere on this machine — every
code change since the one-time push on 2026-08-16 (which covers almost
everything: the real data pipeline, the confidence system, the noise-level
bar redesign, Google Sign-In, the Account screen, and more) existed only as
local files with no backup. Fixed by wiring this exact folder
(`ICM/workspaces/quiet-restaurant-finder/`) to the existing GitHub history
and pushing everything (commit `ee7efb1`). **This folder is now the real
git working tree** — future sessions should commit and push from here
directly rather than assuming a separate clone exists. Needed
`git config --global core.longpaths true` on Windows first — the generated
Android/Kotlin paths are long enough to hit the default path-length limit
on clone/checkout.

## Source of truth

The app's code is mirrored at
[github.com/maxoncaelan-creator/Quiet-Cafe-App](https://github.com/maxoncaelan-creator/Quiet-Cafe-App)
(pushed 2026-08-16). This workspace remains the source of truth for *why*
each decision was made and for the build log; the GitHub repo is where future
code changes happen.
