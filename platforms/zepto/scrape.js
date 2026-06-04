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
const MAX_PAGES = 4;            // page 0..3; Jivo catalogue is small, this is plenty
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
  const toMl = (n, u) => {
    if (u === 'ml' || u === 'g') return n;
    if (u === 'l' || u === 'ltr' || u === 'litre' || u === 'litres' || u === 'kg') return n * 1000;
    return null;
  };
  // Multiplier packs ("combos"): "N L X M" / "N ml x M" => N*M of the unit (e.g. 1 L X 2 = 2 L).
  // Must run BEFORE the single-quantity match, which would otherwise read only the first "1 L".
  let m = s.match(/([\d.]+)\s*(ml|l|ltr|litre|litres|kg|g)\b\s*[x×]\s*([\d.]+)/);
  if (m) { const base = toMl(parseFloat(m[1]), m[2]); return base != null ? base * parseFloat(m[3]) : null; }
  // Additive packs: "A+B L" / "A + B Litres" => (A+B) of the unit (e.g. 1+1 Litres = 2 L).
  m = s.match(/([\d.]+)\s*\+\s*([\d.]+)\s*(ml|l|ltr|litre|litres|kg|g)\b/);
  if (m) { return toMl(parseFloat(m[1]) + parseFloat(m[2]), m[3]); }
  // Single quantity: "1 L", "200 ml", "1 pc (1 L)".
  m = s.match(/([\d.]+)\s*(ml|l|ltr|litre|litres|kg|g)\b/);
  if (m) return toMl(parseFloat(m[1]), m[2]);
  return null;
}
function canonical(name, pack) {
  const base = (name || '').toLowerCase().replace(/\(.*?\)/g, '').replace(/[^a-z0-9 ]/g, '')
    .replace(/\s+/g, ' ').trim().replace(/\s/g, '-');
  const vol = parseVolMl(pack);
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
  const body = JSON.stringify({ query, pageNumber, intentId: uuid(), mode: 'AUTOSUGGEST', userSessionId: uuid() });
  const args = ['-s', '--max-time', '30', '-X', 'POST', '-w', '\n__HTTP__%{http_code}',
    ...hdrArgs(commonHeaders(storeId, lat, lon)), '--data', body, url];
  const r = await curl(args);
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
  const vol = parseVolMl(pack);
  const inStock = pr.outOfStock === true ? 0 : 1;
  return {
    city: rec.city, pincode: rec.pincode, locality: rec.locality,
    store_id: storeId, store_name: '',
    sku_raw: name, canonical: canonical(name, pack), pack,
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

async function scrapeOne(rec) {
  const t0 = Date.now();
  let rows = [], storeId = '', serviceable = false, markers = {};
  try {
    const st = await resolveStore(rec.lat, rec.lon);
    serviceable = st.serviceable; storeId = st.storeId || '';
    if (st.ok) {
      const seenCanon = new Set();
      for (let pn = 0; pn < MAX_PAGES; pn++) {
        const res = await searchPage(storeId, rec.lat, rec.lon, 'jivo', pn);
        if (pn === 0 && res.markers) markers = res.markers;   // page-0 freshness markers for this store
        if (!res.ok || !res.items.length) break;
        let added = 0;
        for (const pr of res.items) {
          // keep only genuine Jivo products (brand == Jivo, or name contains the
          // word "jivo"); excludes fuzzy matches like "Jivika", "Tata", "Saffola".
          const nm = pr.product.name || '';
          const br = (pr.product.brand || '').toLowerCase();
          if (br !== 'jivo' && !/\bjivo\b/i.test(nm)) continue;
          const row = toRow(pr, rec, storeId);
          const key = `${storeId}|${row.canonical}`;
          if (seenCanon.has(key)) continue;
          seenCanon.add(key); rows.push(row); added++;
        }
        if (added === 0 && pn > 0) break; // no new Jivo SKUs on this page
        await new Promise(r => setTimeout(r, 250 + Math.random() * 400));
      }
    }
  } catch (e) { process.stderr.write(`[err] ${rec.city} ${rec.pincode}: ${e.message}\n`); }
  const cachedRows = rows.filter(r => r.cached).length;
  process.stderr.write(`[ok] ${rec.city} ${rec.pincode} serviceable=${serviceable} -> ${rows.length} jivo SKUs (${((Date.now() - t0) / 1000).toFixed(1)}s) store=${storeId || 'n/a'}${cachedRows ? ` CACHED=${cachedRows}` : ''}\n`);
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
