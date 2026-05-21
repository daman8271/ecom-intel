# SKILL: scrape Flipkart marketplace — STATUS: WORKING (datacenter IP)

Flipkart's main marketplace is **scrapable from the VPS datacenter IP** — HTTP
200, no captcha, **no login needed**. First clean run (2026-05-21): **~61 unique
Jivo SKUs in ~16s**. Far richer catalog than the quick-commerce platforms (8–10 SKUs).

## Key design difference vs quick-commerce
Marketplace pricing is **NATIONAL** — a listing's price is the same regardless of
pincode (only delivery date/serviceability vary, and search doesn't expose that).
So we **do NOT loop 40 pincodes** (it would return identical prices). Instead we
paginate the search once and tag every row `city="All India"`. `pincodes.json`
is intentionally unused. Output shape stays Blinkit-compatible.

## Procedure
1. `goto https://www.flipkart.com/search?q=jivo&page=N` for N=1..6.
   ~40 cards/page, ~91 results total. Stop when a page yields 0 Jivo cards.
2. Press Escape to dismiss the occasional login popup (doesn't block scraping).
3. Product card = ~268×439 element. Lines: `[name, pack, rating, price, badge]`.

## Card parsing (IMPORTANT — read prices per-node)
`innerText` GLUES the prices and discount: `"₹1,463₹4,49767% off"` (sale, MRP,
then the discount digits with NO separator). Parsing that string is a trap —
the comma in the MRP makes `\d+%` mis-capture (we hit `sale 4 / mrp 1463` bugs).
**Instead read each ₹ value from its own DOM node:** elements whose trimmed
textContent matches `^₹[\d,]+$` are the individual sale and MRP nodes. A
"Buy 2 items, save extra ₹20" badge is a single node and won't match.
- `sale = min(price nodes)`, `mrp = max(price nodes)`.
- pack: a line matching `^(N x )?N unit$` — handles **multipacks** like
  `3 x 1 L`, `2 x 1000 ml` (parseVolMl multiplies count × size for vol_ml & ₹/L).
- in_stock=0 on `out of stock|currently unavailable|sold out|coming soon|notify me`.
- eta_min = null (marketplace).

## Quirks
- ~91 search results but not all unique Jivo SKUs; deduped on canonical → ~50–61.
- Discounts run 0–84% (median ~38%); MRPs are inflated, typical for the channel.
- Live in `setup_cron.sh` + `healthcheck.sh` PLATFORMS lists.
- `build_excel.py` is platform-aware; the city matrices show a single "All India"
  column by design (national pricing).
