# Zepto seed completeness fix + CANOLA 1+1L ₹469 investigation (2026-06-09, zepto-seed/W1)

## What changed
`jivo_variants.json` `variants` was rebuilt from 11 → **23** ids — the COMPLETE known-variant
**union** of:
- (a) the prior seed (11),
- (b) every Jivo zepto `id` in `tools/pricematch/sku_map.json` (19),
- (c) every distinct `variant_id` ever seen in `platforms/zepto/result.json` across all pincodes (23).

Confirmed final count = **23** (result.json's 23 distinct ids is a superset of both other sources;
`data/zepto/history.csv` carries no variant column, so it adds nothing). The task's "~34" estimate
was high.

`scrape.js` is **untouched**. Enlarging the seed is data-only and tomorrow-safe: it only makes the
next sweep more complete. Cost = one extra PDP probe per serviceable store per added variant
(11→23 = **+12 probes/serviceable store/sweep**).

## Why (the proven bug)
The Zepto scraper finds products two ways: SEARCH (Algolia — index-lagged, rollup-collapses
pack-size siblings, in-stock-gated) **plus** a SEED of variantIds PDP-probed at every serviceable
store. A variant that is only ever search-discovered (not seeded) is **missed at any store where
search doesn't surface it** → recorded as a false n/s. The owner caught exactly this: CANOLA 1+1L
(`50b56b7f-3d9f-45c7-8161-c2327e8db652`) was search-discovered but **not in the seed**, so at
560005 (where search lagged) we recorded nothing. With the variant now seeded, the PDP probes
every store for it → **n/s is authoritative** (a SKU is "not here" only when the PDP route says so).

9 master-SKU variants were seed-missing (CANOLA 1+1L, EXTRA LIGHT 1L/2L, GROUNDNUT 1L,
POMACE 1L / 1L+1L / 2L, MUSTARD 1L, SUNFLOWER 1L). All now seeded.

## Targeted re-scrape + merge (110095 + 560005)
Lock-safe (`flock .zepto.lock`, scraped to `/tmp`, never overwrote prod result.json during scrape):
- **560005:** 16 → 23 rows; +7 newly present incl. CANOLA 1+1L now **in_stock @ ₹485**.
- **110095:** 21 → 23 rows; CANOLA already present (search) — now also +EXTRA LIGHT 2L, +EXTRA LIGHT Combo 2Lx2.
Merge into prod result.json was idempotent (drop existing 110095/560005 rows → append fresh),
backed up to `result.json.bak-w1-refmerge`, summary aggregates recomputed, JSON validated.

## The ₹469 vs ₹485 question (focused probe, raw + stable x3)
The owner's photo showed CANOLA 1+1L LIVE @ **₹469** at 560005 / "Maruthi Seva Nagar". Investigated:
1. **Store:** every 560005-area coordinate (Pulikeshinagar, Maruthi Seva Nagar core/alt, LR Nagar,
   the 560005 geocode) resolves to the SAME store pair — PRIMARY `e4a9d9d2`, SECONDARY `d4205b92`.
   There is **no distinct Maruthi Seva Nagar dark store** with its own price; the location chip is
   cosmetic. Our scrape already hits `e4a9d9d2` for 560005.
2. **Stock:** `availableQuantity = 1` → in-stock. The false n/s is gone.
3. **Price:** the live gateway PDP authoritatively returns, stable across 3 probes:
   **SUPER_SAVER ₹485** (dsp 48500, 35% off, MRP ₹750), **ULTRA_SAVER ₹461** (46100).
   The full raw `storeProduct` has **no ₹469 anywhere** (no 46900); `nonPassTotalDiscount = ₹265`
   → even a non-pass user pays ₹485.

**Conclusion:** ₹469 (= ₹281 OFF / 37.5%) was a **point-in-time promo that has since ended**; the
live price moved 469 → 485 (now ₹265 OFF / 35%). A genuine Zepto intraday reprice, NOT a scraper
bug. We do not fabricate 469 — the scrape now correctly captures the variant in-stock at the
authoritative live price. The owner's underlying complaint (shown as absent while actually live) is
**fully corrected**; the specific ₹469 cross-platform exact-match with Amazon Core (₹469) was real
but is no longer live.
