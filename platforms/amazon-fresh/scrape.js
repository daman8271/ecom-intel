// ---------------------------------------------------------------------------
// AMAZON FRESH scraper — LIVE via the SAME transplanted logged-in session as
// amazon-now (secrets/amazon-fresh.storageState.json is a symlink to the Now jar;
// it's one Amazon account). The VPS datacenter IP cannot pass Amazon's signin WAF
// captcha, so cookies are exported by the user on a clean IP (Cookie-Editor) and
// imported once — see ../amazon-now/PLAN.md.
//
// SURFACE: the `i=freshstore` storefront search (amazon.in/s?k=jivo&i=freshstore).
// Recon (2026-05-30) proved Fresh is a SEPARATE, ~7x RICHER index than Now: ~40-49
// Jivo SKUs/city incl. the 5L bulk packs Now never shows. `i=freshstore`,
// `i=amazonfresh` and `almBrandId=ctnow` are three URL paths into this same Fresh
// catalog — we use freshstore.
//
// SPEED / SAFETY: Amazon's delivery location is ACCOUNT-GLOBAL server-side (proven:
// 3 parallel contexts on one session all collapsed to the last-set pincode), so the
// sweep is SEQUENTIAL — parallel workers on one account corrupt each other's location.
// Each pincode is made cheap (~2.5s, no page render): set location via a raw
// `address-change` POST + read the search as raw HTML. The POST needs an
// `anti-csrftoken-a2z`, minted once by driving the GLOW widget and reused (re-minted
// automatically if the resolved location stops matching).
//
// Output schema matches Blinkit/Zepto (+ asin, now_slot, serviceable) so the rest of
// the pipeline (build_excel/predict/review/vault) works unchanged. store_name='Amazon Fresh'.
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
const STATE = path.join(__dirname, 'secrets', 'amazon-fresh.storageState.json');
const QUERY = process.env.QUERY || 'jivo';
const INDEX = process.env.INDEX || 'freshstore';   // the Fresh search index
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

// --- price/pack helpers (IDENTICAL to zepto/blinkit/now so canonical IDs line up) ---
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

// COMBO-PACK VOLUME (2026-06-04). parseVolMl()/packFromTitle() see only the FIRST number, so a
// combo title like "Jivo Canola ... 1+1 Litres" collapses to "1 L" -> vol 1000 ml, ~doubling
// Rs/L (reported 509 vs correct ~254). Parse the combo straight from the raw title FIRST:
//   "A+B <unit>" (any count) => (A+B+…) units;  "N <unit> x M" / "M x N <unit>" => N*M units.
// Returns ml, or null if no combo pattern (caller then falls back to single-pack parseVolMl).
function comboVolMl(text) {
  if (!text) return null;
  const t = text.toLowerCase();
  const U = '(ml|l|ltr|litres?|liters?|kg|gms?|g)';   // incl. American "liter(s)" (combo addends use it)
  const toMl = (n, u) => (u === 'ml' || u === 'g') ? n : n * 1000; // l/ltr/litre/liter/kg -> ml
  // "1+1 litres", "500 + 500 ml", "1+1+1 l"
  let m = t.match(new RegExp('([\\d.]+(?:\\s*\\+\\s*[\\d.]+)+)\\s*' + U + '\\b'));
  if (m) {
    const sum = m[1].split('+').reduce((s, x) => s + (parseFloat(x) || 0), 0);
    return toMl(sum, m[2]);
  }
  // "1 l x 2", "1l × 2"
  m = t.match(new RegExp('([\\d.]+)\\s*' + U + '\\s*[x×*]\\s*([\\d.]+)\\b'));
  if (m) return toMl(parseFloat(m[1]) * parseFloat(m[3]), m[2]);
  // "2 x 1 l", "2 × 1l"
  m = t.match(new RegExp('([\\d.]+)\\s*[x×*]\\s*([\\d.]+)\\s*' + U + '\\b'));
  if (m) return toMl(parseFloat(m[1]) * parseFloat(m[2]), m[3]);
  // REPEATED-UNIT ADDITIVE COMBOS (2026-06-04 audit BUG-1): the branches above only catch a
  // SHARED trailing unit ("1+1 Litres") or "N unit × M". Combos where EACH addend carries its
  // OWN unit — "5 Litre with 5 Litre" (10L), "5 Litre & 1 Liter" (6L), "5 Litre + 1 Litre Combo
  // Pack" (6L) — slip through to the single-pack fallback, ~halving the denominator (Rs/L
  // inflated 1.2x–2x). Sum every unit-bearing quantity, converting per-unit first so mixed units
  // (e.g. "500 ml + 1 l") add correctly. FIRE ONLY when a combo indicator is present AND there
  // are >=2 unit-bearing quantities — conservative: under-include, never mis-sum a non-combo title.
  if (/\+|&|\bwith\b|\bcombo\b|\bbundle\b/.test(t)) {
    const matches = [...t.matchAll(new RegExp('([\\d.]+)\\s*' + U + '\\b', 'g'))];
    if (matches.length >= 2) {
      const sum = matches.reduce((s, mm) => s + toMl(parseFloat(mm[1]) || 0, mm[2]), 0);
      if (sum > 0) return sum;
    }
  }
  return null;
}

// FRESH-PRESENCE GATE (2026-06-01). The i=freshstore search BACK-FILLS its page with
// ordinary Amazon marketplace listings (multi-day courier promises) when the real Fresh
// catalogue is thin or Fresh is NOT serviceable at the pincode. Those are NOT Fresh prices
// — recording them silently falls back to the marketplace, which we must never do.
// A genuine Amazon Fresh / quick-commerce card carries a same/next-day delivery SLOT:
// "FREE delivery in N minutes", or an explicit time window like "Today 7 pm - 9 pm" /
// "Tomorrow 6 am - 10 am". A marketplace card shows a named weekday+date ("Sat, 6 Jun"),
// a multi-day range ("4 - 7 Jun") or Prime CSS bleed — never a slot window. We keep a row
// ONLY when its slot is a genuine Fresh window; everything else is dropped. Conservative
// by design (an ambiguous slot is treated as NOT Fresh — under-include, never mislabel).
function isFreshSlot(slot) {
  const s = (slot || '').toLowerCase();
  if (!s) return false;
  if (/\bin\s+\d+\s*min/.test(s)) return true;                                 // "in 10 minutes"
  if (/\d{1,2}\s*(?:am|pm)\s*[-–]\s*\d{1,2}\s*(?:am|pm)/.test(s)) return true; // "7 pm - 9 pm"
  return false;
}

async function passInterstitial(page) {
  const hit = await page.evaluate(() => /continue shopping/i.test(document.body.innerText || '') && !document.querySelector('#nav-link-accountList')).catch(() => false);
  if (!hit) return;
  try { await page.getByRole('button', { name: /continue shopping/i }).click({ timeout: 6000 }); } catch (_) {}
  await page.waitForLoadState('domcontentloaded', { timeout: 20000 }).catch(() => {});
  await sleep(1500);
}

// Drive the GLOW widget once to MINT a reusable anti-csrftoken-a2z.
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

// Raw set + Fresh search for one pincode (no page render).
async function fastSetAndSearch(page, pin, token, query, index) {
  return page.evaluate(async ({ pin, token, query, index }) => {
    const set = await fetch('/portal-migration/hz/glow/address-change?actionSource=glow', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'anti-csrftoken-a2z': token, 'x-requested-with': 'XMLHttpRequest' },
      body: JSON.stringify({ locationType: 'LOCATION_INPUT', zipCode: pin, deviceType: 'web', storeContext: 'generic', pageType: 'Gateway', actionSource: 'glow' }),
    }).catch(() => null);
    const setStatus = set ? set.status : 0;
    const r = await fetch('/s?k=' + encodeURIComponent(query) + '&i=' + index, { headers: { accept: 'text/html' } });
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
      isJivo: /jivo/i.test(T(c)),   // textContent glues brand ("JIVOCold…") so \b would miss it
    }));
    return { setStatus, glow: (html.match(/glow-ingress-line2[^>]*>\s*([^<]+?)\s*</) || [])[1] || '', total: cards.length, cards: out };
  }, { pin, token, query, index });
}

function toRow(card, rec) {
  const prod = PRODUCTS[card.asin];
  // Sponsored ad cards prepend "Sponsored … You are seeing this ad …" to the title; strip
  // everything before the brand so they canonicalize identically to the organic listing
  // (dedup then merges the ad into the real SKU instead of creating a phantom one). Same
  // fix as platforms/amazon-now/scrape.js.
  let fullTitle = (card.title || (prod && prod.name) || card.asin).replace(/^.*?(?=jivo)/i, '').replace(/^jivo\s*/i, 'Jivo ');
  const name = fullTitle.split('|')[0].replace(/\s+/g, ' ').trim();
  const pack = packFromTitle(name) || packFromTitle(fullTitle) || (prod && prod.pack ? prod.pack.toLowerCase() : '');
  const sale = numPrice(card.price);
  let mrp = numPrice(card.mrp);
  if (mrp != null && sale != null && mrp < sale) mrp = null;
  // Combo packs ("1+1 Litres", "1 L x 2") carry their TOTAL volume in the title; read it from
  // there first so Rs/L isn't ~doubled, falling back to the single-pack parse. (canonical()
  // still uses pack — the combo/single canonical merge is a separate, deferred fix.)
  const vol = comboVolMl(name) || comboVolMl(fullTitle) || parseVolMl(pack);
  return {
    city: rec.city, pincode: rec.pincode, locality: rec.locality,
    store_id: null, store_name: 'Amazon Fresh',
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

// CANONICAL NORMALIZATION (2026-06-04 audit BUG-2). canonical() is title-derived, so the SAME
// ASIN can split into two canonicals on a title-variant ("...Cooking" vs truncated "...Cookin"),
// and two DISTINCT ASINs with identical titles collapse to one. Fix WITHOUT touching canonical()'s
// cross-platform formula: per ASIN pick the MAJORITY canonical (kills title-variant splits), then
// suffix the ASIN onto any canonical shared by >1 ASIN (keeps genuinely distinct listings separate).
// Mutates row.canonical in place (rows are shared between perPin and allRows).
function normalizeCanonicals(allRows) {
  const votes = {};                  // asin -> { canonical: count }
  for (const r of allRows) (votes[r.asin] || (votes[r.asin] = {}))[r.canonical] = ((votes[r.asin] || {})[r.canonical] || 0) + 1;
  const asinCanon = {};              // asin -> winning (most-frequent) canonical
  for (const [asin, m] of Object.entries(votes)) asinCanon[asin] = Object.entries(m).sort((a, b) => b[1] - a[1])[0][0];
  const canonAsins = {};             // canonical -> Set(asin)
  for (const [asin, c] of Object.entries(asinCanon)) (canonAsins[c] || (canonAsins[c] = new Set())).add(asin);
  for (const r of allRows) {
    let c = asinCanon[r.asin];
    if (canonAsins[c] && canonAsins[c].size > 1) c = `${c}-${String(r.asin).toLowerCase()}`;  // distinct ASINs, same title
    r.canonical = c;
  }
  return allRows;
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

// Pure helpers are exported so they can be unit-tested OFFLINE (no scraper/browser run);
// the live sweep below only executes when this file is run directly, not when required.
module.exports = { parseVolMl, comboVolMl, canonical, packFromTitle, numPrice, isFreshSlot, normalizeCanonicals };

if (require.main === module) (async () => {
  if (!fs.existsSync(STATE)) {
    console.error('FATAL: no session at ' + STATE + ' — symlink it to ../amazon-now/secrets/amazon-now.storageState.json (same account) or run import_cookies.js.');
    process.exit(2);
  }
  const t0 = Date.now();
  let token = '';
  // Open (or RE-open, after a transient Chromium crash) a logged-in browser+context+page,
  // re-attaching the token-capture listener. A single per-pincode browser death (seen under
  // heavy concurrent load) must NOT kill the whole 332-pincode sweep — the loop relaunches via this.
  async function openBrowser() {
    let b;
    try { b = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new', '--disable-blink-features=AutomationControlled'] }); }
    catch (_) { b = await chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }); }
    const c = await b.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
    await c.addInitScript(() => { Object.defineProperty(navigator, 'webdriver', { get: () => undefined }); });
    const p = await c.newPage();
    p.on('request', (req) => { if (/address-change/.test(req.url())) { const t = req.headers()['anti-csrftoken-a2z']; if (t) token = t; } });
    return { browser: b, ctx: c, page: p };
  }
  let { browser, ctx, page } = await openBrowser();

  const sess = await checkSession(page);
  if (!sess.loggedIn) {
    await browser.close().catch(() => {});
    fs.writeFileSync(path.join(__dirname, 'secrets', 'SESSION_EXPIRED'), new Date().toISOString() + '\n');
    console.error('FATAL: Amazon session EXPIRED (greeting="' + sess.greeting + '"). Re-export cookies + run ../amazon-now/import_cookies.js.');
    process.exit(3);
  }
  try { fs.unlinkSync(path.join(__dirname, 'secrets', 'SESSION_EXPIRED')); } catch (_) {}
  process.stderr.write('[session] OK — ' + sess.greeting + '\n');

  await mintToken(page, PINCODES[0] ? PINCODES[0].pincode : '110001');
  process.stderr.write('[token] ' + (token ? token.slice(0, 18) + '… minted' : 'NONE — will retry per-pincode') + '\n');

  const perPin = [];
  for (let i = 0; i < PINCODES.length; i++) {
    const rec = PINCODES[i];
    const ts = Date.now();
    let res;
    try {
      res = await fastSetAndSearch(page, rec.pincode, token, QUERY, INDEX);
      if (!res.glow.includes(rec.pincode)) {
        await mintToken(page, rec.pincode);
        res = await fastSetAndSearch(page, rec.pincode, token, QUERY, INDEX);
      }
    } catch (e) {
      // Transient Chromium death ("Target page/context/browser has been closed") — relaunch
      // the browser ONCE and retry this pincode so we don't lose the whole sweep. If recovery
      // still fails, record the pincode as errored (not serviceable) and move on.
      process.stderr.write(`[recover] ${rec.city} ${rec.pincode}: ${String(e.message).slice(0, 70)} — relaunching\n`);
      try { await browser.close(); } catch (_) {}
      try {
        ({ browser, ctx, page } = await openBrowser());
        await mintToken(page, rec.pincode);
        res = await fastSetAndSearch(page, rec.pincode, token, QUERY, INDEX);
      } catch (e2) {
        process.stderr.write(`[skip] ${rec.city} ${rec.pincode}: recovery failed (${String(e2.message).slice(0, 50)})\n`);
        perPin.push({ ...rec, store_id: null, store_name: 'Amazon Fresh', serviceable: false, location_ok: false, glow: '', matched: false, cards_total: 0, dropped_marketplace: 0, error: true, rows: [] });
        await sleep(800);
        continue;
      }
    }
    const matched = res.glow.includes(rec.pincode);

    // LOCATION GATE: if the account location did not actually switch to this pincode (even
    // after the re-mint retry above), the page we read is for the WRONG location — emit
    // NOTHING rather than mislabel another city's prices as this pincode (the exact bug that
    // hit Amazon Now). FRESH GATE: keep only genuine Fresh-slot Jivo cards; drop the
    // marketplace bleed so a marketplace price is never recorded as a Fresh price.
    const seen = new Set();
    const rows = [];
    let dropped_marketplace = 0;
    if (matched) {
      for (const card of res.cards) {
        if (!card.isJivo) continue;
        if (!isFreshSlot(card.slot)) { dropped_marketplace++; continue; }  // marketplace bleed — skip
        const row = toRow(card, rec);
        // Dedup per-pincode by ASIN, not title-canonical (2026-06-04 audit BUG-2). The sponsored
        // ad + organic listing of one product share an ASIN -> still collapse to one row; but two
        // DISTINCT ASINs that happen to share a title (identical-name relistings, e.g. Rs145-209 vs
        // Rs356 1L mustard) no longer silently drop one price the way canonical-dedup did.
        if (seen.has(card.asin)) continue;
        seen.add(card.asin); rows.push(row);
      }
    }
    // Fresh is "serviceable here" ONLY if the (correctly-located) page shows at least one
    // genuine Fresh slot on ANY card — NOT merely "any card returned" (the old bug).
    const serviceable = matched && res.cards.some((c) => isFreshSlot(c.slot));
    perPin.push({ ...rec, store_id: null, store_name: 'Amazon Fresh', serviceable,
      location_ok: matched, glow: res.glow, matched, cards_total: res.total,
      dropped_marketplace, rows });
    process.stderr.write(`[ok] ${rec.city} ${rec.pincode} ${matched ? '' : '(GLOW MISMATCH→SKIP) '}freshSvc=${serviceable} -> ${rows.length} fresh (dropped ${dropped_marketplace} mkt) (${((Date.now() - ts) / 1000).toFixed(1)}s) [${i + 1}/${PINCODES.length}]\n`);
    await sleep(300 + Math.random() * 400);
  }
  await browser.close().catch(() => {});

  const allRows = normalizeCanonicals(perPin.flatMap((p) => p.rows));
  const summary = {
    pincodes_total: PINCODES.length,
    pincodes_fresh_serviceable: perPin.filter((p) => p.serviceable).length,
    pincodes_serviceable: perPin.filter((p) => p.serviceable).length,
    pincodes_with_jivo: perPin.filter((p) => p.rows.length > 0).length,
    pincodes_location_skipped: perPin.filter((p) => !p.matched).length,
    pincodes_mismatch: perPin.filter((p) => !p.matched).length,
    marketplace_rows_dropped: perPin.reduce((s, p) => s + (p.dropped_marketplace || 0), 0),
    total_rows: allRows.length,
    unique_skus: new Set(allRows.map((r) => r.canonical)).size,
    gate: 'fresh-slot+location v1 (2026-06-01): row kept only if location matched AND card slot is a genuine Fresh window/in-N-min; marketplace-bleed rows dropped',
    wall_s: Math.round((Date.now() - t0) / 1000),
    captured_at: new Date().toISOString(),
  };
  process.stderr.write('[SUMMARY] ' + JSON.stringify(summary) + '\n');
  fs.writeFileSync(OUTFILE, JSON.stringify({ summary, perPin, allRows }, null, 2));
  console.log(JSON.stringify(summary));
})();
