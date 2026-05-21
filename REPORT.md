# ecom-intel — platform coverage report

**Date:** 2026-05-21 · **Run from:** Hostinger VPS (datacenter IP) · **Brand:** Jivo

This is the "does the datacenter IP catch us" map across all 6 target platforms,
plus where Jivo actually has presence. Excel reports for the 4 live platforms are
in `output/`.

## TL;DR
- **4 of 6 platforms are LIVE** from this VPS IP, no proxy, no login:
  Blinkit, Flipkart Minutes, Flipkart, Amazon.
- **Zepto is hard-blocked** (CloudFront 403 on the datacenter IP) → needs a
  residential proxy.
- **Amazon Now** (quick-commerce) is reachable but **location/login-gated** →
  a separate decision (Amazon account + OTP).
- All 4 live scrapers are on **twice-daily cron (9am/7pm IST)** with the daily
  self-heal healthcheck.

## Working platforms (latest run)

| Platform | Type | Coverage | Jivo SKUs | Rows | Time | Notes |
|---|---|---|---|---|---|---|
| **Blinkit** | quick-comm | 28/40 pincodes carry Jivo | 8 | 126 | 98s | proven; localStorage location |
| **Flipkart Minutes** | quick-comm | 26/40 pincodes carry Jivo | 10 | 72 | ~3 min | HYPERLOCAL store; GPS "use my location" click |
| **Flipkart** | marketplace | national | 61 | 61 | 16s | national pricing; 1 row per SKU |
| **Amazon** | marketplace | national | 163 | 163 | 27s | richest catalog; needs interstitial bypass |

Notes on the two marketplaces: prices are **national** (same in every city), so
we scrape the catalog once and tag rows "All India" rather than looping 40
pincodes. That's why their Excel city-matrix is a single column by design — the
value there is **catalog breadth, price, MRP, discount %** (Amazon lists 163
Jivo SKUs vs only 8–10 on the quick-comm apps).

## Blocked / needs-proxy

### Zepto — HARD BLOCKED (needs residential proxy)
- Every request returns **HTTP 403 from CloudFront** ("Request blocked") before
  any page loads — both home and search, with both spoofed-macOS and real-Linux
  user agents. It is an **IP-reputation block on the datacenter IP**, not a
  fingerprint issue.
- **To unblock:** route Playwright through a **residential/mobile proxy with an
  Indian exit IP**. Code is staged (`platforms/zepto/scrape.js` has a 403 guard
  and GPS-based location); just add `proxy:{...}` and re-run. See
  `platforms/zepto/BLOCKED.md`.

## Needs login/OTP (a bigger decision)

### Amazon Now — quick-commerce, reachable but gated
- Good news: amazon.in itself is **not IP-blocked** (we pass the "Continue
  shopping" interstitial and search works with no login). The Amazon Now
  storefront exists on web (`marketplace=HYPERLOCAL` / `almBrandId=ctnow`,
  `i=nowstore`).
- Blocker: **per-pincode delivery location.** Amazon ignores GPS, defaults to
  "Mumbai 400017", and its pincode modal is too fragile headless to drive across
  40 pincodes. Amazon Now is also only serviceable in a few metros.
- **Decision needed:** to do this reliably we need a **logged-in Amazon account
  with saved addresses** (one-time **OTP login**, persisted session). That's the
  same capability that would also harden the main Amazon scraper. See
  `platforms/amazon-now/BLOCKED.md`.

## Where a residential proxy would help (priority order)
1. **Zepto** — only thing standing between us and a 3rd quick-comm platform.
2. **Amazon (insurance)** — currently works via the interstitial bypass, but
   Amazon may escalate to a captcha on a datacenter IP hit twice daily. A proxy
   is the fallback if `amazon` runs start returning 0 rows.

## Operational state
- Cron (IST): Blinkit, Flipkart Minutes, Flipkart, Amazon each at **09:00 & 19:00**;
  healthcheck at **09:30** (flags any platform <20 rows / stale and self-heals).
- `git` is the backup. After any VPS wipe: clone, `npm install` + `npx playwright
  install chromium` per platform, `./setup_cron.sh`.

## Suggested next steps
1. Get a residential proxy (Indian IPs) → unblock Zepto, harden Amazon.
2. Decide on an Amazon account for Amazon Now (OTP) if quick-comm Amazon matters.
3. Optional: raise Flipkart Minutes yield (currently ~70 rows) by retrying the
   location click on the ~10 pincodes that don't resolve in time.
