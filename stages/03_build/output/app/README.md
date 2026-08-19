# Quiet Restaurant Finder

A Flutter app (iOS/Android/Web) that ranks Sydney restaurants by how quiet
they are, combining review-text mining with first-party decibel readings
crowdsourced from users' phones. The mic-reading feature is mobile-only —
see `PLATFORM_SETUP.md`'s "Web" section for what's different on the web
build.

The full history of *why* this app is built the way it is — research,
ranking design, and a running build log of every session's work — lives in
this project's ICM workspace, not in this repo. This repo is where the code
runs from; the workspace is the source of truth for the decisions behind
it. If you're picking this project back up, start with the workspace's
`stages/03_build/output/build-log.md`, not this file.

## Stack

- **Flutter** — the app itself (`lib/`)
- **Supabase** — Postgres (restaurants, mic readings, favorites, account
  usage), Auth (email/password + Google/Apple/Facebook), and Edge Functions
  (`supabase/functions/`) for anything that needs a server-side secret
  (Anthropic API key, service-role writes)
- **Node.js data pipeline** (`data-pipeline/`) — pulls restaurant and review
  data from Google Places, scores it, writes it into Supabase
- **go_router** — client-side routing for the web build (every screen has
  a real URL); native navigation behavior is unchanged
- **Cloudflare Pages** — hosts the web build, deployed via
  `.github/workflows/deploy-web.yml` on every push to `main`

## Features

- Ranked list of Sydney restaurants by quietness, with cuisine/suburb/price
  filters and voice search
- Restaurant detail view with a confidence indicator; in-app microphone
  reading (rate-limited to one submission per 30 seconds per account) and
  a lightweight Quiet/Normal/Loud vote, both signed-in only and both
  feeding the same quietness score — a mic reading from the same account
  within 5 minutes of a vote takes precedence for scoring
- GPS-based venue guess on the Search Assistant screen ("Are you at X?"),
  signed-in only, with a 30-minute cooldown after declining
- Favorites (sign-in required)
- Search Assistant — a Claude-powered chat for finding a restaurant that
  matches what you're after, gated to signed-in accounts with a
  10,000-token/5-hour budget per account
- Account management: email/password or Google/Apple/Facebook sign-in,
  password reset and change (both re-verified, not just accepted; hidden
  entirely for Google-only accounts), account screen with your own reading
  history

## Running it

```
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=...
```

Without the Supabase dart-defines, the app falls back to bundled sample
data and reading submission is disabled — useful for UI work, not for
anything that touches real data. For the real project's values, Google/
Apple/Facebook sign-in setup, and everything else platform-specific, see
[`PLATFORM_SETUP.md`](PLATFORM_SETUP.md).

For web: `flutter run -d chrome --dart-define=...` (same dart-defines) for
local dev, `flutter build web --release --dart-define=...` for a production
build. **Live at [quiet-restaurant-finder.pages.dev](https://quiet-restaurant-finder.pages.dev)**
(Cloudflare Pages) as of 2026-08-19 — `app.cafequiet.com` as a custom
domain is still pending. Deployment details are in `PLATFORM_SETUP.md`'s
"Web" section.

## Contributing changes

This repo does not accept direct pushes to `main` — every change goes
through a feature branch and a pull request. See the workspace's
`_config/decisions.md` ("Git workflow") for why.
