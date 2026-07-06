# BigBasket Recon — 2026-05-31

Status: POC WORKING (poc.js returns real Jivo rows from DC IP).

## 2026-07-06 production update

The original 2026-05-31 conclusion that BigBasket should be scraped as a single
national session is **superseded for production**. The live pincode workflow now
uses `team_run_pincode.sh` across VPS + Mac Pro + KVM1, with logged-in cookies and
`scrape_pincode_browser.js`. It sets address/serviceability per requested pincode,
then calls `listing-svc` from the stealth page context. The national `scrape.js`
path remains only for the smaller national workbook/diagnostic.

The current pincode report records requested pincode, resolved location/service
area, serviceability failures, zero-row pins, Jivo rows, and member/session status.
Private/direct delivery is intentional: the pincode workbook is written to
`output/private-no-group/` and is not a group-batch attachment.

---

## 1. Anti-Bot Verdict

**PARTIALLY BLOCKED — stealth required.**

- Plain headless Chromium (`chromium.launch`) → **HTTP 403** on homepage and all API calls.  
  Response body: `Access Denied … Reference #18.9ff43717.*` (Akamai Bot Manager).  
  No Akamai cookies (`_abck`, `bm_sz`, `ak_bmsc`) are set — the connection is killed outright.

- `playwright-extra` + `puppeteer-extra-plugin-stealth` → **HTTP 200** on homepage.  
  Akamai is bypassed; no challenge or CAPTCHA encountered. The same pattern that already works for  on this VPS.

- Plain `node fetch` (no browser) to any `bigbasket.com` URL → 403 (same Akamai rule).

- In-page `page.evaluate(fetch(...))` from a stealth browser context → **200 OK** on all API endpoints. This is the required invocation mode.

**Required setup:**
```
npm install playwright-extra puppeteer-extra-plugin-stealth
```
Then:
```js
const { chromium } = require('playwright-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
chromium.use(StealthPlugin());
// ... launch with playwright's own chromium executablePath
```

---

## 2. Location / Serviceability Mechanism

**Historical note:** the first recon treated BigBasket scheduled delivery (BB) as
national for Jivo pricing. Production now treats BigBasket as a pincode-wise
availability source because serviceability and stock can vary by location even when
many prices match nationally.

**How location works:**
- On first page load, BB sets cookies that determine the delivery city/hub:
  - `_bb_cid=1` — city ID (1 = Bangalore, 2 = Delhi, etc.)
  - `_bb_nhid=7427` / `_bb_dsid=7427` — hub / dark-store IDs
  - `_bb_sa_ids=19224` — service area ID
  - `_bb_addressinfo=` — empty for anonymous sessions (no saved address)
  - `_bb_pin_code=` — empty for anonymous sessions
  - `csurftoken=…` — CSRF token (required for write ops, not needed for GET search)
  - `x-channel=web` — channel identifier (required in cookies)
  - `csrftoken=…` — Django CSRF token

- The pincode runner sets address/serviceability before calling listing-svc and
  records the resolved service area. Treat listing rows as location-scoped member
  results, not a pure national view.

- The `_bb_nhid` cookie can be overwritten with a known hub ID for a different city before calling the listing API, but empirically it makes no difference to prices or product availability in the catalog.

- **Location API endpoints all returned 404** (old BB 1.0 APIs no longer active):
  - `/api/v1/tb-location/` → 404
  - `/cityapi/detect-city/` → 404
  - `/hub-svc/v1/hubs/` → 404
  - `/sa-svc/v1/service-areas/` → 404
  - `/api/v1/delivery-address/` → 404

- **Location via UI**: The header API `/ui-svc/v2/header/?send_door_info=true&send_address_set_by_user=true` returns `sa_list` with available store areas. The default (no saved address) always resolves to Bangalore hub.

**Recommendation**: Use `team_run_pincode.sh` for production pincode coverage and
`node scrape.js` only for the national BigBasket workbook/diagnostic.

---

## 3. Search / Listing API

**Confirmed endpoint:**
```
GET /listing-svc/v2/products?type=ps&slug=<query>&page=1&bucket_id=32
```

- `type=ps` — product search
- `slug` — URL-encoded search query (e.g. `jivo%20olive%20oil`, `jivo`)
- `page` — pagination (1-indexed); `number_of_pages` in response tells total pages
- `bucket_id=32` — required; BB's internal search bucket for the web app. Omitting it returns 400: `{"errors":[{"code":400,"code_str":"PL400","msg":"Missing Mandatory queryParameter page"}]}` if `page` is also missing; with `page` but no `bucket_id` also returns 400.

**Response shape:**
```json
{
  "tabs": [{
    "product_info": {
      "products": [...],
      "page": 1,
      "number_of_pages": 1,
      "total_count": 35,
      "ps_or_search": "search"
    }
  }],
  "screen_info": {...},
  "base_img_url": "...",
  ...
}
```

**Product object field map:**
| Field | JSON path | Example |
|---|---|---|
| SKU / product ID | `p.id` | `"40249992"` |
| Name / description | `p.desc` | `"Extra Light Olive Oil"` |
| Brand name | `p.brand.name` (trim it — trailing space) | `"Jivo "` |
| Brand slug | `p.brand.slug` | `"jivo"` |
| Pack size | `p.w` | `"5 L"`, `"1 L"`, `"200 ml"` |
| Pack numeric (ml) | `p.magnitude` + `p.unit` | `magnitude:"5000"`, `unit:"ml"` |
| MRP | `p.pricing.discount.mrp` | `"1350"` (string, parse to float) |
| Selling price | `p.pricing.discount.prim_price.sp` | `"835.43"` (string, parse to float) |
| Discount text | `p.pricing.discount.d_text` | `"38% OFF"` |
| Discount % | `p.pricing.discount.camp_detail.d_v` | `38.12` (float) |
| Per-unit price | `p.pricing.discount.prim_price.base_price` + `base_unit` | `"167.08"` per L |
| In stock | `p.availability.avail_status === '001'` AND `!p.availability.not_for_sale` | `"001"` = in stock |
| Not for sale | `p.availability.not_for_sale` | `false` |
| Add-to-cart button | `p.availability.button` | `"Add"` (in stock) or `"Notify Me"` (OOS) |
| Category | `p.category.tlc_name` / `mlc_name` / `llc_name` | `"Edible Oils & Ghee"` |
| Absolute URL | `p.absolute_url` | `"/pd/40249992/jivo-…/"` |

**Pagination**: `total_count: 35` for `slug=jivo`, single page. BB Jivo catalog is small enough to fit in one page. For `slug=jivo olive oil`: 6 products (olive oil only).

**Filter by Jivo brand**: Check `p.brand.name.trim().toLowerCase() === 'jivo'` to exclude competing brands that appear in related results (e.g. bb Royal Canola, Borges, Disano).

---

## 4. Invocation Mode

**Required: in-page `page.evaluate(fetch(...))` from a stealth browser context.**

- External `node fetch` / `curl` with copied cookies → 403 (Akamai still blocks DC IP for raw HTTP clients).
- In-page evaluate from a stealth browser → 200 (cookies + TLS fingerprint inherited from real Chromium).

**Headers required for the in-page fetch (all inherited automatically):**
```js
const r = await fetch('/listing-svc/v2/products?type=ps&slug=jivo+olive+oil&page=1&bucket_id=32', {
  headers: {
    'accept': 'application/json, text/plain, */*',
    'x-requested-with': 'XMLHttpRequest',
    'referer': 'https://www.bigbasket.com/ps/?q=jivo+olive+oil',
  }
});
```

No explicit `csrftoken` / `csurftoken` header needed for GET requests. The cookies are set automatically by the browser context.

**Cookies that BB sets on session init (all auto-managed by browser):**
- `x-channel=web` — channel
- `csrftoken=…` — Django CSRF
- `csurftoken=…` — BB custom CSRF
- `_bb_cid=1` — city (1=Bangalore default)
- `_bb_nhid=7427` — hub node
- `_bb_dsid=7427` — dark store
- `_bb_sa_ids=19224` — service area

---

## 5. BB vs BB Now

- **BB (BigBasket scheduled)** = what the main `www.bigbasket.com` storefront serves.
  The national diagnostic still uses this path; the production pincode runner sets
  location per requested pincode before calling the same listing service.
- **BB Now** = express 10-minute delivery (`bbnow` entry context, `entry_context_id: 10` in `sa_list`). Shares the same site and `sa_id: 19224` but uses a different dark-store inventory. The cookie `xentrycontext=bbnow` is set by default for new sessions. The listing-svc returns BB Now pricing when `entry_context_id: 10` is active.
  - In practice, prices are identical between BB and BB Now for Jivo products (same catalog, same pricing engine).
  - The `availability.show_express: false` flag on products indicates BB Now express availability.

---

## 6. Gotchas / Recommendations

1. **Stealth is mandatory** — plain Chromium or any non-browser HTTP client gets 403 on this DC IP. `playwright-extra` + `puppeteer-extra-plugin-stealth` with Playwright's own Chromium binary works reliably.

2. **One session per run** — load homepage once, then call listing-svc. No need for multiple browser contexts or page navigations. Total time ≈ 15s per run.

3. **Production is pincode-wise** — run the team runner for coverage/availability.
   A single stealth session is only acceptable for the national diagnostic workbook.

4. **bucket_id=32 is required** — without it, the API returns 400. This is the web app's default search bucket. If it ever changes, intercept the XHR from the search page to get the new value.

5. **Query variants**: `slug=jivo` returns all 35 Jivo products (oils + juices + fizzy water). Filter by `p.brand.name.trim() === 'Jivo'` to exclude competitors. `slug=jivo+olive+oil` returns 6 (olive oil only).

6. **Rate limiting**: No evidence of rate limiting at a handful of requests. Recommend ≥3s delay between sessions if running multiple queries.

7. **Pagination**: `number_of_pages: 1`, `total_count: 35` — the entire Jivo catalog fits in one page. No pagination loop needed currently.

8. **avail_status codes**: `'001'` = in stock / available. Other codes (not observed for Jivo but possible): `'002'` = out of stock, `'004'` = not serviceable in area.

9. **`pack_desc`** (e.g. `"Jar"`) is the container type; `p.w` (e.g. `"5 L"`) is the volume/weight shown on listing.

---

## 7. POC Result

```
node poc.js
```
Returns 8 Jivo olive oil rows (2 example):
```json
{"sku_id":"40166397","name":"Extra Light Olive Oil","brand":"Jivo","pack":"5 L","vol_ml":5000,"mrp":3900,"sale":1840,"discount_pct":52.8,"per_litre":368,"in_stock":1,"avail_status":"001","canonical":"extra-light-olive-oil-5l"}
{"sku_id":"40250808","name":"Extra Virgin Olive Oil - Antioxidants Rich, Suitable For Salads, Saute","brand":"Jivo","pack":"1 L","vol_ml":1000,"mrp":1799,"sale":1012,"discount_pct":43.7,"per_litre":1012,"in_stock":1,"avail_status":"001","canonical":"extra-virgin-olive-oil-antioxidants-rich-suitable-for-salads-saute-1l"}
```
