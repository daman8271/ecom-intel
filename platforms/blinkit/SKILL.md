# SKILL: scrape Blinkit (PROVEN)

How the Blinkit scraper works. Status: **working** (40 pincodes, ~98s, 0 errors, residential + datacenter IP both OK).

## The trick
Blinkit picks a dark store from your delivery location, stored in `localStorage.location`. There is **no login needed** — override the location, search, scrape.

## Procedure (per pincode)
1. `goto https://blinkit.com/` (domcontentloaded), wait ~2.5s for hydration.
2. Inject location via `page.evaluate`:
   ```js
   localStorage.setItem('location', JSON.stringify({
     coords: { isDefault:false, lat, lon, locality, id:1, isTopCity:true, cityName, landmark, addressId:null }
   }));
   ```
3. `goto https://blinkit.com/s/?q=jivo` (domcontentloaded), wait ~4.5s for cards to hydrate.
4. Read the dark store: `JSON.parse(localStorage.getItem('merchant'))` → `id`, `name`.
5. Extract product cards: every `div` whose innerText contains `jivo` + `₹`, sized like a card (w 100–420, h 180–620), dedup by text prefix.
6. Parse each card text: `NN% OFF` (discount), `NN MINS` (eta), product name, pack (`1 l`/`5 l`/`500 ml`), `₹sale` `₹mrp`, ADD vs "Out of Stock".
7. Filter `name` matches `/jivo/i`. Dedup on `(store_id, canonical)` where canonical = name+pack-size.

## Tuning / quirks
- Concurrency 4 contexts is safe. 2–3s jitter between pincodes.
- Block images/fonts/media for speed (`context.route`).
- Some pincodes resolve to a **nearest** dark store (e.g. a Delhi-edge pincode → a Gurgaon store, or an unserved pincode → a fallback store). Trust `merchant.name`, not the requested pincode, for which store the data is from.
- ~28/40 pincodes carry Jivo; the other 12 genuinely have zero Jivo stock (real distribution-gap intel, not a bug). Hyderabad / Chennai / Ahmedabad = currently zero Jivo on Blinkit.

## Output shape (keep this for build_excel.py to work)
Each row: `{city, pincode, locality, store_id, store_name, sku_raw, canonical, pack, vol_ml, sale, mrp, discount_pct, per_litre, eta_min, in_stock}`. Written to `result.json` as `{summary, perPin, allRows}`.

## When to adapt for a new platform
Copy this whole folder, then change: the base URL, the location-setting mechanism (Zepto/Amazon-Now store location differently), and the card selectors. Keep the output row shape identical.
