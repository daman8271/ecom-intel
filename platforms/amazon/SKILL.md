# SKILL: scrape Amazon marketplace — STATUS: WORKING (datacenter IP, with bypass)

amazon.in is scrapable from the VPS datacenter IP **after passing a bot
interstitial**, with **no login**. First clean run (2026-05-21): **~163 unique
Jivo SKUs in ~27s** — the richest catalog of all platforms.

## 2026-06-05 fix — combo per-litre / volume inflation (af74b08)
`parseVolMl` now **SUMS additive bundles** instead of reading only the first token: a pack
like `"5+1 LTR"` or `"200ML+5LTR"` now yields the true total volume (6000 ml / 5200 ml), not
1000 ml. (Logic lives in `./volparse.js`, shared shape.) Combined with a **per-litre clamp
at ₹6000/L** (`PRICE_PER_L_MAX`; out-of-band → `per_litre=null`), this fixes the combo ₹/L
inflation that was overstating these SKUs by **1.2–26×**.

## The interstitial bypass (REQUIRED)
A datacenter IP hitting amazon.in gets HTTP **202** + a "Continue shopping"
button (and raw `/s?k=` requests get **503** throttles). So every run must:
1. `goto https://www.amazon.in/`, then click the **"Continue shopping"** button
   (`getByRole('button', {name:/continue shopping/i})`).
2. Then the site + search return 200 normally.
⚠️ Risk: Amazon may escalate to a hard captcha if it sees this twice-daily from
the same IP over time. If runs start returning 0 rows, that's the signal → move
to a residential proxy (see REPORT.md).

## Key design difference vs quick-commerce
Marketplace pricing is **NATIONAL** → scrape the Jivo catalog once by paginating
`/s?k=jivo&page=N` (N=1..5), tag rows `city="All India"`. `pincodes.json` unused.

## Card parsing
- Each result = `[data-component-type="s-search-result"]`.
- **title**: `[data-cy="title-recipe"]` (the `h2` alone only yields the brand
  "JIVO"). Strip leading badges (Sponsored / Amazon's Choice / Overall Pick /
  Bestseller), keep the part before the first `|` (Amazon titles put descriptors
  after `|`). Pack size (e.g. "5 Litre", "1 Litre") is embedded in this name.
- **prices**: `sale` = first `.a-price .a-offscreen`; `mrp` = the **largest
  integer ₹** value in the card (the struck M.R.P.). Per-unit prices like
  `₹247.80` carry a decimal so `^₹[\d,]+$` drops them; coupons sit below sale so
  they can't beat the max. If no higher value, mrp = sale (no discount).
- in_stock=0 on `currently unavailable|out of stock|temporarily out of stock`.
- eta_min = null.

## Quirks
- ~31/163 SKUs have no parseable pack (combo/variant titles w/o a size) → vol_ml
  & per_litre null for those; acceptable.
- Discounts 0–80% (median ~35%). MRPs inflated, typical for the channel.
- Live in `setup_cron.sh` + `healthcheck.sh`. build_excel.py platform-aware;
  single "All India" city column by design (national pricing).
