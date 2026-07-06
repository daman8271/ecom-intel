# SKILL: scrape Blinkit (PROVEN)

How the Blinkit scraper works. Status: **working** (332 store-coords, residential + datacenter IP both OK).

## 2026-06-05 fix — default-store contamination (0537fbf)
The scrape is now **gated on VERIFIED store re-resolution**: the active store (read from
`localStorage.merchant`) must be a real *local* store near the requested coords. If it
hasn't re-resolved off the Gurgaon default (`isDefault=true`, or still store id 31719
`Super Store - Gurgaon Nirvana Country` while the request is NOT in the ~55 km NCR box),
the pincode is treated as unresolved and we **record 0 rows — never the Gurgaon default
catalogue mislabeled under a foreign city** (the 2026-06-04 contamination: 89/146 pincodes
were serving Gurgaon data under the wrong city). The scraper retries the
inject→navigate→poll loop up to 4× and polls the merchant up to 6× per attempt before
giving up to 0 rows.
- **Cost:** this patience is why a full run now takes **~69 min** (vs the old ~10 min — the
  old speed was the bug: it skipped this check). Worth it for clean data.
- **CONCURRENCY default 2** — at **≥3** from the datacenter IP many pincodes never
  re-resolve off the default and get (correctly) dropped, tanking coverage.
- **Known gap:** **~40% of pincodes have bad coordinates** that never re-resolve → recorded
  as 0 rows. This is a **geocoding follow-up** (fix the coords), NOT a scraper bug.

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
- **Concurrency default 2** (env `CONCURRENCY`); **≥3 loses store re-resolution** on the DC IP (see the 2026-06-05 fix above). 2–3s jitter between pincodes.
- Block images/fonts/media for speed (`context.route`).
- Some pincodes resolve to a **nearest** dark store (e.g. a Delhi-edge pincode → a Gurgaon store, or an unserved pincode → a fallback store). Trust `merchant.name`, not the requested pincode, for which store the data is from.
- ~28/40 pincodes carry Jivo; the other 12 genuinely have zero Jivo stock (real distribution-gap intel, not a bug). Hyderabad / Chennai / Ahmedabad = currently zero Jivo on Blinkit.

## Output shape (keep this for build_excel.py to work)
Each row: `{city, pincode, locality, store_id, store_name, sku_raw, canonical, pack, vol_ml, sale, mrp, discount_pct, per_litre, eta_min, in_stock}`. Written to `result.json` as `{summary, perPin, allRows}`.

## When to adapt for a new platform
Copy this whole folder, then change: the base URL, the location-setting mechanism (Zepto/Amazon-Now store location differently), and the card selectors. Keep the output row shape identical.
