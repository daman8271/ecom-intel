# SKILL: scrape Blinkit (PROVEN)

How the Blinkit scraper works. Status: **working in production via the Mac Pro residential collector**, with a strict authenticated VPS+KVM1 shard fallback when the Mac is unavailable. An authenticated Blinkit session is required for stock correctness.

## 2026-06-05 fix — default-store contamination (0537fbf)
The scrape is now **gated on VERIFIED store re-resolution**: the active store (read from
`localStorage.merchant`) must be a real *local* store near the requested coords. If it
hasn't re-resolved off the Gurgaon default (`isDefault=true`, or still store id 31719
`Super Store - Gurgaon Nirvana Country` while the request is NOT in the ~55 km NCR box),
the pincode is treated as unresolved and we **record 0 rows — never the Gurgaon default
catalogue mislabeled under a foreign city** (the 2026-06-04 contamination: 89/146 pincodes
were serving Gurgaon data under the wrong city). The scraper retries the
inject→navigate→poll loop up to 4× and polls the merchant up to 6× per attempt before
giving up to 0 rows.
- **Cost:** this patience is why a full run now takes **~69 min** (vs the old ~10 min — the
  old speed was the bug: it skipped this check). Worth it for clean data.
- **CONCURRENCY default 2** — at **≥3** from the datacenter IP many pincodes never
  re-resolve off the default and get (correctly) dropped, tanking coverage.
- **Known gap:** **~40% of pincodes have bad coordinates** that never re-resolve → recorded
  as 0 rows. This is a **geocoding follow-up** (fix the coords), NOT a scraper bug.

## 2026-07-06 fix — authenticated availability is mandatory

Anonymous/headless Blinkit can show false Out of Stock while the logged-in web/app
session shows ADD for the same pincode/store/SKU. The confirmed regression row was
Delhi `110013`, Jivo Pomace Olive Oil 5 L, PRID `407561`: anonymous output marked
`No`, while the authenticated session showed live stock and the corrected run marked
it `Yes`.

Production must run fail-closed with:

```sh
BLINKIT_REQUIRE_AUTH=1
BLINKIT_AUTH_STATE_FILE=/path/to/blinkit-auth-state.json
```

Current auth state locations:

- Mac daily collector: `/Users/danny./VPS-Migration/secrets/blinkit-auth-state.json`
- VPS emergency/manual/fallback shards: `/opt/ecom-intel/secrets/blinkit-auth-state.json`

The scraper hydrates the Blinkit session before pincode work by setting
`localStorage.auth`, `localStorage.deviceId`, and cookies `gr_1_accessToken` /
`gr_1_deviceId`. If `BLINKIT_REQUIRE_AUTH=1` and no token is available, it exits `3`
before any scrape. The page must also hydrate accepted logged-in state
(`localStorage.user`/`authKey`) for every pincode. Summaries now include
`auth_session`, `auth_required`, `auth_verified`, and `auth_verified_pincodes`, and
`ingest.sh` defaults to `BLINKIT_REQUIRE_AUTH_DROP=1` so unauthenticated or
any-pincode unverified-auth Blinkit drops are rejected before build/delivery and old
false-OOS data cannot be delivered again.

## 2026-07-07 fix — not-listed and PDP price verification

Do not collapse listing absence into stock absence. Blinkit output now separates:

- `Listed - In stock`: product card/PDP exists and is available.
- `Listed - Out of stock`: product is listed, but PDP/search verification says no stock.
- `Not listed`: expected Jivo SKU/PRID is absent from the resolved pincode/store search.

`build_excel.py` writes both a `Listing Status` sheet and a `Not Listed Pincodes`
sheet in the main workbook, and also emits
`Jivo-Blinkit-Not-Listed-Pincodes-YYYY-MM-DD.xlsx`. The ingest path uses
`tools/whatsapp/send_blinkit_main_direct.sh` to direct-send the accepted main
workbook to the Ecom WhatsApp group after quality passes; it writes
`logs/blinkit-main-wa-YYYY-MM-DD.sent`, and batch/mail retry paths skip duplicate
WhatsApp group documents once that marker exists. The ingest path and mailer use
`tools/whatsapp/send_blinkit_not_listed_direct.sh` to direct-send that standalone
workbook to the configured WhatsApp contact only after the main Blinkit workbook
passes quality; the helper writes a per-date sent marker so retries do not
double-send. Cron runs the helper every 15 minutes from 06:00-12:59 IST as a
backstop for late or failed immediate sends. Cron also retries the main direct
sender over the same window.

Price correctness also has a PDP guard. Search cards can show a base/stale price
while the PDP shows a lower effective price such as `Buy at`, `Buy for`, `Effective
price`, or `Get it at`. Production runs keep `BLINKIT_PDP_PRICE_PROBE=1`, and the
quality monitor requires `summary.pdp_price_probe_enabled=1` and
`summary.pdp_price_probe_failed=0` by default. Screenshot canaries include
`110094:407561`, `110012:407851`, and `110012:406593`; the default probe
mode also verifies 5 L high-value/plain-search rows that have no offer/PDP evidence
so the stale-search-price class is not limited to the three canaries without turning
the full run into a PDP visit for every row. PDP price updates are accepted only
when the PDP-detected pack/volume before the first price matches the target row
volume; related/variant cards on the PDP must not overwrite a different pack size.
PDP matching must also tolerate localized Blinkit card suffixes such as
`(Canola Enne)` / `(Olive Enne)`: try the displayed title and the base English
title, but accept stock/price only when the PDP segment's pack volume matches the
row. This prevents Bengaluru rows from falling to `stock_unverified` while keeping
the wrong-pack guard intact.

An unverified search-card OOS is not a final `No`. If the nearby/PDP probes cannot
verify the row, the scraper marks it `stock_unverified`; workbook code renders it as
`Listed - Stock unverified`, and ingest/quality gates fail closed so it cannot be
delivered. Nearby same-pincode search probes and close Delhi neighbor-pincode probes
do the cross-coordinate false-OOS recovery; PDP OOS verification defaults to the
primary PDP only so the scraper does not open many PDP pages and trigger
access-denied responses. If a neighbor probe flips a row live, preserve that
neighbor store/coordinate as the stock evidence. Later PDP price probes must run
against the same proof location and update only price/PDP diagnostic fields, never
`in_stock`, `listing_status`, `stock_source`, `store_id`, or `store_name`.
If a targeted PDP price probe cannot resolve/parse, the row carries
`pdp_price_probe_attempted=1` and `pdp_price_probe_failed=1`; ingest and the quality
monitor fail closed unless `BLINKIT_MAX_PDP_PRICE_PROBE_FAILED` /
`BLINKIT_MONITOR_MAX_PDP_PRICE_PROBE_FAILED` is explicitly raised.

Checkpoint/resume files are keyed by IST date (`.progress.YYYY-MM-DD.json`), not UTC.
This matters for manual/early-morning IST starts: a July 7 run must not reuse a July 6
UTC-date cache and skip the fresh per-pincode auth/PDP checks.
Resume is acceptable only when the existing checkpoint was created by the current
authenticated/probed scraper and already passes the same quality expectations: no
`stock_unverified` rows, no stale canary prices, all pincodes auth-accepted, and no bad
coordinates. Move older or suspect checkpoints aside and restart cleanly.

`tools/cron/start_blinkit_live_watch.sh` starts an idempotent tmux watcher that
logs Mac process status, progress counts
(`done/resolved/auth_ok/blocked/rows/stock_unverified`), workbook presence, and
dry-run quality-monitor output until 10:45 IST. Cron starts the watcher at 05:00
IST and 06:25 IST, the read-only quality monitor polls every 15 minutes from 05:00-10:59 IST,
and the main/not-listed WhatsApp retry helpers poll every 15 minutes from
06:00-12:59 IST.

If the Mac Pro is unreachable during the store-open guard window,
`tools/cron/blinkit_batch_guard.sh` launches
`tools/cron/blinkit_vps_kvm_fallback.sh`. The fallback prepares KVM1 with the
current Blinkit scraper and auth state, runs authenticated shards across VPS+KVM1,
merges them on the VPS, and calls `platforms/blinkit/ingest.sh --deliver`. It does
not bypass any production gate: the merged result still must pass auth, store,
OOS/PDP, price, review, workbook, not-listed, batch, and WhatsApp checks.

## The trick
Blinkit picks a dark store from your authenticated delivery session and
`localStorage.location`. Hydrate auth first, override the delivery location, verify the
local store, then search and scrape.

## Procedure (per pincode)
0. Load the auth state (`BLINKIT_AUTH_STATE_FILE` or direct env token/device id). In
   production keep `BLINKIT_REQUIRE_AUTH=1`.
1. `goto https://blinkit.com/` (domcontentloaded), wait ~2.5s for hydration.
2. Inject auth + location via `page.evaluate`:
   ```js
   localStorage.setItem('auth', JSON.stringify({ accessToken }));
   localStorage.setItem('deviceId', deviceId);
   localStorage.setItem('location', JSON.stringify({
     coords: { isDefault:false, lat, lon, locality, id:1, isTopCity:true, cityName, landmark, addressId:null }
   }));
   ```
3. `goto https://blinkit.com/s/?q=jivo` (domcontentloaded), wait ~4.5s for cards to hydrate.
4. Read the dark store: `JSON.parse(localStorage.getItem('merchant'))` → `id`, `name`.
5. Extract product cards: every `div` whose innerText contains `jivo` + `₹`, sized like a card (w 100–420, h 180–620), dedup by text prefix.
6. Parse each card text: `NN% OFF` (discount), `NN MINS` (eta), product name, pack (`1 l`/`5 l`/`500 ml`), `₹sale` `₹mrp`, ADD vs "Out of Stock".
7. Filter `name` matches `/jivo/i`. Dedup on `(store_id, canonical)` where canonical = name+pack-size.

## Tuning / quirks
- **Concurrency default 2** (env `CONCURRENCY`); **≥3 loses store re-resolution** on the DC IP (see the 2026-06-05 fix above). 2–3s jitter between pincodes.
- Block images/fonts/media for speed (`context.route`).
- Some pincodes resolve to a **nearest** dark store (e.g. a Delhi-edge pincode → a Gurgaon store, or an unserved pincode → a fallback store). Trust `merchant.name`, not the requested pincode, for which store the data is from.
- ~28/40 pincodes carry Jivo; the other 12 genuinely have zero Jivo stock (real distribution-gap intel, not a bug). Hyderabad / Chennai / Ahmedabad = currently zero Jivo on Blinkit.

## Output shape (keep this for build_excel.py to work)
Each row: `{city, pincode, locality, store_id, store_name, sku_raw, canonical, pack, vol_ml, sale, mrp, discount_pct, per_litre, eta_min, in_stock}` plus probe metadata such as `listing_status`, `stock_source`, `price_source`, `base_sale`, `offer_sale`, `pdp_checked`, `pdp_price_checked`, `pdp_price_probe_attempted`, `pdp_price_probe_failed`, and `stock_unverified` when applicable. Written to `result.json` as `{summary, perPin, allRows}`. Blinkit `summary` must carry `auth_session: 1`, `auth_required: 1`, `auth_verified: 1`, `auth_verified_pincodes == pincodes_total`, `oos_probe_enabled: 1`, `pdp_oos_probe_enabled: 1`, `pdp_price_probe_enabled: 1`, and `pdp_price_probe_failed: 0` in production/auth-required runs.

## When to adapt for a new platform
Copy this whole folder, then change: the base URL, the location-setting mechanism (Zepto/Amazon-Now store location differently), and the card selectors. Keep the output row shape identical.
