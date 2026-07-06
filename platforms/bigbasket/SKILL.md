# SKILL: scrape BigBasket — STATUS: WORKING (pincode team runner, stealth, LOGGED-IN member)

## Current production path — 2026-07-06

BigBasket pincode production is now **per-pincode and logged-in**, not the old
single national scrape. The canonical runner is:

```bash
cd /opt/ecom-intel/platforms/bigbasket
./team_run_pincode.sh run
```

`team_run_pincode.sh` shards `pincodes_jivo.json` across the VPS, Mac Pro, and
KVM1 with default weights `5:4:1`. Each worker runs `scrape_pincode_browser.js`
inside `tmux`, using `secrets/bb_cookies.pincode.json` to stay in the logged-in
member session. The runner can be resumed with:

```bash
./team_run_pincode.sh launch <run-id>
./team_run_pincode.sh status <run-id>
./team_run_pincode.sh collect <run-id>
./team_run_pincode.sh merge <run-id>
./team_run_pincode.sh build <run-id>
```

Outputs:
- `result_pincode.json` is the current pincode ground-truth result.
- `Jivo-BigBasket-Pincode-Report-YYYY-MM-DD.xlsx` is copied only to
  `output/private-no-group/`.
- The normal `output/` pincode copy is removed so the Ecom group batch cannot pick
  it up.
- Direct WhatsApp delivery is explicit only: `BB_TEAM_DIRECT_JID` or the gitignored
  `secrets/bigbasket-direct-jid` file. There is no group fallback.

The older national `scrape.js` path still exists for the small national
`Jivo-Bigbasket-Live-Report-YYYY-MM-DD.xlsx` workbook. Use it as a national
catalogue diagnostic, not as the pincode truth source.

BigBasket's web storefront is scrapable from the VPS **only via a stealth browser**
— plain Chromium / curl / node-fetch get **HTTP 403** (Akamai Bot Manager). Full
recon: [`RECON.md`](RECON.md).

## LOGGED-IN MEMBER MODE — we capture MEMBER prices (added 2026-06-04)
The scraper now runs as a **logged-in BigBasket member** by injecting a
transplanted browser session (`secrets/bb_cookies.pincode.json` for pincode,
`secrets/bb_cookies.json` for the national diagnostic; both **gitignored** — live
auth tokens, NEVER commit), so `prim_price.sp` is the **MEMBER price the logged-in
customer actually pays**, not the logged-out public price. `import_cookies.js`
converts the Cookie-Editor export to Playwright cookies; the browser scrapers inject
them with `ctx.addCookies(...)` and confirm the session from BB header/member APIs.

**The pincode runner deliberately changes location per pincode.** It posts the
requested address/serviceability context, then calls `listing-svc` from the page
context and records the requested pincode, resolved location, service area IDs, rows,
and serviceability failures. This gives genuine per-location availability and stock
status instead of one saved-address view.

**Expiry safety — never publish guest-as-member.** If the cookie file is present but
no logged-in member session can be established (token expired, or BB's edge rejects a
stale auth cookie so the homepage won't even load), `scrape.js` writes
`secrets/BB_SESSION_EXPIRED`, sets `summary.session_expired=true`, and emits **0 rows**
or a failed shard so the run is held/escalated — it does
**not** silently fall back to guest prices. The next successful member run clears the
marker. (If `bb_cookies.json` is absent entirely, it degrades to logged-out guest mode
and logs a warning — but cron always ships the cookie file, so that's an ops error.)

### Refreshing the login cookies (when the session expires)
You'll know it expired when bigbasket goes BROKEN with `BB_SESSION_EXPIRED` present /
a Telegram alert. To refresh:
1. On a normal browser (any clean IP), log in to bigbasket.com as the member account.
2. Export cookies with the **Cookie-Editor** extension (Export → JSON) for
   `bigbasket.com`.
3. Replace `platforms/bigbasket/secrets/bb_cookies.pincode.json` with that export
   for the pincode runner. If the national diagnostic also needs refresh, replace
   `platforms/bigbasket/secrets/bb_cookies.json` too. These files are gitignored —
   never commit them.
4. Validate: `cd platforms/bigbasket && node import_cookies.js secrets/bb_cookies.pincode.json` — it reports the
   critical cookies (`BBAUTHTOKEN, sessionid, _bb_cid, customer_hash`) and prints
   `looks LOGGED IN`. Then a smoke `./team_run_pincode.sh run <small-run-id>`
   should show `member=true` / `session_ok=true` in the shard summaries.

## The trick: stealth browser + in-page API fetch
1. `playwright-extra` + `puppeteer-extra-plugin-stealth` (Playwright's own
   Chromium binary) bypasses Akamai → homepage loads HTTP 200. Plain
   `chromium.launch` → 403. Same recipe as .
2. `goto https://www.bigbasket.com/` once — establishes the session cookies
   (`csurftoken`, `x-channel`, `_bb_cid/_bb_nhid/_bb_sa_ids`, Akamai `_abck`/`bm_sz`).
3. From the **page's own JS context** (`page.evaluate(fetch(...))` — inherits the
   real cookies + TLS fingerprint, so Akamai lets it through) call:
   ```
   GET /listing-svc/v2/products?type=ps&slug=<query>&page=<n>&bucket_id=32
   ```
   `bucket_id=32` is **mandatory** (omit → HTTP 400). External node/curl with the
   same cookies still gets 403 — the in-page fetch is required.
4. Parse `tabs[0].product_info.products[]`, keep `brand.name.trim() === "Jivo"`.

## Field map (per product `p`)
| Field | JSON path |
|---|---|
| sku id | `p.id` |
| name | `p.desc` |
| brand | `p.brand.name` (trim — has trailing space) |
| pack | `p.w` (`"5 L"`, `"200 ml"`) |
| volume (ml) | `p.magnitude` (+ `p.unit`; magnitude already in ml) |
| MRP | `p.pricing.discount.mrp` (string) |
| selling price | `p.pricing.discount.prim_price.sp` (string) |
| discount % | `p.pricing.discount.camp_detail.d_v` (fallback; we prefer mrp−sp) |
| per-unit price | `p.pricing.discount.prim_price.base_price` / `base_unit` |
| in stock | `p.availability.avail_status === '001'` and `!not_for_sale` |

## Run
```bash
cd platforms/bigbasket && ./team_run_pincode.sh run
```

For national catalogue diagnostics only:

```bash
cd platforms/bigbasket && node scrape.js       # writes result.json
```

Pincode production defaults to `BB_QUERIES="jivo"` because the broad query returns
the full Jivo catalogue and avoids duplicate query load. Override only for a
targeted debug run.

## Output shape (keep this — build_excel.py depends on it)
`result_pincode.json` and `result.json` both use `{summary, perPin, allRows}`.
Each row carries the canonical
fields (`city, pincode, locality, store_id, store_name, sku_raw, canonical, pack,
vol_ml, sale, mrp, discount_pct, per_litre, eta_min, in_stock`) plus rich
identity (`sku_id, brand, avail_status, base_price, category, absolute_url`) that
build_excel ignores but vault/history/review keep. In pincode production,
`summary.pincodes_total` is the configured pincode count and
`pincodes_with_jivo` is the number of attempted pincodes with at least one Jivo row.

## Jivo's BigBasket catalogue is multi-category (not just oils)
BB lists Jivo **edible/olive oils** AND a **beverages line** — wheatgrass juices,
flavoured fizzy water, Indian tonic water — all genuinely `brand="Jivo"` (verified;
URLs are `/pd/.../jivo-...`). These are **real Jivo products, not scraper
contamination**. (`tools/review.py`'s LLM gut-check was taught this so it no longer
false-flags them as off-brand.)

## Gotchas
- **Stealth is mandatory** — any non-stealth client gets 403 on this DC IP.
- **`bucket_id=32`** is required; if BB ships a new web build and it changes,
  capture the XHR from `https://www.bigbasket.com/ps/?q=jivo` to read the new value.
- **Strict brand filter** (`=== "jivo"`) avoids substring noise (Jivika, JIVOTTAM).
- **0 rows / 403 on homepage** → Akamai escalated against the DC IP → would need
  a residential proxy (see `docs/PROXY.md`); review.py will flag the run BROKEN.
- **`BB_SESSION_EXPIRED` marker present / run BROKEN** → the logged-in cookies
  expired → re-export them (see "Refreshing the login cookies" above). Until then the
  scraper refuses to publish (0 rows) rather than ship guest prices.
- **Zero-row pins are valid only when serviceability/location says so** — the merge
  keeps zero-row pins, serviceability failures, and resolved-location audit fields so
  coverage gaps are visible instead of silently dropped.
- **BB vs BB Now**: the storefront defaults to BB (scheduled); BB Now (express)
  shares the same catalogue + pricing for Jivo, so the listing API value is the same.

## Pincode mode is the production source
The pincode runner sets address/serviceability before listing calls and records the
requested pincode, resolved location, serviceability failures, and zero-row pins.
Even if many prices match nationally, the pincode sheet is the operational truth
for where Jivo is alive and in stock across cities.
