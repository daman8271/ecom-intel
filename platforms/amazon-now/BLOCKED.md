# BLOCKED (partial): Amazon Now — reachable but not production-ready

**Date tested:** 2026-05-21 from the Hostinger VPS (datacenter IP).
**Verdict:** Not a hard IP block, but **not reliably scrapable per-pincode** yet.
The blocker is **delivery-location control**, plus limited Now serviceability.
Recommend revisiting with a **logged-in session + saved addresses**.

## What we saw (the good)
- amazon.in is reachable from this datacenter IP **after passing a bot
  interstitial**: the homepage returns HTTP **202** with a "Continue shopping"
  button; clicking it yields the real site (200). Raw, un-clicked requests to
  `/s?k=...` get **503 "rush hour"** throttles. So: bot-gated but passable.
- **Search/browse works WITHOUT login** (no forced sign-in). `/s?k=jivo+oil`
  returns ~60 results, many real Jivo SKUs with prices.
- The Amazon Now / Fresh quick-commerce storefront exists on web:
  - `/now` and `/amazonnow` → `/l/8557209031`
  - `/fresh` → `/alm/storefront?almBrandId=ctnow`  (**ctnow = Amazon Now**)
  - `i=nowstore` search scope returns a Now-specific subset (~6 Jivo SKUs).

## What blocks a clean per-pincode scrape (the bad)
1. **Location ignores GPS.** Unlike Blinkit/Flipkart-Minutes, Playwright
   `geolocation` does nothing — Amazon resolves "Deliver to" from its own GLOW
   address widget, defaulting to **"Mumbai 400017"**.
2. **The GLOW pincode modal is fragile.** Driving `#nav-global-location-popover-link`
   → `#GLUXZipUpdateInput` → apply is inconsistent headless: after submitting a
   Bengaluru pincode (560034) the "Delivering to" label went blank and the
   `i=nowstore` search returned **0 Jivo** (location didn't cleanly switch /
   Now not serviceable there). Not deterministic enough for a 40-pincode loop.
3. **Limited serviceability.** Amazon Now quick-commerce runs in only a few
   metros, so most of our 40 pincodes won't be Now-serviceable anyway.

## Recommended path to unblock
- Use a **logged-in Amazon session** (persisted `storageState`) with **saved
  addresses** per target city — then switching delivery address is reliable and
  Now-serviceability resolves correctly. This needs an Amazon account + one-time
  OTP login → **a "bigger decision" to flag** (see REPORT.md).
- Always click the "Continue shopping" interstitial first (carried into the
  amazon marketplace scraper, which DOES work — see platforms/amazon).

## State of the code in this folder
- `scrape.js` is still the unmodified Blinkit copy (not adapted — would be a
  fragile, unreliable scraper today). Left as-is pending the logged-in approach.
- NOT added to `setup_cron.sh` / `healthcheck.sh`.
