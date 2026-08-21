# Ranking spec — Quiet Restaurant Finder

Workspace: [[quiet-restaurant-finder/CONTEXT|Quiet Restaurant Finder]]
Stage: [[quiet-restaurant-finder/stages/02_ranking-design/CONTEXT|02 Ranking design]]
Input: [[quiet-restaurant-finder/stages/01_research/output/research-brief|Research brief]]
See also: [[quiet-restaurant-finder/stages/02_ranking-design/output/prd|PRD]], [[quiet-restaurant-finder/stages/02_ranking-design/output/data-schema|Data schema]]

## Signals
Three signals actively feed the quietness score:

1. **Review-text signal** — noise mentions mined from Google Places and Yelp review text.
2. **Microphone signal** — first-party crowdsourced decibel readings submitted by users through the app.
3. **Loudness-vote signal** — added 2026-08-18, per Caelan. A lightweight Quiet/Normal/Loud vote a signed-in user can cast on a venue, without needing to run a mic reading. **Precedence rule:** if the same user submits a mic reading at the same venue within 5 minutes either side of a vote, the vote is excluded from this signal's aggregation — the decibel reading is treated as more trustworthy. The vote itself is still recorded (`loudness_votes`, never deleted), just not counted toward the score in that case. See [[quiet-restaurant-finder/stages/02_ranking-design/output/data-schema|data schema]] "Loudness votes."

A fourth signal, **Popular Times**, was designed and built (Outscraper) but
**dropped on 2026-08-15** after live testing found 0 of 100 Sydney
restaurants had `popular_times` data available — see
[[quiet-restaurant-finder/stages/03_build/output/README|stage 3 README]]
"Outscraper vs. OpenSERP" for the verification. The code (`outscraper.js`)
and this spec's description of it are kept below, dormant, in case
Outscraper restores the field or an alternative source gets pursued later.

### Current on-site loudness (added 2026-08-21, per Caelan)

The combined score below is a **historical venue baseline**. It must not make
a person standing in a loud room see “Moderate” merely because the venue has
usually been quiet. Every newly submitted Loudness vote or completed 10-second
microphone reading is stored as a separate current observation:

- At submission, its sub-score controls displayed loudness at 100% weight
  (Quiet = 100, Normal = 50, Loud = 0; microphone values use the normal dBA
  mapping).
- Its freshness weight decays linearly from 1 to 0 over **21 days**. The
  displayed score then smoothly returns to the historical baseline rather
  than leaving a stale one-off report in control forever.
- A microphone reading from the same account within the existing five-minute
  precedence window remains the current observation in preference to a vote.

```
displayed_quietness = baseline_quietness
  + freshness * (current_observation - baseline_quietness)
freshness = clamp(1 - observation_age / 21 days, 0, 1)
```

The baseline still includes all raw readings and votes for long-term ranking;
the overlay is what makes the app truthful about conditions right now.

## Sub-score normalization
Each active signal is normalized to a 0–100 quietness sub-score (100 = quietest) before combining, since the sources arrive in different units and scales:

- **Review-text sub-score:** ratio of noise-negative mentions ("loud," "couldn't hear," "noisy") to noise-positive mentions ("quiet," "great for conversation," "peaceful") in the mined review text, mapped to 0–100. A venue with no noise-related mentions at all gets no sub-score (excluded from this signal, not scored as neutral) until it has at least a small minimum mention count.
- **Microphone sub-score:** derived directly from crowdsourced decibel readings. Raw dBA is mapped to a 0–100 scale using SoundPrint's public banding as a reference point (quiet below 70 dBA, moderate 70–75, loud 75–80, very loud above 80), inverted so quieter dBA gives a higher sub-score.
- **Loudness-vote sub-score:** each vote maps directly to a fixed point on the 0–100 scale (Quiet → 100, Normal → 50, Loud → 0) and the venue's countable votes (post-precedence-rule) are averaged, unweighted — a vote doesn't carry a platform-accuracy distinction the way iOS/Android mic readings do.
- **(Dormant) Popular Times sub-score:** derived from a busyness figure — busier maps to louder maps to lower quietness sub-score. Not currently computed, since the underlying data isn't available; the formula below still accepts it and renormalizes around its absence, exactly the same way it handles any other missing signal.

## Platform-weighted confidence (microphone signal)
Per the research brief, iOS and Android microphone readings are not equally trustworthy:
- iOS readings (uniform hardware, ~±2 dBA accuracy) are weighted at full confidence.
- Android readings (device-dependent accuracy, no reliable cross-device calibration) are weighted at reduced confidence — proposed at half weight relative to an iOS reading, pending real-world calibration data once the app is live.
- **Web readings (added 2026-08-19)** — real Web Audio API capture (`mic_service_web.dart`), not a plugin — are weighted lower still (0.35): browsers commonly apply their own automatic gain control/noise suppression on top of device-to-device variance, on top of no cross-device calibration either. Same starting-point, needs-real-data status as the Android weight.
- Where a venue has multiple readings, average within each platform first, then apply the platform weighting, rather than pooling all raw readings together.
- As an alternative or refinement once enough data exists: normalize each reading relative to that venue's own reading history (relative quietness over time) rather than trusting the absolute dBA figure, which softens the impact of Android's device variance.

### Per-user mic calibration (added 2026-08-19)
Independent of the platform weighting above, and applied *before* it: every
signed-in user is walked through a one-off "say something normally" mic
recording on their first sign-in and again roughly every 3 months
(`mic_calibration_screen.dart`). An average human speaking voice measures
~60 dBA — comparing that user's own recording against this reference gives
a personal offset (their reading minus 60) reflecting how their specific
device/browser mic runs relative to "true." That offset is subtracted from
every subsequent ambient reading that same account submits, anywhere, before
it's platform-weighted and combined (`calibrationOffset`/
`applyCalibrationOffsets` in `data-pipeline/src/scoring.js`) — without this,
a phone whose mic just runs loud or quiet would make every venue that
person visits look systematically noisier or quieter than it actually is.
A reading from an account with no calibration on file passes through
uncorrected rather than being dropped.

## Combined quietness score
The combined score is a weighted average of the active sub-scores (the formula still has a term for Popular Times, dormant, in case it's revived):

```
baseline_quietness_score = (w_mic * mic_subscore) + (w_review * review_subscore) + (w_vote * vote_subscore) + (w_popular * popular_subscore)
```

Where weights are renormalized based on which signals actually have data for a given venue (cold start handling — see below). In practice today, `popular_subscore` is always absent, so this resolves to a renormalization across review, mic, and vote. The client applies the separate current-on-site overlay above when one is fresh. Starting point (`DEFAULT_WEIGHTS` in `data-pipeline/src/scoring.js`), to be tuned against real data:
- Microphone signal (0.4): highest weight when present — most direct measurement, and the reason it overrides a same-user vote within 5 minutes rather than the other way around.
- Review-text signal (0.25): second weight — asynchronous but broad coverage.
- Loudness-vote signal (0.2): third weight — added 2026-08-18, a lighter-weight signal than a real decibel reading.
- Popular Times signal (0.15): lowest weight — dormant, see above.

Exact numeric weights remain an open item, since they need tuning against real usage data the app doesn't have yet.

## Cold start handling
A new restaurant has no microphone data until users submit it. The score must degrade gracefully:
- 0 signals present: venue is not ranked (insufficient data), shown as "not enough data yet" rather than assumed loud or quiet.
- 1+ signals present: score computed from whatever is present, with a confidence level reflecting both how many signal types are present and how much data backs each one — see "Confidence levels" below. **Lowered 2026-08-17** (was a minimum-3-mentions threshold before a venue counted at all): any venue with even a single noise mention now gets a score, at minimum "Very Low" confidence, rather than being excluded outright.

This is the same mechanism that made dropping Popular Times a small, safe change rather than a rework: a signal that's *never* present is handled identically to one that's *occasionally* absent.

## Confidence levels

**Added 2026-08-17**, replacing an earlier three-bucket model (low/medium/high based purely on how many of the signal types were present). Six graduated levels, low to high: **Very Low, Low, Moderate, High, Very High, Certain.**

Confidence now also reflects how much data backs each present signal, not just whether it's present at all — a venue with 1 review mention and one with 20 both "have the review signal," but shouldn't read as equally trustworthy. Each present signal contributes 1–3 points based on its data volume (0 if absent); points sum and clamp to 1–6, mapping directly onto the six levels. See `data-pipeline/src/scoring.js` (`REVIEW_MENTION_TIERS`, `MIC_READING_TIERS`, and — added 2026-08-18 — `VOTE_TIERS`) for the exact volume cutoffs — a starting point, same as the combination weights above, flagged as an open tuning item rather than a final calibration. With loudness votes now active (not dormant like Popular Times), the max reachable total exceeds 6 (review's 3 + mic's 3 + vote's 3); it simply saturates at "Certain" rather than needing a 7th tier.

Any venue with at least one noise-mention review is at minimum "Very Low" confidence — this is the anchor the tiers are built from, decided with Caelan alongside lowering the minimum-mentions threshold.

Shown in the UI as a confidence indicator wherever a restaurant's quietness score appears (list rows and the detail screen), not just as text in the score breakdown.

## Ranking and sorting
- Default sort: combined quietness score, quietest first.
- **As actually built (updated 2026-08-19)** — a popout filter panel
  (`widgets/filter_drawer.dart`, opened from the List screen, mirroring the
  hamburger menu's slide-out behavior): Suburb, Cuisine Type, Loudness
  (the same Silent…Earsplitting tiers shown on every tile), and a minimum
  Rating threshold (3.0+ through 4.5+). Separately, a Sort By control:
  Loudness Quietest/Loudest First, Rating Highest/Lowest. Price level and
  time-of-day/day-of-week filtering were proposed here but never built —
  removed from this list rather than left as aspirational.
- **Changed 2026-08-18, per Caelan:** the detail screen's per-signal "Score breakdown" (Microphone readings / Review mentions / Popular times, each with a raw 0–100 number) was removed entirely, replaced by the loudness-vote buttons and the mic-reading control — see `ui-design-decisions.md`. Users can still judge confidence via the confidence indicator (dots + label), just no longer via raw per-signal numbers. **Note (2026-08-19):** this was decided and the backend built on 2026-08-18, but the UI itself only actually shipped to `main` on 2026-08-19 — see `_config/decisions.md`'s "Loudness votes" correction note for the full account of the gap.

## Open questions for stage 3
- Exact numeric weights for combining the sub-scores — rebalanced 2026-08-18 to make room for the loudness-vote signal (see "Combined quietness score" above), still a starting point, not a final calibration.
- Exact Android confidence discount (proposed 0.5x, needs validation).
- ~~Minimum mention/reading counts before a signal counts toward the score~~ — decided 2026-08-17: lowered to 1 mention/reading minimum, with the confidence-level tiers (see above) carrying the "how much do we trust this" job instead of a hard cutoff. Exact tier thresholds remain open for tuning.
- Whether to revisit Popular Times later (alternative source, or re-check Outscraper) — see "Signals" above. **Checked 2026-08-17: not available via Google's Places API, old or new — confirmed no such field exists officially, not just intermittently missing like the Outscraper finding.** Only remaining paths are third-party scrapers, not an official API.
