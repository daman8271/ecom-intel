# SKILL: scrape Amazon Now — STATUS: NOT FEASIBLE off /dp (login-gated)

See **BLOCKED.md** for the full 2026-05-22 evidence. Short version:

- amazon.in is reachable from the VPS IP **only after clicking the "Continue
  shopping" bot-interstitial** (homepage 202 -> click -> 200; raw `/s?k=` hits
  get 503). This bypass (`passInterstitial()`) also unlocks the **amazon
  marketplace** scraper, which works — see `platforms/amazon`.

- **Tested (this run): can we read a per-ASIN "Amazon Now / fast delivery"
  signal off the regular `/dp/<asin>` page? NO.**
  - The default GLOW location is "Mumbai 400017" (a Now metro), and explicitly
    re-setting 400017 worked — so location is NOT the blocker here.
  - The /dp delivery block (`#mir-layout-DELIVERY_BLOCK` /
    `#deliveryBlockMessage` / `[data-csa-c-content-id="DEXUnifiedCXPDM"]`) only
    ever shows the **marketplace named-day ship promise** (e.g. "FREE delivery
    Thursday, 28 May. Order within 2 hrs 17 mins"). No Now / today / same-day /
    "in N min" promise on any product.
  - DECISIVE: the 4 Jivo ASINs that ARE live on the Now storefront
    (`i=nowstore`: B09MJ6QDX7, B093BMGPQC, B0DC6JR4F3, B0152TWWSQ) STILL show
    only the marketplace promise on their /dp page — `nowOffer=false`, no Now
    price/ETA. Marketplace /dp and the Now storefront are separate fulfilment
    listings; /dp won't surface the Now offer without a Now-context session.

- **Only weak signal on /dp:** Now-listed ASINs carry a buy-box seller link
  `/sp?...&seller=A3DRET2ZTE1T2S&almBrandId=ctnow` (the Amazon-Now-brand seller);
  marketplace-only ASINs have none. That's a **seller-identity proxy, not a
  delivery signal** (no ETA, no Now price, no per-pincode serviceability), so
  shipping it as `amazon_now_available` would be misleading. Not built.

## To make this work later
Use a **logged-in session (persisted storageState) with saved addresses**, or the
**Amazon app/Now-context**, so a live Now offer/ETA resolves per location. That
requires an Amazon account + OTP login — a separate decision (flagged in
REPORT.md). Until then, NOT in cron.

`scrape.js` is the unmodified Blinkit copy (intentionally NOT adapted). Recon
spikes kept in-folder: `spike.js` / `spike_nowstore.js` / `spike_known.js`
(+ `spike.*.json` dumps).
