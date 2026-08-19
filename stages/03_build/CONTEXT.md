# Stage 03 — Build

Workspace: [[quiet-restaurant-finder/AGENTS|Quiet Restaurant Finder]]

## Inputs

| File | Layer | Why |
|---|---|---|
| ../02_ranking-design/output/prd.md | 4 | product framing the build follows |
| ../02_ranking-design/output/ranking-spec.md | 4 | the scoring formula the pipeline implements |
| ../02_ranking-design/output/data-schema.md | 4 | the schema the pipeline and app share |
| `quiet-restaurant-finder-marketing/stages/05_finalize/output/final.md` (cross-workspace) | 4 | the marketing site's copy — read when building the site, never written here. Falls back to that workspace's `03_draft`/`04_seo-aeo` output while a piece is still in flight |

## Process

1. Build the app: data pipeline, ranking engine, and interface.
2. Platform: iOS and Android (mobile). Confirmed with Caelan — see
   [[quiet-restaurant-finder/stages/01_research/output/research-brief|research brief]].
   Driven by the in-app microphone decibel signal, which needs a native app
   on the device doing the measuring.
3. Tech stack: **Flutter**, targeting iOS and Android — a cross-platform
   framework was worth considering since decibel-metering packages exist for
   both, covering iOS and Android from one codebase. Confirmed with Caelan.
   Backend: **Supabase**.
4. Continue from wherever `build-log.md` in `output/` says the session left
   off — it is the running record of what has been built, tested, and
   decided, and what is still open.
5. **The marketing website is built here; its words are not written here.**
   The site is code and belongs in this stage like any other surface. But
   every user-visible string in it — headlines, body copy, button labels,
   microcopy, form validation text, the confirmation message after signup —
   comes from `quiet-restaurant-finder-marketing`. Take that copy verbatim.
   If a string is needed that doesn't exist yet, ask for it rather than
   writing a placeholder that quietly ships. Marketing copy has a reading
   level, a positioning document, and hard constraints on what may be
   claimed about score accuracy behind it; none of that context lives in
   this workspace.

## Outputs

| File | Goes to |
|---|---|
| build-log.md | output/ — the running build log: what's verified, what's decided, what's open |
| app/ | output/ — Flutter app source (also pushed to [github.com/maxoncaelan-creator/Quiet-Cafe-App](https://github.com/maxoncaelan-creator/Quiet-Cafe-App)) |
| data-pipeline/ | output/ — Node.js pipeline: fetches restaurant + noise-signal data, computes quietness scores, writes to Supabase |
| supabase/ | output/ — SQL migrations shared by app and pipeline |
| marketing site | the `Quiet-Cafe-App` repo, own folder/branch — code only; copy comes from `quiet-restaurant-finder-marketing` |

## Review gate

Caelan reviews each open item in `build-log.md`'s "Open items carried into
further build work" before it's marked resolved — several depend on
credentials or hardware (Google/Apple OAuth, an iOS/Android device) only he
can provide.
