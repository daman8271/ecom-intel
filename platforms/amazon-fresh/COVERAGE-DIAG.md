# Amazon Fresh — false-n/s vs capture-miss @110095 (amzcover W2)

**Date:** 2026-06-09 · **Account:** logged-in "Damanpreet" (session intact, read-only probes) ·
**Pincode:** 110095 (Dilshad Garden, Delhi) · **Surface:** `i=freshstore`

## Question
The W2 audit flagged **14 Amazon-Fresh SKUs carried at other pincodes but absent from the rows
captured @110095**. For each: is it a **REAL** per-store stock-out / not-Fresh-serviceable, or a
**CAPTURE-MISS** — the broad `k=jivo` search drops a genuinely-Fresh SKU that a DIRECT ASIN check
surfaces (Zepto-style)? The standing order: do **not** assume "thin = real"; verify with a direct
live check.

## Method (lock-safe, READ-ONLY)
`coverage_probe.js`, run behind `flock .amazon-fresh.lock`, output → `/tmp` (production
`result.json` never touched). It loads the logged-in `storageState` into a context but **never
saves it back** and performs **no cart mutations** — only GETs + the same GLOW `address-change`
the live sweep already does. For each suspect ASIN @110095 it captured THREE signals:
1. **broad** — does the ASIN appear in `/s?k=jivo&i=freshstore` and with what slot;
2. **directSearch** — `/s?k=<ASIN>&i=freshstore` card + its slot (the **authoritative** signal:
   same surface + same `isFreshSlot` gate the scraper uses);
3. **pdp** — `/dp/<ASIN>` buybox availability / delivery block (corroboration only).

### Authoritative discriminator = the freshstore **search-card** slot
A genuine Amazon Fresh card carries a quick-commerce slot — `FREE delivery in N minutes` or a
same/next-day time window (`Today/Tomorrow 6 am - 10 am`). A non-Fresh listing shows a multi-day
courier promise (`FREE delivery Thu, 11 Jun`, `11 - 22 Jun`).

> ⚠️ **PDP delivery block is NOT a reliable Fresh signal** and was deliberately excluded from the
> verdict. The `/dp` buybox routinely shows a standard Prime window — `Or fastest delivery Tomorrow
> 6 am - 10 am` — for items that are **marketplace-only** at this store. That string matches a naive
> `am-pm` slot regex and would have produced 8 false CAPTURE-MISS calls. The verdict keys ONLY on
> the freshstore **search-card** slot (broad or direct), never the PDP. (This is exactly the
> "thin=real… but verify on the right surface" trap.)

## Verdicts (12 REAL · 2 CAPTURE-MISS)

| SKU | ASIN | broad @110095 | DIRECT `k=ASIN&i=freshstore` | PDP corroboration | Verdict |
|---|---|---|---|---|---|
| EXTRA LIGHT 1L | B09HZY97FR | absent | **FRESH** `in 10 minutes` ₹499 in-stock | In stock | **CAPTURE-MISS** |
| RICE BRAN 1L | B0DBHQ2QWW | absent | **FRESH** `in 10 minutes` ₹189 in-stock | In stock | **CAPTURE-MISS** |
| CANOLA 1+1L | B0152TWWSQ | absent | mkt `FREE delivery Fri, 12 Jun` ₹659 | In stock, courier-only | REAL |
| CANOLA 5L | B077ZN4G28 | mkt `Thu, 11 Jun` | mkt `Thu, 11 Jun` ₹1,249 | In stock, courier-only | REAL |
| COCONUT 1L | B0BZ8K3DQP | absent | mkt `Fri, 12 Jun` ₹539 | In stock, courier-only | REAL |
| COCONUT 500ML | B0CGN9Y3PT | mkt `Thu, 11 Jun` | mkt `Thu, 11 Jun` ₹279 | In stock, courier-only | REAL |
| EXTRA VIRGIN 1L | B093BMGPQC | mkt `Thu, 11 Jun` | mkt `Thu, 11 Jun` ₹789 | In stock, courier-only | REAL |
| GOLD 5L | B0C9Q1S6QG | mkt `Thu, 11 Jun` | mkt `Thu, 11 Jun` ₹930 | In stock, courier-only | REAL |
| MUSTARD 1L | B09NYCSQLF | absent | mkt `Thu, 11 Jun` ₹176 | In stock, courier-only | REAL |
| MUSTARD 1L POUCH | B0DRYVRYYM | absent | **not found** | **Currently unavailable** (not stocked) | REAL |
| SO OLIVE 1L | B0DC6JR4F3 | mkt `Thu, 11 Jun` | mkt `Thu, 11 Jun` ₹279 | In stock, courier-only | REAL |
| SOYABEAN 1L | B0B6HNNL5B | mkt `Thu, 11 Jun` | mkt `Thu, 11 Jun` ₹199 | In stock, courier-only | REAL |
| SUNFLOWER 1L | B0B4SJTNF2 | absent | mkt `Thu, 11 Jun` ₹186 | In stock, courier-only | REAL |
| YELLOW MUSTARD 1L | B0FF9P7XVX | mkt `11 - 22 Jun` | mkt `11 - 22 Jun` ₹259 | courier-only | REAL |

**12 REAL** = genuinely **not Fresh-serviceable** @110095 (a customer there can buy them only via
ordinary multi-day marketplace courier — correctly excluded from the Fresh report; MUSTARD 1L
POUCH is flat out-of-stock). Each REAL is backed by a **direct per-ASIN freshstore probe** showing
no Fresh slot — not merely "the broad search didn't return it" (which W3's gate rightly rejects as
circular).

**2 CAPTURE-MISS** = EXTRA LIGHT 1L + RICE BRAN 1L. Both are in-stock with a genuine
`FREE delivery in 10 minutes` Fresh slot on a direct ASIN lookup, yet the broad `k=jivo` page
(48 cards, relevance-ranked + page-capped) dropped them. Tellingly these two are exactly the
**lowest-frequency** Fresh ASINs across the whole sweep (5 and 9 pincodes) despite being widely
Fresh-serviceable — i.e. the broad search chronically under-returns them, so they are
**under-counted sweep-wide**, not just @110095.

## Fix (CAPTURE-MISS → additive direct-ASIN fallback)
Zepto-style seed fallback in `scrape.js`, default ON, fully fail-safe:
- **`fresh_seed_asins.json`** — the 27 genuine Jivo Fresh ASINs observed as real fresh-slot rows in
  production. (Empty/missing file → fallback no-ops → fully backward-compatible.)
- **`directFreshCard()` + loop hook** — at a store that is already Fresh-serviceable AND correctly
  located, re-probe each seed ASIN the broad search **missed** via `/s?k=<ASIN>&i=freshstore`, and
  add it **only if** the direct card carries a genuine Fresh slot + in-stock + Jivo. Purely additive
  (never removes, never adds a marketplace row), per-ASIN `try/catch` (a bad probe skips that ASIN,
  never aborts the pincode), bounded by `FRESH_FALLBACK_MAX` (default 40). Kill-switch
  `FRESH_DIRECT_FALLBACK=0`. result.json schema unchanged (adds only `recovered_direct` per-pin +
  `rows_recovered_direct` summary counters). `node --check` clean; offline `require()` of exports OK.

### Re-probe proof (modified scraper, 110095 only → `/tmp`, behind the lock)
```
[ok] Delhi 110095 freshSvc=true -> 15 fresh (dropped 43 mkt, +2 direct)
rows_recovered_direct: 2
```
EXTRA LIGHT 1L (B09HZY97FR) + RICE BRAN 1L (B0DBHQ2QWW) now present, both with
`FREE delivery in 10 minutes`. **Zero** of the 12 REAL ASINs leaked in (verified). Production
`result.json` left untouched — a single-pincode merge was deliberately skipped; the fix lands
sweep-wide on the next full Fresh run (W3's rebuild), avoiding a half-patched file.

## Handoff notes for W3 / lead
- **Owner answer:** the Fresh false-n/s class is **mostly REAL** (12/14 are genuine per-store
  not-Fresh-serviceable @110095, direct-probe confirmed) **but real and worth fixing for 2/14** —
  the broad search was silently dropping ≥2 genuinely-Fresh in-stock Jivo SKUs per serviceable
  store (the lowest-frequency ones). The direct-ASIN fallback recovers them. Not a Zepto-scale
  miss, but the same bug class, now closed.
- **Runtime / session:** the fallback adds ~10–15 targeted GETs at each of the ~194 Fresh-
  serviceable pincodes (~+20 min; Fresh ~16 min → ~38 min). The deadline-aligned cron's p90 lead
  predictor self-absorbs the one-time duration jump (starts the sweep earlier). It does raise per-
  sweep request volume on the logged-in account ~10× on the search path — stable so far, but if
  Amazon ever escalates to captcha, throttle via `FRESH_FALLBACK_MAX` or `FRESH_DIRECT_FALLBACK=0`.
- Artifacts: `coverage_probe.js` (reusable diagnostic), `/tmp/fresh_coverage_probe.json` (full raw
  evidence), `/tmp/fresh_reprobe_110095.json` (post-fix proof).
