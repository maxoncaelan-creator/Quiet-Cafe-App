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

Greater Sydney, plus out to Dubbo, north to Newcastle, south to Moss Vale,
and into the Illawarra as far as Kiama. Expanded from "Sydney only"
2026-08-19 — confirmed with Caelan.
Platform: iOS, Android, and Web (added 2026-08-18, live 2026-08-19 at
`quiet-restaurant-finder.pages.dev`).

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
  items in the build log (Popular Times, score weights) are explicitly his
  call, not something to decide silently. (Per-account rate limiting was one
  of these too — resolved 2026-08-18, see `_config/decisions.md`.)
- **Never push directly to `main` on the GitHub repo.** Always work on a
  feature branch and open a pull request for Caelan to review and merge (or
  merge only when he explicitly asks). See `_config/decisions.md`'s "Git
  workflow" — this followed an accidental direct push.
- **Build the marketing site here; don't write its copy here.** The site is
  code, so it belongs in stage 03 like any other surface. Every user-visible
  string in it comes from the `quiet-restaurant-finder-marketing` workspace
  — take it verbatim, and ask for anything missing instead of writing a
  placeholder that ships. That workspace owns the positioning, the voice,
  and the limits on what may be claimed about score accuracy; writing copy
  here bypasses all three.

- **Choose the auth/integration flow per platform before writing code.** When
  a hosted provider (Supabase here) offers both a vendor client-SDK flow and
  its own server-side redirect flow, those are different mechanisms with
  different credentials, different dashboard fields and different failure
  modes — not two styles of the same thing. The vendor SDK belongs on native,
  where it gives a real native account picker; the provider's redirect flow
  belongs on web, where adopting the vendor's browser SDK means reimplementing
  its button rendering, its once-per-page init contract and its nonce handling
  inside this app. Google sign-in on web was built the wrong way round and
  produced five consecutive live-caught failures before the choice itself was
  revisited (`MISTAKES.md`, `vendor-sdk-flow-wrong-for-platform`). Switching
  web to `signInWithOAuth` deleted all five at once and none recurred.

  Two signals that the *flow* is wrong rather than the code:
  - You are writing code to manage the vendor SDK's lifecycle — memoizing an
    initializer, hashing a nonce, subscribing to an SDK event stream to learn
    that an operation finished — rather than code that states what this app
    wants.
  - **Three or more consecutive fixes in one integration.** At that point the
    next patch is the wrong move; re-derive the design instead. This is the
    rule that would have saved the most time here and the easiest one to skip,
    precisely because each individual fix still looks correct in isolation —
    each of these five was.

  Related, and still true: a platform-specific SDK integration isn't done
  until it has been exercised live on that platform. A clean `flutter analyze`
  and a successful build confirm the code is well-typed, not that a
  third-party SDK's runtime contract is satisfied. When a real click-test
  isn't possible in the current session (this sandbox cannot render Flutter
  web — it draws to `<canvas>` with no accessible DOM until a genuine user
  gesture enables semantics), say so plainly rather than reporting a clean
  build as equivalent proof.

- **Before reporting a check as conclusive, say what it would show if the
  claim were false.** If the answer is *the same thing*, the check cannot
  settle the question and must not be reported as if it had. Three occurrences
  here came from checks that were structurally blind to what they were being
  cited for (`MISTAKES.md`, `verification-cannot-detect-the-fault`): an
  emulator run missing the `--dart-define` that would have made the tested
  feature appear at all; a `private: false` reading taken *after* Caelan had
  already flipped the repo to Public; a `merged: false` on every pull request
  from a list endpoint that never populates that field. Each looked like
  evidence and each was compatible with both answers.

  Two specific forms worth naming, because both read as data:
  - **A reading taken after the state changed** says nothing about the state
    before it. When something started working after someone intervened, the
    intervention is the leading explanation, not the thing to rule out.
  - **A value identical across every record** is a signal the field is
    unpopulated, not a finding. Confirm the endpoint actually populates a
    field before drawing conclusions from it — list and single-item endpoints
    of the same API often differ.

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

**"As it happens" has one concrete trigger: being corrected.** When Caelan
corrects something you asserted, record the mistake in the same turn, before
moving on to whatever he asked for next. Writing the correction into a reply,
or into session memory, is not recording it. This class has recurred three
times (`MISTAKES.md`, `mistakes-not-logged-contemporaneously`), each time
because the work continued and the entry was left for later — twice it took an
explicit prompt from Caelan to write it at all.
