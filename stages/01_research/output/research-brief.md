# Research brief — Quiet Restaurant Finder

Workspace: [[quiet-restaurant-finder/CONTEXT|Quiet Restaurant Finder]]
Stage: [[quiet-restaurant-finder/stages/01_research/CONTEXT|01 Research]]

## City
Sydney, NSW, Australia. Confirmed with Caelan on 2026-08-15.

## Platform
iOS and Android. Confirmed with Caelan on 2026-08-15. This follows from the in-app microphone decibel signal below — the app itself is now a data source, not just a consumer of external data, so it needs to run natively on the phones doing the measuring. A cross-platform framework (Flutter or React Native) is worth considering in stage 3 since decibel-metering packages exist for both that cover iOS and Android from one codebase.

## Restaurant data sources (identity and location)

### Google Places API (New)
- **Gives:** Name, address, coordinates, place type, price level, rating, user rating count, opening hours, photos. Good coverage in Sydney.
- **Needs:** Google Cloud API key, billing enabled. Pay-per-request pricing. Standard rate limits apply per project quota.
- **Note:** Does not expose "Popular Times" or any noise attribute officially — see Existing Signals below.

### Yelp Fusion API
- **Gives:** Name, address, coordinates, categories, rating, review count, price level. Yelp's structured business data includes a "noise level" attribute in some markets (needs direct verification for Sydney listings — Yelp's Sydney coverage is thinner than in the US).
- **Needs:** Yelp developer account and API key. Free tier has a daily call cap; production tier requires approval.

### Ruled out
- **TheFork / Dimmi:** Closed its Australian operations in March 2024. Not usable as a live data source.

## Noise signal sources

### 1. Review text mining
- **Google Maps reviews:** The Places API returns up to 5 "most relevant" reviews per place — not enough for reliable noise mining at scale. Full review sets require a third-party scraper (see below).
- **Yelp reviews:** Fusion API returns a small review excerpt per business; same limitation as Google.
- **Approach:** Pull whatever review text is available through the APIs above, then keyword/sentiment-match for noise mentions ("loud," "quiet," "could barely hear," "great for conversation," etc.). For deeper coverage, a scraper (Outscraper, Apify) can pull full review sets, at added cost and with the usual scraping caveats (ToS risk, rate limits, no formal support).

### 2. Decibel / crowdsourced sound data
- **SoundPrint:** Skipped (decided 2026-08-15) — no public API.
- **In-app microphone measurement (decided 2026-08-15):** Instead of relying on a third-party decibel source, the app will measure decibels itself using the user's phone microphone while they're at a restaurant, and crowdsource those readings the same way SoundPrint does — but as our own first-party signal.
  - **iOS:** `AVAudioRecorder` with metering enabled, read via `averagePower(forChannel:)`. Hardware is uniform across iPhone models, so readings are relatively consistent — NIOSH's own iOS sound level meter tested accurate to about ±2 dBA in a reverberant chamber.
  - **Android:** `AudioRecord` or `MediaRecorder.getMaxAmplitude()`. Accuracy varies meaningfully by device because microphone hardware and OS-level gain processing differ across manufacturers — there is no single calibration that holds across all Android phones. NIOSH has stated it isn't currently possible to verify accuracy across the range of Android hardware. This means Android readings should be treated as noisier data than iOS readings, not dropped — the ranking design in stage 2 should account for this (e.g. per-platform confidence weighting, or normalizing relative to a venue's own reading history rather than trusting absolute dBA).
  - **Cross-platform packages:** If the app is built with a cross-platform framework, `noise_meter` (Flutter, wraps both native APIs) or `react-native-sound-level` / `react-native-sound-level-monitor` (React Native) exist and cover both platforms without writing native code twice.
  - **Needs:** Microphone permission on both platforms, with a clear runtime disclosure of why the app needs it (App Store and Play Store review both require a specific, honest purpose string, not a generic one). Needs a moment in the app where the user is prompted to take a reading while seated at the restaurant.
  - **Privacy note:** Only ambient decibel level should be captured, not raw audio — the app should read metering levels or short-lived amplitude samples, not record or store audio itself, to avoid unnecessary privacy exposure and app-store scrutiny.

### 3. Existing signals (popular times / busyness)
- **Google Popular Times:** Not exposed by the official Places API. Decided with Caelan on 2026-08-15 to source this via **OpenSERP** (self-hosted, free), then revised on 2026-08-15 to **Outscraper** (github.com/outscraper) after stage 3 build work confirmed OpenSERP has no dedicated Google Maps/place endpoint at all — it's a generic search-page scraper, so its ability to surface the Popular Times panel was unverified and risky.
  - Outscraper's Google Maps Search API has a purpose-built `popular_times` field per place — a real, documented feature, not a workaround. Confirmed via the official `outscraper` npm package (installed and inspected during stage 3: `googleMapsSearch()` calls `POST /maps/search-v2`).
  - Caveat found during stage 3: Outscraper's own community forum has reports of `popular_times` intermittently not being returned for some places. The pipeline code treats a missing field as "no popular-times signal for this venue" (same graceful fallback as any other cold-start case) rather than failing.
- **Needs:** Outscraper API key (`OUTSCRAPER_API_KEY`), billed per request/credit like Places and Yelp.

## Summary table

| Source | Gives | Needs | Risk |
|---|---|---|---|
| Google Places API | Identity, location, hours, rating | API key, billing | Low — official, stable |
| Yelp Fusion API | Identity, location, rating, possible noise attribute | API key, approval | Low-medium — thinner Sydney coverage |
| Review text (via above APIs) | Noise mentions in review text | Same as above | Medium — limited review volume per call |
| Google Popular Times via Outscraper | Busyness as a noise proxy | API key, billing | Low-medium — purpose-built field, but community-reported gaps for some places |
| In-app microphone (iOS) | Crowdsourced decibel readings, first-party | Mic permission, native metering API | Low-medium — uniform hardware, ~±2 dBA |
| In-app microphone (Android) | Crowdsourced decibel readings, first-party | Mic permission, native metering API | Medium-high — device-dependent accuracy |
| ~~SoundPrint~~ | ~~Purpose-built noise ratings~~ | Skipped | — |

## Decisions (2026-08-15)
- Popular Times data: source via **Outscraper** (revised from an initial OpenSERP decision, same day, after stage 3 build work found OpenSERP has no Maps-specific endpoint).
- SoundPrint: skipped as a data source.
- Decibel data: measured first-party via the app's own use of the phone microphone (iOS `AVAudioRecorder`, Android `AudioRecord`/`MediaRecorder`), crowdsourced from users, instead of relying on a third party.
- Platform: iOS and Android, confirmed — a direct consequence of building our own microphone-based decibel signal.

## Recommendation for stage 2
Build the pipeline on Google Places API + Yelp Fusion API as the identity/location backbone (both officially supported). The quietness score should combine three signals: review-text noise mining, OpenSERP-sourced Popular Times, and first-party crowdsourced microphone decibel readings. The data schema needs to record decibel readings per-platform (iOS vs. Android) so the ranking formula can weight or normalize for Android's wider accuracy variance rather than treating all readings as equally trustworthy.
