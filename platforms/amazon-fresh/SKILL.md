# SKILL: scrape Amazon Fresh — STATUS: LIVE (2026-05-30, no proxy)

## 2026-06-05 fix — additive-combo volume + ASIN-stable canonical (4cde57f)
Two fixes: (1) the **additive-combo volume parse** is completed — `comboVolMl()` sums the
components of a bundle whose volume token lives in the title (e.g. `"5 L with 5 L"` → 10000 ml,
`"5+1 LTR"` → 6000 ml) and is tried *before* the single-pack `parseVolMl`, so Rs/L is no
longer ~doubled on combos. (2) **ASIN-stable canonical** — after scraping, each ASIN's
canonical is locked to its most-frequent (voted) value across all rows, so the same product
canonicalizes identically everywhere (fixes split/duplicate identities for one ASIN).

Amazon **Fresh** = the `i=freshstore` storefront search on amazon.in. Recon (2026-05-30)
proved it is a **separate, ~7× richer index than Amazon Now**: ~40–49 Jivo SKUs/city
(incl. the 5L bulk packs Now never lists) vs Now's 0–14. `i=freshstore`, `i=amazonfresh`,
and `almBrandId=ctnow` are three URL paths into the SAME Fresh catalog — we use `freshstore`.

## How it works (identical mechanism to amazon-now)
- **Same logged-in account.** `secrets/amazon-fresh.storageState.json` is a **symlink** to
  `../amazon-now/secrets/amazon-now.storageState.json` — it's ONE Amazon account. The VPS
  datacenter IP cannot pass Amazon's signin WAF captcha, so cookies are exported by the user
  on a clean IP (Cookie-Editor) and imported via `../amazon-now/import_cookies.js`. Session
  cookies are valid ~1 year (to May 2027).
- **Per pincode (~2.5–4s, no page render):** raw POST `/portal-migration/hz/glow/address-change`
  to set the delivery location, then GET `/s?k=jivo&i=freshstore` as raw HTML, parse the
  `s-search-result` cards, filter to Jivo, dedupe by canonical. The POST needs an
  `anti-csrftoken-a2z` token, minted once by driving the GLOW widget and reused (auto re-minted
  if the resolved location stops matching the target pincode).
- Prices parsed from the search cards (`.a-price .a-offscreen` + strike MRP). Output schema
  matches Blinkit/Zepto (+ `asin`, `now_slot`, `serviceable`); `store_name='Amazon Fresh'`.

## ⚠️ SEQUENTIAL is mandatory — DO NOT parallelize, and DO NOT co-run with amazon-now
Amazon's delivery location is **account-global server-side**, NOT cookie-scoped. Proven by
`../amazon-now/par_safety_test.js`: 3 isolated browser contexts on the same session each set a
different pincode concurrently and ALL collapsed to the last one. So:
- The sweep is a single sequential loop (~15 min for 332, like Blinkit). This IS the fast path;
  the Flipkart-Minutes "10 parallel contexts" trick is impossible here (FK passed location in
  each request body; Amazon stores it per-account).
- **amazon-now and amazon-fresh must NEVER run at the same time** — they'd stomp each other's
  account location. **As of 2026-06-05 the cron sweep is SERIAL (one platform at a time), so
  both are in cron and the serial loop guarantees they never overlap** — the Amazon trio
  (`amazon`, `amazon-fresh`, `amazon-now`) runs consecutively. (Note: the two now run on
  SEPARATE Amazon accounts; the per-platform `.${P}.lock` is still kept so a platform can't
  overlap its OWN previous run.)

## Run
```
node scrape.js                 # full pincodes.json (332)
LIMIT=8 node scrape.js         # smoke test
INDEX=amazonfresh node scrape.js   # alternate Fresh path (same catalog)
PINCODES_FILE=… OUT_FILE=… node scrape.js
```

## Session expiry
If cookies die, scrape.js exits code 3 and writes `secrets/SESSION_EXPIRED`. The VPS cannot
re-login (captcha wall). Recovery = user re-exports cookies on a clean IP and re-runs
`../amazon-now/import_cookies.js`. Cron should Telegram-alert on SESSION_EXPIRED.

## First full run (2026-05-30)
Smoke (8 Bengaluru pincodes): 8/8 serviceable, 93 rows, 16 unique Jivo SKUs, ~35s, 0 mismatch —
all 5L bulk SKUs present (Now showed ~0 Jivo in Bengaluru). Full 332 numbers: see result.json.
