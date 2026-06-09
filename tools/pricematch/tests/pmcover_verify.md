# W5 — Adversarial gate: the owner's false-n/s catch (pmcover fleet, 2026-06-09)

**Verdict: ✅ PASS** (gates LEAD push + delivery)
**Author:** W5 (adversarial verifier) · **Mode:** read-only on prod; all probes/rebuilds to `/tmp`.
**Scope:** independently verify W1 (zepto seed), W2 (false-n/s audit), W3 (fkm), W4 (sheet rebuild)
— trust nothing, re-derive everything. The owner already caught us once.

---

## TL;DR for the owner (plain language)

**You caught a real defect, and it is fixed.** Our Bengaluru-560005 sheet showed the Jivo Cold-Press
Canola 1+1L combo as *not there* when it was live on Zepto. Root cause: our Zepto scraper finds
products two ways — a brand *search* (which lags and sometimes hides pack-size variants) plus a
*seed list* of product IDs we look up directly at every store. **That combo's ID was missing from the
seed**, so at stores where search didn't surface it we recorded nothing → a false "not there." We
completed the seed (now the full 23-ID known-variant union, was 11) so every store is now probed for
every known Jivo variant. The combo now shows **in-stock at 560005** on both Amazon PM sheets.

**One honest correction to the original ask:** the exact **₹469 = ₹469** price-match you saw will
**not** light up — because Zepto's live price for that combo is no longer ₹469. I re-pulled the live
Zepto page myself (independent of the team): it's **₹485** right now (SUPER_SAVER tier, 35% off), with
₹461 on the Ultra-Saver tier. **There is no ₹469 anywhere in the live data.** Your photo showed ₹469
(₹281 OFF); the live offer has since moved to ₹485 (₹265 OFF). So your ₹469 was a **real but
point-in-time promo that has ended** — not a scraper error. We deliberately did **not** fabricate ₹469
to make the match light up; we show the true live ₹485. Your underlying complaint ("shown absent when
it was live") is **fully corrected**.

**We also went looking for others.** A comprehensive audit found **96 suspect "not-there" cells** on
the 5 quick-commerce platforms (the 3 national platforms — Amazon Core, Flipkart MP, BigBasket — are
authoritative; their "not there" is real). Zepto is **fully fixed** this round. **What's still open
is listed below** — chiefly Amazon Fresh and Amazon Now, which have the same kind of search-recall
gaps but no seed system yet. We're not claiming an all-clear.

---

## 1. THE CAUGHT CASE — independently verified (this is the deliverable)

### 1a. Pre-fix state (my own baseline, captured before the workers ran)
- Zepto CANOLA 1+1L (variant `50b56b7f`) @ **560005 = 0 rows** → false "not there" (the catch).
- @ 110095 = 1 row, **OOS** (₹485, in_stock=0).
- ₹469 appeared **nowhere** in zepto data (observed prices 485/493/520).
- Amazon Core CANOLA 1+1L = **₹469** in-stock (the reference / the match target).

### 1b. Post-fix merged data (W1)
`platforms/zepto/result.json` now has, at the 2 ref pincodes:
- 560005: **1 in-stock row, ₹485**, store `e4a9d9d2`, `price_source = pdp:pricingData:SUPER_SAVER`.
- 110095: 1 row, OOS ₹485.

### 1c. INDEPENDENT live re-probe by W5 (did W1 hit the wrong store / misread a field?)
I ran my own lock-safe gateway probe (`/tmp/w5_zepto_probe.sh`) of variant `50b56b7f` at the 560005
coords (12.9986, 77.6205) — replicating the scraper's serviceability→PDP path from scratch:
- Store resolution: **same store pair** W1 found — `e4a9d9d2` (PRIMARY) + `d4205b92` (SECONDARY).
  There is **no separate "Maruthi Seva Nagar" dark store** with its own price (the chip label is
  cosmetic). So W1 did not hit the wrong store.
- `availableQuantity = 1` → **in-stock** (the false n/s is genuinely gone).
- Live price tiers, stable: `pricingEntityPrices[0] = 48500` (₹485 SUPER_SAVER, 35% off),
  `pricingEntityPrices[1] = 46100` (₹461 ULTRA_SAVER); `superSaverSellingPrice = 48500`;
  `nonPassTotalDiscount = 26500` → non-pass price also ₹485.
- **`46900` (₹469) does not exist anywhere in the live response.** Confirmed by raw-byte grep.

**Conclusion:** W1's verdict is correct and evidence-backed. The ₹469 was a transient promo that has
ended; live = ₹485. Refusing to fabricate ₹469 was the right call.

### 1d. Rendered sheet (W4) — faithful
Both PM sheets, CANOLA 1+1L @ 560005:
- **Zepto cell = ₹485, in-stock** (was a quiet-dot / pending false n/s). ✅ false-n/s fixed.
- **"Price match (same ₹)" column = "—"** (Amazon Core ₹469 ≠ Zepto ₹485). ✅ correct — the exact
  match does NOT light up because it is not live. **This is truthful, not a miss.**
- CANOLA 1+1L now also surfaces as a **new row on the Amazon Now PM sheet** (₹485 @560005).

W4's build is faithful: my independent rebuild of the workbook is **cell-for-cell identical** to W4's
committed file (0 value diffs across all 7 sheets) — no hidden hand-edits.

---

## 2. SEED COMPLETENESS (W1) — verified

- `platforms/zepto/jivo_variants.json` = **23 variantIds**, a superset of **all 19** zepto IDs in
  `sku_map.json` (0 sku_map IDs missing from the seed). `50b56b7f` present.
- All 9 formerly-missing master-SKU variants are now in the seed.
- `platforms/zepto/scrape.js` is **git-untouched** (data-only fix) → tomorrow's 08:32 sweep can only
  get **more** complete, never break. Each added seed ID = 1 extra PDP probe/store (11→23 = +12/store).
- Zepto post-fix has **0 remaining "no-row" false-n/s** for mapped SKUs at the ref pins (every mapped
  zepto SKU now renders a price or an authoritative PDP OOS).

---

## 3. COMPREHENSIVE AUDIT (W2) + fkm (W3) — spot-checked

**W2 (96 LIKELY-FALSE cells):** I independently re-derived 3 of its calls via the frozen
`price_at()` contract — all confirmed (mapped + in-stock at many other pincodes, absent at ref):
| Cell | Mapped? | In-stock elsewhere | Verdict |
|---|---|---|---|
| blinkit · JIVO POMACE 1L · 560005 | yes (`528706`) | @120 pins (₹383) | LIKELY-FALSE ✓ |
| amazon-now · CANOLA 1L · 560005 | yes (`B09MJ6QDX7`) | @63 pins (₹259) | LIKELY-FALSE ✓ |
| amazon-fresh · EXTRA VIRGIN 1L · 110095 | yes (`B093BMGPQC`) | @96 pins (₹789) | LIKELY-FALSE ✓ |
W2's "3 national platforms authoritative, 5 per-pincode lossy" framing matches the scrapers' actual
discovery mechanisms. Audit is sound.

**W3 (fkm):** verdict **REAL thin — NOT a capture bug** is genuinely evidence-backed, not assumed. The
decisive test (in `platforms/flipkart-minutes/DIAG2.md`): broad `q=jivo` vs **8 targeted per-product
searches** at both ref pins → targeting surfaced **ZERO** extra in-stock SKUs (the exact opposite of
zepto, where a targeted variant lookup revealed the hidden ₹469). Mechanism: fkm packs are each their
own listing (no parent-hides-variant rollup), so `q=jivo` returns the store's full in-stock Jivo set.
scrape.js + result.json untouched. (Note: fkm data is live, not stale — 560005 canola flipped
OOS→in-stock ₹255 intraday; this self-corrects each sweep.)

---

## 4. NO-REGRESSION / TOMORROW-SAFE — verified by a clean pre-fix rebuild

I rebuilt the workbook on **pre-fix zepto data** (via `PM_PLATFORMS` override pointing zepto at my
pre-fix snapshot, everything else symlinked to prod) and diffed it against W4's committed sheet:

| Original sheet | Result |
|---|---|
| Ecom Head | **identical** (0 changed cells) |
| Matrix | **identical** (0 changed cells) |
| Above reference | **identical** (0 changed cells) |
| Coverage & pending | **identical** (0 changed cells) |
| Violations | **+3 rows, 0 removed, 0 modified** — purely additive |

The 3 new Violations rows are exactly the seed-fix's new in-stock zepto ref-pin undercuts:
`EXTRA LIGHT 2L Zepto @110095 & @560005 = ₹1135` and `CANOLA 1+1L Zepto @560005 = ₹485`. Totals
updated correctly (2832→2835 store rows, Σ loss +₹232). The 2 live intraday reprices in W1's
re-scrape (POMACE 2L @110095 OOS→₹961; Refine-Canola-15L-tin ₹3187→₹3465) had **zero** sheet impact
(the first became a within-tolerance match; the tin is unmapped to any master SKU).

- All zepto data changes are confined to the **2 ref pincodes** (other 56 byte-identical).
- `sku_map.json` and **both** scrape.js (zepto, fkm) are git-untouched.
- W4 made **no** `build_pricematch.py` logic change (faithful render only).
**Tomorrow's 08:32 sweep is safe by construction.**

---

## 5. STILL-OPEN — HONEST list (what is NOT yet fixed)

This round fixed **zepto only**. The audit's other 90 suspect cells are real and **not** addressed:

1. **Amazon Fresh — ~36 false-n/s cells.** Two parts:
   - *560005 coverage hole* (whole column was unswept): LEAD added 560005 to the fresh sweep set →
     **fills tomorrow's 08:32 sweep** (additive, scheduled, unverified until it runs).
   - *Per-SKU search-recall misses @110095* (EXTRA VIRGIN 1L @96 pins, CANOLA 5L @74, SOYABEAN 1L,
     SO-OLIVE 1L, GOLD 5L, …): **NOT fixed** — amazon-fresh has no seed system like zepto's. These
     remain false-n/s until a seed/recall fix is built. **Unowned.**
2. **Amazon Now — ~31 false-n/s cells.** 560005 is already swept but genuinely thin (1 row). The
   per-SKU misses (CANOLA 1L/5L, EXTRA VIRGIN 1L, MUSTARD 5L, JIVO POMACE 5L, …) are the same
   search-recall class — **NOT fixed, no seed. Unowned.**
3. **Blinkit — ~9 false-n/s cells.** Search-recall + the known ~40% bad-coordinate geocoding gap.
   **NOT fixed** (a geocoding follow-up, pre-existing known gap).
4. **The ₹469 cross-platform exact-match is no longer live** (ended promo). Not reproducible, not a
   defect — but the owner should know the specific signal he saw is gone.
5. **fkm intraday churn** — n/s is authoritative *at scrape time* but the thin per-store catalog
   moves within the day; a cell can be right at 08:32 and stale by afternoon. Inherent, low-impact.

**Recommendation:** treat Amazon Fresh + Amazon Now search-recall as the next fleet (a seed/targeted-
lookup pass analogous to W1's zepto fix), and confirm the 560005 fresh coverage actually lands at the
next sweep.

---

## Verdict

**PASS.** The owner's caught defect is genuinely fixed (false n/s → real in-stock price), the fix is
truthful (live ₹485 shown, ₹469 not fabricated — independently re-probed), the seed is complete and
scrape.js untouched (tomorrow-safe), the comprehensive audit is sound and spot-check-confirmed, and
the 5 original sheets are unchanged except for 3 additive Violations rows. The remaining suspect cells
(Amazon Fresh/Now/Blinkit) are honestly catalogued above rather than papered over. **LEAD may push +
deliver.**
