# Ranking spec — Quiet Restaurant Finder

Workspace: [[quiet-restaurant-finder/CONTEXT|Quiet Restaurant Finder]]
Stage: [[quiet-restaurant-finder/stages/02_ranking-design/CONTEXT|02 Ranking design]]
Input: [[quiet-restaurant-finder/stages/01_research/output/research-brief|Research brief]]
See also: [[quiet-restaurant-finder/stages/02_ranking-design/output/prd|PRD]], [[quiet-restaurant-finder/stages/02_ranking-design/output/data-schema|Data schema]]

## Signals
Two signals actively feed the quietness score:

1. **Review-text signal** — noise mentions mined from Google Places and Yelp review text.
2. **Microphone signal** — first-party crowdsourced decibel readings submitted by users through the app.

A third signal, **Popular Times**, was designed and built (Outscraper) but
**dropped on 2026-08-15** after live testing found 0 of 100 Sydney
restaurants had `popular_times` data available — see
[[quiet-restaurant-finder/stages/03_build/output/README|stage 3 README]]
"Outscraper vs. OpenSERP" for the verification. The code (`outscraper.js`)
and this spec's description of it are kept below, dormant, in case
Outscraper restores the field or an alternative source gets pursued later.

## Sub-score normalization
Each active signal is normalized to a 0–100 quietness sub-score (100 = quietest) before combining, since the sources arrive in different units and scales:

- **Review-text sub-score:** ratio of noise-negative mentions ("loud," "couldn't hear," "noisy") to noise-positive mentions ("quiet," "great for conversation," "peaceful") in the mined review text, mapped to 0–100. A venue with no noise-related mentions at all gets no sub-score (excluded from this signal, not scored as neutral) until it has at least a small minimum mention count.
- **Microphone sub-score:** derived directly from crowdsourced decibel readings. Raw dBA is mapped to a 0–100 scale using SoundPrint's public banding as a reference point (quiet below 70 dBA, moderate 70–75, loud 75–80, very loud above 80), inverted so quieter dBA gives a higher sub-score.
- **(Dormant) Popular Times sub-score:** derived from a busyness figure — busier maps to louder maps to lower quietness sub-score. Not currently computed, since the underlying data isn't available; the formula below still accepts it and renormalizes around its absence, exactly the same way it handles any other missing signal.

## Platform-weighted confidence (microphone signal)
Per the research brief, iOS and Android microphone readings are not equally trustworthy:
- iOS readings (uniform hardware, ~±2 dBA accuracy) are weighted at full confidence.
- Android readings (device-dependent accuracy, no reliable cross-device calibration) are weighted at reduced confidence — proposed at half weight relative to an iOS reading, pending real-world calibration data once the app is live.
- Where a venue has multiple readings, average within each platform first, then apply the platform weighting, rather than pooling all raw readings together.
- As an alternative or refinement once enough data exists: normalize each reading relative to that venue's own reading history (relative quietness over time) rather than trusting the absolute dBA figure, which softens the impact of Android's device variance.

## Combined quietness score
The combined score is a weighted average of the active sub-scores (the formula still has a term for Popular Times, dormant, in case it's revived):

```
quietness_score = (w_mic * mic_subscore) + (w_review * review_subscore) + (w_popular * popular_subscore)
```

Where weights are renormalized based on which signals actually have data for a given venue (cold start handling — see below). In practice today, `popular_subscore` is always absent, so this resolves to a straight renormalization between review and mic. Starting point, to be tuned in stage 3 against real data:
- Microphone signal: highest weight when present (most direct measurement).
- Review-text signal: second weight — asynchronous but broad coverage.
- Popular Times signal: lowest weight — dormant, see above.

Exact numeric weights are an open item for stage 3, since they need tuning against real usage data the app doesn't have yet.

## Cold start handling
A new restaurant has no microphone data until users submit it. The score must degrade gracefully:
- 0 signals present: venue is not ranked (insufficient data), shown as "not enough data yet" rather than assumed loud or quiet.
- 1 signal present: score computed from that signal only, flagged as lower-confidence in the UI.
- Both active signals present: full weighted score, higher confidence.

This is the same mechanism that made dropping Popular Times a small, safe change rather than a rework: a signal that's *never* present is handled identically to one that's *occasionally* absent.

## Ranking and sorting
- Default sort: combined quietness score, quietest first.
- Filters: cuisine, price level, suburb, time of day/day of week (since noise varies by time — the microphone data is timestamped for this).
- Each restaurant's detail view shows the sub-score breakdown per signal, not just the combined number, so users can judge confidence themselves (e.g. a venue with 50 iOS microphone readings vs. one with only a review-text sub-score).

## Open questions for stage 3
- Exact numeric weights for combining the sub-scores.
- Exact Android confidence discount (proposed 0.5x, needs validation).
- Minimum mention/reading counts before a signal counts toward the score.
- Whether to revisit Popular Times later (alternative source, or re-check Outscraper) — see "Signals" above.
