# Places discovery/enrichment proposal — decision required

**Status:** Proposal only. No discovery/enrichment split is implemented in
Step 1.

## What the current field mask costs

`places-search` currently asks for `places.reviews`. Google classifies that as
the **Text Search Enterprise + Atmosphere** SKU; `priceLevel`, `rating`, and
`userRatingCount` are Enterprise fields. On Google's current global price list
(reviewed 2026-08-23), Text Search Enterprise + Atmosphere has 1,000 free
monthly requests and costs USD $40 per 1,000 in the first paid tier.

Therefore, if every request reaches Google, the approved operational ceiling of
8,000 calls could cost roughly **USD $280/month** outside India:

```text
(8,000 - 1,000 free requests) / 1,000 × $40 = $280
```

This is an inference from the published global list, not a billing-console
quote. Actual invoicing can differ by account region, negotiated pricing, SKU
mix, and free-use consumption by other project traffic. It does show that the
existing 8,000-call ceiling is not compatible with the plan's previous
USD $10/month assumption if all calls carry `reviews`.

Sources:

- [Google Text Search (New) field-mask SKU mapping](https://developers.google.com/maps/documentation/places/web-service/text-search)
- [Google Maps Platform global pricing list](https://developers.google.com/maps/billing-and-pricing/pricing)

## Proposed two-phase experiment

1. **Discovery:** Text Search with the minimum ID-only field mask (`places.id`
   and pagination), retaining no extra Google fields. Google documents this as
   the Essentials ID Only SKU.
2. **Deduplicate:** compare returned IDs with `restaurants.place_id`.
3. **Enrich only new or stale IDs:** use Place Details with the current review
   fields only after deciding that a new venue needs scoring. Google lists
   Place Details Enterprise + Atmosphere separately, with a 1,000-request free
   cap and USD $25/1,000 in the first paid global tier at the time reviewed.

Potential benefit: repeated locality sweeps no longer buy reviews for rows the
app already has. It can turn a broad coverage pass into mostly low-cost ID
discovery plus a bounded set of detail requests.

## Why it is not in Step 1

- It changes the data/scoring ingestion contract, so it needs a separate
  migration and validation plan rather than an implicit optimization.
- It must be checked against current Google Places data-storage and attribution
  terms before persisting any newly returned fields.
- It needs a benchmark using real suburb response distributions before claiming
  a dollar saving.

## Caelan's decision — made 2026-08-23

**Option 2: stay inside the free tier until user numbers justify paying.**

The ceiling is now **1,000 requests per UTC month**, set by
`20260823110000_free_tier_places_ceiling.sql`. That is the largest value that
stays within Google's free allowance for Text Search Enterprise + Atmosphere,
so the expected marginal cost of the app's automated sweeps is zero.

Review the ceiling when active users reach 50, 100, 300, 500, 1000, 5000, and
every 10,000 thereafter. Option 3 (the discovery/enrichment split) is not
rejected — it is deferred, and becomes the thing to do *instead of* simply
buying a higher ceiling, because it raises effective coverage per dollar rather
than raising spend.

### Two things this decision does not cover

**The 8,000 figure never reached the database.** It was written into
`20260823091000_places_request_budget.sql` by PR #46 after that migration had
already been applied, so production continued to hold the original 300 while
the repository claimed 8,000. Applied migrations do not re-run and that insert
carries `on conflict do nothing`. The new migration uses an unconditional
`update` so both a fresh database and production converge on 1,000, and
`places_budget_ceiling.test.sql` now asserts the settled value so the same
silent divergence fails a test instead of going unnoticed.

**The ledger does not see the whole bill — but in practice it now does.** It
governs only Google traffic routed through the `places-search` Edge Function;
`data-pipeline/src/places.js` calls Google directly and is not counted.
Caelan confirmed on 2026-08-23 that **no further full seed runs are planned** —
coverage grows through automated sweeps only. That retires the gap
operationally rather than closing it in code. Bringing the pipeline under the
same ledger is therefore not urgent, but a future seed run would exceed the
free allowance on its own and must be treated as a budgeted exception.
