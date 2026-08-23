# Step 1 coverage automation release gate

The Step 1 migration creates an empty NSW gazetteer. Do **not** deploy the new
`ondemand-topup` or `search-assistant` functions until the initial official
snapshot has succeeded: an empty gazetteer safely rejects paid area searches,
but would make legitimate suburb refreshes unavailable.

This is a release procedure, not an instruction to enable paid traffic during
the pull-request review.

## Safe deployment order

1. Deploy the new `places-search` **first**. Until the migration creates its
   dispatch-marker RPC, the new proxy preflights that boundary and fails closed
   before either reserving capacity or calling Google. This short maintenance
   window is intentional: do not apply the migration while an older, unguarded
   proxy version can still receive traffic. Confirm the new Function version is
   active before proceeding.
2. Apply `20260823100000_suburb_coverage_automation.sql` using the backend
   release runbook. Confirm it applied once. The already-active proxy can then
   mark each request before dispatching it, so the existing Node pipeline and
   old on-demand Function immediately share the 8,000-request UTC-month
   ceiling.
3. Deploy `sync-nsw-gazetteer` and set the same high-entropy
   `COVERAGE_AUTOMATION_SECRET` in its Function secrets and in
   `coverage-automation-worker`'s Function secrets. Never put its value in
   SQL, Git, logs, or a cron command.
4. Invoke the sync endpoint once with that header. It fetches the official NSW
   Spatial Services FeatureServer, pages through the full result set, and
   records a checksum and outcome. Do not deploy the strict area callers until
   this succeeds.
5. Verify each query separately in the production SQL console:

   ```sql
   select count(*) from public.nsw_suburbs where is_active;
   ```

   The current source has roughly 4,600 active records; investigate a much
   smaller count instead of accepting it.

   ```sql
   select status, records_received, completed_at, error_message
   from public.nsw_suburb_gazetteer_syncs
   order by started_at desc
   limit 1;
   ```

   It must report `succeeded` with no error before strict resolver callers are
   deployed.
6. Deploy `ondemand-topup`, `search-assistant`, and
   `coverage-automation-worker`; then confirm their production versions and the
   migration list directly, as required by `BACKEND_RELEASE_RUNBOOK.md`.

## Enabling scheduled work (separate Caelan approval)

The migration leaves `coverage_automation_config.enabled = false`. That is
intentional: merely merging/deploying the source cannot initiate Google Places
traffic.

Before setting it true, Caelan must explicitly approve the freshness interval
and throughput. Then, in Supabase:

1. Create a Vault secret named `coverage_automation_secret` whose value is the
   same value configured as `COVERAGE_AUTOMATION_SECRET` for the worker.
2. Set `coverage_automation_config.worker_url` to:

   ```text
   https://aesorixtfasfuvcqrvem.supabase.co/functions/v1/coverage-automation-worker
   ```

3. Verify that the worker returns `401` without its private header and works
   with it before enabling cron.
4. Set `enabled = true` only after those checks. The schedules then enqueue up
   to 25 stale localities each hour and invoke one worker tick every 15 minutes.
   Each actual Google request still passes through `places-search` and is
   stopped before dispatch once the 8,000-call ledger has no capacity.

If the source changes, the daily cron attempts a sync but the database refuses
another successful snapshot within 30 days. Retired source names remain aliases
and never silently redirect a sweep to a successor locality.

## What this does not prove

The repository checks prove the code’s contracts and the hosted database suite
will exercise the migration. They do not prove that a production Function
secret, Vault secret, Edge deployment, or the external FeatureServer is
configured correctly. The production checks above are therefore required before
calling Step 1 live.
