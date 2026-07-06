# ecom-intel — platform coverage report

**Last updated:** 2026-07-07 · **Run from:** Hostinger VPS + Mac Pro residential collectors · **Brand:** Jivo

This is the operating coverage map across all target platforms, plus where Jivo
actually has presence. Generated Excel reports for every live platform are in
`output/`; BigBasket pincode-wise workbooks are intentionally kept in
`output/private-no-group/` for direct-only delivery.

## TL;DR (2026-07-06)
- **9 platforms are LIVE** in the daily system: Blinkit, , Zepto,
  Flipkart Minutes, Flipkart, Amazon, **Amazon Fresh**, **Amazon Now**, **BigBasket**.
- **Blinkit is Mac/drop-fed and auth-required.** It runs on the Mac Pro residential
  session via `/Users/danny./VPS-Migration/scripts/run_blinkit_mac_to_vps.sh`
  under LaunchAgent `com.danny.blinkit-mac-to-vps` at **06:30 IST**. The wrapper
  uses `/Users/danny./VPS-Migration/secrets/blinkit-auth-state.json`, exports
  `BLINKIT_REQUIRE_AUTH=1`, `BLINKIT_OOS_PROBE=1`, and
  `BLINKIT_PDP_OOS_PROBE=1`, and `BLINKIT_PDP_PRICE_PROBE=1`. VPS ingest rejects
  unauthenticated/unverified-auth drops by default with
  `BLINKIT_REQUIRE_AUTH_DROP=1`, and the quality monitor rejects drops missing PDP
  price-probe metadata.
- **VPS emergency/manual Blinkit auth state** lives at
  `/opt/ecom-intel/secrets/blinkit-auth-state.json`. Do not publish or accept
  anonymous Blinkit stock data; `summary.auth_session`, `summary.auth_required`,
  `summary.auth_verified`, and `summary.auth_verified_pincodes == pincodes_total`
  must be present/truthy for auth-required production drops.
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
- **BigBasket** now has two live outputs. The national workbook still comes from the
  stealth browser + in-page `listing-svc` flow. The pincode-wise workbook is produced
  by `platforms/bigbasket/team_run_pincode.sh` across VPS + Mac Pro + KVM1 with
  logged-in member cookies; the 2026-07-06 cleaned run covered 227 pins, 155 pins
  with Jivo, 1,903 rows, and 27 SKUs. Pincode delivery is private/direct-only, not
  an Ecom group attachment.
- VPS-hosted scrapers run in a **1×/day serial deadline-aligned cron landing
  10:00 IST** via `run_all.sh`; Mac collectors feed vetted outputs into the same
  batch/ingest path.

## Working platforms (current cron)

| Platform | Type | Coverage | Jivo SKUs | Notes |
|---|---|---|---|---|
| **Blinkit** | quick-comm | 2026-07-06 auth-corrected daily: 902 pins, 870 resolved, 468 Jivo pins, 1915 rows, 0 blocked, 303 stores | ~8 | Mac Pro residential collector; saved Blinkit login/auth cookie state required; no anonymous fallback |
| **** | quick-comm | 332 pincodes | ~8 | stealth POST to `/api//search/v2` |
| **Zepto** | quick-comm | 332 pincodes (≈100 carry Jivo) | ~11 | reached via `bff-gateway.zeptonow.com` BFF API |
| **Flipkart Minutes** | quick-comm | 345 pincodes | ~10 | HYPERLOCAL store; GPS "use my location" |
| **Flipkart** | marketplace | national | ~61 | national pricing; 1 row per SKU |
| **Amazon** | marketplace | national (314 ASINs targeted) | ~163 in-stock | guest `/dp` scrape; interstitial bypass; no account location |
| **Amazon Fresh** | quick-comm | 332/332 pincodes serviceable | ~63 | logged-in session (cookie transplant); `i=freshstore` raw POST+HTML; ~13.2k rows/run, ~22 min |
| **Amazon Now** | quick-comm | ~317/332 pincodes serviceable | ~23 | logged-in (same session as Fresh); `i=nowstore`; per-pincode `now_slot` delivery windows; ~1.7k rows/run; SERIALIZED with Fresh via shared lock |
| **BigBasket** | grocery national + pincode-wise | national workbook + pincode team run: 227 pins, 155 Jivo pins in 2026-07-06 cleaned run | ~27 | stealth browser past Akamai + in-page `listing-svc`; pincode runner uses logged-in member cookies on VPS+Mac Pro+KVM1 and writes private/direct-only workbook |

## Per-pincode coverage (Wave 1, auth-corrected 2026-07-06)

True per-pincode ground truth across the **25 target cities (1,885 distinct pincodes)**, replacing
anchor extrapolation. Honest status per `(platform,pincode)` in `data/coverage/ledger.csv`
(`price_captured | serviceable_no_jivo | not_serviceable | error`). Blinkit values
below are superseded by the authenticated 2026-07-06 corrected daily run.

| Platform | Serviceable (of 1,885) | Jivo on sale | Notes |
|---|--:|--:|---|
| **Amazon Fresh** | **973** | **881** | widest network; richest catalog (39 SKUs). 92-pincode gap (Nagpur 27, TVM 19). Only Nashik dark. |
| **Blinkit** | **902 configured** / **870 resolved** | **468** | auth-corrected daily run; 1915 rows, 0 blocked, 303 stores. Saved login/auth state required. |
| **Zepto** | **693** | 693 | Jivo everywhere it serves; ⚠ only 33% in-stock (2/3 OOS). 0 in Vizag/Bhubaneswar/TVM. |
| **Flipkart-minutes** | **340** | 340 | metro-led; reaches Vizag (4) where Zepto is 0. Cookies expire ~daily → browser fallback. |
| **Amazon Now** | **132** | 132 | narrowest; 88% just Bengaluru+Chennai. 0 in 19 cities — metro express lane only. |
| **Combined (any platform)** | **1,173 / 1,885 (62%)** | **1,071 (57%)** | was 234 (12%) on the old anchor model — ~5× real coverage. |

- **Daily cron runs `COVERAGE_DAILY=1`** (flipped 2026-06-30) → QC scrapes
  serviceable/Jivo-priced daily configs, not anchors. Blinkit is off-box and
  auth-required: 902 configured pins, 870 resolved, 468 Jivo-priced pins in the
  2026-07-06 corrected run. VPS-run Zepto/FKM use zepto 693 / fkm 340. Weekly
  full census refreshes the set.
- **Amazon Wave 2 COMPLETE** — amazon-fresh (acct 259, 973) + amazon-now (acct 520, 132), **separate accounts, never summed/co-scraped**; full per-pincode via `tools/coverage/amazon_chunked.sh` → `amazon_merge.py` → `amazon_ledger.py`. Live HTML: `darkstore-dashboard.vercel.app` (5-platform).

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
- **Cron (IST):** `run_all.sh` scrapes VPS-hosted platforms **serially** as one
  **deadline-aligned sweep landing 10:00**, then runs the self-heal sweep at the
  end of the sweep (flags any platform <20 rows / stale and re-runs once /
  escalates to Telegram). `amazon-now` runs too, serialized with `amazon-fresh`
  via the shared lock (see above). Blinkit is not anonymous and not part of the
  VPS serial scrape: the Mac Pro LaunchAgent `com.danny.blinkit-mac-to-vps` runs
  `/Users/danny./VPS-Migration/scripts/run_blinkit_mac_to_vps.sh` at 06:30 IST,
  using `/Users/danny./VPS-Migration/secrets/blinkit-auth-state.json` and
  `BLINKIT_REQUIRE_AUTH=1`, `BLINKIT_OOS_PROBE=1`, and
  `BLINKIT_PDP_OOS_PROBE=1`, plus `BLINKIT_PDP_PRICE_PROBE=1` for screenshot-class
  stale-price canaries. VPS ingest uses `BLINKIT_REQUIRE_AUTH_DROP=1`. The workbook
  separates `Listed - Out of stock` from `Not listed`; a separate
  `Jivo-Blinkit-Not-Listed-Pincodes-YYYY-MM-DD.xlsx` is sent only to the configured
  direct WhatsApp contact after the main Blinkit workbook passes quality. Ingest
  sends it immediately and the 10:00 mailer retries only if the per-date sent
  marker is absent.
  Blinkit availability is coordinate/dark-store based, not pincode-label based:
  the same header pincode can resolve to a different store from a nearby coordinate,
  so hard OOS rows require nearby and PDP verification before publishing.
- **BigBasket pincode cron (IST):** root crontab runs
  `platforms/bigbasket/team_run_pincode.sh run` at **03:00** in tmux. It shards the
  run across VPS + Mac Pro + KVM1, merges `result_pincode.json`, builds the pincode
  workbook under `output/private-no-group/`, removes any normal `output/` pincode
  copy, and direct-sends only via the configured direct-recipient secret.
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
| **Blinkit** | quick-comm | 28/40 pincodes carry Jivo | 8 | 126 | 98s | historical launch snapshot; current production is Mac/drop auth-required |
| **Flipkart Minutes** | quick-comm | 26/40 pincodes carry Jivo | 10 | 72 | ~3 min | HYPERLOCAL store; GPS "use my location" click |
| **Flipkart** | marketplace | national | 61 | 61 | 16s | national pricing; 1 row per SKU |
| **Amazon** | marketplace | national | 163 | 163 | 27s | richest catalog; needs interstitial bypass |

At launch, **Zepto** was HARD-BLOCKED (HTTP 403 from CloudFront on the datacenter IP)
and **Amazon Now** was deemed not feasible without login. Both have since been resolved
(Zepto via the BFF gateway 2026-05-29; the Amazon login via cookie transplant), which is
why they no longer appear under "blocked" above.
