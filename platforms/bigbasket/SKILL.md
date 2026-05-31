# SKILL: scrape BigBasket — STATUS: WORKING (datacenter IP, stealth)

BigBasket's web storefront is scrapable from the VPS **only via a stealth
browser** — plain Chromium / curl / node-fetch get **HTTP 403** (Akamai Bot
Manager). Full recon: [`RECON.md`](RECON.md).

## Model: NATIONAL (like Flipkart, not hyperlocal)
BigBasket "BB" (scheduled delivery) prices Jivo **nationally** — the
`listing-svc` search API returns the same catalogue + prices regardless of the
session's city/hub. The old per-city location APIs are decommissioned (404) and
overriding the hub cookie doesn't change Jivo pricing. So we do **one scrape**
and tag every row `city="All India"`. We do **not** loop pincodes; `pincodes.json`
is intentionally a single national placeholder, kept only for shape-consistency.

This is the same model as the Flipkart **marketplace** scraper. Its value is
**catalogue breadth + price/MRP/discount** on a major grocery platform, not
per-city granularity (that's what Blinkit/Zepto/ provide).

## The trick: stealth browser + in-page API fetch
1. `playwright-extra` + `puppeteer-extra-plugin-stealth` (Playwright's own
   Chromium binary) bypasses Akamai → homepage loads HTTP 200. Plain
   `chromium.launch` → 403. Same recipe as .
2. `goto https://www.bigbasket.com/` once — establishes the session cookies
   (`csurftoken`, `x-channel`, `_bb_cid/_bb_nhid/_bb_sa_ids`, Akamai `_abck`/`bm_sz`).
3. From the **page's own JS context** (`page.evaluate(fetch(...))` — inherits the
   real cookies + TLS fingerprint, so Akamai lets it through) call:
   ```
   GET /listing-svc/v2/products?type=ps&slug=<query>&page=<n>&bucket_id=32
   ```
   `bucket_id=32` is **mandatory** (omit → HTTP 400). External node/curl with the
   same cookies still gets 403 — the in-page fetch is required.
4. Parse `tabs[0].product_info.products[]`, keep `brand.name.trim() === "Jivo"`.

## Field map (per product `p`)
| Field | JSON path |
|---|---|
| sku id | `p.id` |
| name | `p.desc` |
| brand | `p.brand.name` (trim — has trailing space) |
| pack | `p.w` (`"5 L"`, `"200 ml"`) |
| volume (ml) | `p.magnitude` (+ `p.unit`; magnitude already in ml) |
| MRP | `p.pricing.discount.mrp` (string) |
| selling price | `p.pricing.discount.prim_price.sp` (string) |
| discount % | `p.pricing.discount.camp_detail.d_v` (fallback; we prefer mrp−sp) |
| per-unit price | `p.pricing.discount.prim_price.base_price` / `base_unit` |
| in stock | `p.availability.avail_status === '001'` and `!not_for_sale` |

## Run
```bash
cd platforms/bigbasket && node scrape.js       # ~15-25s, writes result.json
# or from repo root: ./run.sh bigbasket         # scrape→excel→predict→review→vault→telegram→push
```
Queries default to `jivo, jivo olive oil, jivo oil, jivo juice` (deduped on
canonical). Override with `BB_QUERIES="jivo,jivo vinegar"`.

## Output shape (keep this — build_excel.py depends on it)
`result.json` = `{summary, perPin, allRows}`. Each row carries the canonical
fields (`city, pincode, locality, store_id, store_name, sku_raw, canonical, pack,
vol_ml, sale, mrp, discount_pct, per_litre, eta_min, in_stock`) plus rich
identity (`sku_id, brand, avail_status, base_price, category, absolute_url`) that
build_excel ignores but vault/history/review keep. `summary.pincodes_total = 1`,
`pincodes_with_jivo = 1` when any Jivo row is found.

## Jivo's BigBasket catalogue is multi-category (not just oils)
BB lists Jivo **edible/olive oils** AND a **beverages line** — wheatgrass juices,
flavoured fizzy water, Indian tonic water — all genuinely `brand="Jivo"` (verified;
URLs are `/pd/.../jivo-...`). These are **real Jivo products, not scraper
contamination**. (`tools/review.py`'s LLM gut-check was taught this so it no longer
false-flags them as off-brand.)

## Gotchas
- **Stealth is mandatory** — any non-stealth client gets 403 on this DC IP.
- **`bucket_id=32`** is required; if BB ships a new web build and it changes,
  capture the XHR from `https://www.bigbasket.com/ps/?q=jivo` to read the new value.
- **Strict brand filter** (`=== "jivo"`) avoids substring noise (Jivika, JIVOTTAM).
- **0 rows / 403 on homepage** → Akamai escalated against the DC IP → would need
  a residential proxy (see `docs/PROXY.md`); review.py will flag the run BROKEN.
- **BB vs BB Now**: the storefront defaults to BB (scheduled); BB Now (express)
  shares the same catalogue + pricing for Jivo, so the listing API value is the same.

## When prices ever DO vary by city
If BigBasket later reintroduces a usable per-city location switch, this becomes a
per-pincode scraper like Blinkit: set the hub via cookie/address before each
listing call and loop `pincodes.json`. Not needed today (pricing is national).
