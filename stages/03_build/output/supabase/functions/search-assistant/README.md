# Search Assistant venue discovery

The Search Assistant helps a signed-in beta user find a venue without
inventing one. It first reads the public `restaurants` table, then uses the
existing guarded Google Places pathway only when a named venue is not already
present.

## User flow

| User input | Assistant action |
| --- | --- |
| `crows nest` (case-insensitive) | Treat it as a suburb and refresh thin coverage before answering. |
| `Cafe Example in Crows Nest`, `Cafe Example restaurant Crows Nest`, or `in Crows Nest, Cafe Example` | Look for an exact database match first. |
| No exact database match | Make one named Google Places preview query for the venue and suburb. |
| Exact Google match | Add that Google venue to `restaurants`, then say it was found. |
| Similar Google name | Ask a short yes/no question. The candidate is not written to the public venue list until the user says yes. |
| No Google result | Ask for the street (or allow `skip`), then ask permission to add a community venue. |
| `cancel`, `stop`, or a new venue request | Discard the unfinished draft. |

The reply prompt and the deterministic flow use short, simple language. The
model has a 120-token reply limit and may only name venues already provided in
its database context.

## Components and data

- `search-assistant/index.ts` authenticates the caller, enforces the
  per-account assistant budget, routes venue discovery, and owns the draft
  conversation.
- `ondemand-topup/index.ts` owns Google Places access, beta eligibility,
  reservation/cost controls, and additive database writes. `previewOnly` is
  accepted only for a named venue and returns at most five candidates without
  inserting them.
- `assistant_venue_drafts` keeps one in-progress draft per user. Row-level
  security is enabled and browser roles have no privileges; only the Edge
  Function's service role accesses it.
- Community venues are stored in `restaurants` with `source = 'community'`,
  the submitting user id, and an optional address. Google and pipeline rows
  default to `source = 'google'`.

## Deployment

Deploy the migration before either updated function:

```text
supabase/migrations/20260822042954_assistant_venue_discovery.sql
```

Then deploy both functions together because the assistant calls the new
`previewOnly` contract in `ondemand-topup`:

```text
search-assistant
ondemand-topup
```

The production project must already have the existing Edge Function secrets:
`ANTHROPIC_API_KEY`, `GOOGLE_PLACES_KEY`, `PIPELINE_SHARED_SECRET`, and the
runtime-injected Supabase keys. Do not put any of them in the Flutter app or
in source control.

## Verification checklist

Run the automated checks from `stages/03_build/output`:

```text
deno check supabase/functions/search-assistant/index.ts
deno check supabase/functions/ondemand-topup/index.ts
supabase start
supabase test db
```

After deployment, test with a signed-in beta account:

1. Send `crows nest` and confirm coverage is checked before the reply.
2. Send a known venue plus suburb and confirm the existing row is used.
3. Send a misspelling plus suburb and confirm the assistant asks before the
   candidate becomes visible in the list.
4. Send an unknown venue plus suburb, say `skip` for the street, and confirm
   the final yes/no choice creates a `community` row only after approval.
5. Start a draft, then send `cancel` or another venue request and confirm the
   old draft no longer controls the conversation.
