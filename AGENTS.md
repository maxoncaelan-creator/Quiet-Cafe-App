# Quiet Restaurant Finder

Layer 0 — identity. You are inside the `quiet-restaurant-finder` workspace.
The root router sent you here. Root context no longer applies; this file and
the files below it are your context now.

## What this workspace builds

An app that ranks restaurants by how quiet they are.

Code lives at [github.com/maxoncaelan-creator/Quiet-Cafe-App](https://github.com/maxoncaelan-creator/Quiet-Cafe-App),
pushed 2026-08-16. This workspace stays the source of truth for
research/design decisions and the build log — see
[[quiet-restaurant-finder/stages/03_build/output/build-log|stage 3 build log]].

## Scope

One city: Sydney, NSW. Confirmed with Caelan.
Platform: iOS and Android. Confirmed with Caelan.

See `_config/decisions.md` for the full, current set of confirmed
product decisions — scope, platform, and which noise signals are active.

## Structure

```
quiet-restaurant-finder/
  AGENTS.md          this file — identity
  CLAUDE.md          pointer to this file
  CONTEXT.md         Layer 1 — which stage handles what
  workspace.md       routing card read by the root
  .gitignore         keeps secrets (data-pipeline/.env) and node_modules out of git
  stages/
    01_research/         find data sources, confirm the city
    02_ranking-design/    define the quietness score and data schema
    03_build/             build the app (data pipeline, Supabase, Flutter app)
  _config/
    decisions.md      Layer 3 — confirmed product decisions, updated as they change
```

## How to work here

1. Read `CONTEXT.md` to find the stage that handles the request.
2. Read that stage's `CONTEXT.md` and load only the files its Inputs table names.
3. Do the work, write the output file to that stage's `output/`.
4. Stop. Report what was written and let the human review before continuing.

## Rules specific to this workspace

- **This is a single ongoing project, not a repeatable template.** Stage
  outputs are the live state of the project, not stale examples — do not
  reset or overwrite them without being asked. Continuing stage 03 almost
  always means reading `stages/03_build/output/build-log.md` first to see
  where the last session left off.
- **`data-pipeline/.env` holds a real Supabase credential.** Never print it,
  paste it into chat, or commit it. `.gitignore` at this workspace's root
  already excludes it from git.
- **Decisions get confirmed with Caelan before code changes.** Several open
  items in the build log (Popular Times, per-account rate limiting, score
  weights) are explicitly his call, not something to decide silently.

## Standards and mistakes

`/_system/standards.md` applies here, as in every workspace: the rules that
exist because the same mistake happened in more than one workspace. Read it once
at the start of a run.

When you become aware that something you did fell short of a knowable standard,
record it in this workspace's `MISTAKES.md` **as it happens**, not at the end:

```
bin/icm mistake quiet-restaurant-finder --class <slug> --stage <NN_stage> --caught self --what "..." --standard "..." --fix "..."
```

A user changing direction is not a mistake; acting without checking something
checkable is. `/_system/mistakes.md` has the test and the thresholds at which a
repeated class has to become a rule in this file.
