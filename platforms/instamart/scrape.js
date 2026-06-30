#!/usr/bin/env node
'use strict';
/*
 * Swiggy Instamart price scraper for ecom-intel.
 *
 * APPROACH (deliberate, see memory: instamart-scraper-research / no-thirdparty-waf-evasion):
 *   - Reuses a GUEST session the owner transplants from a real browser
 *     (secrets/swiggy_cookies.json) — same cookie-transplant model as bigbasket/amazon.
 *   - curl transport (like zepto) — "Node fetch is flaky on this host".
 *   - NO proxy, NO IP rotation, NO headless/stealth browser, NO fabricated browser
 *     fingerprint headers (sec-ch-ua / sec-fetch-*). Only the app's required protocol
 *     headers (content-type, origin, referer, matcher, x-build-version) — the exact set
 *     that already works for select-location.
 *
 * FLOW (hyperlocal, like zepto/blinkit):
 *   for each pincode:  POST home/select-location/v2 {lat,lng}  -> storeId   [VALIDATED WORKING]
 *     for each query:  POST search/v2?storeId=.. {query}       -> products  [shape pending live confirmation]
 *   parse MRP / selling price / stock -> rows -> result.json
 *
 * FAIL-SAFE CONTRACT (repo-wide): on ANY failure write a valid result.json (possibly 0
 * rows) and exit 0. review.py marks BROKEN and self-heal retries. Never throw upward.
 *
 * KNOWN BLOCKER (2026-06-10): the priced search/listing endpoints 403 with a 2-cookie
 * session. Leading cause: incomplete cookie export (missing __SW + signed location
 * cookies). Provide the FULL www.swiggy.com cookie set and re-run. searchStore() is
 * isolated + env-overridable so the confirmed request shape (from a browser "copy as
 * cURL") drops in with no structural changes.
 *
 * Useful env overrides:
 *   IM_COOKIES, PINCODES_FILE, OUT_FILE, IM_MAX_PINCODES, IM_QUERIES (comma list),
 *   IM_BRAND_FILTER (default "jivo"; empty = keep all brands), IM_MAX_PAGES,
 *   IM_BUILD_VERSION, IM_WATCHDOG_MS, IM_RESOLVE_ONLY (1 = stop after store-resolve),
 *   IM_SEARCH_URL_TMPL (override endpoint; {store}/{query}/{offset} placeholders).
 */
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const { Throttle } = require('./lib/throttle');

const DIR = __dirname;
const SECRETS = path.join(DIR, 'secrets');
const COOKIE_SRC = process.env.IM_COOKIES || path.join(SECRETS, 'swiggy_cookies.json');
const JAR = path.join(SECRETS, 'cookiejar.txt');
const PFILE = process.env.PINCODES_FILE || path.join(DIR, 'pincodes.json');
const OUT = process.env.OUT_FILE || path.join(DIR, 'result.json');

const MAX_PINCODES = parseInt(process.env.IM_MAX_PINCODES || '12', 10);
const MAX_PAGES = parseInt(process.env.IM_MAX_PAGES || '3', 10);
const QUERIES = (process.env.IM_QUERIES || 'jivo').split(',').map((s) => s.trim()).filter(Boolean);
const BRAND_FILTER = (process.env.IM_BRAND_FILTER ?? 'jivo').toLowerCase();
const BUILD_VERSION = process.env.IM_BUILD_VERSION || '2.341.0';
const WATCHDOG_MS = parseInt(process.env.IM_WATCHDOG_MS || '300000', 10);
const RESOLVE_ONLY = process.env.IM_RESOLVE_ONLY === '1';
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

const throttle = new Throttle({ startDelay: 5000, minDelay: 2500, maxDelay: 60000, targetConcurrency: 1, budget: 80 });
const t0 = Date.now();

// ---------- cookie jar (transplant -> Netscape format for curl -b/-c) ----------
function buildJar() {
  const cookies = JSON.parse(fs.readFileSync(COOKIE_SRC, 'utf8'));
  const lines = ['# Netscape HTTP Cookie File'];
  for (const c of cookies) {
    const dom = c.domain;
    const sub = dom.startsWith('.') ? 'TRUE' : 'FALSE';
    const sec = c.secure ? 'TRUE' : 'FALSE';
    const exp = String(Math.floor(c.expirationDate || 0));
    const pre = c.httpOnly ? '#HttpOnly_' : '';
    lines.push(`${pre}${dom}\t${sub}\t${c.path || '/'}\t${sec}\t${exp}\t${c.name}\t${c.value}`);
  }
  fs.writeFileSync(JAR, lines.join('\n') + '\n');
  return cookies.length;
}

const matcher = () => {
  const cs = '0123456789abcdefg';
  let s = '';
  for (let i = 0; i < 23; i++) s += cs[Math.floor(Math.random() * cs.length)];
  return s;
};

// ---------- curl helper: returns {status, latency, raw, retryAfter} ----------
function curlJson(method, url, body) {
  const hdrFile = path.join(SECRETS, '._hdr');
  const bodyFile = path.join(SECRETS, '._body');
  const args = [
    '-sS', '-m', '25', '--http2', '--compressed', '-A', UA,
    '-H', 'accept: */*', '-H', 'accept-language: en-IN,en;q=0.9',
    '-H', 'content-type: application/json',
    '-H', 'origin: https://www.swiggy.com', '-H', 'referer: https://www.swiggy.com/instamart/',
    '-H', `matcher: ${matcher()}`, '-H', `x-build-version: ${BUILD_VERSION}`,
    '-b', JAR, '-c', JAR, '-D', hdrFile, '-o', bodyFile, '-w', '%{http_code} %{time_total}',
  ];
  if (method === 'POST') { args.push('-X', 'POST'); if (body != null) args.push('--data', body); }
  args.push(url);

  let out = '0 0';
  try { out = execFileSync('curl', args, { encoding: 'utf8', maxBuffer: 1 << 26 }); }
  catch (e) { out = (e.stdout || '0 0').toString(); }

  const [codeStr, timeStr] = out.trim().split(/\s+/);
  const status = parseInt(codeStr, 10) || 0;
  const latency = Math.round((parseFloat(timeStr) || 0) * 1000);
  const hdrs = fs.existsSync(hdrFile) ? fs.readFileSync(hdrFile, 'utf8') : '';
  const raw = fs.existsSync(bodyFile) ? fs.readFileSync(bodyFile, 'utf8') : '';
  const ra = hdrs.match(/^retry-after:\s*(\d+)/im);
  return { status, latency, raw, retryAfter: ra ? parseInt(ra[1], 10) : null };
}

// request with throttle + retry/backoff (honors Retry-After)
async function request(method, url, body, label) {
  let attempt = 0;
  for (;;) {
    await throttle.wait();
    const r = curlJson(method, url, body);
    throttle.observe(r.latency, r.status, r.retryAfter);
    if (r.status === 200) return r;
    if (Throttle.retryable(r.status) && attempt < 4) {
      const waitMs = r.retryAfter ? r.retryAfter * 1000 : Throttle.backoffMs(attempt);
      console.error(`[retry] ${label} HTTP ${r.status} attempt ${attempt + 1} -> wait ${Math.round(waitMs / 1000)}s`);
      await new Promise((res) => setTimeout(res, waitMs));
      attempt++;
      continue;
    }
    return r; // give up; caller treats non-200 as empty
  }
}

// ---------- API calls ----------
async function selectLocation(lat, lng) {
  const body = JSON.stringify({ data: { lat, lng, address: '', addressId: '', annotation: '', clientId: 'INSTAMART-APP' } });
  const r = await request('POST', 'https://www.swiggy.com/api/instamart/home/select-location/v2', body, 'select-location');
  let storeId = null;
  const m = r.raw.match(/storeId=(\d+)/); // store id is embedded in card deeplinks
  if (m) storeId = m[1];
  if (!storeId) {
    try { storeId = findFirst(JSON.parse(r.raw), ['storeId', 'primaryStoreId', 'store_id']); } catch (_) {}
  }
  return { storeId, status: r.status };
}

async function searchStore(storeId, query, offset) {
  const tmpl = process.env.IM_SEARCH_URL_TMPL ||
    'https://www.swiggy.com/api/instamart/search/v2?storeId={store}&primaryStoreId={store}&secondaryStoreId=&offset={offset}&query={query}&clientId=INSTAMART-APP&pageType=INSTAMART_SEARCH_PAGE';
  const url = tmpl.replace(/{store}/g, encodeURIComponent(storeId))
                  .replace('{offset}', String(offset))
                  .replace('{query}', encodeURIComponent(query));
  const body = JSON.stringify({ facets: [], sortAttribute: '', query, search_results_offset: String(offset), page_type: 'INSTAMART_SEARCH_PAGE', is_pre_search_tag: false });
  const r = await request('POST', url, body, `search:${query}`);
  if (r.status !== 200) return { products: [], status: r.status, hasMore: false };
  let json;
  try { json = JSON.parse(r.raw); } catch (_) { return { products: [], status: r.status, hasMore: false }; }
  return { products: parseProducts(json), status: 200, hasMore: detectHasMore(json) };
}

// ---------- parsing (tuned to documented shape; VERIFY against a live priced payload) ----------
function findFirst(o, keys) {
  if (o && typeof o === 'object') {
    if (!Array.isArray(o)) {
      for (const k of keys) if (k in o && (typeof o[k] === 'string' || typeof o[k] === 'number') && String(o[k]).trim() && String(o[k]) !== '0') return String(o[k]);
      for (const v of Object.values(o)) { const r = findFirst(v, keys); if (r) return r; }
    } else { for (const v of o) { const r = findFirst(v, keys); if (r) return r; } }
  }
  return null;
}

function detectHasMore(json) {
  let more = false;
  (function w(o) {
    if (!o || typeof o !== 'object') return;
    if (Array.isArray(o)) { for (const v of o) w(v); return; }
    if (o.hasMore === true) more = true;
    for (const v of Object.values(o)) w(v);
  })(json);
  return more;
}

// money fields appear as number (rupees) or {units} — normalize to a number, else null
function money(v) {
  if (v == null) return null;
  if (typeof v === 'number') return v;
  if (typeof v === 'string' && v.trim() !== '' && !isNaN(+v)) return +v;
  if (typeof v === 'object') { if ('units' in v) return money(v.units); if ('amount' in v) return money(v.amount); }
  return null;
}

function parseProducts(json) {
  const out = [];
  const seen = new Set();
  (function walk(o) {
    if (!o || typeof o !== 'object') return;
    if (Array.isArray(o)) { for (const v of o) walk(v); return; }
    const name = o.display_name || o.name;
    const price = o.price;
    if (name && price && typeof price === 'object' && ('mrp' in price || 'offer_price' in price || 'store_price' in price)) {
      const variants = Array.isArray(o.variations) && o.variations.length ? o.variations : [null];
      for (const v of variants) {
        const p = v && v.price ? v.price : price;
        const packStr = (v && (v.sku_quantity_with_combo || v.quantity)) || o.sku_quantity_with_combo || o.quantity || '';
        const mrp = money(p.mrp);
        const sale = money(p.offer_price ?? p.store_price ?? p.mrp);
        const inStock = (o.in_stock ?? o.available ?? (v && v.in_stock)) ? 1 : 0;
        const key = `${name}|${packStr}|${mrp}|${sale}`;
        if (seen.has(key)) continue;
        seen.add(key);
        out.push({ name: String(name), pack: String(packStr) || null, mrp, sale, inStock,
                   productId: o.product_id || o.id || (v && v.id) || null });
      }
    }
    for (const val of Object.values(o)) walk(val);
  })(json);
  return out;
}

// ---------- row schema (REQUIRED fields enforced by review.py / build_excel.py) ----------
const slug = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
function parseVolMl(s) {
  if (!s) return null; s = String(s).toLowerCase();
  let m = s.match(/(\d+(?:\.\d+)?)\s*(?:l|ltr|litre|liter)\b/); if (m) return Math.round(parseFloat(m[1]) * 1000);
  m = s.match(/(\d+(?:\.\d+)?)\s*ml\b/); if (m) return Math.round(parseFloat(m[1]));
  m = s.match(/(\d+(?:\.\d+)?)\s*(?:kg)\b/); if (m) return Math.round(parseFloat(m[1]) * 1000);
  m = s.match(/(\d+(?:\.\d+)?)\s*(?:g|gm|gram)\b/); if (m) return Math.round(parseFloat(m[1]));
  return null;
}
function toRow(p, pin, storeId) {
  const volMl = parseVolMl(p.pack) || parseVolMl(p.name);
  const sale = p.sale ?? 0, mrp = p.mrp ?? 0;
  const disc = (mrp && sale && mrp > sale) ? +(((mrp - sale) / mrp) * 100).toFixed(1) : null;
  return {
    city: pin.city, pincode: String(pin.pincode), locality: pin.locality || null,
    store_id: storeId || null, store_name: `Instamart ${pin.city}`,
    sku_raw: p.name, canonical: volMl ? `${slug(p.name)}-${volMl}ml` : slug(p.name),
    pack: p.pack || null, vol_ml: volMl || null,
    sale: sale || 0, mrp: mrp || 0, discount_pct: disc,
    per_litre: (volMl && sale) ? +((sale / volMl) * 1000).toFixed(2) : null,
    eta_min: null, in_stock: p.inStock ? 1 : 0,
    product_id: p.productId || null, price_source: 'INSTAMART',
  };
}

// ---------- result.json writer (always valid; SOP contract) ----------
function writeResult(perPin, note) {
  const allRows = perPin.flatMap((p) => p.rows);
  const withJivo = perPin.filter((p) => p.rows.length).length;
  const uniq = new Set(allRows.map((r) => r.canonical)).size;
  const summary = {
    pincodes_total: perPin.length, pincodes_with_jivo: withJivo,
    total_rows: allRows.length, unique_skus: uniq,
    wall_s: +((Date.now() - t0) / 1000).toFixed(1),
    captured_at: new Date().toISOString(), requests: throttle.requests,
  };
  if (note) summary.note = note;
  fs.writeFileSync(OUT, JSON.stringify({ summary, perPin, allRows }, null, 2));
  console.error(`[SUMMARY] ${JSON.stringify(summary)}`);
}

// ---------- main ----------
async function main() {
  const n = buildJar();
  console.error(`[ok] cookie jar built: ${n} cookies from ${path.basename(COOKIE_SRC)}`);
  let pins = JSON.parse(fs.readFileSync(PFILE, 'utf8'));
  if (!Array.isArray(pins)) pins = [];
  pins = pins.slice(0, MAX_PINCODES);
  console.error(`[ok] ${pins.length} pincode(s); queries=[${QUERIES.join(', ')}]; resolveOnly=${RESOLVE_ONLY}`);

  const perPin = [];
  for (const pin of pins) {
    const rows = [];
    let storeId = null;
    try {
      const loc = await selectLocation(pin.lat, pin.lon ?? pin.lng);
      storeId = loc.storeId;
      console.error(`[loc] ${pin.city}/${pin.pincode} -> store=${storeId || 'NONE'} (HTTP ${loc.status})`);
    } catch (e) { console.error(`[loc-err] ${pin.city}: ${e.message}`); }

    if (storeId && !RESOLVE_ONLY) {
      for (const q of QUERIES) {
        for (let page = 0; page < MAX_PAGES; page++) {
          let res;
          try { res = await searchStore(storeId, q, page * 20); }
          catch (e) { console.error(`[search-err] ${q}: ${e.message}`); break; }
          if (res.status !== 200) { console.error(`[search] ${pin.city} "${q}" p${page} HTTP ${res.status} (no data)`); break; }
          let kept = 0;
          for (const p of res.products) {
            if (BRAND_FILTER && !(`${p.name}`.toLowerCase().includes(BRAND_FILTER))) continue;
            rows.push(toRow(p, pin, storeId)); kept++;
          }
          console.error(`[search] ${pin.city} "${q}" p${page}: ${res.products.length} products, ${kept} kept`);
          if (!res.hasMore || res.products.length === 0) break;
        }
      }
    }
    perPin.push({ city: pin.city, pincode: String(pin.pincode), locality: pin.locality || null, store_id: storeId || null, rows });
  }

  writeResult(perPin, RESOLVE_ONLY ? 'resolve-only smoke run (no search)' : undefined);
}

// ---------- watchdog + fail-safe entrypoint ----------
if (require.main === module) {
  const wd = setTimeout(() => {
    console.error(`[watchdog] ${WATCHDOG_MS}ms exceeded — emitting empty result and exiting 0`);
    try { writeResult([], 'watchdog timeout'); } catch (_) {}
    process.exit(0);
  }, WATCHDOG_MS);
  wd.unref?.();

  main().then(() => { clearTimeout(wd); process.exit(0); })
        .catch((e) => {
          console.error('[fatal]', e && e.stack ? e.stack : e);
          try { writeResult([], `fatal: ${e && e.message}`); } catch (_) {}
          clearTimeout(wd); process.exit(0);
        });
}

// exported for offline unit testing of the parser (node -e / test files)
module.exports = { parseProducts, parseVolMl, toRow, money, slug };
