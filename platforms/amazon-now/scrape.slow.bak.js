// ---------------------------------------------------------------------------
// AMAZON NOW scraper.  STATUS: LIVE-capable (2026-05-30) via a TRANSPLANTED
// logged-in session (the VPS datacenter IP cannot pass Amazon's /ap/signin WAF
// captcha — see PLAN.md — so cookies are exported by the user from a clean IP via
// the Cookie-Editor extension and imported with import_cookies.js).
//
// Surface: the `i=nowstore` storefront search (amazon.in/s?k=jivo&i=nowstore).
// Logged-out it 503s; logged-in it returns per-SKU Now price + same-day delivery
// SLOT ("FREE delivery Today 5–7 pm"). We set the delivery PINCODE via the GLOW
// widget per location, then search — so Now availability/price varies per pincode
// (metros serviceable w/ slots, non-metros return 0 = not serviceable).
//
// /dp is deliberately NOT used: even logged-in it shows only the multi-day
// marketplace promise, never the Now offer. The nowstore storefront is the truth.
//
// Output schema matches Blinkit/Zepto so build_excel/predict/review/vault work,
// plus amazon-specific fields (asin, now_slot, serviceable).
//
//   node scrape.js                       # full default pincode set
//   LIMIT=8 node scrape.js               # first 8 pincodes (smoke test)
//   CONCURRENCY=1 node scrape.js         # sequential (default; one shared account)
//   PINCODES_FILE=... OUT_FILE=... node scrape.js
// ---------------------------------------------------------------------------
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const PFILE = process.env.PINCODES_FILE || path.join(__dirname, 'pincodes.json');
const OUTFILE = process.env.OUT_FILE || path.join(__dirname, 'result.json');
const STATE = path.join(__dirname, 'secrets', 'amazon-now.storageState.json');
const QUERIES = (process.env.QUERIES || 'jivo').split('|');
const LIMIT = parseInt(process.env.LIMIT || '0', 10);          // 0 = all
const OFFSET = parseInt(process.env.OFFSET || '0', 10);
// One shared account session -> the active delivery location may be tracked
// server-side, so parallel contexts could collide. Sequential by default (safe).
const CONCURRENCY = parseInt(process.env.CONCURRENCY || '1', 10);
const UA = process.env.UA ||
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let PINCODES = JSON.parse(fs.readFileSync(PFILE, 'utf8'));
if (OFFSET) PINCODES = PINCODES.slice(OFFSET);
if (LIMIT) PINCODES = PINCODES.slice(0, LIMIT);

// products.json: asin -> our catalogue metadata (authoritative pack/category).
const PRODUCTS = {};
try {
  const pj = JSON.parse(fs.readFileSync(path.join(__dirname, 'products.json'), 'utf8'));
  for (const p of pj) if (p.asin) PRODUCTS[p.asin] = p;
} catch (_) { /* products.json optional */ }

// --- price/pack helpers (IDENTICAL to zepto/blinkit so canonical IDs line up) ---
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
// Pull a pack token straight out of an Amazon title ("Jivo Canola Oil 1L",
// "...5 Litre", "...500 ml", "...50 gm"). Falls back to products.json pack.
function packFromTitle(title) {
  if (!title) return '';
  const m = title.toLowerCase().match(/([\d.]+)\s*(ml|l|ltr|litres?|kg|gms?|g)\b/);
  if (!m) return '';
  let u = m[2];
  if (/^gms?$/.test(u)) u = 'g';
  if (/^(litres?|ltr)$/.test(u)) u = 'l';
  return `${m[1]} ${u}`;
}
function numPrice(s) {
  if (!s) return null;
  const n = parseFloat(String(s).replace(/[^\d.]/g, ''));
  return Number.isFinite(n) ? n : null;
}

async function passInterstitial(page) {
  const hit = await page.evaluate(() => /continue shopping/i.test(document.body.innerText || '') && !document.querySelector('#nav-link-accountList')).catch(() => false);
  if (!hit) return;
  try { await page.getByRole('button', { name: /continue shopping/i }).click({ timeout: 6000 }); } catch (_) {}
  await page.waitForLoadState('domcontentloaded', { timeout: 20000 }).catch(() => {});
  await sleep(1500);
}

// Set the delivery pincode via the GLOW widget. Returns the resulting glow text
// (so the caller can confirm it took). Proven in probe_pincode_switch.js.
async function setPincode(page, pin) {
  await page.goto('https://www.amazon.in/?ref_=nav_signin', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await sleep(1200); await passInterstitial(page);
  try {
    await page.click('#nav-global-location-popover-link, #glow-ingress-block', { timeout: 8000 });
    await sleep(1500);
    await page.fill('#GLUXZipUpdateInput', pin, { timeout: 8000 });
    await sleep(400);
    try { await page.click('#GLUXZipUpdate input[type="submit"], #GLUXZipUpdate-announce', { timeout: 5000 }); } catch (_) {}
    await sleep(1600);
    try { await page.click('button[name="glowDoneButton"], .a-popover-footer #GLUXConfirmClose, input[name="glowDoneButton"]', { timeout: 4000 }); } catch (_) {}
    await sleep(1200);
  } catch (e) { return ''; }
  return page.evaluate(() => { const g = document.getElementById('glow-ingress-line2'); return g ? (g.innerText || '').replace(/\s+/g, ' ').trim() : ''; }).catch(() => '');
}

// Search the Now storefront for one query; return raw Jivo cards.
async function searchNow(page, query) {
  const url = `https://www.amazon.in/s?k=${encodeURIComponent(query)}&i=nowstore`;
  let r;
  for (let attempt = 1; attempt <= 3; attempt++) {
    try { r = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 40000 }); }
    catch (e) { return { err: 'nav:' + e.message, items: [] }; }
    await sleep(2000); await passInterstitial(page);
    const blocked = await page.evaluate(() => /503|rush hour|service unavailable/i.test(document.body.innerText || '') && !document.querySelector('[data-component-type="s-search-result"][data-asin]')).catch(() => false);
    if (!blocked) break;
    await sleep(2500 + attempt * 1500);
  }
  const items = await page.evaluate(() => {
    const T = (el) => (el ? (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim() : '');
    const cards = [...document.querySelectorAll('[data-component-type="s-search-result"][data-asin]')].filter((c) => (c.getAttribute('data-asin') || '').length > 3);
    return cards.map((c) => {
      const full = T(c);
      return {
        asin: c.getAttribute('data-asin'),
        // [data-cy="title-recipe"] carries the FULL product name ("JIVO Pomace Olive Oil 5
        // Litre Tin …"); h2 alone is just the brand ("JIVO"), which would collapse every
        // Jivo SKU to one canonical. Fall back through the older title containers.
        title: T(c.querySelector('[data-cy="title-recipe"], h2 a span.a-text-normal, a.a-link-normal .a-text-normal, h2 a span')).slice(0, 160),
        price: T(c.querySelector('.a-price[data-a-color="base"] .a-offscreen, .a-price .a-offscreen')),
        // MRP = the STRUCK-THROUGH original only. The bare ".a-price.a-text-price" also
        // matches the per-unit price ("₹238.60/l"), so require data-a-strike to avoid it.
        mrp: T(c.querySelector('[data-a-strike="true"] .a-offscreen')),
        slot: T(c.querySelector('[class*="delivery" i], .udm-primary-delivery-message')).slice(0, 80),
        oos: /currently unavailable|out of stock|sold out/i.test(full),
        isJivo: /\bjivo\b/i.test(full),
      };
    });
  }).catch(() => []);
  return { http: r ? r.status() : null, items };
}

function toRow(card, rec) {
  const prod = PRODUCTS[card.asin];
  // Trim the marketing tail after the first "|" — the pack/size sits before it, and the
  // tail ("| Chemical-Free Oil for Cooking | …") would bloat the canonical id.
  const fullTitle = card.title || (prod && prod.name) || card.asin;
  const name = fullTitle.split('|')[0].replace(/\s+/g, ' ').trim();
  const pack = packFromTitle(name) || packFromTitle(fullTitle) || (prod && prod.pack ? prod.pack.toLowerCase() : '');
  const sale = numPrice(card.price);
  let mrp = numPrice(card.mrp);
  if (mrp != null && sale != null && mrp < sale) mrp = null; // a real MRP is never below the sale price
  const vol = parseVolMl(pack);
  const slot = card.slot || '';
  return {
    city: rec.city, pincode: rec.pincode, locality: rec.locality,
    store_id: null, store_name: 'Amazon Now',
    asin: card.asin,
    sku_raw: name, canonical: canonical(name, pack), pack,
    vol_ml: vol, sale, mrp,
    discount_pct: (mrp && sale && mrp >= sale) ? Math.round(((mrp - sale) / mrp) * 1000) / 10 : null,
    per_litre: (vol && sale) ? Math.round((sale / (vol / 1000)) * 100) / 100 : null,
    eta_min: null,
    now_slot: slot,
    category: prod ? (prod.category || prod.item) : null,
    in_stock: card.oos ? 0 : 1,
  };
}

async function scrapeOne(page, rec) {
  const t0 = Date.now();
  let rows = [], glow = '', serviceable = false;
  try {
    glow = await setPincode(page, rec.pincode);
    const seen = new Set();
    for (const q of QUERIES) {
      const res = await searchNow(page, q);
      if (res.items && res.items.length) serviceable = true; // storefront returned results = Now serviceable here
      for (const card of (res.items || [])) {
        if (!card.isJivo) continue;                 // keep only genuine Jivo SKUs
        const row = toRow(card, rec);
        if (seen.has(row.canonical)) continue;
        seen.add(row.canonical); rows.push(row);
      }
      await sleep(700 + Math.random() * 600);
    }
  } catch (e) { process.stderr.write(`[err] ${rec.city} ${rec.pincode}: ${e.message}\n`); }
  process.stderr.write(`[ok] ${rec.city} ${rec.pincode} glow="${glow}" serviceable=${serviceable} -> ${rows.length} jivo (${((Date.now() - t0) / 1000).toFixed(1)}s)\n`);
  return { ...rec, store_id: null, store_name: 'Amazon Now', serviceable, glow, rows };
}

async function worker(browser, queue) {
  const ctx = await browser.newContext({
    userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata',
    viewport: { width: 1366, height: 900 }, storageState: STATE,
    extraHTTPHeaders: { 'Accept-Language': 'en-IN,en;q=0.9' },
  });
  await ctx.addInitScript(() => { Object.defineProperty(navigator, 'webdriver', { get: () => undefined }); });
  const page = await ctx.newPage();
  const out = [];
  while (queue.length) {
    const rec = queue.shift();
    if (!rec) break;
    out.push(await scrapeOne(page, rec));
    await sleep(900 + Math.random() * 900);
  }
  await ctx.close().catch(() => {});
  return out;
}

// Preflight: confirm the transplanted session is still logged in. The VPS cannot
// re-login (WAF), so an expired cookie must FAIL LOUDLY (exit 3) and prompt a
// re-export — not silently sweep 332 pincodes of logged-out garbage.
async function checkSession(browser) {
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
  const page = await ctx.newPage();
  let info = { loggedIn: false, greeting: '' };
  try {
    await page.goto('https://www.amazon.in/?ref_=nav_signin', { waitUntil: 'domcontentloaded', timeout: 45000 });
    await sleep(2000); await passInterstitial(page);
    info = await page.evaluate(() => {
      const g = document.querySelector('#nav-link-accountList-nav-line-1, #nav-link-accountList .nav-line-1');
      const t = g ? (g.innerText || '').trim() : '';
      return { loggedIn: /hello,?\s+(?!sign)/i.test(t) && !/sign in/i.test(t), greeting: t };
    });
  } catch (_) { /* treated as not-logged-in */ }
  await ctx.close().catch(() => {});
  return info;
}

(async () => {
  if (!fs.existsSync(STATE)) {
    console.error('FATAL: no session at ' + STATE + ' — run import_cookies.js with a fresh Cookie-Editor export.');
    process.exit(2);
  }
  const t0 = Date.now();
  let browser;
  try { browser = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new', '--disable-blink-features=AutomationControlled'] }); }
  catch (_) { browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }); }

  const sess = await checkSession(browser);
  if (!sess.loggedIn) {
    await browser.close().catch(() => {});
    fs.writeFileSync(path.join(__dirname, 'secrets', 'SESSION_EXPIRED'), new Date().toISOString() + '\n');
    console.error('FATAL: Amazon session EXPIRED (greeting="' + sess.greeting + '"). Re-export cookies (Cookie-Editor) and run import_cookies.js.');
    process.exit(3);
  }
  try { fs.unlinkSync(path.join(__dirname, 'secrets', 'SESSION_EXPIRED')); } catch (_) {}
  process.stderr.write('[session] OK — ' + sess.greeting + '\n');

  const queue = [...PINCODES];
  const workers = Array.from({ length: Math.min(CONCURRENCY, queue.length) }, () => worker(browser, queue));
  const perPinNested = await Promise.all(workers);
  const perPin = perPinNested.flat();
  await browser.close().catch(() => {});

  const allRows = perPin.flatMap((p) => p.rows);
  const summary = {
    pincodes_total: PINCODES.length,
    pincodes_serviceable: perPin.filter((p) => p.serviceable).length,
    pincodes_with_jivo: perPin.filter((p) => p.rows.length > 0).length,
    total_rows: allRows.length,
    unique_skus: new Set(allRows.map((r) => r.canonical)).size,
    wall_s: Math.round((Date.now() - t0) / 1000),
    captured_at: new Date().toISOString(),
  };
  process.stderr.write('[SUMMARY] ' + JSON.stringify(summary) + '\n');
  fs.writeFileSync(OUTFILE, JSON.stringify({ summary, perPin, allRows }, null, 2));
  console.log(JSON.stringify(summary));
})();
