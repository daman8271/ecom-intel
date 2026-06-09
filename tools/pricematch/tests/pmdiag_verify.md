# pmdiag — W5 adversarial gate + owner answer

**Date:** 2026-06-09 · **Author:** W5 (adversarial verify) · **Verdict: ✅ PASS (all 4 workers) — LEAD may push + deliver.**

W5 independently reproduced the symptom from raw `result.json` (not from the workers' numbers),
then checked each worker's claim against the data and against tomorrow-safety. Everything below
was re-derived first-hand. Prod left read-only: the two `data/pricematch/*.csv` were md5-guarded
and restored after every probe build; the committed prod xlsx (`8075145b…`) was not altered by W5.

---

## Phase 1 — independent reproduction of the symptom (ground truth)

Per platform, distinct SKUs at the two reference pincodes **110095 (Delhi) vs 560005 (Bengaluru)**,
keyed on variant_id/asin (so duplicate rows can't masquerade as a match):

| platform | stores A/B | common SKUs | same-price (diff store) | diff-price |
|---|---|---|---|---|
| zepto | 1 / 1 (different) | 16 | 9 | 7 |
| blinkit | 1 / 1 (different) | 4 | 1 | 3 |
| flipkart-minutes | 2 / 1 | 0 | 0 | 0 (thin) |
| amazon core | national, 0 rows at ref pins | — | — | — |
| amazon-fresh | 11 @110095 / 0 @560005 | — | — | — |
| amazon-now | 8 @110095 / 1 @560005 | — | — | — |

**Decisive zepto finding (kills the "cached national bug" hypothesis):** across ALL stores in
today's scrape, **15 of 23 SKUs VARY in price store-to-store, 8 are genuinely FLAT**, every one
of them under `price_source=SUPER_SAVER`. The owner's flagged SKU **Extra Light 1L = ₹499 is one
of the flat 8 — identical at all 44 distinct stores it appears in.** The very same scrape that
returns 499/499 for Extra Light also returns 2128 vs 2494 for Pomace 5L at those exact two
stores. A scraper emitting one cached national constant is **mathematically incapable** of
producing that side-by-side variation → the same-price cells are a **true Zepto fact**, not a
merge/dedup/cache defect.

---

## Phase 2 — per-worker verdicts

### W1 — root cause → **PASS** (REAL national/zonal pricing, not a bug)
Did **not** rubber-stamp. Independently confirmed from raw data (above) that SUPER_SAVER resolves
per-store and the scraper captures variation where it exists. Checked the skeptical angle the
brief called out — "is there a per-store tier we're ignoring?": the scraper reads
`pricingData.pricingEntityPrices[tier].discountedSellingPrice` **per store**; the only other
tiers are ZEPTO_NOW (W1: identical at the PDP route) and ULTRA_SAVER (a lower price, same
per-store pattern). There is **no missed per-store tier** that would make the flat SKUs vary.
W1's report (`price_anomaly_diag.md`) matches my numbers; no overclaim. **The 110095-vs-560005
pinning is accurate, not misleading.**

### W2 — flipkart-minutes thin/n-s → **PASS** (REAL thin hyperlocal catalog, scraper untouched)
Independently confirmed it is NOT under-resolution: **every named dark-store returns a constant
SKU count across all pincodes it serves** (e.g. `mum_007`=3 across 7 pincodes, `ben_172`=1 at
560005) — under-resolution would cause per-store variance; there is none. 560005 genuinely carries
1 Jivo SKU; national catalog is a stable **9 SKUs**. `scrape.js` is byte-untouched (git) and
`node --check` clean → tomorrow's 08:32 sweep unaffected. *Minor pre-existing note (out of scope,
not a regression):* 64 rows carry a blank `store_id` but real in-stock prices — a store-label gap,
**not** lost coverage. The n/s wall is TRUE; fix is presentation (W4), which is correct.

### W3 — zepto scraper → **PASS** (correct NO-CHANGE on W1=REAL)
`platforms/zepto/scrape.js` is **byte-untouched** (git diff empty); only `SKILL.md` gained a
documentation section, which accurately states the national-vs-per-store behavior. `result.json`
contract intact, `node --check` clean → **tomorrow-safe by construction** (no code path changed).

### W4 — sheet presentation → **PASS** (presentation-only, originals intact)
Built the true pre-W4 workbook (old `build_pricematch.py` @ `4edfa080`, run from the real dir so
data paths resolve) and diffed cell-by-cell against W4's committed prod build:

- **5 original sheets:** Matrix / Violations / Above reference / Coverage & pending = **0 cell
  diffs**. Ecom Head = exactly **1 diff** — the EXACT-section subtitle text trimmed (the one
  decluttering W4 was explicitly allowed); all KPIs/board data unchanged.
- **Competitor sheets (both):** every priced cell **value-identical AND fill-identical**
  (Now 57/57, Core 145/145) → **prices and red/green colors 100% preserved**. ⚡ exact-match
  column preserved (Now 8/8, Core 11/11). **n/s wall killed** (Now 76→0, Core 173→0, rendered as
  quiet "·"). **Cell comments removed** (Now 57→0, Core 98→0).
- **Tomorrow-safe / robustness:** `py_compile` clean; rebuild is **md5-stable** (two fresh builds
  byte-identical); **fault-injection** (forced `build_compete_sheets` to raise) → workbook still
  saves with exactly the 5 original sheets → the fail-safe correctly isolates the competitor
  sheets and can never break the daily batch.

---

## Phase 3 — tomorrow-safe: confirmed
- Scrapers (zepto, flipkart-minutes): no code change → 08:32 sweep cannot regress; both node-check OK.
- `build_pricematch.py` (W4): fault-injected → still builds; md5-stable; fail-safe + byte-stability
  + pm-history hook intact.

---

## OWNER ANSWER (plain language)

**Your question:** "Why was the same Jivo SKU the same price at two different-city pincodes
(e.g. Zepto Extra Light Olive Oil 1L = ₹499 in both Delhi 110095 and Bengaluru 560005), and what
did you do about it?"

**The answer: that was correct, not a glitch.** We checked it hard. Zepto sets the price for many
of its high-volume oils **uniformly across the whole country** — Extra Light 1L really is ₹499
everywhere (we saw it at 44 different stores in 44 places, all ₹499). For other SKUs Zepto **does**
charge different amounts city-to-city (Pomace 5L was ₹2,128 in Delhi but ₹2,494 in Bengaluru), and
our scraper picks those differences up correctly **in the same pass**. The fact that one SKU shows
two different prices while another shows one identical price — captured in a single scrape — is the
proof it's genuine store-by-store data, not a copied-over or cached number. So when two pincodes
match, that's **real cross-city price parity**, which is itself useful intel.

**What we changed:**
1. **Nothing in the price data** — it was already right, so we left the Zepto and Flipkart-Minutes
   scrapers untouched (documented the behavior so no one re-investigates this next month).
2. **Flipkart-Minutes "not sold here" everywhere:** that's also real — each Flipkart 10-minute dark
   store only stocks a handful of the 113 SKUs, so most cells genuinely aren't sold there. We did
   **not** fake coverage.
3. **We cleaned up the sheets** the way you asked: the loud wall of "n/s" is gone (now a quiet dot),
   and **all the cluttered cell notes/comments were removed** — leaving the real prices, the
   red (undercut) / green (above) coloring, and the exact-price-match (⚡) column, just cleaner.

Bottom line: prices and colors are unchanged and correct; the report is just clearer; and the
"same price in two cities" you spotted is true Zepto pricing, not a bug.

---
**Gate result: PASS — push + deliver approved.**
