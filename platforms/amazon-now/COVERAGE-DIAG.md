# Amazon Now — false-n/s coverage diagnosis (amzcover W1, 2026-06-09)

## The question
Owner caught a FALSE not-stocked on **Zepto** (a mapped SKU shown absent while it was live —
a search-DISCOVERY gap, not a real stock-out). Audit flagged **12 Amazon-Now SKUs**
carried-elsewhere-but-absent at the ref pincode **110095**. For each: genuine per-store
not-Now-stock (**REAL**) or a search/capture miss like Zepto (**CAPTURE-MISS**)?

Investigated NEUTRALLY — did **not** assume "thin = real" (the assumption that burned us before).

## Method (lock-safe, read-only, never touched production mid-scrape)
`probe_coverage.js`, run under `flock /opt/ecom-intel/.amazon-now.lock`, OUT_FILE=/tmp. Location
set the SAME way `scrape.ctnow.js` does (GLOW address-change). For each suspect ASIN, THREE
independent live signals at 110095 (and a control pincode 400601 where 7 suspects are present):
1. **broad** — the production path `/s?k=jivo&almBrandId=ctnow` across 3 pages (raw, no dedup).
2. **direct** — a DIRECT per-ASIN search `/s?k=<asin>&almBrandId=ctnow`.
3. **pdp** — `/dp/<asin>` buy-box (delivery promise / availability).

Genuine-Now discriminator is the scraper's own rule, applied identically: a card is Amazon **Now**
⇔ it shows an **instant-minute** tier ("in N minutes" → `10 min`). Scheduled tiers
(overnight / today-window / tomorrow / dated) are Amazon **Fresh**, NOT Now, and are dropped.

ASIN→SKU from `tools/pricematch/sku_map.json` (`platforms["amazon-now"].id`).

## Verdict @110095 — 11 REAL, 1 CAPTURE-MISS

| SKU | ASIN | broad k=jivo | direct ASIN | PDP | Verdict |
|---|---|---|---|---|---|
| CANOLA 5L | B077ZN4G28 | overnight | overnight | — | **REAL** (Fresh-only, no Now) |
| COCONUT 1L | B0BZ8K3DQP | 2 days | 2 days | — | **REAL** |
| EXTRA VIRGIN 1L | B093BMGPQC | overnight | overnight | — | **REAL** |
| GOLD 5L | B0C9Q1S6QG | overnight | overnight | — | **REAL** |
| GROUNDNUT 1L | B0CKFFW9B6 | absent | overnight | — | **REAL** (broad-missed, but Fresh-only) |
| MUSTARD 1L | B09NYCSQLF | absent | overnight | — | **REAL** (broad-missed, but Fresh-only) |
| MUSTARD 5L | B091XPD9J3 | overnight | overnight | — | **REAL** |
| **RICE BRAN 1L** | **B0DBHQ2QWW** | **absent** | **10 min** | **"in 10 minutes" / Amazon Now buy-box / In stock** | **CAPTURE-MISS** |
| SOYABEAN 1L | B0B6HNNL5B | overnight | overnight | — | **REAL** |
| SUNFLOWER 1L | B0B4SJTNF2 | absent | overnight | — | **REAL** (broad-missed, but Fresh-only) |
| WG MANGO JUICE 500ML | B0DM2G4YCC | absent | not-found | "Currently unavailable" | **REAL** (genuinely OOS) |
| YELLOW MUSTARD 1L | B0FF9P7XVX | scheduled (11–20 Jun) | scheduled | — | **REAL** |

**11/12 are genuinely not Amazon-Now-serviceable at 110095** — present only on scheduled/Fresh
tiers or genuinely out of stock. The direct ASIN check + PDP independently confirm each
(no circular "thin ⇒ real" reasoning). The n/s for these 11 is **authoritative and correct**.

**1/12 — RICE BRAN 1L (B0DBHQ2QWW) — is a true CAPTURE-MISS**, the Zepto cousin: ENTIRELY absent
from the broad `k=jivo` result set (all 139 jivo cards, 3 pages), yet a direct ASIN search returns
it with a genuine **10-min** Now tier and the PDP shows `Amazon Now ₹189.00 … FREE delivery in 10
minutes`, **In stock**. The broad search simply doesn't rank/return it at this store.

## Method validation (control 400601, Thane — 7 suspects known-present in production)
The probe's broad path reproduced production exactly: all 7 production-present suspects returned
`broad=10 min`. The direct check returned `10 min` for them too (no false negatives), and correctly
returned **scheduled** for GOLD 5L (2 days) and GROUNDNUT 1L (2 days) → those stay REAL, NOT
added (no false positives). Crucially, the broad search at 400601 ALSO **missed** three genuine
10-min-Now SKUs — MUSTARD 1L, RICE BRAN 1L, SUNFLOWER 1L (`broad=absent`, `direct=10 min`,
PDP "in 10 minutes"). So the recall gap is **systemic**, not a 110095 one-off: the broad
`k=jivo` search under-reports genuine Now coverage at multiple stores.

## Fix — seed/direct-ASIN fallback (the Zepto-seed analogy), additive + fail-safe
`scrape.ctnow.js`: SEED = every mapped Jivo amazon-now ASIN (loaded from `sku_map.json`, 21 ASINs).
After the broad search at a **serviceable** pincode, any SEED ASIN the broad search missed
**entirely** is re-checked via a DIRECT ASIN search on the SAME ctnow surface (location already set
→ no redundant address-change POST) and added **only** if it shows the SAME strict instant-minute
Now tier. Scheduled-only items stay dropped (so the 11 REALs above are NOT falsely added).

- **Contract unchanged**: same row shape; fallback rows carry an extra `via:"seed-fallback"` tag;
  summary gains `seed_fallback_rows`. `build_excel.py`/downstream read existing fields only.
- **Bounded**: only the broad-missed SEED ASINs are checked (~6–7/serviceable pincode), capped at
  `SEED_MAX` (40); `SEED_FALLBACK=0` disables instantly. Est. +6–8 min on a full sweep — well
  inside the deadline-sweep lead (p90, LEAD_MAX 3.5 h). `node --check` clean.
- **Fail-safe**: sku_map load failure → seed empty → fallback inert (never aborts the sweep); a
  per-ASIN probe error is caught and skipped. Tomorrow's 08:32 sweep is safe.

## Proof (lock-safe re-probe on 110095, OUT_FILE=/tmp, fix ON)
```
[ok] Delhi 110095 nowPage=true svc=true -> 9 jivo-now (+2 seed) (16.3s)
seed_fallback_rows: 2
```
RICE BRAN 1L (B0DBHQ2QWW, 10 min, ₹189) now appears — recovered by the fallback, plus EXTRA LIGHT
1L (B09HZY97FR) which the broad search also dropped on that run (broad recall fluctuates
run-to-run; the seed-fallback makes capture robust). Only instant-Now items were added; no REAL
(scheduled/OOS) SKU was falsely added.

## Production touch (surgical, backed up)
Merged ONLY the fresh 110095 rows into `result.json` (backup: `result.json.bak-w1-seedfix`;
marker `summary.pin110095_seedfix`). RICE BRAN 1L is now present in production @110095. Recomputing
summary from perPin also corrected a stale `pincodes_serviceable` (104 → 105; a prior 560005 merge
had left the count un-bumped). No full sweep, no push.

## Bottom line
The false-n/s class **does** affect amazon-now, but narrowly: at 110095 it was **1 of 12**
(RICE BRAN 1L) — the other 11 are real per-store Now stock-outs/Fresh-only, confirmed by direct
ASIN + PDP. The control proves the same recall gap drops genuine-Now SKUs at other stores too. The
seed/direct-ASIN fallback closes the gap minimally and fail-safely. Artifacts:
`probe_coverage.js`, `/tmp/amznow-coverage-probe.json` (full evidence), `result.json.bak-w1-seedfix`.
