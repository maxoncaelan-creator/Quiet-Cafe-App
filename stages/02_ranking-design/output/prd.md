# PRD — Quiet Restaurant Finder

Workspace: [[quiet-restaurant-finder/CONTEXT|Quiet Restaurant Finder]]
Stage: [[quiet-restaurant-finder/stages/02_ranking-design/CONTEXT|02 Ranking design]]
Input: [[quiet-restaurant-finder/stages/01_research/output/research-brief|Research brief]]
See also: [[quiet-restaurant-finder/stages/02_ranking-design/output/ranking-spec|Ranking spec]] (scoring detail), [[quiet-restaurant-finder/stages/02_ranking-design/output/data-schema|Data schema]] (field-level detail)

## Objective
Help people in Sydney find restaurants where they can hear each other talk. The app ranks restaurants by how quiet they are, using two combined signals: review-text mining and first-party crowdsourced microphone readings from app users. (A third signal, Google Popular Times, was designed but dropped for v1 — see "Assumptions and constraints".)

## Problem statement
Noise level is one of the hardest things to judge about a restaurant before you arrive. Star ratings and photos say nothing about it. People who care about a quiet meal — for conversation, for a work meeting, for sensory sensitivity — currently have no reliable way to check this in advance. No mainstream app in Sydney solves this directly.

## Target users
Anyone choosing a restaurant in Sydney who wants to know the noise level before they book or walk in. Includes people with hearing loss or sensory sensitivity, people wanting a conversation-friendly date or work meeting, and anyone who has been burned by a restaurant too loud to talk in.

## Scope
- City: Sydney, NSW.
- Platform: iOS and Android, built with Flutter (decided 2026-08-15).
- Backend: Supabase (decided 2026-08-15) — stores restaurant/score data and crowdsourced mic readings.
- Account required to submit a mic reading; browsing the ranked list stays open to everyone, no account needed (decided 2026-08-15).
- One version of the ranking, not personalized per user, for v1.

## Quietness score
The score combines two signals per restaurant: review-text noise mentions and crowdsourced microphone readings from app users. Each produces a normalized sub-score; the combined score is a weighted average, weighted toward the microphone signal where it exists since it's the most direct measurement, with iOS readings trusted more than Android readings (iPhone hardware is uniform; Android accuracy varies by device). New restaurants fall back to whichever signal they have until microphone data builds up. Full scoring logic, weighting, and cold-start handling: [[quiet-restaurant-finder/stages/02_ranking-design/output/ranking-spec|ranking spec]].

## Data schema (restaurant record)
Each restaurant record carries identity and location fields, per-signal data (review-text mentions, individual microphone readings with platform tagging), and computed sub-scores plus a combined quietness score with a confidence level. The schema also has a dormant Popular Times section, kept but unpopulated — see data schema. Field-level detail: [[quiet-restaurant-finder/stages/02_ranking-design/output/data-schema|data schema]].

## Ranking and sorting
Restaurants are ranked by combined quietness score, quietest first. Users can filter by cuisine, price, suburb, and time of day, since noise varies by hour and the microphone data is timestamped for this. Each restaurant's detail view shows the score breakdown, not just a single number, since transparency matters when data confidence varies (e.g. a venue with 2 Android readings vs. one with 50 iOS readings). Detail: [[quiet-restaurant-finder/stages/02_ranking-design/output/ranking-spec|ranking spec]].

## Success metrics
- Number of restaurants with at least one crowdsourced microphone reading, in Sydney.
- Number of active users submitting readings (the app depends on this to work).
- User-reported accuracy: does the app's quietness ranking match what people experience when they arrive?

## Assumptions and constraints
- Users will be willing to grant microphone permission and take a brief in-app reading while at a restaurant. This needs a clear, honest permission prompt (App Store/Play Store requirement) and a low-friction moment to do it.
- No raw audio is recorded or stored — only decibel/amplitude metering levels — for privacy and app-store compliance.
- **Popular Times dropped as a signal (2026-08-15):** built against Outscraper, then confirmed live that 0/100 Sydney restaurants had `popular_times` data — not "sometimes missing" as Outscraper's community forum suggested, but absent across the board for this API right now. The app ships on review-text + microphone only; the code and schema for Popular Times are kept dormant rather than removed, in case this gets revisited (alternative source, or Outscraper restoring the field).
- Google Places API and Yelp Fusion API both require billing/API keys; Yelp's Sydney coverage is thinner than Google's.
- Cold start: a new restaurant will have no microphone data until users submit it. The score must degrade gracefully to the review-text signal until then.
- **Mic readings require a real account (2026-08-15):** email/password via Supabase Auth, prompted only at the moment someone taps "Take a reading" — browsing never requires signing in. Supabase requires email confirmation by default, so sign-up doesn't grant an immediate session; the app tells the user to check their email rather than assuming they're logged in. Google/Apple Sign-In would be better mobile UX (and Apple requires offering Sign in with Apple if any other social login is added) but needs Caelan's own developer accounts to configure — not done in this pass.

## Open questions for stage 3
- Exact weighting formula for combining the signals, and how confidence level (amount of microphone data) affects it.
- ~~Cross-platform framework choice~~ — decided: Flutter (2026-08-15).
- ~~Backend~~ — decided: Supabase (2026-08-15).
- ~~Popular Times~~ — decided: dropped for v1 (2026-08-15).
- ~~Mic reading user identity~~ — decided: real accounts, submission-gated only (2026-08-15).
- Whether to add Google/Apple Sign-In (needs Caelan's developer accounts).
- Whether to add per-account rate limiting on readings now that real identity exists (e.g. cap readings per venue per day) — not built yet, but now possible given accounts exist.
