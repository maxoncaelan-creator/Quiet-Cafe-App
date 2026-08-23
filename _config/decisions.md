# Confirmed decisions — Quiet Restaurant Finder

Layer 3. Product-level decisions that hold across every stage, updated as
they change. Stage contracts read this rather than restating it.

## Scope

**Seeded coverage is Greater Sydney, plus out to Dubbo, north to Newcastle,
south to Moss Vale, and into the Illawarra as far as Kiama.** Expanded from the original
"Sydney, NSW only" scope, confirmed with Caelan 2026-08-19, after the
suburb filter turned out to only ever show "All suburbs" — see build log
"Greater NSW scope expansion + cuisine display formatting." The pipeline's
`data-pipeline/src/searchAreas.js` holds the 60+ area queries used to cover
this footprint; it's a curated regional spread, not an exhaustive suburb
list (Greater Sydney alone has 600+ gazetted suburbs). GPS-based nearby checks
can also add Google Places around a beta user's current coordinates anywhere
they are, deliberately allowing demand-led coverage to grow beyond the seeded
region. The List screen's AppBar title changed
from "Quietest in Sydney" to "List View" 2026-08-19 (per Caelan); the
README/store copy still says "Sydney" only — **not changed yet, flagged
for Caelan** since that's a separate branding pass.
Platform: iOS, Android, and Web. Web added 2026-08-18, deployed and
confirmed live 2026-08-19 at `https://quiet-restaurant-finder.pages.dev`
(Cloudflare Pages) — `app.cafequiet.com` as the custom domain is still
Caelan's to attach. **Mic-based decibel reading works on web as of
2026-08-19** — previously native-only (the audio_streamer plugin
noise_meter wraps declares no web platform at all); `mic_service_web.dart`
is a from-scratch Web Audio API (getUserMedia + AnalyserNode) capture, not
that plugin, so it's a genuinely different implementation behind the same
`MicService` interface (conditional export in `mic_service.dart`). See
[[quiet-restaurant-finder/stages/03_build/output/build-log|build log]]
"Web support: routing, responsive shell, mic gating, Cloudflare Pages
deploy" and "Cloudflare Pages deploy — live, after three real fixes" for
the original web-support work and its deploy debugging, and "List/detail
screen UI overhaul" for the web mic capture itself, and
`app/PLATFORM_SETUP.md`'s "Web" section for what's still needed from
Caelan.

## Display formatting

**Cuisine values stay raw (lower_snake_case, e.g. `french_restaurant`) in
Supabase and in `restaurants.json`** — only how they're rendered in the app
changed, 2026-08-19, per Caelan: "I don't think we should change that
element in the backend." A `humanizeSnakeCase()` helper
(`app/lib/utils/text_format.dart`) title-cases and space-joins the value at
render time in the restaurant list tile and the cuisine filter dropdown;
filtering/comparison still uses the raw value untouched.

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
  "Loudness votes." **Correction, 2026-08-19**: this was decided and the
  backend (migration, scoring.js) was built and applied live on
  2026-08-18, but the app-side UI (the actual vote buttons) shipped on
  `feature/loudness-votes-and-venue-guess`, a branch that was never
  merged to `main` — so despite this entry reading as done, the Score
  breakdown section was still live in the app until 2026-08-19, when the
  UI was finally wired up (found while doing an unrelated detail-screen
  redesign). Worth checking decisions.md against what's actually merged
  before trusting a "decided/done" entry at face value.
- **Current loudness uses fresh on-site reports first** — decided 2026-08-21.
  A newly submitted Quiet/Normal/Loud vote or completed 10-second microphone
  average is the best account of conditions right now, so it fully controls
  the displayed loudness at first. Its influence then decays linearly over 21
  days toward the venue’s historical aggregate. Mic capture stays on the
  venue detail screen: the first five seconds show only “Listening,” the next
  five show a Quiet/Normal/Loud assessment of the first five-second average,
  and the final UI shows only the complete 10-second average. A user cannot
  stop that capture early, and Postgres rejects every new venue mic row that
  does not attest to at least 10,000 ms of capture.
- **Mic calibration** — decided with Caelan 2026-08-19. An average human
  speaking voice measures ~60 dBA; every signed-in user is walked through a
  "say something" screen (`mic_calibration_screen.dart`) once on their
  first sign-in and again every ~3 months (90 days — a calendar-month
  interpretation was possible but not specified, flagged as a judgment
  call), comparing their recording against that reference. The resulting
  per-user offset (`scoring.js`'s `calibrationOffset`) corrects that user's
  future ambient mic readings before they're weighted into `micSubscore` —
  a chronically loud- or quiet-reading phone shouldn't just make every
  venue that user visits look noisier or quieter than it is. Triggered from
  `main.dart`'s global auth-state listener (`signedIn` and
  `initialSession` events — the latter is what makes the periodic recheck
  work without needing an actual new sign-in), not gated to one screen.
  **Skippable** — a "Skip for now" action, not a hard block; not explicitly
  specified either way, flagged as a judgment call matching this app's
  general pattern of never force-gating a screen the user can't get past.

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

## Google Places spend

**Stay inside Google's free tier until user numbers justify paying.** Confirmed
with Caelan 2026-08-23. The ceiling is **1,000 Places requests per UTC month**,
held as an editable row in `places_budget_config` and set by
`20260823110000_free_tier_places_ceiling.sql`.

1,000 is not arbitrary: `places-search` requests `places.reviews`, which Google
bills as Text Search **Enterprise + Atmosphere** — about 1,000 free requests a
month, then roughly $40 per 1,000. So 1,000 is the largest ceiling with an
expected marginal cost of zero. An earlier figure of 8,000 would have been
roughly $280/month against a stated budget of $10.

**Review the ceiling at** 50, 100, 300, 500, 1000, 5000 active users, and every
10,000 thereafter. When raising it becomes worthwhile, prefer the
discovery/enrichment split in
[`PLACES_COST_PROPOSAL.md`](../stages/03_build/output/supabase/PLACES_COST_PROPOSAL.md)
over simply buying more calls — it raises coverage per dollar rather than spend.

**No further full seed runs are planned** — confirmed with Caelan 2026-08-23.
Coverage grows through automated sweeps only. This matters because it is what
makes "stay free" achievable: the ledger counts Google traffic through the
`places-search` Edge Function, while `data-pipeline/src/places.js` calls Google
directly and is invisible to it. A full seed run is far larger than 1,000
requests and would blow the free allowance on its own. With seeding retired,
the ledger is in practice the whole bill.

If a seed run is ever needed again — a new region, a rebuild — treat it as a
deliberate, budgeted exception rather than routine work, and expect it to
exceed the free tier regardless of what the ceiling says.

**Changing the ceiling is a data change, not a migration edit.** Editing an
already-applied migration does nothing — that is precisely how production came
to hold 300 while the repository claimed 8,000 (PR #46, corrected 2026-08-23).
Update the row, or add a migration that does, and
`places_budget_ceiling.test.sql` will hold the settled value honest.

## Domain

`cafequiet.com` — purchased by Caelan, confirmed 2026-08-17. DNS fully
delegated to Cloudflare as of 2026-08-19 (nameservers confirmed via direct
lookup, not assumed) — no longer sitting on the registrar (Crazy Domains)
the way it was when this section was last accurate.

**Parking-page incident, found and resolved 2026-08-19.** The apex and
`www` were briefly serving an unrelated ad-tech/parking page (a
`consentmanager.net` script, a Cloudflare bot-challenge, and hidden
"Intentionally hidden, please ignore" text — flagged to Caelan as a likely
prompt-injection attempt aimed at AI browsing agents, not acted on).
Root cause: stale Crazy Domains default-parking `A` records
(`27.124.125.171`, proxied) that got auto-imported into the new Cloudflare
zone during the 2026-08-17 nameserver migration's "Scan DNS Records" step,
and were never replaced once real hosting was planned — not a compromise;
Cloudflare's audit log was checked directly and every action traced to
Caelan's own account or `system`. Caelan deleted the stale `A` records and
separately enabled Domain Lock at the registrar (found off — a real,
unrelated transfer-risk exposure). If `cafequiet.com` or any subdomain
ever shows unexpected content again, check Cloudflare's DNS records first
— this exact failure mode has already happened once.

**Supabase Auth's Site URL updated to `https://cafequiet.com`**, resolved
2026-08-19 (previously `http://localhost:3000`) — confirmed saved live,
not just submitted. `https://app.cafequiet.com` stays as its own explicit
Redirect URL alongside the app's custom URL scheme; Site URL and Redirect
URLs serve different roles (fallback/email-template variable vs. an
explicit allow-list), so there was never a real conflict between the two
domains once separated that way.

Still open, both Caelan's: attaching `app.cafequiet.com` as the Cloudflare
Pages custom domain (see "Platform" above), and adding both
`https://quiet-restaurant-finder.pages.dev` and `https://app.cafequiet.com`
to the Google OAuth Web client's Authorized JavaScript origins (see
`PLATFORM_SETUP.md`'s Google section — currently blocking Google sign-in
on web entirely). Also still planned: the marketing site (see the
`quiet-restaurant-finder-marketing` workspace) at the apex, and eventually
Universal Links (iOS) / App Links (Android) once real hosting + an Apple
Developer Team ID + an Android signing key all exist — see
`PLATFORM_SETUP.md` "Universal Links / App Links."

## Email delivery

**Moving off Supabase Auth's built-in email sender to Resend (custom
SMTP)**, decided 2026-08-18 (yet another continuation) after Supabase's
shared per-hour rate limit blocked live testing of the forgot-password
flow twice in one session. Caelan created a Resend account and generated
an API key. Two dashboard-only steps remain, both Caelan's: verifying
`cafequiet.com` as a sending domain in Resend (SPF/DKIM records added to
Cloudflare DNS, currently propagating), then entering Resend's SMTP
credentials into Supabase Dashboard → Authentication → Emails → SMTP
Settings. See [[quiet-restaurant-finder/stages/03_build/output/build-log|build log]]
"Move Supabase Auth off its built-in email sender to Resend" for the full
credentials/steps breakdown. Domain verification is required, not
optional — Resend won't deliver to real recipients from an unverified
domain.

## Closed-beta referral gate

**Decided and built with Caelan, 2026-08-20; codes rebound to accounts
2026-08-21.** One referral code per approved requester, single-use per
account, expiring a year after issuance if never redeemed. A requester
submits the marketing site's existing "Request early access" form; Caelan
gets one email with a review link that approves the request on a single
click (originally designed as a GET-renders-a-page/POST-approves split to
avoid a mail-scanner pre-fetch risk, but Supabase Edge Functions turned out
unable to serve real clickable HTML at all — see build log "Resend secrets
set, domain verified" session for that finding); approving generates the
code and emails it to the requester. Repeat requests from the same email
dedupe rather than emailing Caelan twice.

**Codes attach to the signed-in account, not the device that redeems
them** — corrected 2026-08-21 after the original device-bound design
locked Caelan himself out on a second browser using his own real code.
During the closed beta, sign-in is required before anything else in the
app (a temporary override of "browsing never needs an account" below, not
a permanent change); a signed-in account without a redeemed code sees the
code-entry screen, with a "sign out and try another account" way out.
Entering an already-used-elsewhere code hard-blocks with a message, same
as before. See
[[quiet-restaurant-finder/stages/03_build/output/build-log|build log]]
"beta codes rebound to accounts, not devices" for the full design and
what's live-verified (the account-binding RPCs, with real test accounts)
vs. still open (not yet click-tested on a real device/build).

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
a Postgres trigger. Loudness votes have a five-minute cooldown per account and
venue, also enforced by a serializing Postgres trigger; this prevents repeated
votes from dominating a venue’s fresh current-loudness state.

### List-search result recovery

**Confirmed with Caelan 2026-08-22.** The List View remains a local filter of
currently loaded venues; it never silently spends a Google Places request just
because a person types a suburb. When a typed area or selected suburb has no
matches, or its results are not suitable, the List View offers three explicit
choices:

- **Ask Assistant** opens Search Assistant with “Find quiet venues in
  [area]” prefilled, but does not auto-send it. The person remains in control
  before any Assistant tokens are used or a coverage check can be initiated.
- **Find more venues** asks for confirmation that the search text is a suburb,
  then calls the existing `ondemand-topup` backend. Beta access, the daily
  paid-search cap, a five-refresh per-account daily allowance, and the
  24-hour area cooldown remain enforced exclusively by that backend. A
  database reservation serializes each paid claim so concurrent calls cannot
  overspend the shared 20-refresh daily budget. The List View reloads after a
  response and explains whether venues were added, the area was recently
  checked, or coverage was already sufficient.
- **Check 1 km nearby** uses the current GPS fix after the person explicitly
  chooses it. The backend calls Google Nearby Search for that exact circle even
  when local venues already exist, then stores the completed result as a shared
  coordinate checkpoint; another request within 250 m reuses it for seven days.
  Search Assistant makes the same cached 1 km check alongside its existing
  5 km thin-coverage refresh. These coordinate searches have no city or NSW
  restriction, deliberately enabling demand-led expansion wherever users are.
  The checkpoint has no account identifier and is not readable through the
  client Data API. An atomic in-flight reservation prevents two simultaneous
  requests in the same 250 m circle from both spending Google; beta access,
  the shared daily cap, and the five-refresh per-account daily allowance remain
  server-side.

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
GitHub branch-protection rule enforcing this still hasn't been set up —
**update 2026-08-19**: a GitHub connector became available and does
authenticate (`get_me` resolves to `maxoncaelan-creator`), but every
repo-scoped call against `Quiet-Cafe-App` specifically still 404s
(confirmed several times, including immediately after Caelan changed the
app's permissions once) — the GitHub App installation doesn't have this
repo in its access list, or that grant hasn't propagated. So this is still
a behavioral rule, not a platform-enforced one, and PRs still need to be
opened by Caelan from a compare link this agent generates — but the
blocker is now "this repo isn't in the App's access list," a narrower,
more fixable gap than "no authenticated path at all." See `AGENTS.md`'s
"Rules specific to this workspace."

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

## Repository visibility

**Changed 2026-08-20**: Caelan manually changed
[Quiet-Cafe-App](https://github.com/maxoncaelan-creator/Quiet-Cafe-App) from
**Private to Public**, and the run of GitHub failures that had been blocking
work stopped immediately — the repo became visible and interactive in the same
moment.

**Cause.** The authorised GitHub connector has **public-repo access only**.
A private repository is not merely refused, it is invisible: it does not appear
in `search_repositories`, and reads against it come back as *not found* rather
than *not authorised*. That failure shape is what made this expensive to
diagnose — it reads like a broken connector, a wrong owner, or a typo in the
repo name, so the debugging goes looking for those instead. Check repository
visibility **first** when GitHub calls fail against a repo that should exist.

**This was misdiagnosed once already.** A `private: false` reading taken from
the API *after* the change was cited as evidence that visibility had never been
the problem. An observation taken after the state changed cannot testify about
the state before it (`MISTAKES.md`,
`verification-cannot-detect-the-fault`).

**Consequence, still open.** The repo is public as a workaround, not as a
decision anybody made on the merits. While public, the full source, the build
log, `MISTAKES.md`, `AGENTS.md` and the whole PR history are world-readable.
Anything committed while it was private on the assumption it stayed private —
credentials, endpoints, internal notes — is exposed now, and flipping it back
does not un-expose whatever has already been fetched or indexed. Worth an
explicit pass over the history for secrets regardless of which way this lands.

Two ways to close it, Caelan's call:

- **Re-grant the connector private-repo access** (claude.ai connector settings)
  and flip the repo back to Private. This is the durable fix; the current grant
  appears to have been approved for public repositories only.
- **Leave it public** if that was always the intent — it is a consumer app with
  a marketing site in flight, so a public repo may be fine by design. Then this
  stops being a workaround and becomes the decision.

Note that `data-pipeline/.env` holds a real Supabase credential and is
gitignored; that protection is unchanged by visibility, but it is the first
thing to confirm still holds if the repo stays public.
