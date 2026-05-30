# Flipkart Minutes — scraper notes

Two modes in `scrape.js`, auto-selected at runtime:

## 1. API mode (default, fast — ~60s for 345 pincodes)
Direct calls to Flipkart's BFF, no DOM scraping. Needs a **logged-in session** transplanted from
the user's own browser (the datacenter IP can't log in, and guests are blocked by a
device-fingerprint cookie — see below).

Flow per pincode (two JSON POSTs to `https://<N>.rome.api.flipkart.com`, `<N>` from the `at`
JWT's `z` field: CH→1, HYD→2, MUM→3, KOL→4; wrong subdomain → 406 "DC Change"):
1. `POST /api/4/location/update` — body `{geoLocation:{latitude,longitude}, addressInfo:{addressLine1,city,state,pincode}, redirectionUrl:"/flipkart-minutes-store?marketplace=HYPERLOCAL", marketplace:"HYPERLOCAL"}`. Sets the delivery store for this context's cookie jar.
2. `POST /api/4/page/fetch?cacheFirst=false` — body `{pageUri:"/search?q=jivo&marketplace=HYPERLOCAL", locationContext:{pincode,changed:false}, requestContext:{type:"BROWSE_PAGE"}, ...}`. Returns structured products.

**Search-only does NOT work** (always 302s) — location/update must run first per pincode.
Runs a pool of isolated browser contexts (each its own cookie jar → no location cross-talk), each
looping its share of pincodes via in-page `fetch` (`credentials:'include'`). 302 → one
re-resolve+retry. Env: `FKM_CONCURRENCY` (default 10), `PINCODES_FILE`, `OUT_FILE`.

Response field map (`slots[].widget.data.products[].productInfo`):
- name `value.titles.title` · pack `value.titles.subtitle` (e.g. "1 L")
- sale `value.pricing.finalPrice.value` (₹, **not paise**) · MRP `value.pricing.prices[priceType=="MRP"].value`
- discount `value.pricing.totalDiscount` · per-litre `value.pricing.pricePerUnit.pricePerUnit` (pivotQualifier=="L")
- in-stock `value.availability.displayState=="IN_STOCK"` · store `action.params.shopId[0]` · brand `value.productBrand`

### Why a login is required (the guest blocker)
Flipkart binds the hyperlocal session to a **`T` device-fingerprint cookie** its JS mints in a real
browser and cross-checks against the `at` JWT's `dId`. Guests can't forge it, so `location/update`
returns 200 but never commits → search 302s. A logged-in session exported from a real browser
carries a **valid `T` + matching `at`** → the bind succeeds.

### Session setup / re-export (the only manual step, ~once per few months)
1. Log into `flipkart.com` in a browser on your own machine; set a delivery location once.
2. Export cookies with **Cookie-Editor** (Export as JSON).
3. On the VPS: `node import_cookies.js <export.json>` → `secrets/flipkart-minutes.storageState.json`
   (gitignored, chmod 600). Verifies the critical `at` + `T` cookies.
4. Optional: `node probe_session.js` (should print Jivo for several pincodes).

**Durability:** loading the logged-in homepage at the start of each run refreshes the short-lived
`at` (30 min) from the long-lived `rt` (~6 months) — *verified* — so cron keeps working for months
with no manual step. When `rt` expires (or you log out) it auto-falls back (mode 2) and logs
"re-export Flipkart cookies"; just redo the 3 steps.

## 2. Browser fallback (`scrape.browser.js`, login-free, ~37 min)
The original Playwright DOM scraper — no login needed (GPS + "Use my current location" click +
card parse with tight geometry bounds w150–380×h300–560; sale=min(₹prices), mrp=max; OOS via
"currently unavailable" etc.). `scrape.js` runs this automatically if the session is missing or
the health-check pincode (Noida 201304) returns no Jivo. The always-available safety net.

## Coverage / output
345 pincodes = Blinkit's 332 deduped store-coords (798-pincode density / 16 cities) + 13
FK-Minutes-only-city points (`pincodes.json`; old 40 in `pincodes.40.bak.json`). FK Minutes is a
narrower network than Blinkit, so ~half the probes are "not serviceable" (handled gracefully);
typical yield ~85-100 pincodes carrying Jivo, ~11 distinct Jivo SKUs. Output shape `{summary,
perPin, allRows}` is identical across both modes so `build_excel.py` / the vault work unchanged.
