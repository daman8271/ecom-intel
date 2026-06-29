# ecom-intel — platform coverage report

**Last updated:** 2026-05-31 · **Run from:** Hostinger VPS (datacenter IP) · **Brand:** Jivo

This is the "does the datacenter IP catch us" map across all target platforms,
plus where Jivo actually has presence. Generated Excel reports for every live
platform are in `output/`.

## TL;DR (2026-05-31)
- **9 platforms are LIVE** and running on cron: Blinkit, , Zepto,
  Flipkart Minutes, Flipkart, Amazon, **Amazon Fresh**, **Amazon Now**, **BigBasket**.
- **7 of the 9 run DIRECT** from this VPS IP with **no proxy and no login**:
  Blinkit, , Zepto, Flipkart Minutes, Flipkart, Amazon, BigBasket
  (BigBasket needs a stealth browser past Akamai, but no login and no proxy).
- **Amazon Fresh** went LIVE **2026-05-30** — it does need a **logged-in session**
  (cookies transplanted from a clean IP, see below), but no proxy. It is the
  `i=freshstore` storefront and is **~7× richer than Amazon Now** (~63 Jivo SKUs
  incl. the 5L bulk packs Now never lists; 332/332 pincodes serviceable, ~13.2k
  rows/run).
- **Zepto** was unblocked 2026-05-29 by bypassing the CloudFront-fronted website
  and calling its **`bff-gateway.zeptonow.com`** BFF API directly.
- **** was unblocked 2026-05-22 via stealth POST to its public search API.
- **Amazon Now** (quick-commerce) joined cron **2026-05-31**. It shares Amazon Fresh's
  single account + **server-side delivery location**, so the two must **never scrape
  concurrently** — `run.sh` serializes exactly this pair behind a shared
  `.amazon-account.lock` (one waits while the other runs; the guest `amazon` scraper sets
  no account location, so it is unaffected). Login is the same cookie transplant as Fresh;
  it's a thinner catalog than Fresh (~23 SKUs). See `platforms/amazon-now/PLAN.md`.
- **BigBasket** went LIVE **2026-05-31** — `www.bigbasket.com` is behind Akamai
  (plain HTTP → 403), so a **stealth browser** loads the session and an **in-page
  fetch** calls the `listing-svc` JSON API. BigBasket "BB" prices Jivo
  **nationally**, so (like Flipkart) it scrapes once and tags rows "All India"
  (~27 SKUs, no proxy, no login).
- All 9 live scrapers run on **3×/day parallel cron (09:00 / 12:00 / 16:00 IST)**
  via `run_all.sh`, with a self-heal sweep at the end of each window.

## Working platforms (current cron)

| Platform | Type | Coverage | Jivo SKUs | Notes |
|---|---|---|---|---|
| **Blinkit** | quick-comm | 161/332 stores · ~798 pincodes | ~8 | `localStorage` location override |
| **** | quick-comm | 332 pincodes | ~8 | stealth POST to `/api//search/v2` |
| **Zepto** | quick-comm | 332 pincodes (≈100 carry Jivo) | ~11 | reached via `bff-gateway.zeptonow.com` BFF API |
| **Flipkart Minutes** | quick-comm | 345 pincodes | ~10 | HYPERLOCAL store; GPS "use my location" |
| **Flipkart** | marketplace | national | ~61 | national pricing; 1 row per SKU |
| **Amazon** | marketplace | national (314 ASINs targeted) | ~163 in-stock | guest `/dp` scrape; interstitial bypass; no account location |
| **Amazon Fresh** | quick-comm | 332/332 pincodes serviceable | ~63 | logged-in session (cookie transplant); `i=freshstore` raw POST+HTML; ~13.2k rows/run, ~22 min |
| **Amazon Now** | quick-comm | ~317/332 pincodes serviceable | ~23 | logged-in (same session as Fresh); `i=nowstore`; per-pincode `now_slot` delivery windows; ~1.7k rows/run; SERIALIZED with Fresh via shared lock |
| **BigBasket** | grocery (national) | national (single "All India") | ~27 | stealth browser past Akamai + in-page `listing-svc` JSON API; national pricing → 1 row/SKU; no proxy, no login |

## Per-pincode coverage (Wave 1 — 2026-06-29)

True per-pincode ground truth across the **25 target cities (1,885 distinct pincodes)**, replacing
anchor extrapolation. Honest status per `(platform,pincode)` in `data/coverage/ledger.csv`
(`price_captured | serviceable_no_jivo | not_serviceable | error`). Full census 2026-06-29.

| Platform | Serviceable (of 1,885) | Jivo on sale | Notes |
|---|--:|--:|---|
| **Zepto** | **693** | 693 | up from ~214 anchors. 0 in Visakhapatnam / Bhubaneswar / Thiruvananthapuram (doesn't operate there). |
| **Blinkit** | **902** | **486** | delivers widely but Jivo only in 486 → **416-pincode delivers-but-no-Jivo gap**. |
| **Flipkart-minutes** | **340** | 340 | fast API once cookies re-imported. Reaches Vizag (4) where Zepto is 0. |
| **Combined (any QC)** | **935 / 1,885 (50%)** | **806 (43%)** | was 234 (12%) on the old anchor model the same morning. |

- **Daily cron now runs `COVERAGE_DAILY=1`** (flipped 2026-06-30) → QC scrapes the **Jivo-priced subsets** (blinkit 486 / zepto 693 / fkm 340), not anchors. Weekly full census refreshes the set.
- **Amazon = Wave 2** — amazon-fresh (acct 259) + amazon-now (acct 520), **separate accounts, never summed/co-scraped**; full per-pincode via `tools/coverage/amazon_chunked.sh` (per-city resilient), guarded from colliding with the daily cron. Live HTML: `darkstore-dashboard.vercel.app`.

## Amazon Fresh — how the logged-in scrape works (no proxy)
- **One Amazon account, cookies transplanted.** `secrets/amazon-fresh.storageState.json`
  is a **symlink** to `../amazon-now/secrets/amazon-now.storageState.json` — it is ONE
  account. The VPS datacenter IP cannot pass Amazon's signin WAF captcha, so the user
  exports cookies on a clean IP (Cookie-Editor) and imports them via
  `../amazon-now/import_cookies.js`. Session cookies are valid ~1 year (to ~May 2027).
- **Per pincode (~2.5–4s, no page render):** raw POST `/portal-migration/hz/glow/address-change`
  to set the delivery location, then GET `/s?k=jivo&i=freshstore` as raw HTML, parse the
  `s-search-result` cards, filter to Jivo, dedupe by canonical. The POST needs an
  `anti-csrftoken-a2z` token minted once from the GLOW widget and reused.
- Output schema matches Blinkit/Zepto (+ `asin`, `now_slot`, `serviceable`);
  `store_name='Amazon Fresh'`. Full recipe: `platforms/amazon-fresh/SKILL.md`.

## Amazon Now + Amazon Fresh — one account, serialized (both in cron)
- **Login works** (same cookie-transplant session as Amazon Fresh) — the old
  2026-05-22 "not feasible without login" verdict is superseded.
- **They share one Amazon account** and Amazon resolves delivery location
  **server-side per account**, so Amazon Now and Amazon Fresh cannot scrape at the same
  time without clobbering each other's location.
- **How both still run in cron (since 2026-05-31):** `run.sh` wraps the scrape step of
  *these two only* in a shared `.amazon-account.lock`; the parallel sweep launches both,
  but one blocks until the other finishes. Every other platform stays fully parallel, and
  the guest `amazon` scraper (no account location) is unaffected. If the shared session
  expires, both go BROKEN and self-heal alerts you to re-import cookies.
  See `platforms/amazon-now/PLAN.md`.

## Marketplaces vs quick-commerce (by design)
The two marketplaces (Flipkart, Amazon) price **nationally** — the same listing costs
the same everywhere — so we scrape the catalog **once** and tag rows "All India" rather
than looping pincodes. That's why their Excel city-matrix is a single column **by
design** — the value there is **catalog breadth, price, MRP, discount %** (Amazon lists
~163 in-stock Jivo SKUs vs 8–11 on the quick-comm apps).

## Where a residential proxy would help
**None needed today** — all 9 live platforms run without a proxy. `tools/proxy.js`
stays wired only as insurance if **Amazon** ever escalates from the interstitial bypass
to a captcha on the datacenter IP. See `docs/PROXY.md`.

## Operational state
- **Cron (IST):** `run_all.sh` scrapes all 9 live platforms **in parallel** at
  **09:00 / 12:00 / 16:00**, then runs the self-heal sweep at the end of each window
  (flags any platform <20 rows / stale and re-runs once / escalates to Telegram).
  `amazon-now` runs too, serialized with `amazon-fresh` via the shared lock (see above).
- **Amazon canonical auto-heal (LIVE 2026-06-13):** the recurring Amazon `shared_price_dup`
  hold — a *truncated* product title minting a duplicate "stub" SKU at the same ASIN/price — is
  now auto-fixed in `run.sh`: Claude merges each stub into its real product (identity-only,
  **never** prices) and re-reviews, so the report ships instead of being held. Fail-safe
  (Claude unreachable → stays held). See `tools/autoheal_amazon.py` + CLAUDE.md.
- `git` is the backup. After any VPS wipe: clone, `npm install` + `npx playwright
  install chromium` per platform, recreate `secrets.env` + re-import Amazon cookies,
  `./setup_cron.sh`.

---

## Historical snapshots (preserved)

### 2026-05-30 — Amazon Fresh proven, 6→7 live

Amazon Fresh recon proved `i=freshstore` is a separate, ~7× richer index than Amazon
Now (~40–49 Jivo SKUs/city incl. 5L bulk packs vs Now's 0–14), and was brought live on
the logged-in cookie-transplant session.

### 2026-05-21 — original launch snapshot

| Platform | Type | Coverage | Jivo SKUs | Rows | Time | Notes |
|---|---|---|---|---|---|---|
| **Blinkit** | quick-comm | 28/40 pincodes carry Jivo | 8 | 126 | 98s | proven; localStorage location |
| **Flipkart Minutes** | quick-comm | 26/40 pincodes carry Jivo | 10 | 72 | ~3 min | HYPERLOCAL store; GPS "use my location" click |
| **Flipkart** | marketplace | national | 61 | 61 | 16s | national pricing; 1 row per SKU |
| **Amazon** | marketplace | national | 163 | 163 | 27s | richest catalog; needs interstitial bypass |

At launch, **Zepto** was HARD-BLOCKED (HTTP 403 from CloudFront on the datacenter IP)
and **Amazon Now** was deemed not feasible without login. Both have since been resolved
(Zepto via the BFF gateway 2026-05-29; the Amazon login via cookie transplant), which is
why they no longer appear under "blocked" above.
