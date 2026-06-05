// Flipkart Minutes scraper — DIRECT-API mode (ridiculously fast).
//
// Flipkart binds the hyperlocal session to a browser-minted `T` fingerprint cookie, so a guest
// can't hit the API directly. We transplant a LOGGED-IN session (cookies exported on the user's
// clean machine via Cookie-Editor -> import_cookies.js -> secrets/flipkart-minutes.storageState.json).
// With that session, the whole flow is two fast JSON POSTs per pincode through Flipkart's BFF:
//   1) /api/4/location/update          (set the delivery pincode for this context)
//   2) /api/4/page/fetch  pageUri=/search?q=jivo&marketplace=HYPERLOCAL   (structured products)
// We run a pool of isolated browser contexts (each its own cookie jar -> no location cross-talk),
// each looping its share of the 345 pincodes via in-page fetch. ~30s for 345 vs ~37 min for the
// browser DOM flow, AND cleaner data (exact sale/MRP/per-litre/stock/pid from JSON).
//
// ROBUSTNESS: if the session is missing or expired, we fall back to scrape.browser.js (the
// login-free Playwright DOM scraper) so the cron never goes dark — and warn to re-export cookies.
//
// Env: FKM_CONCURRENCY (default 10) · PINCODES_FILE · OUT_FILE
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const PFILE = process.env.PINCODES_FILE || path.join(__dirname, 'pincodes.json');
const PINCODES = JSON.parse(fs.readFileSync(PFILE, 'utf8'));
const CONCURRENCY = parseInt(process.env.FKM_CONCURRENCY || '10', 10);
const OUT = process.env.OUT_FILE || path.join(__dirname, 'result.json');
const STATE = path.join(__dirname, 'secrets', 'flipkart-minutes.storageState.json');
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 FKUA/msite/0.0.4/msite/Mobile';

// addressInfo.state for the 26 cities in the pincode grid (location/update wants a state).
const STATE_OF = {
  Bengaluru: 'Karnataka', Mysuru: 'Karnataka', Bhopal: 'Madhya Pradesh', Indore: 'Madhya Pradesh',
  Chandigarh: 'Chandigarh', Delhi: 'Delhi', Faridabad: 'Haryana', Gurgaon: 'Haryana',
  Ghaziabad: 'Uttar Pradesh', Noida: 'Uttar Pradesh', Kanpur: 'Uttar Pradesh', Lucknow: 'Uttar Pradesh',
  Jaipur: 'Rajasthan', Kolkata: 'West Bengal', Ludhiana: 'Punjab', Mumbai: 'Maharashtra',
  Pune: 'Maharashtra', Nagpur: 'Maharashtra', Surat: 'Gujarat', Ahmedabad: 'Gujarat',
  Vadodara: 'Gujarat', Chennai: 'Tamil Nadu', Coimbatore: 'Tamil Nadu', Hyderabad: 'Telangana',
  Patna: 'Bihar', Visakhapatnam: 'Andhra Pradesh',
};

function fallbackToBrowser(reason) {
  process.stderr.write(`[fkm-api] ${reason}\n[fkm-api] FALLING BACK to browser scraper (scrape.browser.js). Re-export Flipkart cookies (import_cookies.js) to restore fast mode.\n`);
  try {
    require('child_process').execFileSync('node', [path.join(__dirname, 'scrape.browser.js')],
      { stdio: 'inherit', env: process.env });
  } catch (e) { process.stderr.write('[fkm-api] browser fallback also failed: ' + e.message + '\n'); process.exit(1); }
  process.exit(0);
}

if (!fs.existsSync(STATE)) fallbackToBrowser('no logged-in session at secrets/flipkart-minutes.storageState.json');

function dcN() {
  try {
    const at = JSON.parse(fs.readFileSync(STATE, 'utf8')).cookies.find((c) => c.name === 'at');
    const z = JSON.parse(Buffer.from(at.value.split('.')[1], 'base64').toString()).z;
    return { CH: 1, HYD: 2, MUM: 3, KOL: 4 }[z] || 2;
  } catch (_) { return 2; }
}
const N = dcN();
const LOC_URL = `https://${N}.rome.api.flipkart.com/api/4/location/update`;
const SEARCH_URL = `https://${N}.rome.api.flipkart.com/api/4/page/fetch?cacheFirst=false`;

// ml for one "<number> <unit>" token. l/ltr/litre/kg -> *1000; ml/g -> as-is.
function unitMl(n, u) {
  if (u === 'ml' || u === 'g') return n;
  if (u === 'l' || u === 'ltr' || u === 'litre' || u === 'kg') return n * 1000;
  return null;
}
// TOTAL pack volume in ml. Combo-aware: a multiplicative pack like "2 x 1 L" is
// 2 * 1L = 2000 ml. The old regex matched only the first "1 L" and silently dropped
// the "2 x" multiplier, so 2L combos were recorded as 1000 ml (and, when the API
// per-litre was absent, the Rs/L fallback came out 2x too high).
function parseVolMl(pack) {
  if (!pack) return null;
  const s = pack.toLowerCase();
  const combo = s.match(/([\d.]+)\s*[x×*]\s*([\d.]+)\s*(ml|l|ltr|litre|kg|g)/);
  if (combo) {
    const each = unitMl(parseFloat(combo[2]), combo[3]);
    return each != null ? parseFloat(combo[1]) * each : null;
  }
  const m = s.match(/([\d.]+)\s*(ml|l|ltr|litre|kg|g)/);
  if (!m) return null;
  return unitMl(parseFloat(m[1]), m[2]);
}
function canonical(name, pack) {
  const base = (name || '').toLowerCase()
    .replace(/\(.*?\)/g, '').replace(/[^a-z0-9 ]/g, '')
    .replace(/\s+/g, ' ').trim().replace(/\s/g, '-');
  const vol = parseVolMl(pack);
  const volTag = vol ? (vol >= 1000 ? (vol / 1000) + 'l' : vol + 'ml') : 'na';
  return `${base}-${volTag}`.replace(/--+/g, '-');
}

// POST a Flipkart BFF call from inside the page (inherits the transplanted cookies + DC routing).
async function api(page, url, body) {
  return page.evaluate(async ({ url, body }) => {
    try {
      const r = await fetch(url, {
        method: 'POST', credentials: 'include',
        headers: { flipkart_secure: 'true', 'content-type': 'application/json',
          'accept-language': 'en-IN,en;q=0.9', 'x-user-agent': navigator.userAgent },
        body: JSON.stringify(body),
      });
      const t = await r.text(); let j = null; try { j = JSON.parse(t); } catch (_) {}
      return { status: r.status, json: j };
    } catch (e) { return { status: -1, error: String(e) }; }
  }, { url, body });
}

function parseProducts(searchJson, rec) {
  const rows = [];
  const slots = ((searchJson && (searchJson.RESPONSE || searchJson).slots)) || [];
  for (const s of slots) {
    const ps = (((s.widget || {}).data || {}).products) || [];
    for (const p of ps) {
      const v = ((p.productInfo || {}).value) || {};
      const act = (p.productInfo || {}).action || {};
      const title = ((v.titles || {}).title) || '';
      if (!/jivo/i.test(title) && !/jivo/i.test(v.productBrand || '')) continue;
      const pack = ((v.titles || {}).subtitle) || '';
      const name = title.replace(/\(pack of \d+\)/i, '').replace(/\s+/g, ' ').trim();
      const pricing = v.pricing || {};
      const sale = (pricing.finalPrice || {}).value;
      const mrpEntry = (pricing.prices || []).find((x) => x.priceType === 'MRP');
      // No MRP from the API (e.g. some combo packs) -> leave it null. Do NOT fabricate
      // mrp = sale: that invents a phantom MRP and a fake 0% "discount" on a real SKU.
      const mrp = mrpEntry ? mrpEntry.value : null;
      if (!/jivo/i.test(name) || !sale) continue;
      // Discount is undefined without an MRP basis -> null (not 0) when mrp is absent.
      const disc = (mrp == null) ? null
        : (typeof pricing.totalDiscount === 'number') ? pricing.totalDiscount
        : (mrp && sale && mrp >= sale ? Math.round(((mrp - sale) / mrp) * 1000) / 10 : null);
      const vol = parseVolMl(pack);
      const ppu = ((pricing.pricePerUnit || {}).pivotQualifier === 'L') ? (pricing.pricePerUnit || {}).pricePerUnit : null;
      const storeId = (((act.params || {}).shopId) || [])[0] || '';
      // ---- listing identity (ADDITIVE, fail-safe): pid + PDP url for the SKU map ----
      // productInfo.action carries the product navigation target. Evidence: action.params
      // values are arrays (shopId above); the PDP url form is /…/p/itm…?pid=<PID>&… and the
      // generic https://www.flipkart.com/product/p/itme?pid=<PID> resolves (both proven in
      // tools/pricematch/fragments/map-flipkart.json). Field names defensive: several
      // candidate paths, first hit wins; on ANY error the row is built exactly as before
      // (keys simply omitted).
      let fkPid = '';
      let listingUrl = '';
      try {
        // primitives only — a non-string/number candidate (object/bool/etc.) is junk, not a pid
        const first = (x) => {
          if (Array.isArray(x)) x = x.length ? x[0] : null;
          return (typeof x === 'string' || typeof x === 'number') ? String(x) : '';
        };
        // pid shape gate (e.g. GHEHHZBQJBNVZGGQ), applied PER candidate so a junk
        // candidate falls through to the next instead of killing the whole chain.
        // itm…/lst… are Flipkart PAGE/LISTING ids (16-char alnum — they'd pass the
        // shape gate) but are NOT product pids; never record one (W4 review ruling).
        const pidOk = (s) => (/^[A-Za-z0-9]{8,32}$/.test(s) && !/^(itm|lst)/i.test(s)) ? s : '';
        const ap = act.params || {};
        const aurl = typeof act.url === 'string' ? act.url : '';
        fkPid = pidOk(first(ap.pid)) || pidOk(first(ap.productId))
          || pidOk((aurl.match(/[?&]pid=([A-Za-z0-9]+)/) || [])[1] || '')
          || pidOk(first(v.id)) || pidOk(first(v.productId)) || '';
        if (aurl) listingUrl = /^https?:\/\//i.test(aurl) ? aurl : 'https://www.flipkart.com' + (aurl.startsWith('/') ? '' : '/') + aurl;
        else if (fkPid) listingUrl = 'https://www.flipkart.com/product/p/itme?pid=' + fkPid;
      } catch (_) { fkPid = ''; listingUrl = ''; }
      rows.push({
        city: rec.city, pincode: rec.pincode, locality: rec.locality,
        store_id: storeId, store_name: storeId,
        sku_raw: name, canonical: canonical(name, pack), pack,
        vol_ml: vol, sale, mrp, discount_pct: disc,
        per_litre: ppu != null ? ppu : (vol ? Math.round((sale / (vol / 1000)) * 100) / 100 : null),
        eta_min: null, in_stock: ((v.availability || {}).displayState === 'IN_STOCK') ? 1 : 0,
        ...((fkPid || listingUrl) ? { fk_pid: fkPid, listing_url: listingUrl } : {}),
      });
    }
  }
  const dd = new Map();
  for (const r of rows) { const k = `${r.store_id}|${r.canonical}`; if (!dd.has(k)) dd.set(k, r); }
  return [...dd.values()];
}

async function scrapePincode(page, rec) {
  const locBody = {
    geoLocation: { latitude: String(rec.lat), longitude: String(rec.lon) },
    addressInfo: { addressLine1: rec.locality || rec.city, city: rec.city, state: STATE_OF[rec.city] || '', pincode: String(rec.pincode) },
    redirectionUrl: '/flipkart-minutes-store?marketplace=HYPERLOCAL', marketplace: 'HYPERLOCAL',
  };
  const searchBody = {
    pageUri: '/search?q=jivo&marketplace=HYPERLOCAL',
    locationContext: { pincode: parseInt(rec.pincode, 10), changed: false },
    pageContext: { trackingContext: { context: { eVar51: 'direct_browse', eVar61: 'direct_browse' } }, fetchSeoData: true, networkSpeed: 9400 },
    requestContext: { type: 'BROWSE_PAGE' },
  };
  let serviceable = false;
  for (let attempt = 1; attempt <= 2; attempt++) {
    const loc = await api(page, LOC_URL, locBody);
    serviceable = loc.status === 200;
    const srch = await api(page, SEARCH_URL, searchBody);
    const redir = (((srch.json && (srch.json.RESPONSE || srch.json).pageMeta) || {}).redirectionObject || {}).statusCode;
    if (redir === 302) { if (attempt < 2) { await page.waitForTimeout(600); continue; } return { ...rec, serviceable: false, store_id: '', store_name: '', rows: [] }; }
    const rows = parseProducts(srch.json, rec);
    const sid = (rows[0] || {}).store_id || '';
    return { ...rec, serviceable: true, store_id: sid, store_name: sid, rows };
  }
  return { ...rec, serviceable, store_id: '', store_name: '', rows: [] };
}

async function newCtxPage(browser) {
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', storageState: STATE });
  await ctx.route('**/*', (route) => {
    const t = route.request().resourceType();
    if (['image', 'font', 'media', 'stylesheet'].includes(t)) return route.abort();
    return route.continue();
  });
  const page = await ctx.newPage();
  // Load the logged-in homepage once: establishes flipkart.com origin (for credentialed fetch)
  // and lets Flipkart refresh the short-lived `at` from the long-lived `rt` if needed.
  await page.goto('https://www.flipkart.com/', { waitUntil: 'domcontentloaded', timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(800);
  return { ctx, page };
}

(async () => {
  let browser;
  try { browser = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox'] }); }
  catch (_) { browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] }); }
  const t0 = Date.now();

  // Health check: a known-good pincode must return Jivo, else the session is dead -> fall back.
  const hc = await newCtxPage(browser);
  const probe = await scrapePincode(hc.page, { city: 'Noida', pincode: '201304', locality: 'Sector 106', lat: 28.5355, lon: 77.391 });
  await hc.ctx.close();
  if (probe.rows.length === 0) { await browser.close(); fallbackToBrowser('session health-check failed (pincode 201304 returned no Jivo — cookies likely expired)'); }

  // Partition pincodes round-robin across CONCURRENCY isolated contexts.
  const buckets = Array.from({ length: CONCURRENCY }, () => []);
  PINCODES.forEach((p, i) => buckets[i % CONCURRENCY].push(p));
  const perPin = [];
  await Promise.all(buckets.map(async (bucket) => {
    if (!bucket.length) return;
    const { ctx, page } = await newCtxPage(browser);
    for (const rec of bucket) {
      try { perPin.push(await scrapePincode(page, rec)); }
      catch (e) { process.stderr.write(`[err] ${rec.city} ${rec.pincode}: ${e.message}\n`); perPin.push({ ...rec, serviceable: false, store_id: '', store_name: '', rows: [] }); }
    }
    await ctx.close();
  }));
  await browser.close();

  perPin.sort((a, b) => String(a.pincode).localeCompare(String(b.pincode)));
  const allRows = perPin.flatMap((p) => p.rows);
  const summary = {
    pincodes_total: PINCODES.length,
    pincodes_serviceable: perPin.filter((p) => p.serviceable).length,
    pincodes_with_jivo: perPin.filter((p) => p.rows.length > 0).length,
    total_rows: allRows.length,
    unique_skus: new Set(allRows.map((r) => r.canonical)).size,
    wall_s: Math.round((Date.now() - t0) / 1000),
    captured_at: new Date().toISOString(),
    mode: 'api',
  };
  process.stderr.write('[SUMMARY] ' + JSON.stringify(summary) + '\n');
  fs.writeFileSync(OUT, JSON.stringify({ summary, perPin, allRows }, null, 2));
  console.log(JSON.stringify(summary));
})().catch((e) => { fallbackToBrowser('api scraper crashed: ' + e.message); });
