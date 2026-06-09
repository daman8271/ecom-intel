# SKILL: scrape Zepto — STATUS: LIVE (BFF API gateway, no proxy)

## 2026-06-05 note (earlier fix, 02f8937)
A **full-catalog PDP-seed pass** recovered the catalogue from **12 → 23 SKUs**, including
**Jivo Mustard 5L** and OOS / rollup-hidden variants the plain search missed. Zepto tracks
the **SUPER_SAVER** price tier (the price the app shows by default — see "Two price tiers"
below).

Zepto's WEBSITE edge (`www.zeptonow.com` / `api.zeptonow.com`, CloudFront) hard-`403`s this
datacenter VPS IP. BUT the app's **BFF API gateway `bff-gateway.zeptonow.com` (Kong) is reachable
direct, no proxy**, and authenticates guest browsing with `x-without-bearer: true` (no login).
That is how we scrape. **This is a curl-against-API scraper — NOT Playwright/DOM.** (The old
"BLOCKED / GPS+DOM" design never shipped; ignore any stale mention of it.)

## How it works (`scrape.js`) — two calls per pincode
1. **Resolve store** (GET):
   `bff-gateway.zeptonow.com/serviceability-service/api/v1/serviceability?lat=&long=`
   → `{ data:{ serviceable, stores:[{storeId, serviceable, storeConstruct}] } }`; pick a
   serviceable PRIMARY store.
2. **Search catalogue** (POST):
   `bff-gateway.zeptonow.com/user-search-service/api/v3/search`
   body `{ query:"jivo", pageNumber, intentId, mode:"AUTOSUGGEST", userSessionId }`.
   Walk the response for `productResponse` nodes; keep `product.brand == "Jivo"` (or name
   contains the word "jivo"); dedup by `store|canonical`.

Key headers (`commonHeaders`): `tenant: ZEPTO`, `platform/app_sub_platform: WEB`,
`app_version: 12.64.1`, `x-without-bearer: true`, per-store `store_id`/`store_etas`,
geo `x-latitude`/`x-longitude`, and **`marketplace_type`** (see tiers below). Prices are in
**paise** (÷100). Run: `node scrape.js` (env: `PINCODES_FILE`, `OUT_FILE`, `CONCURRENCY`,
`ZEPTO_MARKETPLACE`).

## Two price tiers (same store, same catalogue, different price)
Selected purely by the `marketplace_type` header:
- **SUPER_SAVER** — scheduled delivery, the price the app shows by default → **we track this**.
- **ZEPTO_NOW** — instant ~10-min delivery. Override with `ZEPTO_MARKETPLACE=ZEPTO_NOW`.

The response also carries `pricingData.pricingEntityPrices` = an explicit
`{pricingEntity, discountedSellingPrice}` per tier (SUPER_SAVER / ULTRA_SAVER / …). `scrape.js`
records the price from **that structured tier field** (authoritative, app-rendered), falling
back to `superSaverSellingPrice` → `discountedSellingPrice` only if absent.

## Per-pincode pricing: national vs per-store — when a SKU shows the SAME price in two cities, that is REAL (verified 2026-06-09, pmdiag W1+W3)
The scrape is **already per-store**: it resolves a distinct store per pincode and reads THAT
store's `pricingData:SUPER_SAVER`. So when a SKU shows the **same price at two different-city
pincodes, that is a TRUE Zepto fact, not a scrape/merge/cache bug.** Zepto prices many
high-volume SUPER_SAVER SKUs **uniformly nationwide**, and prices others **per store** — and
`scrape.js` captures both correctly. Proof (W1 live PDP probe + W3 cross-check of the same
`result.json` scrape, Delhi store `0c865653` vs Bengaluru `e4a9d9d2`):
- **National (genuinely flat):** Extra Light 1L = ₹499 at both cities (and all 48 in-stock
  stores in that day's scrape); Pomace 1L ₹379; Extra Virgin 1L ₹934 — all `cached:false`.
- **Per-store (genuinely varies, SAME scrape, SAME route):** Pomace 5L 2128 vs 2494
  (≈13 distinct values across stores); Kachi Ghani Mustard 1L 180 vs 181; Canola ₹1193–1617;
  Sunflower 182–192; Groundnut peanut ₹49 vs 72. In W3's audit of `result.json`, **6 of 18
  in-stock SKUs vary across stores**, 12 are flat.
A scraper recording one cached national constant could NOT produce that side-by-side variation
in a single scrape — so the flat SKUs are flat because Zepto sets them flat. **SUPER_SAVER is
the correct tier:** the `marketplace_type` header (SUPER_SAVER vs ZEPTO_NOW) makes ZERO
difference at the PDP route, and ULTRA_SAVER is just a lower price with the same per-store
pattern. **No per-store "tier X" to switch to; no scraper change.** Implication for the
competitor price-match sheets: pinning Zepto to `110095` (Delhi) vs `560005` (Bengaluru) is
**accurate** — identical values are real cross-city parity, not a defect. (Sheet labeling is
W4/W5's call; the scraper data is correct as-is.)

## Freshness (the ~1-day staleness problem) — IMPORTANT
The search endpoint is backed by a search index. When it serves a product from cache it sets
**`cached: true`** on that product (a stale-price risk); when `cached: false` the search price
equals the live app price. There is **NO read-only PDP/product-price route on this gateway**
(every product/inventory/pdp path returns Kong `404 "no Route matched"`; only `cart-service`
exists and needs a stateful guest-cart mutation — unfit for a national loop). So the freshness
strategy is detect-not-replace:
- `scrape.js` records per-row **`cached`** + per-store realtime markers
  (`is_realtime_model_data_fetched`, `realtime_model_not_enabled_reason`, `algoliaTimeOut`),
  and aggregates `summary.freshness` (`rows_cached`, `pct_cached`).
- `tools/review.py` raises a **price-staleness SUSPECT** when `pct_cached` is high, or when a
  SKU's modal price is frozen across many runs AND some rows are cache-served.
If Zepto ever exposes a guest PDP/price route, switch step (price) to read it directly.

## Output shape (identical to Blinkit, so `build_excel.py` is unchanged)
`{city, pincode, locality, store_id, store_name, sku_raw, canonical, pack, vol_ml, sale, mrp,
discount_pct, per_litre, eta_min, in_stock, cached, price_source}`
(`cached`/`price_source` are additive; build_excel ignores them.)

## Coverage / cron
`pincodes.json` = 332 store-distinct coords. LIVE in the serial cron sweep (`run_all.sh`,
10:00 + 15:00 IST), no Amazon lock needed (Zepto is account-independent).

## Recon probes (kept for future debugging)
`probe_cache.js` (CloudFront/edge cache check on the search POST — shows `x-cache: Miss`,
i.e. not CDN-cached) and `probe_dom.js` (confirms the website still 403s this IP). Run with
`node platforms/zepto/probe_cache.js`.
