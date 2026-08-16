# Quiet Restaurant Finder

Root: [[Vault-root/CONTEXT|Vault-root]]

## What this workspace builds
An app that ranks restaurants by how quiet they are.

## Scope
One city: Sydney, NSW. Confirmed with Caelan.
Platform: iOS and Android. Confirmed with Caelan.

## Noise signals
Active for v1:
- Review text mining (reviews that mention noise)
- Decibel data — measured first-party via the phone's microphone inside the app, crowdsourced from users. Submitting a reading requires a real (email/password) account; browsing the ranked list never does. Decided 2026-08-15.

Not active:
- SoundPrint (third-party decibel data) — considered and skipped 2026-08-15 in favor of first-party in-app microphone measurement.
- Google Popular Times — built against Outscraper (revised 2026-08-15 from an initial OpenSERP plan), then dropped the same day after confirming live that 0/100 Sydney restaurants had `popular_times` data. Code kept dormant. See [[quiet-restaurant-finder/stages/01_research/output/research-brief|research brief]] and [[quiet-restaurant-finder/stages/03_build/output/README|stage 3 README]].

## Stages
1. [[quiet-restaurant-finder/stages/01_research/CONTEXT|01 Research]] — find data sources, confirm the city.
2. [[quiet-restaurant-finder/stages/02_ranking-design/CONTEXT|02 Ranking design]] — define the quietness score and data schema.
3. [[quiet-restaurant-finder/stages/03_build/CONTEXT|03 Build]] — build the app.
