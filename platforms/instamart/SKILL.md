# SKILL: scrape Swiggy Instamart — SCRAPABLE (working)

Status: WORKING from this datacenter VPS IP. `scrape.js` is live-ready. Verified 2026-05-22.

## Verdict: SCRAPABLE (direct, no proxy)
Instamart loads fine from this IP (home page renders, no 403/captcha). The catch is a
soft bot-block on the search API: the SPA's own GET `/api/instamart/search/v2` returns
HTTP 200 with an EMPTY body and header `x-rate-limit: SignalAutomatedBrowser` when it
detects an automated browser. The fix is a stealth context + a POST (not GET) issued
from the page's own JS context — that path is NOT blocked and returns full product JSON.

## How scrape.js works (proven by recon)
1. **Location** = browser **geolocation** (lat/lon from pincodes.json), permission granted.
   No localStorage/address-modal needed. On loading `https://www.swiggy.com/instamart?lat=&lng=`
   Swiggy resolves a dark-store and fires `/api/instamart/home/v2?storeId=<id>` — we sniff
   `storeId` off that request URL. If no storeId appears, the pincode is not serviceable
   (genuine, not a block) → 0 rows for that pincode.
2. **Stealth** = `--disable-blink-features=AutomationControlled` + an addInitScript that sets
   `navigator.webdriver=undefined`, fakes `window.chrome`, plugins, languages. This is what
   makes search/v2 return data instead of the `SignalAutomatedBrowser` empty body.
3. **Search** = `page.evaluate(fetch('/api/instamart/search/v2?...storeId=<id>...', {method:'POST',
   body: JSON.stringify({query:'jivo', pageType:'INSTAMART_SEARCH', queryType:'GLOBAL'})}))`.
   Runs in page context so it inherits the live session cookies/headers. Returns ~200-240KB JSON.
   (GET on the same path = 404; the POST body is required.)
4. **Parse**: `data.cards[]` → cards where `card.card.card['@type']` ends with `GridWidget` →
   `gridElements.infoWithStyle.items[]`. Each item has `brand`/`displayName` + `variations[]`.
   Per variation: `quantityDescription` (pack, e.g. "1 ltr"), `price.mrp.units`,
   `price.offerPrice.units` (sale), `price.offerApplied.listingDescription` ("17% OFF"),
   `inventory.inStock`, `podId` (store_id). ETA is store-level, scraped from home DOM ("18 Mins").
   No dark-store *name* is exposed by the API → store_name = `Instamart <city>`.

## Output shape (unchanged — build_excel.py works as-is)
Each row: `{city, pincode, locality, store_id, store_name, sku_raw, canonical, pack, vol_ml,
sale, mrp, discount_pct, per_litre, eta_min, in_stock}`. Written to `result.json` as
`{summary, perPin, allRows}`. Verified: scrape.js → result.json → build_excel.py → 6-sheet xlsx.

## Run / test
```bash
node scrape.js                                  # all pincodes (332 store-coords)
ONLY_PINCODE=560019 node scrape.js              # single-pincode block-test path
LIMIT=3 CONCURRENCY=3 node scrape.js            # quick multi-pincode smoke test
OUT_FILE=/tmp/x.json ONLY_PINCODE=110001 node scrape.js   # custom output path
```
Tunables (env): `CONCURRENCY` (default 3), `ONLY_PINCODE`, `LIMIT`, `PINCODES_FILE`, `OUT_FILE`.

## Sample verified run (2026-05-22)
- `ONLY_PINCODE=560019` → 12 Jivo SKUs, store 788742, eta 13min, 8s.
- `LIMIT=3 CONCURRENCY=3` (Bengaluru) → 29 rows, 17 unique SKUs, 2/3 pincodes serviceable, 9s.
- Cross-city storeId resolves correctly: Delhi 110001=1062419, Bengaluru 560019=788742, Chandigarh 160011=1381441.
- Example row: `{city:Bengaluru, pincode:560019, store_id:788742, sku_raw:"Jivo Gold Refined Oil ...",
  pack:"1 ltr", vol_ml:1000, sale:167, mrp:225, discount_pct:25.8, per_litre:167, eta_min:13, in_stock:1}`.

## To make it LIVE
- `run.sh <platform>` already handles instamart unchanged (`cd platforms/instamart && node scrape.js`).
- Add `instamart` to the platform loop in `run_all.sh` (line ~15: `for P in blinkit flipkart-minutes flipkart amazon; do`).
  At 332 store-coords and ~6s/pincode it's a multi-minute sweep — keep it in the sequential sweep, same as others.
- No proxy needed. If Swiggy later tightens the WAF and search/v2 starts returning the
  `SignalAutomatedBrowser` empty body again, the residential proxy (tools/proxy.js, the zepto
  pattern) is the fallback — add the 2-line chromium.launch proxy change.

## Recon history
`spike.js` (this round's one-shot recon) + the prior `probe.js`, `recon_instamart.js`,
`instamart_recon.js` here, and `platforms/blinkit/{instamart_recon,recon_instamart}*.js`
(phases 1-7, prior spillover). Phases 5-7 correctly found the search/v2 endpoint + storeId
sourcing but missed that (a) the block is bot-detection not empty-storeId, and (b) a stealth
POST defeats it. That's the delta this round closed.

## When to adapt for a new platform
Copy this folder, then change: the base URL, the location mechanism, the card selectors /
API parse. Keep the output row shape identical.
