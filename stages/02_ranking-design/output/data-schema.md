# Data schema — Quiet Restaurant Finder

Workspace: [[quiet-restaurant-finder/CONTEXT|Quiet Restaurant Finder]]
Stage: [[quiet-restaurant-finder/stages/02_ranking-design/CONTEXT|02 Ranking design]]
Input: [[quiet-restaurant-finder/stages/01_research/output/research-brief|Research brief]]
See also: [[quiet-restaurant-finder/stages/02_ranking-design/output/prd|PRD]], [[quiet-restaurant-finder/stages/02_ranking-design/output/ranking-spec|Ranking spec]]

Backend: **Supabase** (decided 2026-08-15). This schema is implemented as Postgres migrations at `stages/03_build/output/supabase/migrations/`, split into two tables (`restaurants`, `mic_readings`) rather than one nested record — see those files for exact column types and Row Level Security policies. `0003_auth_required_for_mic_readings.sql` (2026-08-15) requires a real Supabase Auth account to submit a reading, decided with Caelan; browsing `restaurants` stays open to everyone.

## Restaurant record

### Identity
| Field | Type | Notes |
|---|---|---|
| `place_id` | string | Google Places ID, primary key |
| `yelp_id` | string, nullable | Yelp business ID, if matched |
| `name` | string | |
| `cuisine` | string / array | From Places/Yelp category data |
| `price_level` | integer 1–4 | From Places/Yelp |
| `google_rating` | float, nullable | For display only, not part of quietness score |
| `yelp_rating` | float, nullable | For display only, not part of quietness score |

### Location
| Field | Type | Notes |
|---|---|---|
| `address` | string | |
| `suburb` | string | Used for filtering |
| `lat` | float | |
| `lng` | float | |

### Review-text signal
| Field | Type | Notes |
|---|---|---|
| `noise_mention_count` | integer | Total noise-related mentions found |
| `noise_positive_count` | integer | Mentions like "quiet," "great for conversation" |
| `noise_negative_count` | integer | Mentions like "loud," "couldn't hear" |
| `review_subscore` | float 0–100, nullable | Null if below minimum mention count |
| `review_signal_updated_at` | timestamp | |

### Popular Times signal (dormant — see ranking-spec.md "Signals")
Columns exist in the live schema but are currently always null: dropped as
an active signal on 2026-08-15 after confirming 0/100 Sydney restaurants had
`popular_times` data via Outscraper. Kept rather than dropped from the
table, in case this gets revisited.

| Field | Type | Notes |
|---|---|---|
| `popular_times_by_hour` | object | Busyness level per hour, per day of week — currently never populated |
| `popular_subscore` | float 0–100, nullable | Currently always null |
| `popular_signal_updated_at` | timestamp | |

### Microphone signal
Individual readings, stored separately (one-to-many with the restaurant record) so raw data supports re-tuning the ranking formula later:

| Field | Type | Notes |
|---|---|---|
| `reading_id` | string | Primary key |
| `place_id` | string | Foreign key to restaurant record |
| `user_id` | uuid, not null | Real Supabase Auth account (decided 2026-08-15). References `auth.users`, defaults to `auth.uid()`, and RLS requires it match the submitter's own session — a client cannot submit under someone else's identity. A user can read back their own readings, not anyone else's. |
| `decibel_value` | float | From native metering API, not stored audio |
| `capture_duration_ms` | integer, required for new rows | The completed capture duration. Postgres rejects every new venue reading below 10,000 ms, including attempts from a modified client. Historical rows predate this rule and remain null. |
| `platform` | enum: `ios` \| `android` \| `web` | Drives confidence weighting per [[quiet-restaurant-finder/stages/02_ranking-design/output/ranking-spec|ranking spec]]. `web` added 2026-08-19 (`0009_mic_readings_allow_web.sql`) once real Web Audio API capture existed — previously the CHECK constraint only allowed `ios`/`android`. |
| `device_model` | string, nullable | For future per-device calibration work |
| `recorded_at` | timestamp | |
| `day_of_week` | derived | For time-of-day filtering |
| `hour_bucket` | derived | For time-of-day filtering |

Aggregated onto the restaurant record for fast ranking lookups:

| Field | Type | Notes |
|---|---|---|
| `mic_reading_count_ios` | integer | |
| `mic_reading_count_android` | integer | |
| `mic_subscore` | float 0–100, nullable | Null if zero readings |
| `mic_signal_updated_at` | timestamp | Recomputed as new readings arrive |

### Computed (combined)
| Field | Type | Notes |
|---|---|---|
| `quietness_score` | float 0–100, nullable | Weighted combination per [[quiet-restaurant-finder/stages/02_ranking-design/output/ranking-spec|ranking spec]] |
| `confidence` | enum: `Very Low` \| `Low` \| `Moderate` \| `High` \| `Very High` \| `Certain` | **Changed 2026-08-17** (was `low`/`medium`/`high`, purely signal-count based) — six graduated levels based on how many of the active signals are present *and* their data volume. See [[quiet-restaurant-finder/stages/02_ranking-design/output/ranking-spec|ranking spec]] "Confidence levels." Migration: `0005_confidence_levels.sql`. |
| `score_updated_at` | timestamp | |
| `current_loudness_subscore` | float 0–100, nullable | Most recent on-site vote or completed mic observation; starts at full display weight. |
| `current_loudness_observed_at` | timestamp, nullable | Server-set time of that current observation. The app uses it to decay the display weight over 21 days. |
| `current_loudness_source` | enum: `mic` \| `vote`, nullable | Makes the overlay auditable without exposing the submitter. |

## Loudness votes

Added 2026-08-18, per Caelan — a lightweight alternative to a mic reading:
`stages/03_build/output/supabase/migrations/0008_loudness_votes.sql`. One
row per vote (not one per user per restaurant — a user can vote more than
once), same account gate as `mic_readings`:

| Field | Type | Notes |
|---|---|---|
| `id` | uuid | Primary key |
| `place_id` | string | Foreign key to restaurant record |
| `user_id` | uuid, not null | Real Supabase Auth account — same gate as `mic_readings.user_id`. Needed so the pipeline can apply the precedence rule below, not just for privacy. |
| `vote` | enum: `quiet` \| `normal` \| `loud` | |
| `submitted_at` | timestamp | Server-set (`now()`), not client-supplied — same reasoning as `mic_readings.submitted_at`: it's what the pipeline compares against a mic reading's own timestamp. |

**Precedence rule:** if the same user has a mic reading at the same venue
within 5 minutes either side of a vote, the pipeline excludes that vote
from scoring — the decibel reading is the more trustworthy signal. The
vote row itself is never deleted or modified; only this run's aggregation
skips it. See [[quiet-restaurant-finder/stages/02_ranking-design/output/ranking-spec|ranking spec]] "Signals."

**Current-condition rule (added 2026-08-21):** both an inserted vote and a
completed mic reading update the restaurant's current-loudness fields through
a tightly scoped database trigger. The raw row remains the historical record;
the client uses the separate timestamped current observation to display what a
person is experiencing now before it decays back to the venue baseline.

Aggregated onto the restaurant record, mirroring the microphone signal's shape:

| Field | Type | Notes |
|---|---|---|
| `vote_count` | integer | Count of votes actually counted toward scoring this run (post-precedence-rule), not the raw total in `loudness_votes` |
| `vote_subscore` | float 0–100, nullable | Null if zero countable votes |
| `vote_signal_updated_at` | timestamp | |

## Mic calibration

Added 2026-08-19, per Caelan —
`stages/03_build/output/supabase/migrations/0010_mic_calibrations.sql`.
One row per calibration attempt (not one per user — a user can
recalibrate, and the pipeline only ever uses their most recent one), same
account gate as `mic_readings`:

| Field | Type | Notes |
|---|---|---|
| `id` | uuid | Primary key |
| `user_id` | uuid, not null | Real Supabase Auth account — same gate as `mic_readings.user_id`. Not tied to any one restaurant; a calibration corrects that user's readings everywhere. |
| `decibel_value` | float | The user's own recorded speaking volume, compared against the ~60 dBA human-voice reference (`HUMAN_VOICE_REFERENCE_DBA` in `scoring.js`) to derive their personal offset |
| `platform` | enum: `ios` \| `android` \| `web` | Recorded for completeness; the correction itself doesn't currently distinguish by platform |
| `recorded_at` | timestamp | Server-set (`now()`) |

Not aggregated onto the restaurant record — unlike mic readings and
loudness votes, a calibration isn't a per-venue signal. The pipeline reads
every user's most recent calibration once per run
(`fetchLatestCalibrationByUser` in `supabase.js`) and applies the
resulting offset to that user's `mic_readings` rows before scoring — see
[[quiet-restaurant-finder/stages/02_ranking-design/output/ranking-spec|ranking spec]]
"Per-user mic calibration."

## Favorites

Added from the UI redesign (2026-08-17) — `stages/03_build/output/supabase/migrations/0004_favorites.sql`. One row per user per favorited restaurant:

| Field | Type | Notes |
|---|---|---|
| `user_id` | uuid, not null | Real Supabase Auth account — same gate as `mic_readings.user_id`. Favoriting requires sign-in; browsing and the ranked list stay open to everyone. |
| `place_id` | string | Foreign key to restaurant record |
| `created_at` | timestamp | |

Primary key is `(user_id, place_id)` — a favorite is either present or not, no separate id needed. RLS scopes every operation (select/insert/delete) to `auth.uid() = user_id`, so a user can only ever see or change their own favorites — same privacy shape as individual mic readings.

## Notes
- No raw audio is ever stored — only the `decibel_value` from native metering, per the privacy constraint confirmed with Caelan.
- Nullable sub-scores are intentional: a venue with no data for a signal should not be silently scored as neutral (50) — see cold-start handling in the ranking spec.
- Individual mic readings are retained (not just the aggregate) to allow future recalibration of the platform confidence weighting once real usage data exists.
