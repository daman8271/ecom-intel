# SKILL: scrape BigBasket — STATUS: WORKING (datacenter IP, stealth, LOGGED-IN member)

## 2026-06-05 note (earlier fixes, in the serial cron sweep)
BigBasket runs **LOGGED-IN as a member** (cookie transplant) to capture **member prices**
(what a logged-in customer actually pays, not guest public prices — the "wrong SP" fix; see
"LOGGED-IN MEMBER MODE" below), and the parser **walks `children[]`** so sibling
**sub-packs** nested under a parent listing are captured (not just the top-level
`products[]`). It is now part of the **serial** `run_all.sh` cron sweep.

BigBasket's web storefront is scrapable from the VPS **only via a stealth
browser** — plain Chromium / curl / node-fetch get **HTTP 403** (Akamai Bot
Manager). Full recon: [`RECON.md`](RECON.md).

## Model: NATIONAL (like Flipkart, not hyperlocal)
BigBasket "BB" (scheduled delivery) prices Jivo **nationally** — the
`listing-svc` search API returns the same catalogue + prices regardless of the
session's city/hub. The old per-city location APIs are decommissioned (404) and
overriding the hub cookie doesn't change Jivo pricing. So we do **one scrape**
and tag every row `city="All India"`. We do **not** loop pincodes; `pincodes.json`
is intentionally a single national placeholder, kept only for shape-consistency.

This is the same model as the Flipkart **marketplace** scraper. Its value is
**catalogue breadth + price/MRP/discount** on a major grocery platform, not
per-city granularity (that's what Blinkit/Zepto/ provide).

## LOGGED-IN MEMBER MODE — we capture MEMBER prices (added 2026-06-04)
The scraper now runs as a **logged-in BigBasket member** by injecting a
transplanted browser session (`secrets/bb_cookies.json`, **gitignored** — live auth
tokens, NEVER commit), so `prim_price.sp` is the **MEMBER price the logged-in
customer actually pays**, not the logged-out public price. (Manager reported "wrong
SP": the report was showing guest prices; members see different — usually lower —
discounted prices.) `import_cookies.js` converts the Cookie-Editor export to
Playwright cookies; `scrape.js` injects them via `ctx.addCookies(...)` right after
`newContext`, then confirms the session with `/ui-svc/v1/header/` (`member_info.id`).
`result.json` `summary` carries `member`, `pricing_mode:"member"`, `member_id`,
`member_email`, `member_is_bbstar`.

**The member session is LOCALIZED, not national.** A logged-in session is bound to
the member's saved delivery address (this account = Delhi), so the listing-svc
returns what's **serviceable at that hub**: genuine per-location availability
(`avail_status "000"` / "Coming back soon" → real OOS) and a slightly smaller
catalogue (~23 vs the ~27 guest "All India" view — a few large 5L packs aren't
stocked at that hub). Rows are still tagged `city="All India"` for shape-consistency,
but the prices/stock reflect that member's location. This is the deliberate trade:
**accurate member prices + real stock** over a fictitious all-in-stock national list.
If broader coverage is needed later, use an account whose address sits on a hub that
stocks the full range.

**Expiry safety — never publish guest-as-member.** If the cookie file is present but
no logged-in member session can be established (token expired, or BB's edge rejects a
stale auth cookie so the homepage won't even load), `scrape.js` writes
`secrets/BB_SESSION_EXPIRED`, sets `summary.session_expired=true`, and emits **0 rows**
so `review.py` marks the run **BROKEN** and self-heal Telegram-escalates — it does
**not** silently fall back to guest prices. The next successful member run clears the
marker. (If `bb_cookies.json` is absent entirely, it degrades to logged-out guest mode
and logs a warning — but cron always ships the cookie file, so that's an ops error.)

### Refreshing the login cookies (when the session expires)
You'll know it expired when bigbasket goes BROKEN with `BB_SESSION_EXPIRED` present /
a Telegram alert. To refresh:
1. On a normal browser (any clean IP), log in to bigbasket.com as the member account.
2. Export cookies with the **Cookie-Editor** extension (Export → JSON) for
   `bigbasket.com`.
3. Replace `platforms/bigbasket/secrets/bb_cookies.json` with that export (the file is
   gitignored — never commit it).
4. Validate: `cd platforms/bigbasket && node import_cookies.js` — it reports the
   critical cookies (`BBAUTHTOKEN, sessionid, _bb_cid, customer_hash`) and prints
   `looks LOGGED IN`. Then `node scrape.js` should log `[member] logged in as id=…`
   and clear the marker. Optional deeper check: `node probe_member.js` (member
   identity + prices) or `node probe_ab.js` (guest-vs-member price diff).

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
cd platforms/bigbasket && node scrape.js       # ~15-25s, writes result.json
# or from repo root: ./run.sh bigbasket         # scrape→excel→predict→review→vault→telegram→push
```
Queries default to `jivo, jivo olive oil, jivo oil, jivo juice` (deduped on
canonical). Override with `BB_QUERIES="jivo,jivo vinegar"`.

## Output shape (keep this — build_excel.py depends on it)
`result.json` = `{summary, perPin, allRows}`. Each row carries the canonical
fields (`city, pincode, locality, store_id, store_name, sku_raw, canonical, pack,
vol_ml, sale, mrp, discount_pct, per_litre, eta_min, in_stock`) plus rich
identity (`sku_id, brand, avail_status, base_price, category, absolute_url`) that
build_excel ignores but vault/history/review keep. `summary.pincodes_total = 1`,
`pincodes_with_jivo = 1` when any Jivo row is found.

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
- **Member catalogue is smaller + has real OOS** (~23 rows, `avail_status "000"`) —
  expected for the localized logged-in view; not a regression. `ABS_MIN_ROWS=20` floor
  is the safety net.
- **BB vs BB Now**: the storefront defaults to BB (scheduled); BB Now (express)
  shares the same catalogue + pricing for Jivo, so the listing API value is the same.

## When prices ever DO vary by city
If BigBasket later reintroduces a usable per-city location switch, this becomes a
per-pincode scraper like Blinkit: set the hub via cookie/address before each
listing call and loop `pincodes.json`. Not needed today (pricing is national).
