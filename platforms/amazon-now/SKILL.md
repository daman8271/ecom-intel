# SKILL: scrape Amazon Now — STATUS: PARTIAL / not production-ready

See **BLOCKED.md** for the full evidence. Short version:

- amazon.in is reachable from the VPS IP **only after clicking the "Continue
  shopping" bot-interstitial** (homepage 202 → click → 200; raw `/s?k=` hits get
  503). This bypass also unlocks the **amazon marketplace** scraper (which works
  — see `platforms/amazon`).
- **Search works without login** and returns Jivo SKUs; `i=nowstore` scopes to
  the Amazon Now quick-commerce subset; `almBrandId=ctnow` is the Now storefront.
- **Blocker:** per-pincode delivery location. Amazon ignores GPS and defaults to
  "Mumbai 400017"; the GLOW pincode modal is too fragile headless to drive
  deterministically across 40 pincodes, and Amazon Now is only serviceable in a
  few metros.

## To make this work later
Use a **logged-in session (persisted storageState) with saved addresses** so
delivery-location switching is reliable. That requires an Amazon account + OTP
login — a separate decision (flagged in REPORT.md). Until then, not in cron.

`scrape.js` is the unmodified Blinkit copy (not adapted — a scraper built today
would be unreliable). Output shape stays Blinkit-compatible when adapted.
