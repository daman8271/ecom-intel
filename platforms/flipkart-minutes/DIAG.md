# Flipkart-Minutes thin / "n/s wall" deep-dive — 2026-06-09 (W2, pmdiag)

## VERDICT: **REAL thin catalog. The n/s wall is CORRECT — NOT a scraper bug.**
Flipkart Minutes is a hyperlocal dark-store model. Each dark store stocks only a **subset
(0–8) of the ~9 national Jivo SKUs**. The owner-flagged "almost nothing / n/s for most SKUs"
is the genuine per-store assortment, not under-resolution. **No scraper change made** (the
scraper sets location correctly, captures the full per-store result set, and dedups
correctly). The fix is **presentation-side (W4)**: de-clutter the n/s wall — there is nothing
to fix in the scrape.

---

## What the owner saw
- 560005 → 1 SKU (OOS), 110095 → 4 SKUs, ~269–270 rows total across all pincodes today.
- Concern: scraper is under-resolving (location not taking / pagination cut / wrong store).

## How many Jivo SKUs fkm carries (coverage NOT shrinking)
National distinct Jivo SKUs is **stable at 9–11 across 18 days** of history.csv:
```
date        rows  uSKU  pins        date        rows  uSKU  pins
2026-05-21   72   10   26           2026-06-01  832   11    99
... (10–11 SKUs) ...                2026-06-05  610   10    98
2026-05-30  466   11   96 (grid     2026-06-07  441   10    91
2026-05-31  884   11  107  →345)    2026-06-08  443    9    91
                                    2026-06-09  520    9    90
```
Today: **9 distinct SKUs nationally** (canola 1L, mustard 1L, extra-light olive 2L, mineral
water 1L, pomace olive 1L, mustard 5L, soybean 1L, pomace olive tin 5L, canola combo 2L).
The dip 11→9 is 1–2 genuine national delists/canonical merges, NOT a coverage collapse — the
scraper still captures every SKU the brand lists on the platform.

## Per-pincode is thin because each DARK STORE is thin (the decisive evidence)
Rows-per-pincode today: 24 pins=1 SKU, 15=2, 17=3, 18=4, 5=5, 3=6, 6=7, 1=8. Max 8 of 9.

**Per-store SKU count has ZERO variance** across every pincode a given store serves:
```
mum_007_wh_hl_01  n=7 pincodes  → 3 SKUs every time (union=3)
del_113_wh_hl_01  n=2           → 5 every time
del_193_wh_hl_01  n=2           → 4 every time   (this is 110095's store)
ben_172_wh_hl_01                → 1               (this is 560005's store)
```
A scraper that under-resolved (location sometimes not taking, pagination sometimes cutting)
would produce **variance** within the same store. There is **none** — each warehouse returns
its fixed Jivo assortment deterministically. Store ids are real warehouse codes
(`<city>_NNN_wh_hl_01`).

## Live probe (lock-safe, /tmp, result.json untouched) — confirms it directly
Replayed the exact 2-POST flow (`location/update` → `page/fetch q=jivo&HYPERLOCAL`) live:

| pincode | locStatus | total products in response | Jivo found | pagination hints |
|---|---|---|---|---|
| 110095 Delhi | 200 | 34 | **5** listings (→4 SKUs after dedup) | none |
| 560005 Bengaluru | 200 | 31 | **1** (Canola 1L) | none |
| 201304 Noida | 200 | 34 | 4 | none |
| 400050 Mumbai | 200 | 30 | **0** (store serviceable, no Jivo) | none |
| 110092 Delhi | 200 | 32 | 2 | none |

Three things proven:
1. **Location IS set per pincode** — `locStatus 200`, each store returns a *different*
   store-specific Jivo subset. No store cross-talk.
2. **No pagination truncation** — each response carries the FULL result set (~30–34 products,
   well under any page cap) with **zero** `nextUrl`/`hasMore`/`totalPages` hints. Every Jivo
   item the store carries is in page 1; nothing is dropped.
3. **560005 genuinely has 1 Jivo SKU; 400050 genuinely has 0.** 110095 returns the SAME
   mustard-oil SKU as 2 distinct seller listings → the scraper's `store_id|canonical` dedup
   correctly collapses to 4 rows. That is correct de-duplication, not a missed SKU.

## "Serviceable but 0 Jivo" (65 pincodes) and non-serviceable CBD pincodes — also REAL
- 65 serviceable pincodes carry 0 Jivo: store is open, just doesn't stock Jivo (e.g. 400050).
- 110001 / 400001 / 560001 are non-serviceable (`redir 302`). Tested a CORRECTED central
  Bangalore coord for 560001 (12.9766,77.5993 vs the grid's off-center 13.2257,77.575): **still
  `redir 302`**. So these CBD/port pincodes are genuinely not served by Flipkart Minutes — the
  coordinate is not the lever for them, ruling out geocoding as the dominant cause here.

## Residual coverage note (NOT a scraper bug; data follow-up, like blinkit)
There is a latent geocoding-accuracy gap on *some* edge pincodes (grid coords are
region-level, not street-level), and the 345-point grid maps many pincodes onto one
store-point. Squeezing more coverage would come from **grid/geocoding tuning (a data task)**,
not scraper logic. The scraper correctly records non-serviceable rather than contaminating.

## Decision
- **Scraper: UNCHANGED.** Location-setting, single-page capture, and dedup are all correct and
  complete. Tomorrow's 08:32 sweep is unaffected; `result.json` contract identical.
- **Owner answer:** fkm genuinely stocks only a thin, per-store subset of Jivo's range. The
  n/s wall is the truth of a hyperlocal dark-store network. → **W4 presentation de-clutter**
  (collapse the n/s wall, show per-store availability cleanly), not a scrape fix.

_Probe scripts: /tmp/fkm_probe.js, /tmp/fkm_probe2.js (read-only, never wrote result.json)._
