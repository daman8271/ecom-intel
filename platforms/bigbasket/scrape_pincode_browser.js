// BigBasket pincode-wise scraper via the logged-in browser session.
//
// This is intentionally separate from scrape.js:
//   - scrape.js keeps producing the national BigBasket report.
//   - this file produces the pincode-shaped JSON for build_excel_pincode.py.
//
// No QuickCommerce API is used here. The flow mirrors the real website: resolve a
// pincode through BigBasket's places endpoints, set the logged-in account's current
// partial delivery address, then fetch listing-svc from inside the same browser.

const { chromium } = require('playwright-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
const fs = require('fs');
const path = require('path');
const { loadBBCookies, DEFAULT_COOKIE_PATH } = require('./import_cookies');
const { fetchQuery, verifyMember } = require('./scrape');

chromium.use(StealthPlugin());

const HERE = __dirname;
const OUTFILE = process.env.OUT_FILE || path.join(HERE, 'result_pincode.browser.json');
const COOKIE_PATH = process.env.BB_COOKIE_PATH || DEFAULT_COOKIE_PATH;
const PINCODES_FILE = process.env.PINCODES_FILE || path.join(HERE, 'pincodes_jivo.json');
const PINCODE_LIMIT = parseInt(process.env.BB_PINCODE_LIMIT || '0', 10);
const PINCODE_OFFSET = parseInt(process.env.BB_PINCODE_OFFSET || '0', 10);
const WATCHDOG_MS = parseInt(process.env.BB_PINCODE_WATCHDOG_MS || '14400000', 10);
const PIN_DELAY_MS = parseInt(process.env.BB_PINCODE_DELAY_MS || '1500', 10);
const QUERY_DELAY_MS = parseInt(process.env.BB_PINCODE_QUERY_DELAY_MS || '2500', 10);
const MIN_REQUIRED_ENV = parseInt(process.env.BB_PINCODE_MIN_REQUIRED || '0', 10);
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

const QUERIES = (process.env.BB_QUERIES
  ? process.env.BB_QUERIES.split(',')
  : ['jivo']
).map((s) => s.trim()).filter(Boolean);

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function readPincodes() {
  const raw = JSON.parse(fs.readFileSync(PINCODES_FILE, 'utf8'));
  if (!Array.isArray(raw)) throw new Error(`pincode file must be a JSON array: ${PINCODES_FILE}`);
  const start = Math.max(0, PINCODE_OFFSET || 0);
  const end = PINCODE_LIMIT > 0 ? start + PINCODE_LIMIT : undefined;
  return { target: raw.length, pins: raw.slice(start, end) };
}

function r1(n) {
  return Math.round(n * 10) / 10;
}

function summarize(perPin, target, t0, opts = {}) {
  const allRows = perPin.flatMap((p) => p.rows || []);
  const bySku = new Map();
  for (const r of allRows) {
    if (!bySku.has(r.canonical)) bySku.set(r.canonical, []);
    bySku.get(r.canonical).push(r.sale);
  }
  let varied = 0;
  for (const prices of bySku.values()) {
    const vals = [...new Set(prices.filter((v) => v != null).map((v) => Number(v).toFixed(2)))];
    if (vals.length > 1) varied += 1;
  }
  const minRequired = MIN_REQUIRED_ENV > 0 ? MIN_REQUIRED_ENV : Math.ceil(target * 0.75);
  return {
    pincodes_total: perPin.length,
    pincodes_with_jivo: perPin.filter((p) => (p.rows || []).length > 0).length,
    unique_skus: bySku.size,
    total_rows: allRows.length,
    skus_with_price_variance: varied,
    verdict: varied ? 'HYPERLOCAL - Jivo price varies by pincode' : 'NO PRICE VARIANCE DETECTED in captured pincodes',
    source: 'BigBasket logged-in browser pincode',
    queries: QUERIES,
    session_ok: !!opts.sessionOk,
    member: !!opts.member,
    pricing_mode: opts.member ? 'member' : 'guest',
    member_id: opts.memberInfo ? opts.memberInfo.id : null,
    member_email: opts.memberInfo ? opts.memberInfo.email : null,
    member_is_bbstar: opts.memberInfo ? opts.memberInfo.is_bbstar : null,
    wall_s: Math.round((Date.now() - t0) / 1000),
    captured_at: new Date().toISOString(),
    pincodes_target: target,
    pincode_pull_complete: perPin.length >= target && perPin.every((p) => p.set_status === 'ok'),
    min_pincodes_required: minRequired,
    coverage_ok: perPin.length >= minRequired,
  };
}

function writeResult(perPin, target, t0, opts = {}) {
  const summary = summarize(perPin, target, t0, opts);
  const allRows = perPin.flatMap((p) => p.rows || []);
  const payload = { summary, perPin, allRows };
  fs.mkdirSync(path.dirname(OUTFILE), { recursive: true });
  const tmp = `${OUTFILE}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(payload, null, 2));
  fs.renameSync(tmp, OUTFILE);
  process.stderr.write('[SUMMARY] ' + JSON.stringify(summary) + '\n');
  return summary;
}

async function openSession(browser) {
  const loaded = loadBBCookies(COOKIE_PATH);
  process.stderr.write(`[cookies] loaded ${loaded.cookies.length} cookies from secrets (critical: ${loaded.haveCritical.join(',') || 'NONE'})\n`);
  if (loaded.missing.length) process.stderr.write(`[cookies] WARNING missing critical: ${loaded.missing.join(',')}\n`);

  const ctx = await browser.newContext({
    userAgent: UA,
    locale: 'en-IN',
    timezoneId: 'Asia/Kolkata',
    viewport: { width: 1280, height: 900 },
    extraHTTPHeaders: { 'accept-language': 'en-IN,en;q=0.9' },
  });
  await ctx.addCookies(loaded.cookies);
  await ctx.route('**/*', (route) => {
    const t = route.request().resourceType();
    if (['image', 'font', 'media'].includes(t)) return route.abort();
    return route.continue();
  });

  const page = await ctx.newPage();
  let ok = false;
  for (let i = 0; i < 3 && !ok; i += 1) {
    try {
      const resp = await page.goto('https://www.bigbasket.com/', { waitUntil: 'domcontentloaded', timeout: 45000 });
      const status = resp ? resp.status() : 0;
      if (status === 200) ok = true;
      else process.stderr.write(`[warn] homepage status ${status} (try ${i + 1}/3)\n`);
    } catch (e) {
      process.stderr.write(`[warn] homepage error "${e.message}" (try ${i + 1}/3)\n`);
    }
    if (!ok) await page.waitForTimeout(1500 + Math.random() * 1500);
  }
  if (ok) await page.waitForTimeout(2500);

  const v = ok ? await verifyMember(page) : { member: false, info: null };
  if (!v.member) {
    if (!loaded.loggedIn) throw new Error('BigBasket cookie file did not include the logged-in auth token');
    process.stderr.write('[member] header check did not return member_info; continuing with auth cookies and validating through address POST per pincode\n');
    return { ctx, page, ok, member: true, memberInfo: null };
  }
  return { ctx, page, ok, member: v.member, memberInfo: v.info };
}

async function setPincode(page, pin) {
  return page.evaluate(async ({ pin }) => {
    function parseCookies() {
      return Object.fromEntries(document.cookie.split(';').map((s) => {
        const i = s.indexOf('=');
        if (i < 0) return [s.trim(), ''];
        return [decodeURIComponent(s.slice(0, i).trim()), decodeURIComponent(s.slice(i + 1))];
      }).filter((x) => x[0]));
    }
    async function readJson(resp) {
      const text = await resp.text();
      if (!text) return null;
      try { return JSON.parse(text); } catch (_) { return { __raw: text.slice(0, 200) }; }
    }
    function pickPrediction(predictions, expectedPin, expectedCity) {
      const city = String(expectedCity || '').toLowerCase();
      const scored = predictions.map((p, idx) => {
        const text = `${p.description || ''} ${p.mainText || ''} ${p.secondaryText || ''}`.toLowerCase();
        let score = 0;
        if (text.includes(String(expectedPin))) score += 5;
        if (city && text.includes(city)) score += 3;
        if (text.includes('india')) score += 1;
        return { p, idx, score };
      });
      scored.sort((a, b) => b.score - a.score || a.idx - b.idx);
      return scored[0] && scored[0].p;
    }

    const token = crypto.randomUUID();
    const common = {
      accept: 'application/json, text/plain, */*',
      'content-type': 'application/json',
      'x-channel': 'BB-WEB',
      'x-caller': 'UI-KIRK',
      'x-requested-with': 'XMLHttpRequest',
      'common-client-static-version': '101',
      referer: '',
    };
    const pincode = String(pin.pincode);
    const autoResp = await fetch(`/places/v1/places/autocomplete/?inputText=${encodeURIComponent(pincode)}&token=${token}`, {
      headers: { ...common, 'x-entry-context': 'bb-b2c', 'x-entry-context-id': '100' },
    });
    const auto = await readJson(autoResp);
    if (!autoResp.ok) return { ok: false, stage: 'autocomplete', status: autoResp.status, detail: auto };
    const predictions = (auto && auto.predictions) || [];
    const pick = pickPrediction(predictions, pincode, pin.city);
    const placeId = pick && (pick.placeId || pick.place_id || pick.id);
    let lat = null;
    let lng = null;
    let chosen = pick && pick.description;
    if (placeId) {
      const detResp = await fetch(`/places/v1/places/details/?placeId=${encodeURIComponent(placeId)}&token=${token}&xArm=1004&yArm=252`, {
        headers: { ...common, 'x-entry-context': 'bb-b2c', 'x-entry-context-id': '100' },
      });
      const det = await readJson(detResp);
      if (!detResp.ok) return { ok: false, stage: 'details', status: detResp.status, detail: det };
      const loc = det && det.geometry && det.geometry.location;
      lat = Number(loc && (loc.lat || loc.latitude));
      lng = Number(loc && (loc.lng || loc.longitude));
    } else {
      lat = Number(pin.lat);
      lng = Number(pin.lon != null ? pin.lon : pin.lng);
      chosen = `config:${pincode}`;
    }
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      return { ok: false, stage: 'details', status: placeId ? 200 : autoResp.status, detail: 'no lat/lng' };
    }

    const before = parseCookies();
    const serviceResp = await fetch(`/ui-svc/v1/serviceable/?lat=${encodeURIComponent(lat)}&lng=${encodeURIComponent(lng)}&send_all_serviceability=true`, {
      headers: {
        ...common,
        'x-entry-context': before.xentrycontext || 'bb-b2c',
        'x-entry-context-id': before.xentrycontextid || '100',
        'x-csurftoken': before.csurftoken || before.csrftoken || '',
      },
    });
    const service = await readJson(serviceResp);
    if (!serviceResp.ok) return { ok: false, stage: 'serviceable', status: serviceResp.status, detail: service };

    const mid = parseCookies();
    const addrResp = await fetch('/member-svc/v2/address/', {
      method: 'POST',
      credentials: 'include',
      headers: {
        ...common,
        'x-entry-context': 'bb-b2c',
        'x-entry-context-id': '100',
        'x-csurftoken': mid.csurftoken || mid.csrftoken || '',
      },
      body: JSON.stringify({ lat, lng, is_partial: true, set_current_address: true }),
    });
    const addr = await readJson(addrResp);
    if (!addrResp.ok) return { ok: false, stage: 'address', status: addrResp.status, detail: addr };

    const responseCookies = (addr && addr.cookies) || {};
    const locationCookieNames = new Set([
      '_bb_cid', '_bb_pin_code', '_bb_lat_long', '_bb_sa_ids', '_bb_cda_sa_info',
      '_bb_addressinfo', '_bb_visaddr', '_bb_hid', '_bb_nhid', '_bb_dsid',
      '_bb_dsevid', '_bb_locSrc', 'xentrycontext', 'xentrycontextid',
      'jentrycontextid', 'is_global', 'is_integrated_sa', 'is_subscribe_sa',
      'isintegratedsa',
    ]);
    for (const [name, value] of Object.entries(responseCookies)) {
      if (!locationCookieNames.has(name) || value == null || value === '') continue;
      document.cookie = `${encodeURIComponent(name)}=${encodeURIComponent(String(value))}; path=/; domain=.bigbasket.com`;
    }

    await new Promise((resolve) => setTimeout(resolve, 1200));
    const after = parseCookies();
    const places = (service && service.places_info) || {};
    return {
      ok: true,
      stage: 'done',
      status: addrResp.status,
      chosen: chosen || `${pincode}`,
      lat,
      lng,
      requested_city: pin.city || '',
      resolved_city: addr && (addr.city_name || addr.city) || places.city || '',
      city: pin.city || addr && (addr.city_name || addr.city) || places.city || '',
      pincode,
      resolved_pincode: addr && (addr.pin || addr.pincode) || places.pincode || pincode,
      requested_locality: pin.locality || '',
      resolved_locality: addr && addr.area || places.area || places.locTitle || '',
      locality: pin.locality || addr && addr.area || places.area || places.locTitle || '',
      serving_sa: responseCookies._bb_sa_ids || after._bb_sa_ids || '',
      entry_context: responseCookies.xentrycontext || after.xentrycontext || '',
      entry_context_id: responseCookies.xentrycontextid || after.xentrycontextid || '',
    };
  }, { pin });
}

async function fetchRowsForPin(page, loc) {
  const rows = [];
  const seen = new Set();
  for (const q of QUERIES) {
    let qr = [];
    try {
      qr = await fetchQuery(page, q);
    } catch (e) {
      process.stderr.write(`[err] ${loc.pincode} q="${q}": ${e.message}\n`);
    }
    for (const r of qr) {
      const key = r.sku_id || r.canonical;
      if (seen.has(key)) continue;
      seen.add(key);
      rows.push({
        ...r,
        city: loc.city || '',
        pincode: String(loc.pincode || ''),
        requested_city: loc.requested_city || loc.city || '',
        resolved_city: loc.resolved_city || '',
        resolved_pincode: loc.resolved_pincode || '',
        requested_locality: loc.requested_locality || loc.locality || '',
        resolved_locality: loc.resolved_locality || '',
        locality: loc.locality || '',
        store_id: loc.serving_sa || '',
        store_name: 'BigBasket',
      });
    }
    await page.waitForTimeout(QUERY_DELAY_MS + Math.random() * 1000);
  }
  return rows;
}

const T0 = Date.now();
let DONE = false;
let latestPerPin = [];
let latestTarget = 0;
let latestOpts = {};
const watchdog = setTimeout(() => {
  if (DONE) return;
  DONE = true;
  process.stderr.write(`[FATAL] watchdog: pincode scrape exceeded ${WATCHDOG_MS}ms - writing partial result\n`);
  try { writeResult(latestPerPin, latestTarget, T0, latestOpts); } catch (_) {}
  process.exit(0);
}, WATCHDOG_MS);

(async () => {
  const { pins, target } = readPincodes();
  latestTarget = target;
  process.stderr.write(`[pins] loaded ${pins.length}/${target} pincodes from ${PINCODES_FILE}\n`);

  const browser = await chromium.launch({
    headless: true,
    timeout: 60000,
    executablePath: require('playwright').chromium.executablePath(),
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-blink-features=AutomationControlled'],
  });

  let ctx = null;
  try {
    const session = await openSession(browser);
    ctx = session.ctx;
    latestOpts = { sessionOk: session.ok, member: session.member, memberInfo: session.memberInfo };

    for (let i = 0; i < pins.length; i += 1) {
      const pin = pins[i];
      const pincode = String(pin.pincode || '');
      const base = {
        city: pin.city || '',
        pincode,
        locality: pin.locality || '',
        tier: pin.tier || 0,
        store_id: '',
        store_name: 'BigBasket',
        set_status: 'pending',
        fetch_ok: false,
        serving_sa: '',
        rows: [],
      };
      process.stderr.write(`[pin] ${i + 1}/${pins.length} ${pincode} ${pin.city || ''}\n`);
      try {
        const loc = await setPincode(session.page, pin);
        if (!loc.ok) {
          base.set_status = `failed:${loc.stage}:${loc.status || 0}`;
          base.error = typeof loc.detail === 'string' ? loc.detail : JSON.stringify(loc.detail || {}).slice(0, 300);
          process.stderr.write(`[warn] ${pincode} location set failed: ${base.set_status}\n`);
        } else {
          base.set_status = 'ok';
          base.requested_city = pin.city || base.city;
          base.resolved_city = loc.resolved_city || '';
          base.city = pin.city || base.city;
          base.pincode = String(loc.pincode || base.pincode);
          base.resolved_pincode = loc.resolved_pincode || '';
          base.requested_locality = pin.locality || base.locality;
          base.resolved_locality = loc.resolved_locality || '';
          base.locality = pin.locality || base.locality;
          base.store_id = loc.serving_sa || '';
          base.serving_sa = loc.serving_sa || '';
          base.entry_context = loc.entry_context || '';
          base.entry_context_id = loc.entry_context_id || '';
          if (base.resolved_pincode && base.resolved_pincode !== base.pincode) {
            process.stderr.write(`[warn] ${pincode} resolved as ${base.resolved_pincode}${base.resolved_city ? ` ${base.resolved_city}` : ''}; keeping requested pincode for report\n`);
          }
          base.rows = await fetchRowsForPin(session.page, base);
          base.fetch_ok = true;
          process.stderr.write(`[ok] ${pincode} -> ${base.rows.length} Jivo rows (sa=${base.serving_sa || '-'})\n`);
        }
      } catch (e) {
        base.set_status = 'failed:exception';
        base.error = e.message;
        process.stderr.write(`[err] ${pincode}: ${e.message}\n`);
      }
      latestPerPin.push(base);
      writeResult(latestPerPin, target, T0, latestOpts);
      await sleep(PIN_DELAY_MS + Math.random() * 1000);
    }
  } finally {
    if (ctx) { try { await ctx.close(); } catch (_) {} }
    try { await browser.close(); } catch (_) {}
  }

  DONE = true;
  clearTimeout(watchdog);
  const summary = writeResult(latestPerPin, latestTarget, T0, latestOpts);
  console.log(JSON.stringify(summary));
})().catch((e) => {
  process.stderr.write(`[FATAL] ${e && e.message}\n`);
  if (!DONE) {
    DONE = true;
    clearTimeout(watchdog);
    try { writeResult(latestPerPin, latestTarget, T0, latestOpts); } catch (_) {}
  }
  process.exit(0);
});
