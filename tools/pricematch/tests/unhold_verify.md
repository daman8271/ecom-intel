# W3 adversarial verification — unhold flipkart + zepto (2026-06-08)

**Role:** independent adversarial verifier. I did NOT trust W1/W2's claims — I re-derived
every verdict from production data + the committed code. The LEAD re-delivers the held
flipkart/zepto reports + pushes ONLY on the PASS below.

**Code under verification:** `review-cal: identity-aware shared_price_dup + mover-aware
price_staleness` (commit `a4bce2db`, HEAD). Pre-change = HEAD~1. zepto scraper untouched
(W2 confirmed FRESH-FALSE-POSITIVE; no scraper change).

---

## VERDICT: ✅ PASS — both held platforms SHIP, zero regression on the other 6

| Platform | SHIP? | Why |
|---|---|---|
| **flipkart** | ✅ **SHIP** | 3 flagged shared-price pairs are all the SAME underlying product / legit combos, not fabrication. Prices sane. False positive correctly cleared. |
| **zepto** | ✅ **SHIP** (data as-is, zero change) | 14 "frozen" SKUs are genuinely price-stable, not stuck. Detector was a false positive; recalibrated detector clears it and still catches a truly-stuck scraper. |
| amazon, amazon-fresh, amazon-now, bigbasket, blinkit, flipkart-minutes | ✅ unchanged | Identical verdict AND identical per-check pass status before vs after. |

---

## 1. flipkart — genuinely OK to ship (independent inspection)

Inspected `platforms/flipkart/result.json` directly (268 rows, 159 priced). The only
qualifying shared discounted (sale,mrp) pairs:

| pair (sale,mrp) | listings | identity check |
|---|---|---|
| (1285, 1650) | `CANOLA 5L` (FSN EDOHHX9R…), `CANOLA 5L` (FSN EDOHYRG4…), `CANOLA 4+1L` combo | **same product** — Canola 5L under two seller FSNs (both SAP FG0000118) + a 4+1L combo = 5L canola |
| (1496, 3247) | `EXTRA LIGHT 1L+POMACE 1L+EXTRA VIRGIN 1L`, `EXTRA LIGHT 1L+EXTRA VIRGIN 1L+POMACE 1L` | **same combo** — identical 3×1L olive-oil bundle, oils listed in a different name order |
| (1404, 2025) | `CANOLA 5+1L` (FSN EDOHHXAB…), `CANOLA 5+1L` (FSN EDOHHZBQ…) | **same product** — Canola 5+1L combo under two seller FSNs |

→ Every shared pair is a marketplace seller-duplicate of one product and/or a combo that
naturally shares a bundle price. **Zero unrelated-product-at-a-fabricated-price.** The old
`shared_price_dup` counted per-FSN `canonical`, so seller-duplicates looked like "distinct
SKUs" — that is the false positive.

**Price sanity spot-check (10 SKUs across the range):** 0 rows with `sale > mrp`; oil SP/MRP
all plausible (MUSTARD 5L 1133/1250, EXTRA VIRGIN 250ML 219/450, A2 GHEE 500G 572/2200,
POMACE 5L+2L 2553/4997 …); per_litre values sane. The only two >80% discounts are non-oil
accessories (ginger-ale 6-pack, roti box) — not the core Jivo oil intelligence, not
fabrication. **flipkart data = SHIP.** (`sku_map.json` not present in repo; verified against
the in-row `item`/`fk_name`/`sap_code` fields instead.)

## 2. W1's `shared_price_dup` change — identity-correct AND still catches fabrication

Logic (verified by reading the diff): combo listings excluded (`item`/`sku_raw` contains
`+`/`combo`/`pack of N`); remaining rows collapsed to a normalized product identity
(`item`, else `canonical`); count distinct **identities** ≥ N. Monotonically RELAXING vs the
old canonical count (identities ≤ canonicals, combos dropped) → it can only clear false
positives, never newly-flag a clean platform.

Fixtures (`tools/pricematch/tests/unhold_fixtures.py`, all PASS):
- **A — fabrication STILL FIRES:** one price stamped across 5 unrelated non-combo oils →
  **BROKEN**; across 3 unrelated oils (padded so the fraction path is dormant) → **SUSPECT**.
  The genuine signal survives.
- **B — flipkart legit case PASSES:** the real 3 pairs above (seller-dups + combos) →
  PASS ("no discounted pair shared across distinct products").

## 3. zepto — independently confirmed FRESH-FALSE-POSITIVE (did not just accept W2)

From `data/zepto/history.csv` (23 runs; frozen window = last 9, `2026-06-05-0421` →
`2026-06-08-1144`):
- The 14 "frozen" SKUs' own scraper captured a **real price spike+revert on 2026-06-03/04**
  immediately before the window — extra-light-1l 499→560→499, groundnut 199→230→199,
  pomace 379→426→379, and mustard-1l 149→**181** + sunflower-1l 230→**192** which *persisted*
  a genuine change. A stuck snapshot path cannot produce those transitions → the path is live.
- **Cross-platform freshness:** blinkit shows the same SKUs at the same price LEVELS
  (extra-light-2l = 1135, pomace-1l = 379 — identical to zepto) with only minor wiggle; the
  prices are real and correctly-leveled, just stable. (W2 independently confirmed via 9/23
  zepto SKUs moving on the same snapshot path, a bigbasket cross-check, and a live PDP probe
  where the frozen value == today's live value.)
- Root cause of the false positive: `pct_non_realtime` is ~100% for every zepto run
  (`mongo_data_exists` = all stores), so the `NONREALTIME_GATE` is permanently open and gives
  zero discrimination — the old alarm reduced to "any price stable for 9 runs".

W1's recalibration: alarm now requires `frozen AND snapshot AND **no SKU moved across the
window**` — i.e. a stuck path freezes *everything*; if anything moved, the path is live and a
frozen price is genuine market stability. Verified still catches a stuck scraper:
- **C — truly-stuck scraper STILL FIRES:** every SKU frozen 9+ runs, snapshot path, zero
  movers → SUSPECT ("path looks stuck").
- **D — genuinely-stable PASSES:** frozen SKUs but one mover on the same path → PASS
  ("path proven live by 1 SKU that moved → genuinely stable"). This is the zepto real case.

**Caveat (noted, not blocking):** the new rule treats the path as live if *any* SKU moved, so
a *partially*-stuck scraper (some SKUs cached, others live) would not alarm. That is a strictly
better failure mode than the old "any stable price → hold", and a fully-stuck scraper (the real
risk) still fires. Recommend the daily guardian keep an eye on per-SKU staleness if this ever
matters.

## 4. NO collateral — regression gate (the whole point)

Ran `review.py`'s deterministic checks against ALL 8 platforms' CURRENT `result.json`,
side-effect-free (no baseline/verdict writes), importing **HEAD~1 (before)** and **HEAD
(after)** as isolated modules — harness `tools/pricematch/tests/unhold_regress.py`:

| platform | before | after | flip | per-check pass diffs |
|---|---|---|---|---|
| flipkart-minutes | OK | OK | — | none |
| **flipkart** | **SUSPECT** (shared_price_dup) | **OK** | ✅ FLIP | shared_price_dup |
| **zepto** | **SUSPECT** (price_staleness) | **OK** | ✅ FLIP | price_staleness |
| bigbasket | OK | OK | — | none |
| amazon | OK | OK | — | none |
| amazon-fresh | OK | OK | — | none |
| amazon-now | OK | OK | — | none |
| blinkit | OK | OK | — | none |

**GATE = PASS:** the only verdict flips are flipkart→OK and zepto→OK; the other 6 are
identical not just in verdict but in **every individual check's pass status** before vs after.

---

## Reproduce
```
python3 tools/pricematch/tests/unhold_regress.py     # 8-platform deterministic verdicts
python3 tools/pricematch/tests/unhold_fixtures.py     # 4 adversarial fixtures, all PASS
```

**W3 → PASS. Both held reports are shippable; zero regression. LEAD cleared to re-deliver
flipkart + zepto and push.**
