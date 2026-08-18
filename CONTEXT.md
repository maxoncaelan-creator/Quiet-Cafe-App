# Quiet Restaurant Finder — stage routing

Layer 1. Given what the user wants, this file says which stage handles it.

## Stages

| Stage | Handles | Reads | Writes |
|---|---|---|---|
| `01_research` | Find data sources, confirm the city | the user | `research-brief.md` |
| `02_ranking-design` | Define the quietness score and data schema | the research brief | `prd.md`, `ranking-spec.md`, `data-schema.md` |
| `03_build` | Build the app: data pipeline, ranking engine, interface | the PRD, ranking spec, data schema | `build-log.md`, `app/`, `data-pipeline/`, `supabase/` |

## Pipeline

```
01_research → (review gate) → 02_ranking-design → (review gate) → 03_build
```

All three stages are complete at least once; the project currently lives
inside stage 03, iterating on the build. Re-entering this workspace almost
always means continuing stage 03, not restarting from 01.

## Starting a run

To continue the build: read `stages/03_build/output/build-log.md` first —
specifically "Open items carried into further build work" at the bottom — to
see what was last done and what's still pending.

To revisit an earlier decision (e.g. the quietness-score formula), open the
relevant stage's `output/` and edit or re-run it, then check whether stage 03
needs to follow.

## Re-running one stage

Any stage can be re-run on its own. If a later stage's output is wrong but the
earlier work is fine, re-run only the stage that produced the problem. Because
this is a live project rather than a template, prefer editing stage 03's
outputs in place (and logging the change in `build-log.md`) over a full
re-run — that log is the project's history and is worth keeping intact.

## Shared resources

| File | Layer | Used by |
|---|---|---|
| `_config/decisions.md` | 3 | all three stages |
