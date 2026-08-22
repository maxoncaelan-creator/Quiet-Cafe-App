# Backend release verification

**Owner:** release author | **Frequency:** after every merged PR that changes
`supabase/migrations/` or `supabase/functions/` | **Last updated:** 2026-08-22

## Purpose

Prove that a backend PR is deployed to production. A green Flutter build,
source commit, or static-web deployment does not establish this.

## Prerequisites

- The PR is merged into `main` and the Supabase GitHub integration has finished.
- Access to the production Supabase project (`aesorixtfasfuvcqrvem`).
- The merged commit SHA and the list of changed files.

## Procedure

1. In the merged PR, record the exact `main` commit SHA and list every changed
   migration and Edge Function. If neither path changed, mark the backend
   checklist as **not applicable**.
2. In Supabase Dashboard → **Settings → Integrations**, confirm the linked
   repository is `maxoncaelan-creator/Quiet-Cafe-App`, production deployment is
   enabled, and the production branch is `main`.
3. In **Database → Migrations**, verify every migration from the merged PR is
   present. Record the migration ID/name shown by production; do not infer this
   from the source file existing in Git.
4. In **Edge Functions**, open every changed function and record its active
   version. Confirm its source contains the merged change (or capture the
   version/source hash using the Supabase management tooling).
5. Run the least-cost relevant live request. For an Assistant or coverage
   change, use a signed-in test account and verify the response plus Function
   logs. Do not include user messages, coordinates, tokens, API keys or other
   sensitive payloads in the PR.
6. Add a PR comment containing the commit SHA, production migration IDs,
   function names/versions, live-check outcome, and any remaining limitation.

## Failure handling

If a source migration is missing from production, **stop**. Do not insert rows
directly into Supabase's migration-history table and do not call an MCP
"apply migration" helper with a substituted timestamp: either action makes
the deployed migration history differ from the repository's source IDs.

Use the Supabase Dashboard's GitHub integration or an authenticated
`supabase db push --linked` from a clean checkout of `main` so the original
migration IDs are preserved. Re-run steps 3–5 before declaring the release
complete.

## 2026-08-22 recovery record

Production history was reconciled on 2026-08-22 using an authenticated linked
CLI. Generated timestamp records for already-present schema changes were
replaced with their repository migration IDs via `supabase migration repair`;
no table data was changed during that step. A dry run then identified only two
absent migrations, which were applied with:

```powershell
supabase db push --linked --include-all --skip-vault
```

`supabase migration list --linked` now shows every local migration matching
production. The contribution-score function, current-loudness columns, and
five associated triggers were verified. Treat this as the required recovery
pattern if historical manual changes ever cause migration-record drift again:
inspect schema first, repair history only when equivalence is proven, dry-run,
then apply the exact missing source migrations.
