# W2 — Comprehensive "false n/s" audit across ALL platforms + sheets

**Date:** 2026-06-09 · **Author:** W2 (pmcover fleet) · **Mode:** READ-ONLY (data + sheets, no scraping, no edits)
**Inputs:** `tools/pricematch/sku_map.json` (114 master SKUs, 263 platform mappings) joined to fresh
`platforms/<p>/result.json` via the FROZEN `pricematch_core.price_at()` contract, evaluated at the two
owner reference pincodes **110095 (Delhi)** and **560005 (Bengaluru)**.

---

## TL;DR for the owner

You caught **one** false n/s (Zepto CANOLA 1+1L @ 560005). It is **not** a one-off — there are
**96 false-or-suspect n/s cells** on the price-match sheets, all on the **5 per-pincode quick-commerce
platforms**. The good news: the **3 national platforms you care most about (Amazon Core, Flipkart MP,
BigBasket) are AUTHORITATIVE** — when they say n/s, it is real. The false n/s are confined to the
quick-commerce columns, and they come from **two distinct causes**:

1. **Per-SKU capture miss** (65 cells) — your exact flavour: the pincode *was* swept and we have other
   SKUs there, but a specific product the platform genuinely carries was missed by the search. This is a
   scraper-recall problem (seed-lag / search ranking / in-stock-only gating).
2. **Pincode-unswept coverage hole** (31 cells) — the reference pincode itself was barely/never visited
   for that platform, so the **whole column** reads n/s. This is a coverage problem, not a per-SKU bug.

---

## Headline counts (mapped-SKU cells at the two ref pincodes)

| Bucket | Cells | Meaning |
|---|---:|---|
| **OK** | 236 | mapped + in-stock priced at the ref pin — correct |
| **AUTH-NATIONAL** | 226 | national platform (amazon/flipkart/bigbasket) reads OOS/n-s — **real, authoritative** |
| **LIKELY-FALSE** | **96** | mapped + we KNOW it exists on the platform, yet the cell shows n/s/OOS |
| **LIKELY-REAL** (per-pincode) | 14 | mapped but genuinely OOS everywhere / genuinely not carried |
| **TOTAL** | 572 | (286 mapped SKU×platform pairs × 2 ref pincodes) |

**The 96 LIKELY-FALSE split by root cause:**

| Root cause | Cells | Where |
|---|---:|---|
| **A. CAPTURE-MISS** (ref pin swept, SKU missed) | **65** | amazon-now, amazon-fresh, blinkit, zepto, flipkart-minutes |
| **B. COVERAGE-HOLE** (ref pin unswept, whole column gone) | **31** | amazon-fresh @560005 (22), flipkart-minutes @560005 (9) |

---

## Per-platform verdict — is each platform's n/s AUTHORITATIVE or LOSSY?

Determined by reading each scraper's discovery mechanism (`platforms/<p>/scrape*.js`):

| Platform | Discovery mechanism | Per-pincode? | n/s authority | False-n/s risk |
|---|---|---|---|---|
| **amazon** (core) | TARGETED per-ASIN detail fetch (every mapped ASIN fetched directly) | national | **AUTHORITATIVE** | none |
| **flipkart** (MP) | scrapes Jivo's DEFINED official catalogue (not a search) | national | **AUTHORITATIVE** | none |
| **bigbasket** | listing-svc `slug=jivo` returns the WHOLE brand catalogue, paginated | national | **AUTHORITATIVE** | none |
| **zepto** | bare-brand `jivo` SEARCH (pages 0–3, **in-stock-gated**) + seed-list variant PDP pass | per-pincode | **LOSSY** | HIGH (search recall + hidden variants → the owner's CANOLA bug) |
| **blinkit** | per-store search-page navigation; ~40% pincodes have bad coords → 0 rows | per-pincode | **LOSSY** | HIGH (recall + geocoding) |
| **flipkart-minutes** | `search?q=jivo&marketplace=HYPERLOCAL` per pincode (store warm-up flaky) | per-pincode | **LOSSY** | HIGH (thin coverage — W3 territory) |
| **amazon-fresh** | `i=freshstore&k=jivo` search per pincode | per-pincode | **LOSSY** | HIGH (search recall + unswept pins) |
| **amazon-now** | `ctnow&k=jivo` search per pincode | per-pincode | **LOSSY** | HIGH (search recall + unswept pins) |

**Rule of thumb: the 3 NATIONAL platforms are authoritative; the 5 PER-PINCODE quick-commerce platforms
are all lossy and can produce false n/s.** Every one of the 96 LIKELY-FALSE cells is on a per-pincode
platform — exactly as expected.

---

## A. LIKELY-FALSE — CAPTURE-MISS (65 cells) — the owner's flavour

The ref pincode WAS swept (we have in-stock rows for *other* SKUs there) but this specific mapped SKU,
which we observe **in-stock at N other pincodes**, is missing/OOS at the ref pin. Ranked by N (more
pincodes elsewhere = more confident it's a miss, not real). `cell`: NS = no row at all, OOS = row present
but out of stock.

| Platform | Pin | Master SKU | Cell | Live elsewhere | Verdict |
|---|---|---|---|---:|---|
| blinkit | 560005 | JIVO POMACE 1L | OOS | @120 pins | LIKELY-FALSE |
| blinkit | 560005 | EXTRA LIGHT 2L | OOS | @113 pins | LIKELY-FALSE |
| amazon-fresh | 110095 | EXTRA VIRGIN 1L | NS | @96 pins | LIKELY-FALSE |
| blinkit | 560005 | JIVO POMACE 5L | NS | @87 pins | LIKELY-FALSE |
| amazon-now | 560005 | JIVO POMACE 5L | NS | @84 pins | LIKELY-FALSE |
| amazon-fresh | 110095 | CANOLA 5L | NS | @74 pins | LIKELY-FALSE |
| amazon-now | 560005 | EXTRA LIGHT 2L | NS | @68 pins | LIKELY-FALSE |
| blinkit | 560005 | CANOLA 5L | NS | @67 pins | LIKELY-FALSE |
| amazon-now | 560005 | JIVO POMACE 1L | NS | @66 pins | LIKELY-FALSE |
| amazon-now | 560005 | CANOLA 1L | NS | @63 pins | LIKELY-FALSE |
| amazon-now | 110095 | CANOLA 5L | NS | @61 pins | LIKELY-FALSE |
| amazon-now | 110095 | EXTRA VIRGIN 1L | NS | @56 pins | LIKELY-FALSE |
| amazon-now | 560005 | EXTRA VIRGIN 1L | NS | @56 pins | LIKELY-FALSE |
| amazon-now | 110095 | MUSTARD 5L | NS | @54 pins | LIKELY-FALSE |
| amazon-now | 560005 | MUSTARD 5L | NS | @54 pins | LIKELY-FALSE |
| amazon-now | 560005 | SUNFLOWER 5L | NS | @54 pins | LIKELY-FALSE |
| amazon-fresh | 110095 | SOYABEAN 1L | NS | @47 pins | LIKELY-FALSE |
| amazon-fresh | 110095 | SO OLIVE 1L | NS | @42 pins | LIKELY-FALSE |
| blinkit | 110095 | SUNFLOWER 1L | NS | @41 pins | LIKELY-FALSE |
| flipkart-minutes | 110095 | CANOLA 1L | NS | @38 pins | LIKELY-FALSE |
| amazon-now | 560005 | GROUNDNUT 5L | NS | @36 pins | LIKELY-FALSE |
| zepto | 560005 | MUSTARD 5L | OOS | @34 pins | LIKELY-FALSE |
| amazon-fresh | 110095 | GOLD 5L | NS | @30 pins | LIKELY-FALSE |
| amazon-now | 110095 | COCONUT 1L | NS | @28 pins | LIKELY-FALSE |
| amazon-now | 560005 | COCONUT 1L | NS | @28 pins | LIKELY-FALSE |
| zepto | 110095 | CANOLA 5L | OOS | @28 pins | LIKELY-FALSE |
| zepto | 560005 | JIVO POMACE 1L + 1L | OOS | @23 pins | LIKELY-FALSE |
| **zepto** | **110095** | **CANOLA 1+1L** | **OOS** | **@21 pins** | **LIKELY-FALSE ← owner's catch** |
| amazon-now | 110095 | RICE BRAN 1L | NS | @20 pins | LIKELY-FALSE |
| amazon-now | 560005 | RICE BRAN 1L | NS | @20 pins | LIKELY-FALSE |
| amazon-now | 110095 | SOYABEAN 1L | NS | @20 pins | LIKELY-FALSE |
| amazon-now | 560005 | SOYABEAN 1L | NS | @20 pins | LIKELY-FALSE |
| amazon-now | 560005 | RICE BRAN 5L | NS | @18 pins | LIKELY-FALSE |
| blinkit | 110095 | MUSTARD 1L | NS | @16 pins | LIKELY-FALSE |
| blinkit | 560005 | MUSTARD 1L | NS | @16 pins | LIKELY-FALSE |
| blinkit | 110095 | MUSTARD 5L | NS | @16 pins | LIKELY-FALSE |
| blinkit | 560005 | MUSTARD 5L | NS | @16 pins | LIKELY-FALSE |
| amazon-now | 560005 | EXTRA LIGHT 1L | NS | @15 pins | LIKELY-FALSE |
| amazon-fresh | 110095 | MUSTARD 1L | NS | @14 pins | LIKELY-FALSE |
| amazon-now | 110095 | GOLD 5L | NS | @13 pins | LIKELY-FALSE |
| amazon-now | 560005 | GOLD 5L | NS | @13 pins | LIKELY-FALSE |
| amazon-fresh | 110095 | RICE BRAN 1L | NS | @9 pins | LIKELY-FALSE |
| amazon-fresh | 110095 | YELLOW MUSTARD 1L | NS | @8 pins | LIKELY-FALSE |
| amazon-now | 110095 | WG MANGO JUICE 500ML | NS | @8 pins | LIKELY-FALSE |
| amazon-now | 560005 | WG MANGO JUICE 500ML | NS | @8 pins | LIKELY-FALSE |
| amazon-now | 110095 | YELLOW MUSTARD 1L | NS | @8 pins | LIKELY-FALSE |
| amazon-now | 560005 | YELLOW MUSTARD 1L | NS | @8 pins | LIKELY-FALSE |
| amazon-now | 110095 | MUSTARD 1L | NS | @7 pins | LIKELY-FALSE |
| amazon-now | 560005 | MUSTARD 1L | NS | @7 pins | LIKELY-FALSE |
| flipkart-minutes | 110095 | JIVO POMACE 1L | NS | @7 pins | LIKELY-FALSE |
| amazon-now | 110095 | SUNFLOWER 1L | NS | @6 pins | LIKELY-FALSE |
| amazon-now | 560005 | SUNFLOWER 1L | NS | @6 pins | LIKELY-FALSE |
| amazon-fresh | 110095 | EXTRA LIGHT 1L | NS | @5 pins | LIKELY-FALSE |
| amazon-fresh | 110095 | SUNFLOWER 1L | NS | @5 pins | LIKELY-FALSE |
| amazon-fresh | 110095 | CANOLA 1+1L | NS | @3 pins | LIKELY-FALSE |
| amazon-fresh | 110095 | COCONUT 1L | NS | @3 pins | LIKELY-FALSE |
| flipkart-minutes | 110095 | SOYABEAN 1L POUCH | NS | @3 pins | LIKELY-FALSE |
| flipkart-minutes | 110095 | CANOLA 1+1L | NS | @2 pins | LIKELY-FALSE |
| flipkart-minutes | 110095 | JIVO WATER 1L | NS | @2 pins | LIKELY-FALSE |
| zepto | 560005 | JIVO POMACE 2L | OOS | @2 pins | LIKELY-FALSE (thin) |
| zepto | 110095 | SO OLIVE 1L | OOS | @2 pins | LIKELY-FALSE (thin) |
| amazon-fresh | 110095 | COCONUT 500ML | NS | @1 pin | LIKELY-FALSE (marginal) |
| amazon-fresh | 110095 | MUSTARD 1L POUCH | NS | @1 pin | LIKELY-FALSE (marginal) |
| amazon-now | 110095 | GROUNDNUT 1L | NS | @1 pin | LIKELY-FALSE (marginal) |
| amazon-now | 560005 | GROUNDNUT 1L | NS | @1 pin | LIKELY-FALSE (marginal) |

> The last 5 rows (@1–2 pins) are the weakest: a single corroborating pincode could itself be a transient.
> They are still flagged FALSE because the SKU is mapped exact, but they merit lower priority than the
> high-N rows.

---

## B. LIKELY-FALSE — COVERAGE-HOLE (31 cells) — pincode never properly swept

The reference pincode has **0 in-stock rows for ANY SKU** on this platform, so every mapped SKU reads
n/s. This is **not** a per-SKU bug — the sweep simply did not cover (or returned empty for) this pincode.
Fix is on the coverage/sweep side, not the SKU search.

| Platform | Pin | Mapped SKUs blanked | Cause |
|---|---|---:|---|
| amazon-fresh | 560005 | **22** | 560005 returned **0 rows** for amazon-fresh in today's result.json (Bengaluru not in the fresh sweep set / store returned empty) |
| flipkart-minutes | 560005 | **9** | 560005 returned **0 in-stock rows** (1 raw row only) — hyperlocal store not warmed/serviceable |

Ref-pincode swept depth (in-stock priced rows of ANY SKU at the pin) — the diagnostic that separates A
from B:

| Platform | @110095 | @560005 |
|---|---:|---:|
| amazon-fresh | 11 | **0** ← coverage hole |
| amazon-now | 9 | 1 ← near-hole |
| flipkart-minutes | 4 | **0** ← coverage hole |
| zepto | 14 | 13 (well swept both) |
| blinkit | 6 | 3 (swept both) |

> NB: amazon-now @560005 has only 1 swept row, so its 19 "@560005" CAPTURE-MISS cells in table A are
> borderline between A and B — effectively the 560005 column for amazon-now is also a near-coverage-hole.

---

## C. LIKELY-REAL (14 cells) — do NOT chase these

Mapped, but the evidence says the cell is correct:

| Platform | Pin | Master SKU | Cell | Why it's real |
|---|---|---|---|---|
| amazon-now | 110095 / 560005 | CANOLA 1+1L | NS | **0 rows anywhere** on amazon-now — the 1+1L combo is genuinely not on Now (or a mapping/discovery gap; needs a targeted probe before calling it 100% real) |
| flipkart-minutes | 110095 / 560005 | MUSTARD 4L | NS | **0 rows anywhere** on FK-Minutes — genuinely not carried |
| zepto | 110095 / 560005 | EXTRA VIRGIN 5L | OOS | captured but OOS at every pincode → genuinely out of stock |
| zepto | 110095 / 560005 | GOLD 1L | OOS | captured, OOS everywhere |
| zepto | 110095 / 560005 | GOLD 5L | OOS | captured, OOS everywhere |
| zepto | 110095 / 560005 | RICE BRAN 1L | OOS | captured, OOS everywhere |
| zepto | 110095 / 560005 | SUNFLOWER 5L | OOS | captured, OOS everywhere |

> Caveat on the 2 NOCAP cases (amazon-now CANOLA 1+1L, fk-minutes MUSTARD 4L): "0 rows anywhere" can
> mean genuinely-absent OR a deeper discovery gap. They are the SAME failure shape as the original Zepto
> CANOLA bug (a mapped SKU captured nowhere). Rated REAL pending a one-shot live PDP probe, not asserted.

---

## Zepto specifically — the 9 seed-missing variants (W1's target)

Cross-check: each of the 9 master SKUs whose Zepto variant was missing from the seed is **confirmed
available somewhere on Zepto** in today's (post-W1-merge) result.json → so any ref-pin absence is a
CAPTURE gap, not "not carried". W1's premise is correct.

| Master SKU | variant_id | #rows | #in-stock | @110095 | @560005 | Verdict |
|---|---|---:|---:|---|---|---|
| CANOLA 1+1L | 50b56b7f… | 39 | 20 | **OOS** | **NO ROW** | avail elsewhere → capture gap |
| EXTRA LIGHT 1L | 2300d5e1… | 56 | 48 | IN ₹499 | IN ₹499 | ✅ fixed both pins |
| EXTRA LIGHT 2L | 29e72c8c… | 22 | 14 | NO ROW | NO ROW | avail elsewhere → capture gap |
| GROUNDNUT 1L | 41367ef4… | 56 | 46 | IN ₹199 | IN ₹199 | ✅ fixed both pins |
| JIVO POMACE 1L | ac9a7dd8… | 56 | 48 | IN ₹379 | IN ₹379 | ✅ fixed both pins |
| JIVO POMACE 1L + 1L | 3d955a07… | 25 | 23 | IN ₹758 | NO ROW | avail elsewhere → capture gap @560005 |
| JIVO POMACE 2L | 8eedf6ff… | 3 | 1 | OOS | NO ROW | thin — avail at 1 pin only |
| MUSTARD 1L | 89804a83… | 56 | 53 | IN ₹180 | IN ₹181 | ✅ fixed both pins |
| SUNFLOWER 1L | 06c8f55b… | 51 | 46 | IN ₹192 | IN ₹192 | ✅ fixed both pins |

**5 of 9 now show in-stock at BOTH ref pincodes** after W1's seed merge. Good progress.

### ⚠️ Critical caveat for W1/W4/W5 — the owner's EXACT catch is NOT yet reflected at the ref pincodes

The owner caught **CANOLA 1+1L live @ ₹469 at 560005**. After W1's merge, variant `50b56b7f` now appears
at 39 pincodes, **but**:
- @110095 it is **OOS** (in_stock=0), and
- @560005 it has **NO ROW AT ALL** — even though 560005 *was* swept (13 in-stock rows of other SKUs).

The two CANOLA-named rows that DO exist at 560005 are **different variants** (`c935f17d` "Cold Pressed"
₹1600, `b84e15b9` "Refine Tin" ₹3187) — neither is the 1+1L combo @ ₹469.

**Consequence:** at the two reference pincodes the sheet evaluates, CANOLA 1+1L still does NOT show an
in-stock ₹469 → **the exact-match against Amazon Core ₹469 will NOT light up** at the ref pins yet. W1's
re-scrape captured the variant broadly (20 Delhi pins in-stock) but did not land an in-stock ₹469 row at
560005. W4 must not claim the exact-match is fixed at the ref pins until a 560005 in-stock row for
`50b56b7f` exists; W5's adversarial gate should verify this specifically.

---

## Cross-sheet blast radius (item 4)

The false n/s originate in `pricematch_core.price_at(platform, sku, pincode)` (returns `None` →
NOT_SERVICEABLE when no row at the pincode). Which sheets consume it:

| Sheet (`build_pricematch.py`) | Data source | Per-pincode false-n/s exposure |
|---|---|---|
| **Amazon Now PM Check** | `competitor_compare("amazon-now", [blinkit, zepto, fk-minutes, bigbasket])` at ref pins | **FULLY EXPOSED** — ref (amazon-now) is per-pincode lossy AND 3 of 4 competitor cols are per-pincode |
| **Amazon Core PM Check** | `competitor_compare("amazon", [blinkit, zepto, fk-minutes, flipkart-MP])` at ref pins | **EXPOSED** on the 3 quick-comm competitor columns (ref = national, safe) |
| **Matrix** | `all_comparisons` → `platform_comparison` = **modal across ALL pincodes** | **MOSTLY IMMUNE** — a SKU in-stock at ANY pincode shows a price; only NOCAP SKUs (captured nowhere) read n/s here. e.g. Zepto CANOLA shows correctly on the Matrix (20 in-stock pins) but n/s on the PM Check sheets. |
| **Ecom Head / Violations / Above / Coverage** | KPIs/rollups off the same records | Inherit whatever the above produce |

**Confirmed blast radius:** the owner saw it on **Amazon Core PM Check**; the **identical underlying
data drives Amazon Now PM Check** (same `competitor_compare`, same ref pins) — so **both PM Check sheets**
carry the false n/s. The **Matrix is largely protected** by its cross-pincode aggregation (this is why
the owner saw the gap on the PM Check sheet and not necessarily the Matrix). The two PM Check sheets are
the blast radius for the owner's flavour; the Matrix only suffers for the 2 genuinely-uncaptured (NOCAP)
SKUs.

---

## Who needs a DATA fix vs who is AUTHORITATIVE

**Needs a data/coverage fix (lossy, producing false n/s):**
- **zepto** — W1 (seed completion, in progress). Mostly resolved; CANOLA 1+1L @560005 still open (see caveat).
- **flipkart-minutes** — W3 (real-thin vs capture-bug). Audit confirms BOTH: a real-thin tail AND a
  coverage hole @560005 (0 rows) + thin @110095 (4 rows). 15 LIKELY-FALSE + 1 NOCAP across the two pins.
- **amazon-now** — **largest single contributor: 31 LIKELY-FALSE cells.** Per-pincode search recall is
  weak and 560005 is a near-coverage-hole (1 row). Not owned by any current worker — **flag to owner.**
- **amazon-fresh** — 36 LIKELY-FALSE (14 capture-miss @110095 + 22 coverage-hole @560005). 560005 not
  swept at all for fresh. Not owned by any current worker — **flag to owner.**
- **blinkit** — 9 LIKELY-FALSE; known ~40%-bad-coords + search recall. Chronic, geocoding follow-up.

**Authoritative (n/s is real — no fix needed):**
- **amazon** (core), **flipkart** (MP), **bigbasket** — all national, direct-catalogue/targeted; their
  n/s reflects the true national listing state.

### Suggested priority (by false-cell count, fixability)
1. **zepto** — finish W1 (esp. CANOLA 1+1L @560005 in-stock row) → unblocks the owner's exact catch.
2. **amazon-now (31) + amazon-fresh (36)** — biggest volume; need a coverage + recall pass on the
   Amazon quick-comm storefronts at the ref pincodes. **Not currently assigned — recommend to owner.**
3. **flipkart-minutes** — W3 in flight.
4. **blinkit** — geocoding backlog, lower urgency.

---

## Method / reproducibility

```
# regenerate the raw classification (read-only)
cd /opt/ecom-intel && python3 - <<'PY'
import sys; sys.path.insert(0,'tools/pricematch'); import pricematch_core as pc
# price_at(plat,sku,pin) == None -> NOT_SERVICEABLE (n/s); {in_stock:False} -> OOS; else OK.
# A cell is LIKELY-FALSE when the SAME listing id is in-stock at >=1 OTHER pincode in result.json.
# CAPTURE-MISS vs COVERAGE-HOLE split on whether the ref pin has >=1 in-stock row of ANY sku.
PY
```

Engine: `pricematch_core.price_at` / `_rows_for` / `_candidate_listings` (only `exact`/`anchored`
mappings participate, matching the live sheet). National platforms (amazon, flipkart, bigbasket) ignore
the pincode by design. All figures are from result.json files dated 2026-06-09 (zepto post-W1-merge,
16:07). No scrape, no edit — read-only.
