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
  const m = pack.toLowerCase().match(/([\d.]+)\s*(ml|l|ltr|litre|kg|g)\b/);
  if (!m) return null;
  const n = parseFloat(m[1]); const u = m[2];
  if (u === 'ml' || u === 'g') return n;
  if (u === 'l' || u === 'ltr' || u === 'litre' || u === 'kg') return n * 1000;
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
  return { ok: true, items };
}

function toRow(pr, rec, storeId) {
  const p = pr.product, v = pr.productVariant || {};
  const name = p.name;
  const pack = v.formattedPacksize || '';
  const mrp = pr.mrp != null ? pr.mrp / 100 : (v.mrp != null ? v.mrp / 100 : null);
  const sale = (pr.discountedSellingPrice != null ? pr.discountedSellingPrice
    : pr.sellingPrice != null ? pr.sellingPrice : pr.superSaverSellingPrice);
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
  };
}

async function scrapeOne(rec) {
  const t0 = Date.now();
  let rows = [], storeId = '', serviceable = false;
  try {
    const st = await resolveStore(rec.lat, rec.lon);
    serviceable = st.serviceable; storeId = st.storeId || '';
    if (st.ok) {
      const seenCanon = new Set();
      for (let pn = 0; pn < MAX_PAGES; pn++) {
        const res = await searchPage(storeId, rec.lat, rec.lon, 'jivo', pn);
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
  process.stderr.write(`[ok] ${rec.city} ${rec.pincode} serviceable=${serviceable} -> ${rows.length} jivo SKUs (${((Date.now() - t0) / 1000).toFixed(1)}s) store=${storeId || 'n/a'}\n`);
  return { ...rec, store_id: storeId, store_name: '', serviceable, rows };
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
  const summary = {
    pincodes_total: PINCODES.length,
    pincodes_serviceable: perPin.filter(p => p.serviceable).length,
    pincodes_with_jivo: perPin.filter(p => p.rows.length > 0).length,
    total_rows: allRows.length,
    unique_skus: new Set(allRows.map(r => r.canonical)).size,
    wall_s: Math.round((Date.now() - t0) / 1000),
    captured_at: new Date().toISOString(),
  };
  process.stderr.write('[SUMMARY] ' + JSON.stringify(summary) + '\n');
  fs.writeFileSync(OUTFILE, JSON.stringify({ summary, perPin, allRows }, null, 2));
  console.log(JSON.stringify(summary));
})();
