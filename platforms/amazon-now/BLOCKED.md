> **✅ STATUS 2026-05-31 — Amazon Now is LIVE in cron.** The doc below is a preserved
> *2026-05-22 snapshot* explaining why a per-ASIN "Now" signal can't be read off the guest
> `/dp` page (still true). It has since been superseded: the path that works is the
> logged-in **`i=nowstore` storefront search** on the same cookie-transplant session as
> Amazon Fresh. `scrape.js` is now that live scraper (NOT the Blinkit copy this doc
> describes), and amazon-now is wired into `run_all.sh` / `setup_cron.sh` / self-heal —
> serialized with Amazon Fresh behind a shared `.amazon-account.lock` so the two (one
> account, server-side location) never co-scrape. Login automation remains captcha-walled
> (AWS WAF "AAMation"), so the session is refreshed by a **manual cookie transplant** when
> it expires. Current strategy + the manual-refresh drill: `PLAN.md`.

# BLOCKED: Amazon Now — no reliable per-ASIN "Now" signal on the /dp page

**Date tested:** 2026-05-21 (storefront recon) + **2026-05-22** (per-ASIN /dp
delivery-signal spike, this run), from the Hostinger VPS (datacenter IP).
**Verdict:** **NOT FEASIBLE** to read a per-product "available on Amazon Now /
fast quick-commerce delivery" signal off the regular `amazon.in/dp/<asin>`
page (with or without setting a Now-serviceable metro pincode, without login).
The /dp page renders the **marketplace** offer only (multi-day ship promise);
it never surfaces a live Now delivery offer/ETA/price. Evidence below.

## 2026-05-22 spike — what we actually captured
Tools (kept in this folder): `spike.js` (wide delivery-block + AOD sweep),
`spike_nowstore.js` (Now storefront search vs marketplace search),
`spike_known.js` (/dp of ASINs CONFIRMED on the Now storefront). Raw dumps:
`spike.default.json`, `spike.pin400017.json`.

1. **The default location IS a Now metro.** GLOW resolves to "Mumbai 400017"
   out of the box, and explicitly re-setting 400017 via the GLOW widget
   succeeded ("Deliver to Mumbai 400017"). So a Now-serviceable location was
   confirmed in both runs — the signal's absence is not a location problem.

2. **The /dp delivery block IS populated now** (the prior probe's empty
   `deliveryBlock` was a stale/legacy selector). The correct selectors are
   `#mir-layout-DELIVERY_BLOCK` = `#deliveryBlockMessage` =
   `[data-csa-c-content-id="DEXUnifiedCXPDM"]`. For in-stock Jivo SKUs it reads
   e.g. **"FREE delivery Thursday, 28 May. Order within 2 hrs 17 mins. Details"**
   — a **named-day marketplace ship promise**. ("Order within 2 hrs 17 mins" is
   the *cutoff timer to qualify for that day*, NOT a 2-hour quick-commerce ETA.)

3. **No Now / fast / same-day promise anywhere on /dp.** Across the sample, at
   both the default and explicitly-set 400017: `amazon now`=false,
   `get it today`=false, `same-day`=false, `in N hours/min`=false, `tatkal`=false
   on every product. The only "fresh" hit is the generic top-nav **"Amazon Fresh"**
   flyout boilerplate (present on every page, even out-of-stock ones with no
   delivery block at all) — not a per-product offer.

4. **DECISIVE: even ASINs confirmed live on the Now storefront show no Now offer
   on /dp.** `i=nowstore` search for "jivo" returns 4 real Jivo SKUs that ARE in
   our products.json: `B09MJ6QDX7` (Canola 1L ₹248), `B093BMGPQC` (EVOO 1L ₹799),
   `B0DC6JR4F3` (So Olive 1L ₹249), `B0152TWWSQ` (Canola 1+1L ₹509). Loading each
   one's marketplace `/dp` page still shows only the multi-day promise
   ("FREE delivery Thursday, 28 May" / "Wednesday, 3 June"), `nowOffer=false`,
   no Now price, no Now ETA, no Now buy button. The marketplace /dp listing and
   the Now storefront listing are **separate fulfilment channels**; /dp does not
   cross-surface the Now offer without a Now-context (logged-in / app) session.

## The one weak signal that DOES exist (and why it's not enough)
On those 4 Now-listed ASINs, /dp carries a **seller-profile link**
`/sp?...&seller=A3DRET2ZTE1T2S&almBrandId=ctnow` — i.e. the buy-box seller is the
**Amazon-Now-brand seller** (`almBrandId=ctnow`, seller id `A3DRET2ZTE1T2S`).
This link is **discriminating**: marketplace-only Jivo ASINs (sold by "RK World
Infocom", "Jivo Mart", etc.) have **zero** `ctnow` links. So it is a usable
*proxy* for "this ASIN is a Now-storefront listing." BUT it is a **seller-identity
proxy, not a delivery signal**: it gives no Now ETA, no Now price, no per-pincode
Now serviceability, and the price/delivery shown is still the marketplace
multi-day offer. Shipping a field called `amazon_now_available` off this would be
misleading — it answers "is the listing sold by the Now-brand seller", not
"can I get this on Now today at pincode X". Per the project rule (never ship a
fragile/misleading scraper), we did NOT build it.

## What the user's "option to see if it's on Now" actually is
It's the **`i=nowstore` storefront search** (a separate listing channel /
storefront), not a per-/dp-page badge. Scraping that = the original blocked
per-pincode Now-storefront path (fragile GLOW location control + only a few
metro-serviceable pincodes + a tiny ~4-SKU Jivo catalogue), which the steer told
us to avoid. There is no clean per-ASIN Now delivery promise on /dp.

## Recommended path to unblock (unchanged, still a "bigger decision")
A **logged-in Amazon session (persisted storageState) with saved addresses** — or
the **Amazon app/API Now context** — is required for the /dp page (or a Now
storefront) to resolve and display a live Now offer/ETA per location. That needs
an Amazon account + one-time OTP login. Until that decision is made, Amazon Now
stays out of cron.

## State of the code in this folder
- `scrape.js` is still the unmodified Blinkit copy — **NOT adapted**, because no
  reliable per-ASIN Now signal exists to scrape off /dp today.
- Recon artifacts left for the record: `spike.js`, `spike_nowstore.js`,
  `spike_known.js`, `spike.default.json`, `spike.pin400017.json`,
  `investigate*.js`, `investigate.dp.json`.
- NOT added to `setup_cron.sh` / `run_all.sh` / `healthcheck.sh`.
