# SKILL: scrape Amazon Now — STATUS: LIVE (2026-05-30, via transplanted session)

The 2026-05-22 "NOT FEASIBLE" verdict (kept in **BLOCKED.md**) is **obsolete**. Amazon
Now IS scrapable. Key correction to the old verdict: `/dp` was the wrong surface — even
logged-in it shows only the multi-day marketplace promise. The right surface is the
**`i=nowstore` storefront search**, which is login-gated (503s logged-out) but, logged-in,
returns per-SKU **Now price + same-day delivery SLOT** that varies per delivery pincode.

## The mechanism (what `scrape.js` does)
1. **Auth = a transplanted logged-in session.** The VPS datacenter IP CANNOT log in:
   Amazon's `/ap/signin` serves the AWS WAF "AAMation" grid captcha (`/ap/cvf/request`)
   which **rejects even correct solves** from a flagged DC IP (proven — see PLAN.md). So
   the user logs into amazon.in on their **own clean IP**, exports cookies with the
   **Cookie-Editor** browser extension, and we import them:
   `node import_cookies.js <cookie-editor-export.json>` → `secrets/amazon-now.storageState.json`.
   The session works from the VPS for *browsing* (WAF only guards the login path).
   Auth cookies (`session-token`, `at-acbin`) last ~1 yr but Amazon may rotate sooner.
2. **Per-pincode** = set the delivery pincode via the **GLOW** widget
   (`#nav-global-location-popover-link` → `#GLUXZipUpdateInput`). No need to seed saved
   addresses — a bare pincode set is enough; the nowstore search then reflects it.
   Metros return ~24 results w/ Now slots; non-metros return 0 = Now not serviceable.
3. **Search** `amazon.in/s?k=jivo&i=nowstore`, parse the result cards:
   - full title in **`[data-cy="title-recipe"]`** (h2 alone is just the brand "JIVO" →
     would collapse every SKU to one canonical — DO NOT use h2 for the name);
   - sale = `.a-price[data-a-color="base"] .a-offscreen`; **MRP = `[data-a-strike="true"]
     .a-offscreen` ONLY** (the bare `.a-text-price` also matches the per-unit "₹/L" price);
   - slot = `[class*="delivery"]` ("FREE delivery Today 5–7 pm").
4. Keep only genuine Jivo cards (`\bjivo\b`), dedupe by canonical, cross-ref `products.json`
   by ASIN for category. Output schema matches Blinkit/Zepto (+ `asin`, `now_slot`,
   `serviceable`) so build_excel/predict/review/vault work.

## Run
```
node scrape.js                 # full pincodes.json (332), sequential (CONCURRENCY=1, safe:
                               #   one shared account → server-side location could collide)
LIMIT=8 node scrape.js         # smoke test
PINCODES_FILE=… OUT_FILE=… node scrape.js
```
`scrape.js` does a **session preflight** (checks "Hello, <name>") and exits **3** +
writes `secrets/SESSION_EXPIRED` if the cookie died — so it fails loud instead of
sweeping logged-out garbage. **Recovery: ask the user (Telegram) to re-export cookies,
re-run `import_cookies.js`.** The VPS can never re-login itself.

## Files
- `scrape.js` (live), `build_excel.py` (+ Now Serviceability sheet), `import_cookies.js`,
  `verify_session.js` (session healthcheck), `probe_now.js` / `probe_pincode_switch.js`
  (recon, keepable), `login_v2.js` (the failed DC-IP captcha solver — reference only).
- `secrets/` (gitignored): `amazon-now.storageState.json` (the live session, chmod 600).
- **Amazon Fresh** = the same surface (`/fresh` → `/alm?almBrandId=ctnow`), covered by this
  same Now scrape; no separate platform dir.
