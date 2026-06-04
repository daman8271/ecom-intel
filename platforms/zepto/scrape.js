// ---------------------------------------------------------------------------
// ZEPTO scraper.  STATUS: LIVE (2026-05-29) via the public BFF API gateway.
//
// The Zepto WEBSITE edge (www / api.zeptonow.com on CloudFront dist d3kfwk7jfmwo3t)
// hard-403s this datacenter IP. BUT the app's API gateway, bff-gateway.zeptonow.com
// (Kong), is reachable from this IP with NO proxy. The web app authenticates guest
// browsing with `x-without-bearer: true` (no login/token needed). Two calls per pincode:
//   1) GET  serviceability-service/api/v1/serviceability?lat=&long=  -> { serviceable, storeId }
//   2) POST user-search-service/api/v3/search { query, pageNumber, mode } + store_id headers
// Recipe reconstructed from public repos (tanishq-y/android, DebadityaHait/ShopLense,
// vedant-2525/QuickCompare, Garvitx/assigment-node) and verified live from this host.
//
// Prices are returned in PAISE (mrp:46000 == Rs 460.00) -> divide by 100.
// We keep only products whose product.brand == "Jivo" (excludes "Jivika"/"Tata" etc).
// Output schema is identical to Blinkit so build_excel.py works unchanged.
//
// FRESHNESS (2026-06-03): the owner saw the API lag a real price change by ~1 day. Recon
// confirmed there is NO read-only PDP/product-price route on this gateway (every product/
// inventory/pdp path 404s "no Route matched"; only cart-service exists and needs a stateful
// guest-cart mutation — unfit for a 332-store loop). BUT the search response is itself
// authoritative when its per-product `cached` flag is false (then it equals the live app
// price), and it already carries the structured per-tier price in pricingData. So the fix is:
//   (1) record the price from pricingData.pricingEntityPrices[tier] (the exact app-rendered
//       tier price) instead of the ambiguous top-level fallback chain;
//   (2) capture the per-store realtime signal (is_realtime_model_data_fetched / reason, the true
//       lag indicator — NOT the always-false `cached` flag) into summary.freshness; and
//   (3) raise a staleness alarm (tools/review.py): SUSPECT when a SKU's modal price is frozen
//       across many runs while stores are served from the non-realtime (snapshot) path.
// ---------------------------------------------------------------------------

const { execFile } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const uuid = () => crypto.randomUUID();

// PINCODES_FILE / OUT_FILE let a caller scrape a subset to a separate output
// (used for the parallel split-scrape); both default to the in-folder files so
// the cron call `node scrape.js` keeps running the full default set unchanged.
const PFILE = process.env.PINCODES_FILE || (__dirname + '/pincodes.json');
const OUTFILE = process.env.OUT_FILE || (__dirname + '/result.json');
const PINCODES = JSON.parse(fs.readFileSync(PFILE, 'utf8'));
const CONCURRENCY = parseInt(process.env.CONCURRENCY || '3', 10);
const MAX_PAGES = 4;            // page 0..3 for the bare-brand query; all in-stock Jivo ranks on page 0
// The bare-brand "jivo" search is gated to IN-STOCK products (oos_products_shown_count=0), so it
// silently omits chronically-OOS Jivo SKUs: Extra Virgin Olive Oil 1L, Pomace Olive Oil 5L, the
// single-2L Pomace bottle, the Extra Light 2L, Canola combo, etc. Those reappear under SECONDARY
// queries that add a category/size term. We use BRAND-SCOPED queries ("jivo olive oil", "jivo 5l",
// …) rather than bare-category ones ("olive oil"): brand-scoped keeps Jivo on page 0-1 (reliable +
// cheap, ~8 results), whereas bare-category buries Jivo on pages 5-6 of 7 amid hundreds of competitor
// products (unreliable + expensive — empirically it missed Pomace 5L / EV 1L at the Saket store the
// brand-scoped set recovered). Set matches A1's live-verified minimal recovery set. Each query is
// full-swept to its first empty page (no early-break) up to CAT_MAX_PAGES; deduped per-store by
// canonical against the bare-"jivo" results, so in-stock prices are untouched and OOS SKUs only ADD.
// Override/disable via env (ZEPTO_CATEGORY_QUERIES='' turns the secondary sweep off, brand-only).
const CAT_QUERIES = (process.env.ZEPTO_CATEGORY_QUERIES !== undefined
  ? process.env.ZEPTO_CATEGORY_QUERIES : 'jivo olive oil,jivo oil 5 litre,jivo 5l,jivo 2l,jivo pomace')
  .split(',').map(s => s.trim()).filter(Boolean);
const CAT_MAX_PAGES = parseInt(process.env.ZEPTO_CAT_MAX_PAGES || '6', 10);
// SEED VARIANTS — the catalog-completeness fix (2026-06-04, zcat).
// Zepto's search (Algolia) HIDES whole pack-size variants: it collapses a product's pack-size
// siblings into ONE representative variant (variant-rollup) and the bare-brand query is in-stock-
// gated. So large/OOS/rollup-hidden SKUs never surface in search under ANY query — e.g. the owner's
// Kachi Ghani Mustard 5 L (in stock, MRP 1250), Sunflower 5 L, Canola 5 L, Gold blend, Rice Bran,
// So-Olive, etc. We recover them deterministically: jivo_variants.json holds their (catalog-global)
// variantIds, and for each serviceable store we hit the PDP route get_page?page_type=PDP&product_
// variant_id=<id> (Agent-1's endpoint) for AUTHORITATIVE per-store price + availableQuantity, incl.
// OOS. variantIds come from the public zepto.com /pvid/<id> index + live PDP verification (no proxy,
// no login; the gateway PDP route is reachable from the DC IP). Rows merge with the search rows and
// dedup BY VARIANT ID (PDP wins — it also corrects search's wrong oos:true / stale price on the few
// large variants search does surface, e.g. Pomace 5 L). Disable with ZEPTO_SEED_VARIANTS=0.
const SEED_ENABLED = process.env.ZEPTO_SEED_VARIANTS !== '0';
let SEED_VARIANTS = [];
if (SEED_ENABLED) {
  try {
    const sv = JSON.parse(fs.readFileSync(__dirname + '/jivo_variants.json', 'utf8'));
    SEED_VARIANTS = (sv && Array.isArray(sv.variants) ? sv.variants : []).filter(v => v && v.variantId);
  } catch (e) { process.stderr.write(`[warn] seed variants not loaded: ${e.message}\n`); }
}
const GW = 'https://bff-gateway.zeptonow.com';
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';
const COMPAT = 'CONVENIENCE_FEE,RAIN_FEE,EXTERNAL_COUPONS,STANDSTILL,BUNDLE,MULTI_SELLER_ENABLED,PIP_V1,ROLLUPS,SCHEDULED_DELIVERY,SAMPLING_ENABLED,HOMEPAGE_V2,NEW_ETA_BANNER,SUPER_SAVER:1,PROMO_CASH:0,24X7_ENABLED_V1,HP_V4_FEED,NEW_ROLLUPS_ENABLED,PLP_ON_SEARCH,DYNAMIC_FILTERS,NEW_FEE_STRUCTURE,NEW_BILL_INFO,SUPERSTORE_V1,MARKETPLACE_REPLACEMENT';
// Zepto runs TWO storefronts over the SAME catalogue at the SAME store, with DIFFERENT
// prices for the identical SKU, selected purely by the `marketplace_type` header:
//   SUPER_SAVER  = scheduled delivery, cheaper  (e.g. Canola combo 469)  <- the price the app shows by default
//   ZEPTO_NOW    = instant ~10-min delivery     (e.g. Canola combo 485)
// We track SUPER_SAVER because that is the price customers (and our reference checks)
// actually see. Override with ZEPTO_MARKETPLACE=ZEPTO_NOW to capture the instant tier.
const MARKETPLACE = process.env.ZEPTO_MARKETPLACE || 'SUPER_SAVER';

// --- price/pack helpers (same conventions as the other platforms) ---
function parseVolMl(pack) {
  if (!pack) return null;
  const s = pack.toLowerCase();
  // 'm' = Zepto's truncated 'ml' (it clips formattedPacksize at a fixed width, so "200 ml"
  // renders as "200 m"). Placed LAST in every alternation so it never shadows 'ml'/'l'.
  const toMl = (n, u) => {
    if (u === 'ml' || u === 'm' || u === 'g') return n;
    if (u === 'l' || u === 'ltr' || u === 'litre' || u === 'litres' || u === 'kg') return n * 1000;
    return null;
  };
  // Multiplier packs ("combos"): "N L X M" / "N ml x M" => N*M of the unit (e.g. 1 L X 2 = 2 L).
  // Must run BEFORE the single-quantity match, which would otherwise read only the first "1 L".
  let m = s.match(/([\d.]+)\s*(ml|l|ltr|litre|litres|kg|g|m)\b\s*[x×]\s*([\d.]+)/);
  if (m) { const base = toMl(parseFloat(m[1]), m[2]); return base != null ? base * parseFloat(m[3]) : null; }
  // Additive packs: "A+B L" / "A + B Litres" => (A+B) of the unit (e.g. 1+1 Litres = 2 L).
  m = s.match(/([\d.]+)\s*\+\s*([\d.]+)\s*(ml|l|ltr|litre|litres|kg|g|m)\b/);
  if (m) { return toMl(parseFloat(m[1]) + parseFloat(m[2]), m[3]); }
  // Single quantity: "1 L", "200 ml", "1 pc (1 L)", "1 Pack(200 m)".
  m = s.match(/([\d.]+)\s*(ml|l|ltr|litre|litres|kg|g|m)\b/);
  if (m) return toMl(parseFloat(m[1]), m[2]);
  return null;
}
// Authoritative volume from the variant's STRUCTURED fields (packsize + unitOfMeasure), which are
// immune to the display-string truncation that breaks formattedPacksize (e.g. "1 Pack(200 m)").
// packsize is the TOTAL volume in unitOfMeasure units (Zepto does NOT double combos: "1 L X 2"
// reports packsize=2/LITER), so this is correct for combos too. Falls back to parsing the display
// string for any variant that lacks the structured fields.
function volFromVariant(v, pack) {
  const ps = v && v.packsize;
  const u = v && String(v.unitOfMeasure || '').toLowerCase();
  if (ps != null && u) {
    if (/^milli/.test(u) || u === 'ml') return ps;            // MILLILITRE
    if (/^lit(er|re)/.test(u) || u === 'l') return ps * 1000; // LITER / LITRE
    if (/^gram/.test(u) || u === 'g') return ps;              // GRAM
    if (/^kilo/.test(u) || u === 'kg') return ps * 1000;      // KILOGRAM
  }
  return parseVolMl(pack);
}
// Canonical slug = slugify(product.name) + volume tag. The vol is precomputed (see volFromVariant)
// so the tag is correct even when the display pack string is truncated. NOTE: distinct products that
// share a volume (single 2L bottle vs 2x1L combo, both -> "2l") stay separate ONLY via their names
// ("Daily" vs "Combo"), which Zepto returns consistently per product.
function canonical(name, vol) {
  const base = (name || '').toLowerCase().replace(/\(.*?\)/g, '').replace(/[^a-z0-9 ]/g, '')
    .replace(/\s+/g, ' ').trim().replace(/\s/g, '-');
  const volTag = vol ? (vol >= 1000 ? (vol / 1000) + 'l' : vol + 'ml') : 'na';
  return `${base}-${volTag}`.replace(/--+/g, '-');
}

// --- low-level: run curl, return {status, body} (Node fetch is flaky on this host) ---
function curl(args) {
  return new Promise((resolve) => {
    execFile('curl', args, { maxBuffer: 128 * 1024 * 1024, encoding: 'utf8' }, (err, stdout) => {
      const out = stdout || '';
      const i = out.lastIndexOf('__HTTP__');
      resolve({ status: i >= 0 ? out.slice(i + 8).trim() : (err ? 'ERR' : '?'), body: i >= 0 ? out.slice(0, i) : out });
    });
  });
}
function commonHeaders(storeId, lat, lon) {
  const sid = uuid(), did = uuid(), rid = uuid();
  const h = {
    'accept': 'application/json, text/plain, */*', 'accept-language': 'en-US,en;q=0.9',
    'app_sub_platform': 'WEB', 'app_version': '12.64.1', 'appversion': '12.64.1',
    'auth_revamp_flow': 'v2', 'compatible_components': COMPAT, 'content-type': 'application/json',
    'device_id': did, 'deviceid': did, 'marketplace_type': MARKETPLACE,
    'origin': 'https://www.zeptonow.com', 'platform': 'WEB', 'referer': 'https://www.zeptonow.com/',
    'request_id': rid, 'requestid': rid, 'session_id': sid, 'sessionid': sid,
    'tenant': 'ZEPTO', 'x-without-bearer': 'true', 'user-agent': UA,
    'x-latitude': String(lat), 'x-longitude': String(lon), 'latitude': String(lat), 'longitude': String(lon),
  };
  if (storeId) {
    h['store_id'] = storeId; h['store_ids'] = storeId; h['storeid'] = storeId;
    h['store_etas'] = `{"${storeId}":10}`;
  }
  return h;
}
function hdrArgs(h) { const a = []; for (const [k, v] of Object.entries(h)) a.push('-H', `${k}: ${v}`); return a; }

async function resolveStore(lat, lon) {
  const url = `${GW}/serviceability-service/api/v1/serviceability?lat=${lat}&long=${lon}`;
  const args = ['-s', '--max-time', '25', '-w', '\n__HTTP__%{http_code}', ...hdrArgs(commonHeaders(null, lat, lon)), url];
  const r = await curl(args);
  if (r.status !== '200') return { ok: false, status: r.status };
  let j; try { j = JSON.parse(r.body); } catch { return { ok: false, status: 'badjson' }; }
  // Response shape: { errors:[], data:{ serviceable:bool, stores:[{storeId, serviceable, storeConstruct}] } }
  const data = j.data || {};
  const serviceable = !!data.serviceable;
  let storeId = null;
  if (Array.isArray(data.stores)) {
    const s = data.stores.find(x => x && x.serviceable && /PRIMARY/i.test(x.storeConstruct || ''))
      || data.stores.find(x => x && x.serviceable)
      || data.stores[0];
    storeId = s && s.storeId;
  }
  return { ok: !!(serviceable && storeId), serviceable, storeId };
}

// Pull the response-level freshness markers Zepto's search service emits. These tell us whether
// the catalogue we just read came from a live fetch or a cache/snapshot:
//   is_realtime_model_data_fetched / realtime_model_not_enabled_reason / algoliaTimeOut
function findMarkers(j) {
  const m = {};
  (function walk(o, depth) {
    if (!o || typeof o !== 'object' || depth > 6) return;
    for (const k of Object.keys(o)) {
      if (/^(is_realtime_model_data_fetched|realtime_model_not_enabled_reason|algoliaTimeOut)$/.test(k)
        && !(k in m)) m[k] = o[k];
      const v = o[k];
      if (v && typeof v === 'object' && k !== 'productResponse') walk(v, depth + 1);
    }
  })(j, 0);
  return m;
}

async function searchPage(storeId, lat, lon, query, pageNumber) {
  const url = `${GW}/user-search-service/api/v3/search`;
  // The gateway 429-rate-limits aggressive bursts (~>5 req/s). The multi-query category sweep
  // multiplies request volume, so retry 429s with exponential backoff before giving up.
  let r;
  for (let attempt = 0; attempt < 4; attempt++) {
    const body = JSON.stringify({ query, pageNumber, intentId: uuid(), mode: 'AUTOSUGGEST', userSessionId: uuid() });
    const args = ['-s', '--max-time', '30', '-X', 'POST', '-w', '\n__HTTP__%{http_code}',
      ...hdrArgs(commonHeaders(storeId, lat, lon)), '--data', body, url];
    r = await curl(args);
    if (r.status !== '429') break;
    await new Promise(res => setTimeout(res, 1500 * (attempt + 1) + Math.random() * 1500));
  }
  if (r.status !== '200') return { ok: false, status: r.status, items: [] };
  let j; try { j = JSON.parse(r.body); } catch { return { ok: false, status: 'badjson', items: [] }; }
  const items = [];
  (function walk(o) {
    if (!o || typeof o !== 'object') return;
    const pr = o.productResponse;
    if (pr && pr.product && pr.product.name) items.push(pr);
    for (const k of Object.keys(o)) { const v = o[k]; if (v && typeof v === 'object') walk(v); }
  })(j);
  return { ok: true, items, markers: findMarkers(j) };
}

// Fetch a single variant's PDP (the catalog-completeness recovery path). Returns the productInfo
// object { product, productVariant, storeProduct } or null. A 404 ("Product not found in store")
// means this store does not carry the variant -> null (no row, correctly). 429-backoff like search.
async function fetchPdp(storeId, lat, lon, variantId) {
  const url = `${GW}/lms/api/v2/get_page?page_type=PDP&product_variant_id=${variantId}`
    + `&latitude=${lat}&longitude=${lon}&store_id=${storeId}`;
  let r;
  for (let attempt = 0; attempt < 4; attempt++) {
    const args = ['-s', '--max-time', '30', '-w', '\n__HTTP__%{http_code}',
      ...hdrArgs(commonHeaders(storeId, lat, lon)), url];
    r = await curl(args);
    if (r.status !== '429') break;
    await new Promise(res => setTimeout(res, 1500 * (attempt + 1) + Math.random() * 1500));
  }
  if (r.status !== '200') return null;          // 404 = not carried at this store; other = transient
  let j; try { j = JSON.parse(r.body); } catch { return null; }
  const widgets = (j.pageLayout && j.pageLayout.widgets) || [];
  const w = widgets.find(x => x && x.widgetType === 'PRODUCT_INFO');
  const pi = w && w.data && w.data.productInfo;
  return (pi && pi.productVariant) ? pi : null;
}

// Authoritative per-tier price from the PDP storeProduct (same shape/precedence as tierPrice for
// search, but the pricingData lives under storeProduct here).
function tierPriceSP(sp, mk) {
  const pe = (sp.pricingData && sp.pricingData.pricingEntityPrices) || [];
  const hit = pe.find(x => x && x.pricingEntity === mk && x.discountedSellingPrice != null);
  return hit ? hit.discountedSellingPrice : null;
}

// Build a row from a PDP productInfo. Stock is authoritative: availableQuantity > 0 == in stock
// (there is NO outOfStock bool in the PDP payload). OOS variants keep their listed price but are
// flagged in_stock=0 (build_excel's cheapest picker / review's price-band check both skip OOS rows).
function pdpToRow(pi, rec, storeId, seed) {
  const p = pi.product || {}, v = pi.productVariant || {}, sp = pi.storeProduct || {};
  const name = p.name || (seed && seed.name) || '';
  const pack = v.formattedPacksize || (seed && seed.pack) || '';
  const mrp = sp.mrp != null ? sp.mrp / 100 : null;
  let sale = tierPriceSP(sp, MARKETPLACE);
  let priceSource = sale != null ? 'pdp:pricingData:' + MARKETPLACE : null;
  if (sale == null && MARKETPLACE === 'SUPER_SAVER' && sp.superSaverSellingPrice != null) {
    sale = sp.superSaverSellingPrice; priceSource = 'pdp:superSaverSellingPrice';
  }
  if (sale == null && sp.discountedSellingPrice != null) {
    sale = sp.discountedSellingPrice; priceSource = 'pdp:discountedSellingPrice';
  }
  const saleR = sale != null ? sale / 100 : null;
  const vol = volFromVariant(v, pack);
  const inStock = (sp.availableQuantity != null && sp.availableQuantity > 0) ? 1 : 0;
  return {
    city: rec.city, pincode: rec.pincode, locality: rec.locality,
    store_id: storeId, store_name: '',
    product_id: (p && p.id) || (seed && seed.productId) || null, variant_id: v.id || (seed && seed.variantId) || null,
    sku_raw: name, canonical: canonical(name, vol), pack,
    vol_ml: vol, sale: saleR, mrp,
    discount_pct: (mrp && saleR && mrp >= saleR) ? Math.round(((mrp - saleR) / mrp) * 1000) / 10
      : (sp.discountPercent != null ? sp.discountPercent : null),
    per_litre: (vol && saleR) ? Math.round((saleR / (vol / 1000)) * 100) / 100 : null,
    eta_min: null,
    in_stock: inStock,
    cached: false,            // PDP is a live per-store fetch, never the search cache
    price_source: priceSource,
    source: 'pdp_seed',       // provenance: recovered via the seed-variant PDP pass (vs search)
  };
}

// Authoritative per-tier price. Zepto's response carries pricingData.pricingEntityPrices —
// an explicit { pricingEntity, discountedSellingPrice } per storefront tier (SUPER_SAVER /
// ULTRA_SAVER / ...). That is the structured price the app actually renders for the selected
// tier, so we PREFER it over the ambiguous top-level discountedSellingPrice fallback chain
// (which is tier-dependent and easy to mis-read). This removes the "wrong tier" class of error.
function tierPrice(pr, mk) {
  const pe = (pr.pricingData && pr.pricingData.pricingEntityPrices) || [];
  const hit = pe.find(x => x && x.pricingEntity === mk && x.discountedSellingPrice != null);
  return hit ? hit.discountedSellingPrice : null;
}

function toRow(pr, rec, storeId) {
  const p = pr.product, v = pr.productVariant || {};
  const name = p.name;
  const pack = v.formattedPacksize || '';
  const mrp = pr.mrp != null ? pr.mrp / 100 : (v.mrp != null ? v.mrp / 100 : null);
  // Price source, most-authoritative first: explicit tier price -> tier-specific field
  // (superSaver) -> generic discounted/selling chain. price_source records which one we used
  // so a stale/odd value can be traced back to its origin field.
  let sale = tierPrice(pr, MARKETPLACE);
  let priceSource = sale != null ? 'pricingData:' + MARKETPLACE : null;
  if (sale == null && MARKETPLACE === 'SUPER_SAVER' && pr.superSaverSellingPrice != null) {
    sale = pr.superSaverSellingPrice; priceSource = 'superSaverSellingPrice';
  }
  if (sale == null) {
    sale = pr.discountedSellingPrice != null ? pr.discountedSellingPrice
      : pr.sellingPrice != null ? pr.sellingPrice : pr.superSaverSellingPrice;
    priceSource = pr.discountedSellingPrice != null ? 'discountedSellingPrice'
      : pr.sellingPrice != null ? 'sellingPrice' : 'superSaverSellingPrice';
  }
  const saleR = sale != null ? sale / 100 : null;
  const vol = volFromVariant(v, pack);
  const inStock = pr.outOfStock === true ? 0 : 1;
  return {
    city: rec.city, pincode: rec.pincode, locality: rec.locality,
    store_id: storeId, store_name: '',
    // Stable Zepto identifiers, persisted for traceability / future variantId-keyed canonicalization.
    product_id: (p && p.id) || null, variant_id: v.id || null,
    sku_raw: name, canonical: canonical(name, vol), pack,
    vol_ml: vol, sale: saleR, mrp,
    discount_pct: (mrp && saleR && mrp >= saleR) ? Math.round(((mrp - saleR) / mrp) * 1000) / 10
      : (pr.discountPercent != null ? pr.discountPercent : null),
    per_litre: (vol && saleR) ? Math.round((saleR / (vol / 1000)) * 100) / 100 : null,
    eta_min: null,
    in_stock: inStock,
    // Freshness signal: Zepto sets cached=true when this product was served from its search
    // cache (a stale-price risk) and false when it was fetched live. Recorded so the review
    // step can raise a staleness alarm. price_source aids debugging odd values.
    cached: pr.cached === true,
    price_source: priceSource,
  };
}

// Run one search query across its pages, appending genuine-Jivo rows into `rows` and deduping by
// per-store canonical against `seenCanon` (shared across all queries for the store, so a SKU seen
// under "jivo" is not re-added by a category query). Returns the page-0 freshness markers.
//   opts.maxPages   how many pages to walk
//   opts.earlyBreak stop once a page (after page 0) adds no NEW Jivo SKU (cheap; for the brand query
//                   where everything is on page 0). OFF for category queries, where Jivo is sparse
//                   and interleaved with blank pages, so we must full-sweep to the empty page.
async function collectQuery(rec, storeId, query, opts, seenCanon, rows) {
  let firstMarkers = null;
  for (let pn = 0; pn < opts.maxPages; pn++) {
    const res = await searchPage(storeId, rec.lat, rec.lon, query, pn);
    if (pn === 0) firstMarkers = res.markers || {};
    if (!res.ok || !res.items.length) break;
    let added = 0;
    for (const pr of res.items) {
      // keep only genuine Jivo products (brand == Jivo, or name contains the
      // word "jivo"); excludes fuzzy matches like "Jivika", "Tata", "Saffola".
      const nm = (pr.product && pr.product.name) || '';
      const br = ((pr.product && pr.product.brand) || '').toLowerCase();
      if (br !== 'jivo' && !/\bjivo\b/i.test(nm)) continue;
      const row = toRow(pr, rec, storeId);
      const key = `${storeId}|${row.canonical}`;
      if (seenCanon.has(key)) continue;
      seenCanon.add(key); rows.push(row); added++;
    }
    if (opts.earlyBreak && added === 0 && pn > 0) break; // brand query: no new Jivo SKUs on this page
    await new Promise(r => setTimeout(r, 250 + Math.random() * 400));
  }
  return firstMarkers;
}

async function scrapeOne(rec) {
  const t0 = Date.now();
  let rows = [], storeId = '', serviceable = false, markers = {};
  try {
    const st = await resolveStore(rec.lat, rec.lon);
    serviceable = st.serviceable; storeId = st.storeId || '';
    if (st.ok) {
      const seenCanon = new Set();
      // 1) Primary brand query — returns all in-stock Jivo SKUs (on page 0); keep the cheap early-break.
      //    Its page-0 markers are the store's freshness signal (unchanged from before).
      markers = (await collectQuery(rec, storeId, 'jivo', { maxPages: MAX_PAGES, earlyBreak: true }, seenCanon, rows)) || {};
      // 2) Brand-scoped secondary queries — recover the chronically-OOS Jivo SKUs the bare-brand
      //    query suppresses (Extra Virgin 1L, Pomace 5L, single-2L Pomace bottle, …). Full-sweep to
      //    the first empty page (no early-break) so a SKU on page 1 isn't missed; deduped per-store.
      for (const cq of CAT_QUERIES) {
        await collectQuery(rec, storeId, cq, { maxPages: CAT_MAX_PAGES, earlyBreak: false }, seenCanon, rows);
      }
      // 3) SEED-VARIANT PDP PASS — recover rollup-hidden / OOS / large-pack variants that Zepto's
      //    search never emits under ANY query (Mustard 5 L, Sunflower 5 L, Canola 5 L, Gold blend,
      //    Rice Bran, So-Olive, …). For each known variantId hit the PDP route for authoritative
      //    per-store price + availableQuantity (incl. OOS). Dedup BY VARIANT ID, PDP overriding any
      //    search row for the same variant (PDP also corrects search's wrong oos/stale price on the
      //    few large variants search does surface, e.g. Pomace 5 L).
      if (SEED_VARIANTS.length) {
        const byVid = new Map();
        for (const r of rows) if (r.variant_id) byVid.set(r.variant_id, r);
        for (const seed of SEED_VARIANTS) {
          const pi = await fetchPdp(storeId, rec.lat, rec.lon, seed.variantId);
          if (!pi) continue;                                   // 404 -> not carried at this store
          const nm = (pi.product && pi.product.name) || seed.name || '';
          const br = ((pi.product && pi.product.brand) || '').toLowerCase();
          if (br !== 'jivo' && !/\bjivo\b/i.test(nm)) continue; // safety: only genuine Jivo
          const row = pdpToRow(pi, rec, storeId, seed);
          const existing = byVid.get(seed.variantId);
          if (existing) Object.assign(existing, row);           // PDP wins (authoritative)
          else { rows.push(row); byVid.set(seed.variantId, row); }
          await new Promise(r => setTimeout(r, 220 + Math.random() * 300));
        }
      }
    }
  } catch (e) { process.stderr.write(`[err] ${rec.city} ${rec.pincode}: ${e.message}\n`); }
  const cachedRows = rows.filter(r => r.cached).length;
  const seedRows = rows.filter(r => r.source === 'pdp_seed').length;
  process.stderr.write(`[ok] ${rec.city} ${rec.pincode} serviceable=${serviceable} -> ${rows.length} jivo SKUs (${((Date.now() - t0) / 1000).toFixed(1)}s) store=${storeId || 'n/a'}${seedRows ? ` SEED=${seedRows}` : ''}${cachedRows ? ` CACHED=${cachedRows}` : ''}\n`);
  return { ...rec, store_id: storeId, store_name: '', serviceable, rows, freshness: { cached_rows: cachedRows, markers } };
}

async function pool(items, n, fn) {
  const results = []; let i = 0;
  async function worker() {
    while (i < items.length) {
      const idx = i++;
      results[idx] = await fn(items[idx], idx);
      await new Promise(r => setTimeout(r, 500 + Math.random() * 900));
    }
  }
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, worker));
  return results;
}

(async () => {
  const t0 = Date.now();
  const perPin = await pool(PINCODES, CONCURRENCY, scrapeOne);
  const allRows = perPin.flatMap(p => p.rows);
  // Freshness aggregate for the review/staleness alarm. The REAL lag signal is NOT the per-product
  // `cached` flag (Zepto leaves it false even when serving a stale MongoDB snapshot) — it is the
  // per-store `is_realtime_model_data_fetched`: when false (reason e.g. mongo_data_exists) the store
  // was served from a NON-realtime snapshot that can lag the live catalogue. We aggregate the share
  // of serviceable stores served that way (pct_non_realtime) plus the reason histogram; the review
  // step uses this to GATE the frozen-price alarm. (pct_cached kept too, for completeness.)
  const cachedRows = allRows.filter(r => r.cached).length;
  const servStores = perPin.filter(p => p.serviceable);
  let storesNonRealtime = 0;
  const reasonCounts = {};
  for (const p of servStores) {
    const m = (p.freshness && p.freshness.markers) || {};
    if (m.is_realtime_model_data_fetched === false) {
      storesNonRealtime++;
      const reason = m.realtime_model_not_enabled_reason;
      if (reason) reasonCounts[reason] = (reasonCounts[reason] || 0) + 1;
    }
  }
  const summary = {
    pincodes_total: PINCODES.length,
    pincodes_serviceable: perPin.filter(p => p.serviceable).length,
    pincodes_with_jivo: perPin.filter(p => p.rows.length > 0).length,
    total_rows: allRows.length,
    unique_skus: new Set(allRows.map(r => r.canonical)).size,
    rows_in_stock: allRows.filter(r => r.in_stock).length,
    rows_oos: allRows.filter(r => !r.in_stock).length,
    rows_seed_pdp: allRows.filter(r => r.source === 'pdp_seed').length,
    skus_via_seed: new Set(allRows.filter(r => r.source === 'pdp_seed').map(r => r.canonical)).size,
    wall_s: Math.round((Date.now() - t0) / 1000),
    captured_at: new Date().toISOString(),
    marketplace: MARKETPLACE,
    freshness: {
      rows_total: allRows.length,
      rows_cached: cachedRows,
      pct_cached: allRows.length ? Math.round((cachedRows / allRows.length) * 1000) / 10 : 0,
      stores_total: servStores.length,
      stores_non_realtime: storesNonRealtime,
      pct_non_realtime: servStores.length ? Math.round((storesNonRealtime / servStores.length) * 1000) / 10 : 0,
      realtime_not_enabled_reasons: reasonCounts,
    },
  };
  process.stderr.write('[SUMMARY] ' + JSON.stringify(summary) + '\n');
  fs.writeFileSync(OUTFILE, JSON.stringify({ summary, perPin, allRows }, null, 2));
  console.log(JSON.stringify(summary));
})();
