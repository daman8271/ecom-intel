# SKILL: scrape Flipkart Minutes — STATUS: WORKING (datacenter IP)

Flipkart Minutes (10-min quick-commerce) is **scrapable from the VPS datacenter
IP** — HTTP 200, no captcha, **no login needed**. First clean run (2026-05-21):
**30/40 pincodes serviceable, 26 carry Jivo, ~72 rows, 10 unique Jivo SKUs, ~3 min.**

## The trick
Minutes products live in the **`HYPERLOCAL` marketplace** on `flipkart.com`. You
must first resolve a serviceable delivery location, then search:
`https://www.flipkart.com/search?q=jivo&marketplace=HYPERLOCAL`.

Location is **NOT** settable by writing `localStorage.mypin` — that bounces to
`/hyperlocal-preview-page`. You must trigger the real serviceability resolution:

1. Create the context with the pincode's GPS coords:
   `newContext({ geolocation: {latitude, longitude}, permissions: ['geolocation'] })`.
2. `goto /flipkart-minutes-store?marketplace=HYPERLOCAL`.
3. Click the **"Use my current location"** button → Flipkart geocodes the GPS
   coords to a dark store and serves the Minutes catalog. (`mypin` gets set as a
   side effect.) Poll until the "Select delivery address" picker disappears
   (~up to 14s). ~10/40 pincodes don't resolve in time → `serviceable=false`.
4. `goto /search?q=jivo&marketplace=HYPERLOCAL`, wait ~5s, scroll once.

## Card parsing (line-based — IMPORTANT)
A single product card is a ~**300×424** element. Use **tight geometry bounds
(w 150–380, h 300–560)** so you grab one card, not a multi-product row wrapper
(a wrapper mixes prices/ETA across SKUs and produces garbage — that was the
first-run bug). Split each card's innerText into lines:

```
[AD] [NN%] [Off] [N L] <JIVO product name> ₹MRP ₹SALE Add        (in stock)
Currently unavailable [N L] <JIVO product name> ₹PRICE           (OOS)
```

- **pack**: the line matching `^\d[\d.]*\s*(ml|l|kg|g)$`.
- **name**: the line containing `jivo` (strip `(Pack of N)`).
- **prices**: lines starting with `₹`. Flipkart lists **MRP first (struck),
  SALE second** → `sale = min(prices)`, `mrp = max(prices)`.
- **in_stock = 0** if any line matches `currently unavailable|out of stock|sold out|notify me`.
- eta is store-level (shown once, e.g. "10 min"), not per-product → `eta_min = null`;
  the store ETA is captured in `store_name`.

## Output shape
Identical to Blinkit so `build_excel.py` works unchanged. `build_excel.py` is
platform-aware (derives "Flipkart Minutes" from the folder name).

## Quirks / tuning
- Jivo present in Gurgaon, Delhi, Kanpur, Patna, Mysuru… **absent at Bandra/Mumbai**.
- Per-run yield varies (~70–110 rows) with how many pincodes resolve their GPS
  location. Comfortably above the healthcheck's 20-row floor. To raise yield,
  increase the post-search wait or retry the location click.
- Live in `setup_cron.sh` + `healthcheck.sh` PLATFORMS lists.
