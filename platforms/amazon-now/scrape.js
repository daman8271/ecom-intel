// ---------------------------------------------------------------------------
// AMAZON NOW scraper — FAST recipe (2026-05-30). LIVE via a TRANSPLANTED logged-in
// session (the VPS datacenter IP cannot pass Amazon's /ap/signin WAF captcha — see
// PLAN.md — so cookies are exported by the user on a clean IP via the Cookie-Editor
// extension and imported with import_cookies.js).
//
// SURFACE: the `i=nowstore` storefront search (amazon.in/s?k=jivo&i=nowstore). Logged
// out it 503s; logged in it returns per-SKU Now price + same-day SLOT, varying per
// delivery pincode. (/dp shows only the marketplace promise even logged in — wrong surface.)
//
// SERVICEABILITY (critical): `i=nowstore` is NOT a clean Now-only filter. Where Amazon Now
// is NOT serviceable, the search silently FALLS BACK to ordinary marketplace listings
// (multi-day delivery dates / the "FREE delivery on orders over ₹149" add-on line). Those
// are NOT Amazon Now and must NEVER be recorded as Now prices. A card counts as Now ONLY if
// its delivery line is a same-day time SLOT (see isNowSlot). A pincode is "serviceable" only
// if the location resolved correctly AND ≥1 returned card carries a Now slot — otherwise it
// has no Amazon Now and contributes ZERO rows (we do not substitute the regular Amazon price).
//
// SPEED: the delivery location is account-global server-side, so parallel workers would
// collide — SEQUENTIAL is mandatory. Instead each pincode is made cheap (~2s, no page
// render): set location via a raw `address-change` POST + read the search as raw HTML.
// The POST needs an `anti-csrftoken-a2z` token, which we MINT once by driving the GLOW
// widget through the UI and capturing the token off its request; the token is reusable
// across the whole sweep and re-minted automatically if it ever expires mid-run.
//
// Output schema matches Blinkit/Zepto (+ asin, now_slot, serviceable) so the rest of the
// pipeline (build_excel/predict/review/vault) works unchanged.
//
//   node scrape.js                 # full pincodes.json
//   LIMIT=8 node scrape.js         # smoke test
//   PINCODES_FILE=… OUT_FILE=… node scrape.js
// ---------------------------------------------------------------------------
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const PFILE = process.env.PINCODES_FILE || path.join(__dirname, 'pincodes.json');
const OUTFILE = process.env.OUT_FILE || path.join(__dirname, 'result.json');
const STATE = path.join(__dirname, 'secrets', 'amazon-now.storageState.json');
const QUERY = process.env.QUERY || 'jivo';
const LIMIT = parseInt(process.env.LIMIT || '0', 10);
const OFFSET = parseInt(process.env.OFFSET || '0', 10);
const UA = process.env.UA ||
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let PINCODES = JSON.parse(fs.readFileSync(PFILE, 'utf8'));
if (OFFSET) PINCODES = PINCODES.slice(OFFSET);
if (LIMIT) PINCODES = PINCODES.slice(0, LIMIT);

const PRODUCTS = {};
try {
  const pj = JSON.parse(fs.readFileSync(path.join(__dirname, 'products.json'), 'utf8'));
  for (const p of pj) if (p.asin) PRODUCTS[p.asin] = p;
} catch (_) {}

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

// A card is a GENUINE Amazon Now offer only if its delivery line is a same-day / slotted
// time window — "Today 8 pm - 10 pm", "Tomorrow 7 am - 9 am". Marketplace-fallback cards
// (returned where Now isn't serviceable) instead show a multi-day calendar date
// ("FREE delivery Thu, 11 Jun", "Tomorrow, 2 Jun") or the add-on line
// ("FREE delivery on orders over ₹149") — none of which match here, so they're rejected.
function isNowSlot(slot) {
  const s = slot || '';
  const window = /\d{1,2}\s*(?:am|pm)\s*[-–]\s*\d{1,2}\s*(?:am|pm)/i.test(s); // intraday window
  const sameDay = /\b(?:today|tomorrow)\b/i.test(s) && /\d{1,2}\s*(?:am|pm)/i.test(s);
  return window || sameDay;
}

async function passInterstitial(page) {
  const hit = await page.evaluate(() => /continue shopping/i.test(document.body.innerText || '') && !document.querySelector('#nav-link-accountList')).catch(() => false);
  if (!hit) return;
  try { await page.getByRole('button', { name: /continue shopping/i }).click({ timeout: 6000 }); } catch (_) {}
  await page.waitForLoadState('domcontentloaded', { timeout: 20000 }).catch(() => {});
  await sleep(1500);
}

// Drive the GLOW widget through the UI once to MINT a reusable anti-csrftoken-a2z.
// (The token is attached to the widget's address-change request; we capture it there.)
async function mintToken(page, seedPin) {
  await page.goto('https://www.amazon.in/?ref_=nav_signin', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await sleep(1200); await passInterstitial(page);
  try {
    await page.click('#nav-global-location-popover-link, #glow-ingress-block', { timeout: 8000 }); await sleep(1400);
    await page.fill('#GLUXZipUpdateInput', seedPin, { timeout: 8000 }); await sleep(400);
    try { await page.click('#GLUXZipUpdate input[type="submit"], #GLUXZipUpdate-announce', { timeout: 5000 }); } catch (_) {}
    await sleep(1600);
    try { await page.click('button[name="glowDoneButton"], .a-popover-footer #GLUXConfirmClose', { timeout: 4000 }); } catch (_) {}
    await sleep(1000);
  } catch (e) { process.stderr.write('[mint] ui err ' + e.message + '\n'); }
}

// Raw set+search for one pincode (no page render). Returns the location label that the
// server resolved + the raw search cards. token is the minted anti-csrftoken-a2z.
async function fastSetAndSearch(page, pin, token, query) {
  return page.evaluate(async ({ pin, token, query }) => {
    const set = await fetch('/portal-migration/hz/glow/address-change?actionSource=glow', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'anti-csrftoken-a2z': token, 'x-requested-with': 'XMLHttpRequest' },
      body: JSON.stringify({ locationType: 'LOCATION_INPUT', zipCode: pin, deviceType: 'web', storeContext: 'generic', pageType: 'Gateway', actionSource: 'glow' }),
    }).catch(() => null);
    const setStatus = set ? set.status : 0;
    const r = await fetch('/s?k=' + encodeURIComponent(query) + '&i=nowstore', { headers: { accept: 'text/html' } });
    const html = await r.text();
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const T = (el) => el ? (el.textContent || '').replace(/\s+/g, ' ').trim() : '';
    const cards = [...doc.querySelectorAll('[data-component-type="s-search-result"][data-asin]')]
      .filter((c) => (c.getAttribute('data-asin') || '').length > 3);
    const out = cards.map((c) => ({
      asin: c.getAttribute('data-asin'),
      title: T(c.querySelector('[data-cy="title-recipe"], h2 a span.a-text-normal, a.a-link-normal .a-text-normal, h2 a span')).slice(0, 160),
      price: T(c.querySelector('.a-price[data-a-color="base"] .a-offscreen, .a-price .a-offscreen')),
      mrp: T(c.querySelector('[data-a-strike="true"] .a-offscreen')),
      slot: T(c.querySelector('[class*="delivery" i], .udm-primary-delivery-message')).slice(0, 80),
      oos: /currently unavailable|out of stock|sold out/i.test(T(c)),
      isJivo: /jivo/i.test(T(c)),   // textContent concatenates brand ("JIVOCold…"); \b would miss it
    }));
    return { setStatus, glow: (html.match(/glow-ingress-line2[^>]*>\s*([^<]+?)\s*</) || [])[1] || '', total: cards.length, cards: out };
  }, { pin, token, query });
}

function toRow(card, rec) {
  const prod = PRODUCTS[card.asin];
  // raw-HTML textContent glues the brand span to the name ("JIVOCold Pressed…") since there's
  // no whitespace node between them — re-insert the space so name + canonical stay clean.
  // Sponsored ad cards prepend "Sponsored … You are seeing this ad …" to the title; strip
  // everything before the brand so they canonicalize identically to the organic listing
  // (the per-pincode dedup then merges the ad into the real row instead of doubling SKUs).
  let fullTitle = (card.title || (prod && prod.name) || card.asin).replace(/^.*?(?=jivo)/i, '').replace(/^jivo\s*/i, 'Jivo ');
  const name = fullTitle.split('|')[0].replace(/\s+/g, ' ').trim();
  const pack = packFromTitle(name) || packFromTitle(fullTitle) || (prod && prod.pack ? prod.pack.toLowerCase() : '');
  const sale = numPrice(card.price);
  let mrp = numPrice(card.mrp);
  if (mrp != null && sale != null && mrp < sale) mrp = null;
  const vol = parseVolMl(pack);
  return {
    city: rec.city, pincode: rec.pincode, locality: rec.locality,
    store_id: null, store_name: 'Amazon Now',
    asin: card.asin,
    sku_raw: name, canonical: canonical(name, pack), pack,
    vol_ml: vol, sale, mrp,
    discount_pct: (mrp && sale && mrp >= sale) ? Math.round(((mrp - sale) / mrp) * 1000) / 10 : null,
    per_litre: (vol && sale) ? Math.round((sale / (vol / 1000)) * 100) / 100 : null,
    eta_min: null,
    now_slot: card.slot || '',
    category: prod ? (prod.category || prod.item) : null,
    in_stock: card.oos ? 0 : 1,
  };
}

async function checkSession(page) {
  try {
    await page.goto('https://www.amazon.in/?ref_=nav_signin', { waitUntil: 'domcontentloaded', timeout: 45000 });
    await sleep(1500); await passInterstitial(page);
    return await page.evaluate(() => {
      const g = document.querySelector('#nav-link-accountList-nav-line-1, #nav-link-accountList .nav-line-1');
      const t = g ? (g.innerText || '').trim() : '';
      return { loggedIn: /hello,?\s+(?!sign)/i.test(t) && !/sign in/i.test(t), greeting: t };
    });
  } catch (_) { return { loggedIn: false, greeting: '' }; }
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
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
  await ctx.addInitScript(() => { Object.defineProperty(navigator, 'webdriver', { get: () => undefined }); });
  const page = await ctx.newPage();

  // capture the anti-csrftoken-a2z off any address-change request the widget fires
  let token = '';
  page.on('request', (req) => { if (/address-change/.test(req.url())) { const t = req.headers()['anti-csrftoken-a2z']; if (t) token = t; } });

  // preflight: session must be logged in (VPS can't re-login)
  const sess = await checkSession(page);
  if (!sess.loggedIn) {
    await browser.close().catch(() => {});
    fs.writeFileSync(path.join(__dirname, 'secrets', 'SESSION_EXPIRED'), new Date().toISOString() + '\n');
    console.error('FATAL: Amazon session EXPIRED (greeting="' + sess.greeting + '"). Re-export cookies + run import_cookies.js.');
    process.exit(3);
  }
  try { fs.unlinkSync(path.join(__dirname, 'secrets', 'SESSION_EXPIRED')); } catch (_) {}
  process.stderr.write('[session] OK — ' + sess.greeting + '\n');

  // mint the reusable token (seed location = first pincode)
  await mintToken(page, PINCODES[0] ? PINCODES[0].pincode : '110001');
  process.stderr.write('[token] ' + (token ? token.slice(0, 18) + '… minted' : 'NONE — will retry per-pincode') + '\n');

  const perPin = [];
  for (let i = 0; i < PINCODES.length; i++) {
    const rec = PINCODES[i];
    const ts = Date.now();
    let res = await fastSetAndSearch(page, rec.pincode, token, QUERY);
    // token expired / set didn't take -> the resolved location won't match. Re-mint once.
    if (!res.glow.includes(rec.pincode)) {
      await mintToken(page, rec.pincode);
      res = await fastSetAndSearch(page, rec.pincode, token, QUERY);
    }
    const matched = res.glow.includes(rec.pincode);
    // Amazon Now is serviceable here ONLY if the location resolved correctly (matched) AND at
    // least one returned card carries a real Now slot. If the set-location failed (GLOW
    // mismatch) we scraped the WRONG place; if no card shows a Now slot, i=nowstore fell back
    // to the marketplace. Either way this pincode has NO Amazon Now -> 0 rows, not counted.
    const nowOffered = res.cards.some((c) => isNowSlot(c.slot));
    const serviceable = matched && nowOffered;
    const seen = new Set();
    const rows = [];
    if (serviceable) {
      for (const card of res.cards) {
        if (!card.isJivo) continue;
        if (!isNowSlot(card.slot)) continue;   // this SKU isn't on Now here (marketplace fallback) — drop it
        const row = toRow(card, rec);
        if (seen.has(row.canonical)) continue;
        seen.add(row.canonical); rows.push(row);
      }
    }
    perPin.push({ ...rec, store_id: null, store_name: 'Amazon Now', serviceable, glow: res.glow, matched, total_cards: res.total, rows });
    process.stderr.write(`[ok] ${rec.city} ${rec.pincode} ${matched ? '' : '(GLOW MISMATCH) '}svc=${serviceable} -> ${rows.length} jivo (${((Date.now() - ts) / 1000).toFixed(1)}s) [${i + 1}/${PINCODES.length}]\n`);
    await sleep(350 + Math.random() * 450);
  }
  await browser.close().catch(() => {});

  const allRows = perPin.flatMap((p) => p.rows);
  const summary = {
    pincodes_total: PINCODES.length,
    pincodes_serviceable: perPin.filter((p) => p.serviceable).length,
    pincodes_with_jivo: perPin.filter((p) => p.rows.length > 0).length,
    pincodes_mismatch: perPin.filter((p) => !p.matched).length,
    total_rows: allRows.length,
    unique_skus: new Set(allRows.map((r) => r.canonical)).size,
    wall_s: Math.round((Date.now() - t0) / 1000),
    captured_at: new Date().toISOString(),
  };
  process.stderr.write('[SUMMARY] ' + JSON.stringify(summary) + '\n');
  fs.writeFileSync(OUTFILE, JSON.stringify({ summary, perPin, allRows }, null, 2));
  console.log(JSON.stringify(summary));
})();
