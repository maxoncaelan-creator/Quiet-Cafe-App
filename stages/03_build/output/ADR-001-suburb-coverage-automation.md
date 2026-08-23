# ADR-001: Canonical NSW locality coverage automation

**Status:** Proposed — pending Caelan review in the Step 1 pull request

**Date:** 2026-08-23

**Decider:** Caelan (review required before merge and activation)

## Context

The existing on-demand collector accepts free-form suburb text, uses it in a
substring database query, and can send it to Google Places. That allowed a
natural-language phrase to authorise a billed search. Its `MIN_COVERAGE`
threshold also leaves dense suburbs permanently stale. The app now has a hard
8,000-call monthly Places ceiling, but the ledger is not yet at the sole
provider boundary, so both the Node pipeline and on-demand path can currently
bypass it.

Step 1 must add a safe, repeatable NSW coverage system without changing the
Flutter response contracts reserved for Step 2.

## Proposed decision

1. Use NSW Spatial Services' official **Suburb — NSW Administrative Boundaries
   Theme — GDA2020** FeatureServer layer as the canonical gazetteer. The sync
   fetches a monthly full snapshot, keyed by `cadid`; the source endpoint and
   extraction time are recorded. It does not use the ABS statistical suburb
   layer or GNB proposal data.
2. Preserve renamed or subdivided localities as **aliases**, never automatic
   redirects. A retired locality remains resolvable for legacy restaurant rows
   but cannot start a new Places sweep until an operator explicitly maps a
   successor. This avoids silently attributing a former locality's coverage to
   every successor of a split.
3. Resolve every area input inside `ondemand-topup` to one canonical locality
   before a coverage query, reservation, queue entry, or Google request. Exact
   normalised matches cover casing, spacing and accents; fuzzy results must be
   unique and conservative. An unresolvable or retired name cannot spend a
   Places call.
4. Enforce the monthly request ledger inside `places-search`, immediately
   before each Google request. This covers the Node pipeline, on-demand
   collector, Assistant, and background worker equally. Existing per-user and
   daily on-demand limits remain separate product controls.
5. Replace area `MIN_COVERAGE` with durable sweep freshness and completion
   state. A dense locality is eligible once stale. The existing GPS rules stay
   separate: the deliberate one-kilometre checkpoint is unchanged, and the
   five-kilometre Assistant path retains its current bounded policy until a
   separately approved change.
6. Use `pgmq` for worker wake-ups, a priority job table for recency-of-demand
   ordering and retry state, and `pg_cron`/`pg_net` to invoke the worker. The
   scheduler is disabled until its server-side secret and worker URL are set in
   Supabase; source deployment alone cannot start paid traffic.

## Options considered

### Budget at every caller

This would require each existing and future caller to reserve correctly and
would miss retries or a new integration. It was rejected because a global
ceiling cannot depend on every caller remembering a guard.

### Budget at `places-search`

`places-search` is the only function that actually calls Google. Reserving and
settling there counts real provider attempts across every caller. This is the
proposed option.

### Redirect retired locality names automatically

An old locality can split into more than one successor. Automatic redirects
would make stale or unrelated data look current, so aliases with an explicit
retired result are accepted instead.

## Consequences

- Existing Flutter response shapes remain stable through Step 1.
- A source deployment must first switch `places-search` to its fail-closed
  dispatch-marker version, then apply the migration, then run the backend
  release runbook and initial gazetteer sync before strict area refreshes are
  treated as live. This avoids any migration-before-proxy window in which an
  older proxy could call Google without the global ceiling.
- The exact sweep freshness interval and worker throughput remain editable
  operator configuration; the schedule starts disabled rather than quietly
  choosing a paid-traffic rate.
- The official source must be attributed as `© DCS Spatial Services` with the
  extraction date when its data is surfaced outside the app.
- The current `reviews` field mask is priced at Google’s Enterprise +
  Atmosphere tier. The unimplemented, costed discovery/enrichment proposal is
  in [`PLACES_COST_PROPOSAL.md`](supabase/PLACES_COST_PROPOSAL.md); Caelan must
  decide between its options before scheduled paid sweeps are enabled.

## References

- [NSW Spatial Services FeatureServer layer](https://portal.spatial.nsw.gov.au/server/rest/services/NSW_Administrative_Boundaries_Theme_multiCRS/FeatureServer/2)
- [Data.NSW catalog record](https://www.data.nsw.gov.au/data/dataset/1-56651906158a416e94fd244201782464)
- [NSW Cadastral Data Dictionary](https://www.spatial.nsw.gov.au/__data/assets/pdf_file/0019/232561/NSW_Cadastral_Data_Dictionary_-_Feb24.pdf)
