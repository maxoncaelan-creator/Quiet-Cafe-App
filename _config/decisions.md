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
