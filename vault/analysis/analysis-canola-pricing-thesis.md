---
type: analysis-note
title: Canola cold-press — pricing thesis (working)
status: draft
tags:
  - analysis
  - thesis
  - category/canola
created: 2026-05-30
---

# Canola cold-press — pricing thesis (working)

Up: [[analysis-index]] · Dashboards: [[price-intel-dashboard]] · Home: [[index]]

> This is an example of a **hand-written** note that links *into* the auto-generated
> graph. It lives in `vault/analysis/`, so the cron rebuild never touches it. Edit it
> freely, fork it per category, delete it when you have your own. The point is the
> pattern: write your read, then link the live SKU + platform hubs so it all connects in
> Obsidian's graph view.

## The question
Where is Jivo cold-press **canola** cheapest right now, who's discounting hardest, and is
the budget **Sano** line undercutting the flagship Jivo line on the same shelf?

## Anchor SKUs (live hubs — click through for full price history)
- [[jivo-canola-cold-press-edible-oil-1l]] — flagship 1 L, the most-observed canola SKU
- [[jivo-cold-pressed-canola-oil-1l]] — alt 1 L listing
- [[jivo-cold-pressed-canola-oil-5l]] — 5 L value pack
- [[jivo-canola-cold-pressed-edible-oil-5-litres-5l]] — IMA-badged 5 L
- [[sano-canola-oil-healthy-cooking-oil-for-daily-userecommended-by-for-all-type-of-cuisineslowest-in-saturated-fat-1l-1l]] — Sano budget 1 L (watch vs flagship)

## Platforms in play
[[blinkit]] · [[]] · [[zepto]] · [[flipkart-minutes]] (quick-commerce, per-pincode)
· [[amazon]] · [[flipkart]] (marketplace, national)

## Live data — every canola SKU by current price
```dataview
TABLE WITHOUT ID
  link(file.link, default(display_name, file.name)) AS "Product",
  latest_price AS "₹ now", min_price AS "₹ low", max_price AS "₹ high",
  (max_price - min_price) AS "swing",
  join(platforms, ", ") AS "Where", last_seen AS "Seen"
FROM "skus"
WHERE type = "sku-hub" AND contains(lower(file.name), "canola") AND latest_price
SORT latest_price ASC
LIMIT 60
```

## Working notes (fill these in as you watch)
- [ ] Cheapest channel for the flagship 1 L right now → __
- [ ] Is `latest_price` at/under `min_price` anywhere? (buy signal) → __
- [ ] Sano 1 L vs Jivo 1 L gap on the same platform → __
- [ ] Any SKU not seen in 2+ days (stockout / delist)? cross-check [[price-intel-dashboard]] → __
- [ ] Biggest swing — is it time-movement or just geographic spread? → __

## Thesis (rewrite as evidence lands)
> _Draft: cold-press canola is priced as a premium-daily oil; quick-commerce runs deeper
> promo than marketplace, and Sano floors the category. Confirm against the table above._
