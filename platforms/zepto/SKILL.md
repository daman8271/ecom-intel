# SKILL: scrape Zepto — STATUS: BLOCKED (datacenter IP)

Zepto sits behind **AWS CloudFront WAF**, which returns a hard `403` to this
datacenter VPS IP before any page JS runs. See `BLOCKED.md` for the evidence.
**This platform needs a residential proxy** to be scraped from here.

## The intended trick (once a proxy is in place)
Unlike Blinkit (localStorage `location` override), Zepto resolves its dark
store from the **browser GPS position**. So `scrape.js` feeds real coords per
pincode via Playwright:

```js
browser.newContext({
  geolocation: { latitude: rec.lat, longitude: rec.lon },
  permissions: ['geolocation'],
});
```

No login is expected for browsing/search (same as Blinkit).

## Procedure (per pincode) — UNVERIFIED beyond the 403
1. `goto https://www.zeptonow.com/` with GPS coords set on the context.
2. **403 guard:** if status 403 or body contains `403 ERROR`/`Request blocked`,
   throw `BLOCKED` (the IP is flagged). This is what currently happens here.
3. `goto https://www.zeptonow.com/search?query=jivo`, wait ~5s for hydration.
4. Read the resolved store id from localStorage (key name unconfirmed —
   tries `storeId` / `store_id` / `store`).
5. Extract cards with the portable geometry heuristic: `a`/`div` whose innerText
   has `jivo` + `₹`, card-sized (w 100–460, h 150–640), dedup by text prefix.
6. Parse `₹sale`/`₹mrp`, pack, eta, out-of-stock — same parser as Blinkit.

## Output shape
Identical to Blinkit (so `build_excel.py` works unchanged):
`{city, pincode, locality, store_id, store_name, sku_raw, canonical, pack,
vol_ml, sale, mrp, discount_pct, per_litre, eta_min, in_stock}`.

## When unblocked
Add a residential proxy to `chromium.launch({ proxy: {...} })`, run
`./run.sh zepto`, and verify the card selectors against the real DOM (the
geometry heuristic is a starting point, not confirmed). If rows > 20, add
`zepto` to the PLATFORMS list in `setup_cron.sh` and `healthcheck.sh`.
