# Stage 02 — Ranking design

Workspace: [[quiet-restaurant-finder/AGENTS|Quiet Restaurant Finder]]

## Inputs

| File | Layer | Why |
|---|---|---|
| ../01_research/output/research-brief.md | 4 | the sources this stage turns into a score |

## Process

1. Write a concise PRD (product requirements document) for the app.
   Reference: [Atlassian — What is a PRD?](https://www.atlassian.com/agile/product-management/requirements).
   The PRD covers: objective and problem statement, target users, scope,
   success metrics, assumptions/constraints, and open questions —
   product-level framing, pointing to the two spec docs below for technical
   detail.
2. Define the quietness score. Combine the signals from the research brief
   into one formula.
3. Define the data schema for a restaurant record: identity, location, and
   each noise signal.
4. Define how the app ranks and sorts restaurants from the score.

## Outputs

| File | Goes to |
|---|---|
| prd.md | output/ |
| ranking-spec.md | output/ |
| data-schema.md | output/ |

## Review gate

Caelan confirms the quietness-score formula and the data schema before build
starts — both are expensive to change once the pipeline and app are wired to
them.
