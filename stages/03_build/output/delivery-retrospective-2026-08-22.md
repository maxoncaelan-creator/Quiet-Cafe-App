# Delivery retrospective and PR #37 review — 2026-08-22

This review was completed before beginning the speech-to-text investigation.
It records evidence available through 2026-08-22 and is a companion to the
full occurrence log in [`MISTAKES.md`](../../../MISTAKES.md).

## Outcome first

The production Search Assistant failure was not caused by Cloudflare Pages.
The web app was reaching Supabase, but production had an older Search
Assistant function and did not have the venue-discovery migration. The app
then rendered the function's HTTP 429 rate-limit response as a generic
connectivity error.

The database migration was applied and the reviewed functions were deployed
manually on 2026-08-22:

| Production component | Verified state |
| --- | --- |
| `assistant_venue_discovery` migration | Applied |
| `assistant_venue_drafts` | Present with RLS; browser roles have no read access |
| `search-assistant` | Version 12; contains venue drafts and named-venue flow |
| `ondemand-topup` | Version 9; contains `previewOnly` candidate flow |

The Supabase GitHub integration was enabled after PR #37 had already merged.
It is expected to deploy later changes to `main`; it did not backfill the
already-merged PR, so the first production sync was completed manually. The
next Supabase-changing merge must be observed in the Supabase migration and
function-version views before it is called live.

## Evidence and verification limits

- PR #37's hosted Flutter, Node, Deno, and Supabase database checks passed.
- The local Podman engine starts containers, but Windows could not reach a
  published container port. `supabase start` therefore cannot currently be
  treated as a local database-test result on this workstation.
- Production deployment state was checked directly through Supabase after the
  manual deployment. A signed-in end-to-end venue conversation still needs a
  manual browser/device smoke test; no test may substitute a real user token.

## Mistake inventory

`MISTAKES.md` has 38 class headings and 70 recorded occurrences at this review.
The duplicate `patch-target-duplicated` heading is retained as historical
recording data; it should be consolidated only through the ICM mistake tooling,
not manually while doing product work.

### Delivery, deployment and configuration

- `workflow-file-placed-in-wrong-repo-root`
- `cloudflare-pages-project-assumed-auto-created`
- `cloudflare-token-permission-incomplete`
- `edge-function-not-deployed`
- `deploy-workflow-missing-dart-define`
- `migration-cli-project-root-assumed`
- `external-api-contract-assumed`
- `production-deployment-contract-unverified` (recorded below under the
  existing deployment class)

Pattern: the web deployment, database migration and Edge Function deployment
were treated as related but separate manual steps. A static-host success did
not prove the Supabase release. The remedy is release evidence from both
systems, not replacing Cloudflare with another static host.

### Verification and reporting

- `verification-cannot-detect-the-fault`
- `test-action-reported-despite-failure`
- `stale-diagnostic-artifact-after-collection-failure`
- `decision-documented-as-shipped-when-unmerged`
- `mistakes-not-logged-contemporaneously`
- `backend-rate-limit-classified-as-connectivity` (new)

Pattern: compilation, CI, source inspection and deployment metadata were
occasionally reported beyond what they could establish. A release claim needs
a test capable of failing if the deployed path is wrong: current migration,
current function source/version, and a protected end-to-end request where
appropriate.

### Scope, architecture and integration decisions

- `user-coverage-constraint-underweighted`
- `shared-endpoint-caller-impact-unreviewed`
- `vendor-sdk-flow-wrong-for-platform`
- `oauth-redirect-target-left-to-provider-fallback`
- `gate-identity-diverged-from-app-precedent`
- `platform-capability-assumed-not-verified`
- `migration-logic-reviewed-late`
- `structural-edit-not-reviewed`

Pattern: shared services and platform integrations need their existing callers,
runtime constraints and trusted-data sources enumerated before changing a
default. This remains especially important for speech-to-text because the
feature crosses browser, Android/iOS permissions and native/plugin APIs.

### Operational safety and workspace discipline

- `unscoped-filesystem-search`
- `unintended-tool-call-not-disclosed`
- `shell-special-chars-unquoted-for-remote-shell`
- `formatter-run-beyond-feature-scope`
- `discarded-real-change-assuming-it-was-noise`
- `configuration-value-surfaced-during-diagnostics`
- `disposable-test-cleanup-not-persistent`
- `source-path-assumed-from-context`
- `source-path-assumed-from-summary`
- `root-routing-protocol-skipped`
- `branch-not-reverified-before-commit`
- `mistake-class-slug-too-granular`
- `patch-target-duplicated`

Pattern: broad commands, inferred paths and diagnostic output caused avoidable
noise or disclosure risk. The existing workspace rules already cover the
highest-frequency cases; future changes must use targeted reads, explicit
working directories and redacted diagnostics.

### User-facing quality

- `keyboard-overflow-unhandled`
- `raw-backend-error-shown-to-user`
- `unbounded-native-async-call`
- `backend-rate-limit-classified-as-connectivity` (new)

Pattern: backend and native-plugin failures need deliberately designed UI
states. The generic Search Assistant fallback is now an identified defect, not
an acceptable catch-all.

## PR #37 review

PR #37, **Document and refine Search Assistant venue discovery**, was the
current draft under review at the start of this work and was merged during the
deployment follow-up. Its two commits were `ddb609d` and `b60e1f3`.

### What it changed

- A venue-plus-suburb request checks an exact local match before making a
  guarded Google Places preview request.
- A close Google match is held in `assistant_venue_drafts` until the user
  confirms it; it is not inserted into the public venue list first.
- A missing venue follows a short address/confirmation draft and is written as
  a `community` venue only after confirmation.
- Cancel and replacement inputs clear an unfinished draft.
- The migration adds source provenance to `restaurants`, a private draft table,
  RLS, revoked browser privileges, and a `service_role` grant.
- The new pgTAP test checks draft-table existence, RLS, revoked browser read
  access and the default `restaurants.source` value.

### Review result

**No new critical security issue was found in PR #37.** The migration is
appropriately private: it enables RLS, explicitly revokes `anon` and
`authenticated`, and grants the Edge Function service role only. The
preview-only flow corrects the prior risk of inserting an unconfirmed
similar-sounding venue.

The review did find release and test gaps:

| Priority | Finding | Required follow-up |
| --- | --- | --- |
| P1, resolved | PR source was merged while production still had the old functions and no migration. | Migration and both functions were deployed manually; GitHub integration is now enabled for future `main` changes. |
| P2, open | A real HTTP 429 is displayed as “couldn't reach the search assistant.” Supabase documents 4xx/5xx function outcomes as HTTP-function errors that need explicit client handling. | Catch and map the SDK's HTTP-function exception, then add a regression test for 429 and a non-429 backend error. |
| P2, open | Database tests validate schema/privileges only. They do not exercise the venue parser, confirmation state machine, Google preview or cancellation behaviour. | Add Edge Function behavioural tests with mocked Supabase/Google boundaries, plus a signed-in staging smoke test. |
| P3, open | A preview lookup records no inserted rows by design, so its event count is not a measure of Google candidates found. | Decide whether operational reporting needs separate `candidates_found` data before using the event table for discovery quality metrics. |

## Gate before speech-to-text work

The speech-to-text task begins only after this record has been reviewed. Its
first pass must:

1. Inventory every speech-recognition caller and each platform's permissions,
   lifecycle and error path.
2. Reproduce the failure on web and a native target separately; do not assume a
   browser failure is a Flutter widget failure or vice versa.
3. Add a written error state for permission denied, unavailable recognition,
   network failure and timeout rather than swallowing them in a generic state.
4. Verify the final path with a real microphone interaction on each supported
   platform, while keeping test output free of spoken/transcribed personal
   content.

## Owner-facing next actions

- Merge a small UI-only follow-up for Search Assistant 429/error
  classification before relying on the current generic message.
- On the next backend PR, confirm both the Supabase GitHub deployment and the
  production migration/function versions before marking the release complete.
- Resolve Podman's Windows port-forwarding issue or use a CI runner for local
  database testing; do not record a failed `supabase start` as a test pass.
- Then start the speech-to-text investigation under the gate above.

The canonical actionable list is the `Immediate defects` section of
[`build-log.md`](build-log.md). It is deliberately kept there rather than
duplicated here, so the next implementation session starts from one current
queue.
