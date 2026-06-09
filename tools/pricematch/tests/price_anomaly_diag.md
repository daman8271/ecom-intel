# W1 — ROOT-CAUSE: same SKU, same price at two different pincodes (Zepto)

**Date:** 2026-06-09 · **Author:** W1 (pmdiag) · **Status:** CLOSED
**VERDICT: REAL (national/zonal pricing) — NOT a scraper bug. W3 should change NOTHING for this issue.**

---

## 1. The symptom

On the competitor price-match sheets, many Zepto SKUs show the IDENTICAL price at both
reference pincodes — 110095 (Delhi) and 560005 (Bengaluru). Owner example:
Extra Light 1 L = ₹499 at both. Confirmed: these are DIFFERENT stores
(Delhi `0c865653…`, Bengaluru `e4a9d9d2…`), same price, both
`price_source=pricingData:SUPER_SAVER`, no duplicate rows. So it is NOT a merge/dedup bug.

The question to settle, neutrally: is same-price-across-pincodes **REAL** (Zepto's
SUPER_SAVER is genuinely uniform for that SKU) or a **BUG** (scraper records a
national/cached price while a true per-store price exists and varies)?

---

## 2. The decisive evidence: it's REAL

### 2a. The same scrape ALSO shows large per-store variation

From the current `platforms/zepto/result.json` (58 pincodes, 46 distinct stores,
in-stock rows), per-canonical distinct SUPER_SAVER prices:

| SKU | # distinct prices across stores | range |
|---|---|---|
| `pomace-olive-oil-5l` | 13 | 2114 – 2494 |
| `canola-cold-pressed-5l` | 6 | 1193 – 1617 |
| `sunflower-cold-pressed-1l` | 4 | 182 – 192 |
| `kachi-ghani-mustard-1l` | 3 | 179 – 181 |
| `groundnut-200ml` | 2 | 49 / 72 |
| `canola-combo-2l` | 2 | 485 / 520 |
| `extra-light-1l` | **1** | **499 everywhere** |
| `pomace-1l` | 1 | 379 everywhere |
| `extra-virgin-1l` | 1 | 934 everywhere |
| `groundnut-1l` | 1 | 199 everywhere |
| `kachi-ghani-5l` | 1 | 960 everywhere |
| `soolive-1l` | 1 | 257 everywhere |

**A scraper that recorded one cached national constant could not produce the
top rows.** pomace-5l ranges ₹2114–2494; the very same run records extra-light-1l flat at
499. So the scraper IS reading genuine per-store prices — when a SKU shows the same number
at both pincodes, that is because Zepto's price for that SKU genuinely IS the same at both
stores, not because we lost the per-store signal.

### 2b. Live PDP probe — same variantId at the two reference stores (run 2026-06-09)

Probe: `/tmp/zepto_w1_probe.js` (read-only, bff-gateway PDP route, no login, /tmp). For each
variant, hit the PDP at the Delhi store and the Bengaluru store, dumping the full
`pricingData.pricingEntityPrices`:

```
=== extra-light-1l (FLAT in data) ===
  Delhi 110095     store=0c865653 mrp=1499 tiers={SUPER_SAVER:499, ULTRA_SAVER:474}
  Bengaluru 560005 store=e4a9d9d2 mrp=1499 tiers={SUPER_SAVER:499, ULTRA_SAVER:474}   ← identical, LIVE

=== pomace-5l (VARIES in data) ===
  Delhi 110095     store=0c865653 mrp=4999 tiers={SUPER_SAVER:2128, ULTRA_SAVER:2128}
  Bengaluru 560005 store=e4a9d9d2 mrp=4999 tiers={SUPER_SAVER:2494, ULTRA_SAVER:2494}  ← ₹366 apart, LIVE

=== kachi-ghani-1l (VARIES in data) ===
  Delhi 110095     store=0c865653 mrp=255 tiers={SUPER_SAVER:180, ULTRA_SAVER:171}
  Bengaluru 560005 store=e4a9d9d2 mrp=255 tiers={SUPER_SAVER:181, ULTRA_SAVER:172}    ← ₹1 apart, LIVE
```

Conclusions from the live probe:
1. **The API returns genuinely per-store prices.** Identical variantId → different price by
   store (2128 vs 2494; 180 vs 181). Our recorded values match the live values exactly.
2. **extra-light-1l really is 499 in BOTH cities** — verified live, not a stale/cached
   artifact. The same-price symptom is a true fact about Zepto's pricing.
3. **There is NO per-store tier we should switch to.** The `marketplace_type` header
   (SUPER_SAVER vs ZEPTO_NOW) makes ZERO difference at the PDP route — both return the
   identical tier set. The only other tier exposed is **ULTRA_SAVER** (an even-cheaper
   scheduled tier, e.g. 474 vs 499), which follows the SAME per-store variation pattern.
   SUPER_SAVER is the default app-shown price and the correct consumer-facing comparison.

> Note: the old "Canola 469 SS vs 485 NOW" differential (memory:
> `zepto-staleness-false-positive`) was a SEARCH-response tier split. At the PDP route the
> two marketplace headers return identical numbers for these SKUs, so there is no
> more-varying NOW price to harvest. Switching tiers would not "fix" the flat SKUs — they
> are flat in every tier.

**Why some SKUs are flat across cities:** Zepto sets the SUPER_SAVER price for its
high-volume hero SKUs (1 L olive/pomace bottles) at a uniform city-spanning / near-national
level, and lets longer-tail and large-pack SKUs (5 L tins, mustard, sunflower) drift per
store/zone. Both behaviours are captured correctly.

---

## 3. Cross-platform: per-pincode vs national (does price vary, and is that real?)

From each platform's current `result.json` (in-stock rows; distinct SUPER_SAVER/sale price
per canonical across that platform's scraped pincodes):

| Platform | pincodes scraped | SKUs vary / flat | Verdict |
|---|---|---|---|
| **blinkit** | 154 | 9 vary / 0 flat | **REAL per-store.** Hyperlocal; every SKU drifts ₹1–several across stores (pomace 379–382, sunflower 192–209, canola 250–256). Genuine per-store pricing. |
| **zepto** | 58 (46 stores) | 6 vary / 12 flat | **REAL (mixed).** Per-store where Zepto varies (pomace-5l 2114–2494, canola-5l 1193–1617); uniform city-spanning for hero 1 L SKUs (499, 379, 199). Proven live above. |
| **amazon-now** | 105 | 17 vary / 8 flat | **REAL per-city.** Owner: uniform WITHIN a city, varies ACROSS cities. Data agrees (canola-5l 1193/1249, pomace-5l 1950–2083). |
| **flipkart-minutes** | 89 | 3 vary / 6 flat | **REAL.** Hyperlocal store; some SKUs vary (canola 241–267, pomace 379–405), heroes flat. |
| **bigbasket** | 1 (member address, tagged "All India") | 0 vary / 11 flat | **REAL by design.** Single logged-in member address → one national member price; not a per-pincode scrape. |
| **flipkart** | 1 | 0 vary / 106 flat | **REAL by design.** Marketplace national pricing, 1 row/SKU. No location dimension. |
| **amazon** | 1 | flat (1 minor pack-parse outlier) | **REAL by design.** Guest /dp, no account location → national listing price. |

Takeaway: the **4 genuinely multi-pincode platforms** (blinkit, zepto, amazon-now,
flipkart-minutes) ALL show real per-store variation → the scrapers capture per-store prices
correctly. The **3 single-location platforms** (bigbasket, flipkart, amazon) are national by
design and SHOULD be flat. Zepto is correctly in the multi-pincode group; its flat SKUs are
flat because Zepto prices them uniformly, not because we collapsed the signal.

---

## 4. Competitor-sheet implication & recommendation

Pinning Zepto to **110095 vs 560005 is ACCURATE, not misleading.**
- When the two columns MATCH (extra-light 499/499) → that is a **true** cross-city parity
  fact, just verified live.
- When they DIFFER (pomace-5l 2128/2494, kachi-ghani 180/181, canola-5l) → the sheet
  correctly surfaces real per-store variation.

**No data change required. No relabeling required.** SUPER_SAVER is the right price (default
app-shown, consumer-facing).

Optional (cosmetic, owner's call — NOT a fix): a one-line legend note that "Zepto sets many
high-volume SKUs at a uniform city-spanning SUPER_SAVER price, so cross-city parity on those
rows is expected and real." This is presentation only.

---

## 5. Hand-off to W3 (zepto scraper)

**Change NOTHING for this issue.** The scraper already records the authoritative per-store
SUPER_SAVER price from `pricingData.pricingEntityPrices` (scrape.js `tierPrice`/`tierPriceSP`)
and that is correct. There is no per-store tier "X" to switch to — ZEPTO_NOW is identical at
PDP, ULTRA_SAVER varies the same way and is not the default price.

Out-of-scope, separate-ticket idea only (do NOT bundle here): Zepto also exposes an
even-cheaper **ULTRA_SAVER** tier; if the owner ever wants the absolute floor price, it could
be captured as an extra column. Irrelevant to the same-price-across-pincodes question.

---

## Reproduce
- Data: `python3` over `platforms/zepto/result.json` `allRows` (per-canonical distinct `sale`).
- Live probe: `cd platforms/zepto && node /tmp/zepto_w1_probe.js` (read-only, /tmp, no login,
  6 PDP calls). Same variantId at the two reference stores; dumps every price tier.
