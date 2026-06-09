# amzcover_verify — W3 adversarial gate + rebuild + owner answer

**Date:** 2026-06-09 · **Author:** W3 (amzcover fleet) · **Mode:** READ-ONLY on prod (probes to /tmp, my report only)
**Mission:** Close the false-n/s class. Verify W1 (amazon-now) + W2 (amazon-fresh) REAL-vs-MISS verdicts are
EVIDENCE-BACKED (direct-ASIN live check, not circular search re-runs), rebuild the PM workbook if data changed,
confirm tomorrow-safe, and write the owner the definitive answer.

---

## Phase 1 — Independent baseline (W3's own ground truth, no reliance on W1/W2)

Reproduced directly from `tools/pricematch/sku_map.json` (mapped ASIN per platform) joined to
`platforms/<p>/result.json` (`allRows`), at ref pincode **110095**. Confirms each suspect is:
*mapped* + *present at ≥1 other pincode* + *no row at 110095* (i.e. renders n/s via `price_at`→None).

**Contract recall:** `pricematch_core.price_at(platform, sku, '110095')` for a per-pincode platform filters
`allRows` to that pincode; **no row → returns None → cell = NOT_SERVICEABLE ("n/s")**. So merging a genuine
captured 110095 row flips the cell to a price (or OOS). Rebuild = re-run `build_pricematch.py --date 2026-06-09`
(reads result.json fresh).

### Key context: 110095 is a PARTIAL-catalog store, not a capture failure
At 110095 the search DOES return Jivo — **amazon-now: 8 distinct ASINs in-stock; amazon-fresh: 10**. So this is
not a "0 rows / whole-column-gone" case. The suspects are the SKUs *absent from that returned set*. Notably on
amazon-now, **CANOLA 1L (B09MJ6QDX7) IS present** at 110095 while **CANOLA 5L (B077ZN4G28) is absent** — a
plausible per-pack assortment/stock difference, but NOT proven real without a direct check. The zepto bug was
exactly "SKU exists at the store but the brand search doesn't surface it" — so the only acceptable evidence is
a **direct per-ASIN availability probe at 110095**. "Present at N other pincodes" is NOT evidence of a miss
(circular), and "the search didn't return it" is NOT evidence it's real (also circular).

### amazon-now — 12 suspects (all reproduce; ref 110095 serviceable=True)
| SKU | ASIN | @110095 | #other pins |
|---|---|---|---:|
| CANOLA 5L | B077ZN4G28 | absent | 61 |
| COCONUT 1L | B0BZ8K3DQP | absent | 28 |
| EXTRA VIRGIN 1L | B093BMGPQC | absent | 56 |
| GOLD 5L | B0C9Q1S6QG | absent | 13 |
| GROUNDNUT 1L | B0CKFFW9B6 | absent | 1 |
| MUSTARD 1L | B09NYCSQLF | absent | 7 |
| MUSTARD 5L | B091XPD9J3 | absent | 54 |
| RICE BRAN 1L | B0DBHQ2QWW | absent | 20 |
| SOYABEAN 1L | B0B6HNNL5B | absent | 20 |
| SUNFLOWER 1L | B0B4SJTNF2 | absent | 6 |
| WG MANGO JUICE 500ML | B0DM2G4YCC | absent | 8 |
| YELLOW MUSTARD 1L | B0FF9P7XVX | absent | 8 |

Present in-stock @110095 (amazon-now): CANOLA 1L, GROUNDNUT 5L, POMACE 1L, POMACE 5L, EXTRA LIGHT 1L,
EXTRA LIGHT 2L, SUNFLOWER 5L, RICE BRAN 5L.

### amazon-fresh — 14 suspects (all reproduce; ref 110095 serviceable=True)
| SKU | ASIN | @110095 | #other pins |
|---|---|---|---:|
| CANOLA 1+1L | B0152TWWSQ | absent | 3 |
| CANOLA 5L | B077ZN4G28 | absent | 74 |
| COCONUT 1L | B0BZ8K3DQP | absent | 3 |
| COCONUT 500ML | B0CGN9Y3PT | absent | 1 |
| EXTRA LIGHT 1L | B09HZY97FR | absent | 5 |
| EXTRA VIRGIN 1L | B093BMGPQC | absent | 96 |
| GOLD 5L | B0C9Q1S6QG | absent | 30 |
| MUSTARD 1L | B09NYCSQLF | absent | 14 |
| MUSTARD 1L POUCH | B0DRYVRYYM | absent | 1 |
| RICE BRAN 1L | B0DBHQ2QWW | absent | 9 |
| SO OLIVE 1L | B0DC6JR4F3 | absent | 42 |
| SOYABEAN 1L | B0B6HNNL5B | absent | 47 |
| SUNFLOWER 1L | B0B4SJTNF2 | absent | 5 |
| YELLOW MUSTARD 1L | B0FF9P7XVX | absent | 8 |

Present in-stock @110095 (amazon-fresh): CANOLA 1L, GROUNDNUT 5L, POMACE 1L, POMACE 5L, EXTRA LIGHT 1L/2L,
SUNFLOWER 5L, RICE BRAN 5L, MUSTARD 5L, + 2 combos (B0FR5BLRH6 RICE BRAN 5L+1L combo, B0BKQ6PBQP mustard 5L).

**Phase 1 verdict:** baseline established and matches the dispatch's 12 + 14 suspect counts exactly. This is my
independent ground truth. Phases 2–4 below.

---

## Phase 2 — Adversarial gate on W1/W2 verdicts → **BOTH PASS**

### The gate rule I enforced
A **REAL** verdict is only accepted when backed by a **DIRECT per-ASIN live check** showing the SKU
is genuinely not serviceable on that fast surface at 110095 — *not* "the broad `k=jivo` search didn't
return it" (circular: the search-miss is the very thing in question). A **CAPTURE-MISS** needs a direct
probe showing the SKU *is* fast-serviceable + a re-probe proving capture now works. I did not take
either worker's table at face value — I went to their raw probe JSON, cross-checked the discriminator
against the **production scraper's own gate**, and re-ran an independent live probe.

### W1 — amazon-now (verdict: 11 REAL, 1 CAPTURE-MISS) → **PASS**
- **Discriminator is the production rule.** `scrape.ctnow.js` keeps a row only when the card shows an
  **instant-minute** tier (`isInstantNow()`: "in N minutes" → `10 min`); overnight/today-window/
  tomorrow/dated = Amazon **Fresh/scheduled**, dropped. W1 classified on exactly this rule, applied to
  a **direct `/s?k=<ASIN>&almBrandId=ctnow`** lookup — the same ctnow surface, not the PDP.
- **Non-circular evidence (raw `/tmp/amznow-coverage-probe.json`).** Each REAL has
  `direct_asin_search.tier ∈ {overnight, 2 days, scheduled}` / `instant:false` / `now_serviceable:false`
  (several also `nowPage:false`, buybox "Amazon Fresh"). RICE BRAN 1L: `tier:10 min`, `instant:true`,
  `nowPage:true`, buybox "Amazon Now ₹189" → the lone genuine miss. WG MANGO 500ML: direct `found:false`
  + PDP "Currently unavailable" → genuinely OOS. (W1 correctly used the ctnow direct-search tier, **not**
  the PDP delivery promise, which is unreliable — RICE BRAN's PDP even mislabels "Tomorrow 8am-12pm".)
- **My INDEPENDENT live re-probe** (fresh pull, `flock .amazon-now.lock`, `PINS=110095`,
  `OUT_FILE=/tmp/w3-amznow-reprobe.json`) reproduced the verdict **exactly**: the only
  `now_serviceable:true` SKU is **RICE BRAN 1L**; all 11 others overnight/2-days/scheduled/not-found.
- **Systemic, not a 110095 one-off:** W1's control pincode 400601 shows the broad search *also* drops
  genuine-10-min MUSTARD 1L / RICE BRAN 1L / SUNFLOWER 1L there → a real recall gap, fix justified.

### W2 — amazon-fresh (verdict: 12 REAL, 2 CAPTURE-MISS) → **PASS**
- **Discriminator is the production rule.** `scrape.js` `isFreshSlot()` keeps a row only when the
  freshstore **search-card** slot is a genuine Fresh window ("in N min" / same-/next-day time window);
  multi-day courier promises ("Thu, 11 Jun", "11–22 Jun", Prime-CSS bleed) are dropped as marketplace.
  W2 keyed on the freshstore search-card slot (broad or **direct `/s?k=<ASIN>&i=freshstore`**), and
  **explicitly excluded the PDP delivery block** — which would have produced 8 false MISS calls (the
  Prime "fastest Tomorrow 6am–10am" string false-matches a fresh-slot regex). That self-correction is
  exactly the right instinct and matches the standing lesson.
- **Non-circular evidence (raw `/tmp/fresh_coverage_probe.json`).** Confirmed each row: the 2 MISS
  (EXTRA LIGHT 1L B09HZY97FR, RICE BRAN 1L B0DBHQ2QWW) show **"FREE delivery in 10 minutes"** on the
  direct freshstore card; all 12 REAL show multi-day courier ("Thu 11 Jun"/"Fri 12 Jun"/"11–22 Jun")
  or NOT-FOUND (MUSTARD 1L POUCH = currently-unavailable). The raw slots match the verdict table 1:1.
- **Probe is genuinely read-only** (`coverage_probe.js`: loads `storageState` but never saves it,
  no cart mutations, only GETs + the same GLOW the live sweep does; writes only to `/tmp`). Session
  intact ("Hello, Damanpreet"). Per the standing caution I did **not** add my own probe load to the
  fragile logged-in Fresh account — the raw-evidence + prod-gate cross-check is the safe equivalent,
  and no Fresh data enters today's workbook (W2 deliberately did not merge — see Phase 3).
- **Key reframing the owner should hear:** the 12 Fresh "REAL" are *available* at 110095 — but only by
  ordinary multi-day marketplace courier, **not** Amazon Fresh quick-commerce. On the **Fresh** sheet,
  n/s for those is **correct** (the sheet must only show genuinely-Fresh-serviceable stock). So they are
  authoritative, not false.

**Independent cross-check breadth:** I verified the raw direct-probe evidence for **all 26** suspects
(12 now + 14 fresh), not just a 2–3 sample, plus a from-scratch live re-probe of all 12 now suspects.

## Phase 3 — Rebuild → done (amazon-now data changed; amazon-fresh did not)

- **amazon-now:** W1 merged ONLY the 110095 rows into `result.json` (backup `result.json.bak-w1-seedfix`).
  I verified the merge is **surgical** by diffing backup→current `allRows`: the *only* net change at
  110095 is **RICE BRAN 1L (B0DBHQ2QWW) added** (₹189, in-stock, `now_eta:10 min`, `via:seed-fallback`);
  a duplicate CANOLA 1L row was de-duped (9→9 net); EXTRA LIGHT 1L (already present) was just tagged.
  **No REAL (scheduled/OOS) SKU was falsely added; no pincode other than 110095 was touched.** Summary
  `pincodes_serviceable` correctly bumped 104→105 (a prior 560005 merge had left it stale).
- **amazon-fresh:** W2 did **not** merge (avoids a half-patched file; the fix lands sweep-wide tomorrow).
  So no Fresh data changed → no Fresh-driven rebuild delta.
- **Rebuild + value-diff (23,208 cells).** The builder is **fully deterministic** (verified: a pre-merge
  rebuild was 0-cell-different from the committed workbook). Post-merge rebuild vs committed = **47 changed
  cells, ALL in the Violations sheet, and ALL a single sorted-list reflow** from inserting one new row:
  **`RICE BRAN 1L · Amazon Now · Delhi · 110095 · ₹189 · ref ₹199 · −₹10`**. The recovered SKU now shows a
  **priced in-stock row instead of a missing 110095 entry.**
- **5 core sheets + the 2 PM-Check sheets verified.** Ecom Head, Matrix, Above reference, Coverage &
  pending, and both PM-Check sheets are **byte-identical**; only Violations gained the one legitimate row.
  - *Why Matrix didn't change:* the Matrix "Amazon Now" cell is the modal across pincodes — RICE BRAN 1L
    already read ₹189 there (from 20 other pincodes), so it was never a visible n/s in the Matrix.
  - *Why "Amazon Now PM Check" didn't change:* that sheet filters to SKUs a **competitor** carries head-to-head
    at the ref pincodes (`_sku_has_compete_data`); no quick-comm competitor carries RICE BRAN 1L @110095/560005,
    so it is correctly not a row — independent of amazon-now's own stock.
- **History tables:** `data/pricematch/history.csv` changed by exactly 2 lines (RICE BRAN 1L now store-count
  20→21; CANOLA 1L 69→68 from the de-dup) — prices unchanged. Consistent with the surgical merge.
- Rebuilt workbook written to `tools/pricematch/Jivo-Price-Match-2026-06-09.xlsx` (byte-parity with the
  verified /tmp build).

## Phase 4 — Tomorrow-safe (08:32 sweep) → confirmed

- **W1 `scrape.ctnow.js`** (+51 lines, commit b8377ef3): additive seed/direct-ASIN fallback, **default ON**,
  `SEED_FALLBACK=0` kill-switch, gated on `serviceable`, bounded by `SEED_MAX`, every probe in try/catch;
  sku_map load failure → empty seed → **inert** (never aborts the sweep). `node --check` clean. result.json
  contract additive (`via` tag + `seed_fallback_rows`). Normal broad-search path unchanged.
- **W2 `scrape.js`** (+70 lines, commit 892375bf): additive `directFreshCard` fallback, **default ON**,
  `FRESH_DIRECT_FALLBACK=0` kill-switch, `FRESH_FALLBACK_MAX` bound, gated on `serviceable` + seed-present,
  per-ASIN try/catch, `isFreshSlot` gate prevents marketplace leak. `node --check` clean; module require()
  smoke-test loads without crashing. Schema additive (`recovered_direct`/`rows_recovered_direct`). The
  logged-in session was kept intact (read-only probes, storageState never re-saved).
- **`platforms/amazon-fresh/pincodes.json`** in W2's commit shows a huge line delta — I verified it is a
  **reformat, not a coverage cut**: entries 332 → **333** (coverage *up* by 1). Not a regression.
- Seeds present + valid: `fresh_seed_asins.json` = 27 ASINs; amazon-now seed = 21 mapped ASINs from
  `tools/pricematch/sku_map.json`.
- **Runtime:** now +~6–8 min, fresh +~20 min per sweep — absorbed by the deadline-sweep p90 lead predictor.
  **One thing to watch (not a blocker):** the Fresh fallback ~10× the search-path request volume on the
  logged-in account; stable so far, throttle via `FRESH_FALLBACK_MAX` / kill-switch if Amazon ever
  escalates to captcha.

---

## OWNER ANSWER (plain language)

**Is the Zepto-type "shown as not-there when it's actually live" bug anywhere else? We checked its two
closest cousins — Amazon Now and Amazon Fresh — with direct, live, per-product checks. Short answer:
almost entirely no, with a small real recall gap we found and fixed.**

**Amazon Now (12 suspects @ Delhi-110095):** 11 of 12 are **genuinely correct** "not there" — those
products are only on Amazon's slower scheduled/Fresh delivery (overnight / 2-day) or out of stock at
that store, *not* on the 10-minute Amazon Now service, so leaving them off the Now report is right. We
confirmed each by pulling the product directly, not by trusting the search. **1 of 12 — Rice Bran Oil
1L — was a true miss** (genuinely available in 10 minutes at ₹189, but the broad "jivo" search dropped
it): the exact Zepto pattern. **Fixed** with the same seed-style direct-lookup fallback, and Rice Bran
1L now shows correctly @110095 in today's workbook.

**Amazon Fresh (14 suspects @ 110095):** 12 of 14 are **genuinely correct** "not there" on Fresh — a
shopper there can only get them by ordinary multi-day courier, not Fresh quick-commerce, so the Fresh
report correctly omits them. **2 of 14 — Extra Light Olive 1L and Rice Bran 1L — were true misses**
(genuinely "in 10 minutes" on Fresh, dropped by the broad search). **Fixed** with the same fallback.

**The whole false-n/s class across all 8 platforms — where it stands now:**
- **The 3 platforms you care most about — Amazon (core), Flipkart Marketplace, BigBasket — are
  AUTHORITATIVE.** They fetch every product directly / pull the whole brand catalogue, so when they say
  "not there," it is real. No false-n/s risk there.
- **Zepto** — the one you caught — is **fixed** (seed completed to the 23-variant union).
- **Amazon Now & Amazon Fresh** — investigated and **closed this round**: the search-recall gap is real
  but **narrow** (1 of 12 / 2 of 14), and a fail-safe direct-ASIN fallback now backfills the missed
  fast-delivery SKUs at every serviceable store, starting with tomorrow's 08:32 sweep.

**Honest still-open items (no false all-clear):**
1. **Amazon Fresh's 2 fixed SKUs are not in *today's* workbook** — Fresh's fix is committed but, to avoid
   a half-patched data file, was deliberately not merged into today's data; it takes effect sweep-wide on
   **tomorrow's run**. (Today's sheet only shows Amazon Now's Rice Bran 1L, which we did merge. Note: in
   the top "Matrix" view these two Fresh SKUs already show a price anyway — the gap was only in the
   per-store detail list.)
2. **560005 (Bengaluru) Fresh/Flipkart-Minutes coverage** — those columns are thin because the reference
   pincode itself is barely swept for those platforms (a *coverage* hole, not a per-product bug); it fills
   as coverage broadens.
3. **The other quick-commerce platforms (Blinkit, Flipkart Minutes)** carry the same *class* of
   search-recall/coverage limitation; this round closed Amazon Now/Fresh + Zepto. Blinkit also has its
   known ~40% bad-coordinate pincodes (a geocoding follow-up).

**Bottom line:** the bug you caught is not widespread. On the national platforms it cannot happen; on the
fast quick-commerce surfaces it was narrow, is now understood, and is fixed with the same seed/direct-lookup
technique — fully reversible via a kill-switch and safe for tomorrow's run.

---
*Artifacts:* my baseline `/tmp/w3_baseline.py`; independent live re-probe `/tmp/w3-amznow-reprobe.json`;
W1 evidence `/tmp/amznow-coverage-probe.json` + `platforms/amazon-now/COVERAGE-DIAG.md`; W2 evidence
`/tmp/fresh_coverage_probe.json` + `platforms/amazon-fresh/COVERAGE-DIAG.md`; rebuild diff
`/tmp/w3_diff.py`. Verdict: **W1 PASS · W2 PASS · rebuild faithful · tomorrow-safe.**
