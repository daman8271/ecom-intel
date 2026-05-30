---
type: analysis-dashboard
title: Price Intelligence — Live Dashboard
tags:
  - moc
  - analysis
created: 2026-05-30
---

# Price Intelligence — Live Dashboard

Up: [[index]] · Sibling: [[analysis-index]]

> **Requires the *Dataview* community plugin** (Settings → Community plugins → Browse →
> "Dataview" → Install → Enable). These are live queries over the `min_price` /
> `max_price` / `latest_price` / `platforms` / `last_seen` / `observations` fields that
> `tools/vault_build.py` writes into every SKU hub's frontmatter. They refresh every
> time the vault syncs — nothing here is hand-maintained.

---

## 🟢 Cheapest right now (lowest `latest_price`)
```dataview
TABLE WITHOUT ID
  link(file.link, display_name) AS "Product",
  latest_price AS "₹ now", min_price AS "₹ low", max_price AS "₹ high",
  join(platforms, ", ") AS "Where", last_seen AS "Seen"
FROM "skus"
WHERE type = "sku-hub" AND latest_price
SORT latest_price ASC
LIMIT 30
```

## 🔻 At/under their cheapest-ever (buy-signal: `latest_price` ≤ `min_price`)
```dataview
TABLE WITHOUT ID
  link(file.link, display_name) AS "Product",
  latest_price AS "₹ now", min_price AS "₹ best-ever",
  join(platforms, ", ") AS "Where", last_seen AS "Seen"
FROM "skus"
WHERE type = "sku-hub" AND latest_price AND min_price AND latest_price <= min_price
SORT latest_price ASC
```

## 📈 Biggest price swing (spread = `max_price` − `min_price`)
```dataview
TABLE WITHOUT ID
  link(file.link, display_name) AS "Product",
  min_price AS "low", max_price AS "high",
  (max_price - min_price) AS "swing", latest_price AS "now",
  join(platforms, ", ") AS "Where"
FROM "skus"
WHERE type = "sku-hub" AND min_price AND max_price AND max_price > min_price
SORT (max_price - min_price) DESC
LIMIT 25
```

## 🧊 Possibly delisted / stockout (not seen in 2+ days)
```dataview
TABLE WITHOUT ID
  link(file.link, display_name) AS "Product",
  last_seen AS "Last seen", latest_price AS "Last ₹",
  join(platforms, ", ") AS "Where"
FROM "skus"
WHERE type = "sku-hub" AND last_seen AND last_seen < date(today) - dur(2 days)
SORT last_seen ASC
LIMIT 30
```

## 📊 Most-observed SKUs (data depth)
```dataview
TABLE WITHOUT ID
  link(file.link, display_name) AS "Product",
  observations AS "obs", latest_price AS "₹ now",
  join(platforms, ", ") AS "Where", first_seen AS "Since"
FROM "skus"
WHERE type = "sku-hub"
SORT observations DESC
LIMIT 20
```

## 🛒 Per-platform price board
Change `""` to `blinkit` / `flipkart` / `flipkart-minutes` / `amazon` to retarget.
```dataview
TABLE WITHOUT ID
  link(file.link, display_name) AS "Product",
  latest_price AS "₹ now", min_price AS "₹ low", max_price AS "₹ high",
  observations AS "obs"
FROM "skus"
WHERE type = "sku-hub" AND contains(platforms, "") AND latest_price
SORT latest_price ASC
LIMIT 40
```

## 🔢 Catalog coverage by platform
```dataview
TABLE WITHOUT ID
  rows.platforms AS "Platform",
  length(rows) AS "SKUs tracked"
FROM "skus"
WHERE type = "sku-hub"
FLATTEN platforms AS platforms
GROUP BY platforms
SORT length(rows) DESC
```

---

### Notes
- `latest_price`/`min_price`/`max_price` exist only on SKUs that were ever **in-stock and
  priced** (currently ~659 of ~817 hubs). SKUs that never showed a price are omitted from
  price tables by the `WHERE … latest_price` guard — that's intentional.
- Prices mix per-pincode (quick-commerce: blinkit, , flipkart-minutes) and
  national (amazon, flipkart). `min`/`max`/`latest` are across **all** observed locations
  for that SKU, so a wide "swing" can mean geographic price spread, not just time movement.
- For true time-series / forecasting, the source of truth is `data/<platform>/history.csv`
  and the deterministic `tools/predict.py` Predictions sheet — see [[analysis-index]].
