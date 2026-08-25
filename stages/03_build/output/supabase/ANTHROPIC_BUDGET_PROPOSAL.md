# Global Anthropic ceiling — proposal

**Status:** Implemented 2026-08-25 in
`20260825090000_anthropic_monthly_ceiling.sql`. Kept as the design record.

**One thing this document got wrong.** It described checking the global ceiling
"first, before the per-account window." Done literally, a request that passes the
global check and then fails the per-account one leaves the month charged for a
request that never ran — and reversing the order just mirrors the bug. The
implementation evaluates **both limits before writing either**, so there is no
partial reservation in either direction.

**The ceiling was set from measurement, not estimate**, as this document
insisted. At 2026-08-25 only two accounts had ever used the assistant and the
busiest 5-hour window was 6,864 tokens. 5,000,000 tokens/month is about 2,250
questions, ~75 a day across all users. Confirm the dollar value in the Anthropic
console and change the row, never the migration.

## The problem

Search Assistant calls Anthropic. Spend is capped **per account** — 10,000 tokens
per rolling 5-hour window, enforced atomically by
`claim_search_assistant_budget` — but there is **no ceiling across accounts**.
Sign-up is open, with email confirmation the only friction, so total Anthropic
spend is bounded only by how many accounts exist.

That is the one genuinely unbounded cost in the project. Google Places is capped
at 1,000 requests per UTC month by `places_budget_config` and stopped before
dispatch. Anthropic has no equivalent.

This is **not** the same problem as the beta gate. The gate is a scope control in
the app router plus one server-side check; it changes who reaches the assistant
casually, not what the system will spend. A ceiling holds whether the gate is on,
off, or bypassed again later — which is why this is the durable fix and the gate
is not.

## Shape

Mirror `places_budget_config` deliberately. That pattern is already proven in
production, already understood, and already has a test precedent. A second,
differently-shaped budget system would be worse than a slightly imperfect fit.

### Denomination: total tokens per UTC month

Anthropic bills input and output separately, so a single total is an
approximation. It is a good one here: `MAX_OUTPUT_TOKENS` is 120, while the
prompt carries a system message plus up to 20 venue lines of 180 characters, so
input dominates output by roughly an order of magnitude. A single ceiling is
worth the accuracy loss for the simplicity gain.

Revisit if output ever becomes substantial — a longer `MAX_OUTPUT_TOKENS`, or
streaming replies, would change the ratio.

Month is UTC, matching the Places ledger. Consistency between the two budgets
matters more than picking the theoretically better window for each.

### Tables

```sql
create table public.anthropic_budget_config (
  id boolean primary key default true check (id),
  monthly_token_ceiling bigint not null check (monthly_token_ceiling >= 0),
  updated_at timestamptz not null default now(),
  note text
);

create table public.anthropic_monthly_usage (
  month_start timestamptz primary key,
  reserved_tokens bigint not null default 0,
  settled_tokens bigint not null default 0,
  updated_at timestamptz not null default now()
);
```

One row per month rather than per reservation. The Places ledger keeps a row per
request because it needs a dispatch marker per Google call; there is no
equivalent per-call artefact here, and the per-account table
(`search_assistant_usage`) already holds who spent what.

### Enforcement point

**Extend `claim_search_assistant_budget` rather than adding a second call.**
`search-assistant` already calls it before every Anthropic request, in the right
place — after auth and the beta gate, before any provider call. Adding a separate
global claim would mean two reservations that can disagree.

Check the global ceiling **first**, before the per-account window. Per-account
budget costs nothing to consume, but failing fast keeps the reasoning simple and
avoids a user burning their window on a request that was never going to run.

New outcome value: `global_ceiling_reached`, distinct from the existing
`rate_limited`.

`settle_search_assistant_budget` correspondingly adjusts
`anthropic_monthly_usage`, replacing the reservation with actual usage in the
same transaction it already settles the per-account row.

### Concurrency

Serialise on `pg_advisory_xact_lock(hashtext('anthropic_monthly_budget'))`,
taken **before** the existing per-user lock so lock ordering is consistent and
cannot deadlock against it.

Known trade-off: every assistant request serialises on one global lock. At
current volume that is irrelevant. It becomes a bottleneck long before the
ceiling itself does, and the fix then is sharded counters — deliberately not
built now.

## The user-visible half, which matters more than it looks

The app currently has one failure story: `SearchAssistantRateLimited`, carrying
`resetAt`, rendered as "you're on a break until X."

**A global ceiling must not reuse that message.** Telling someone "you have hit
your limit" when the *app* has hit its monthly limit is a lie, and it sends them
to check their own usage for something they cannot influence. It needs its own
exception, its own 429 payload discriminator, and copy along the lines of "the
assistant is unavailable for the rest of the month" — with no personal reset
time, because there is no personal reset.

Parsing must stay total, the same as `assistantCoverageFromResponse`: an unknown
discriminator falls back to the generic failure rather than throwing.

## Setting the number

**Caelan must read Anthropic billing to set this**, exactly as with Places. The
ceiling is expressed in tokens; the mapping to dollars belongs to the console,
not to a figure inferred from published rates. The Places ledger shipped with a
placeholder that was wrong by 26x precisely because a plausible-looking number
was written down before anyone checked — do not repeat that.

Two anchors for the conversation:

- One account at its cap spends 10,000 tokens per 5-hour window, so about 48,000
  tokens a day if used relentlessly.
- Current usage is effectively nil. The ceiling is a blast radius, not a forecast
  — set it at what an unwelcome surprise would look like, not at expected use.

Store it as an editable row so it can change without a deploy, and add a pgTAP
assertion on the settled value so an edit to an already-applied migration cannot
silently diverge from production. That failure has already happened once.

## Tests

pgTAP, mirroring `places_budget_ceiling.test.sql` and the budget assertions in
`suburb_coverage_automation.test.sql`:

- grants below the ceiling; blocks the request that would exceed it
- settle replaces reservation with actual usage, and usage falls accordingly
- a failed provider call retains the conservative reservation rather than
  refunding it — the existing `finally` block in `search-assistant` already does
  this per-account, and the global counter must agree
- month rollover starts from zero
- the config row is not writable by `anon` or `authenticated`
- every new function is revoked from browser roles at creation, per PR #43

## Deliberately out of scope

- **Per-account limits stay as they are.** This adds a ceiling above them, it
  does not replace them.
- **No spend-based throttling or degradation.** When the ceiling is reached the
  assistant stops, honestly. Silently switching to a cheaper model or a shorter
  context would change answers in ways nobody could see.
- **Nothing about the beta gate.** Independent concern, independent fix.

## Estimated size

One migration, one Edge Function change of a few lines, one new exception plus
parser in the app, one UI string, and a pgTAP file. Comparable to
`20260823091000_places_request_budget.sql`, and smaller than step 1.
