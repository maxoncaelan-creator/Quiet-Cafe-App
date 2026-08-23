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

## Caelan's decision

Before enabling scheduled paid sweeps, choose one:

1. keep the 8,000-call ceiling and explicitly accept the higher potential
   spend;
2. lower the ceiling to match the intended monthly spend; or
3. approve a separate discovery/enrichment design and policy review.
