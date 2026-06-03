// ---------------------------------------------------------------------------
// AMAZON NOW scraper v2 — the REAL quick-commerce surface (2026-06-02).
//
// SURFACE: `amazon.in/s?k=jivo&almBrandId=ctnow` — the genuine Amazon Now storefront
// search (the `alm`/ctnow backend, sibling of Amazon Fresh's i=freshstore). Proven
// 2026-06-02 (recon_now_real.js + probe_ctnow.js) vs the OLD i=nowstore (which was the
// legacy Prime-Now/marketplace search — 0 minute-ETAs, ~8% catalog, wrong prices):
//   ctnow @ Bengaluru 560034 -> 44 Jivo SKUs, page says "Amazon Now", real "in 10 minutes"
//   ETAs; i=nowstore @ same pincode -> 0 Jivo (empty). See ROOTCAUSE-AmazonNow-2026-06-01.md.
//
// NOW vs MARKETPLACE inside the storefront: every genuine Now offer carries a blue speed
// BADGE (`.udm-badge-block` / `.dex-text-slanted-blue-highlight`) reading "in 10 minutes",
// "Overnight", "Tomorrow", "Today …". Cards WITHOUT that badge (plain "FREE delivery Thu,
// 4 Jun") are ordinary marketplace listings surfaced in the same results and are NOT Amazon
// Now — they are dropped. We record the speed tier per row in `now_eta`.
//
// ACCOUNT: uses its OWN dedicated Amazon account (secrets/amazon-now.storageState.json),
// SEPARATE from Amazon Fresh's account — so the account-global delivery location no longer
// collides with Fresh and the two can run in parallel (the shared .amazon-account.lock is
// no longer required for Now vs Fresh). Location is still set per-pincode via the GLOW
// address-change POST; pincodes are swept SEQUENTIALLY within this one account.
//
//   node scrape.ctnow.js                 # full pincodes.json
//   LIMIT=4 node scrape.ctnow.js         # smoke test
//   PINCODES_FILE=… OUT_FILE=… MAXPAGES=3 node scrape.ctnow.js
// ---------------------------------------------------------------------------
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const PFILE = process.env.PINCODES_FILE || path.join(__dirname, 'pincodes.json');
const OUTFILE = process.env.OUT_FILE || path.join(__dirname, 'result.json');
const STATE = path.join(__dirname, 'secrets', 'amazon-now.storageState.json');
const QUERY = process.env.QUERY || 'jivo';
const MAXPAGES = parseInt(process.env.MAXPAGES || '3', 10);
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

// --- price/pack helpers (IDENTICAL to zepto/blinkit/fresh so canonical IDs line up) ---
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

// Normalise the speed badge into a tier label. '' = no Now badge (marketplace, not Now).
function nowTier(badge, deliv) {
  const s = ((badge || '') + ' ' + (deliv || '')).toLowerCase();
  if (/\bin\s+\d+\s*min/.test(s)) return '10 min';
  if (/\bovernight\b/.test(s)) return 'overnight';
  if (/\btoday\b/.test(s)) return 'today';
  if (/\btomorrow\b/.test(s)) return 'tomorrow';
  return badge ? badge.trim().toLowerCase() : '';
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

// Raw set-location + ctnow search for one pincode + page (no page render). Returns the
// resolved GLOW label + ALL Jivo cards with their Now speed badge.
async function fastSetAndSearch(page, pin, token, query, pageNo) {
  return page.evaluate(async ({ pin, token, query, pageNo }) => {
    if (token) {
      await fetch('/portal-migration/hz/glow/address-change?actionSource=glow', {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'anti-csrftoken-a2z': token, 'x-requested-with': 'XMLHttpRequest' },
        body: JSON.stringify({ locationType: 'LOCATION_INPUT', zipCode: pin, deviceType: 'web', storeContext: 'generic', pageType: 'Gateway', actionSource: 'glow' }),
      }).catch(() => null);
    }
    const url = '/s?k=' + encodeURIComponent(query) + '&almBrandId=ctnow' + (pageNo > 1 ? '&page=' + pageNo : '');
    const r = await fetch(url, { headers: { accept: 'text/html' } });
    const html = await r.text();
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const clean = (el) => { if (!el) return ''; const c = el.cloneNode(true); c.querySelectorAll('style,script').forEach((s) => s.remove()); return (c.textContent || '').replace(/\s+/g, ' ').trim(); };
    const cards = [...doc.querySelectorAll('[data-component-type="s-search-result"][data-asin]')]
      .filter((c) => (c.getAttribute('data-asin') || '').length > 3);
    const out = cards.map((c) => {
      // The blue Amazon Now speed chip. Marketplace cards lack it (or the generic
      // .udm-badge-block is present but EMPTY) — so require this element AND non-empty text.
      const badgeEl = c.querySelector('.dex-text-slanted-blue-highlight');
      const badgeTxt = clean(badgeEl);
      return {
        asin: c.getAttribute('data-asin'),
        title: clean(c.querySelector('[data-cy="title-recipe"], h2 a span.a-text-normal, h2 a span')).slice(0, 160),
        price: clean(c.querySelector('.a-price[data-a-color="base"] .a-offscreen, .a-price .a-offscreen')),
        mrp: clean(c.querySelector('[data-a-strike="true"] .a-offscreen')),
        badge: badgeTxt,                     // "Tomorrow" | "Overnight" | "10 min" | ''
        deliv: clean(c.querySelector('[data-cy="delivery-recipe"]')).slice(0, 120),
        nowBadge: !!(badgeEl && badgeTxt),   // <- the real Now-vs-marketplace discriminator
        oos: /currently unavailable|out of stock|sold out/i.test(clean(c)),
        isJivo: /jivo/i.test(clean(c)),
      };
    });
    const hasNext = !!doc.querySelector('a.s-pagination-next:not(.s-pagination-disabled)');
    return {
      glow: (html.match(/glow-ingress-line2[^>]*>\s*([^<]+?)\s*</) || [])[1] || '',
      amazonNowPage: /amazon\s*now/i.test(html),
      total: cards.length, hasNext, cards: out,
    };
  }, { pin, token, query, pageNo });
}

function toRow(card, rec) {
  const prod = PRODUCTS[card.asin];
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
    now_slot: nowTier(card.badge, card.deliv),   // speed tier: "10 min" | "overnight" | "tomorrow" | "today"
    now_eta: nowTier(card.badge, card.deliv),
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
    console.error('FATAL: no session at ' + STATE + ' — import the dedicated Now account with import_cookies.js.');
    process.exit(2);
  }
  const t0 = Date.now();
  let browser;
  try { browser = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new', '--disable-blink-features=AutomationControlled'] }); }
  catch (_) { browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }); }
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
  await ctx.addInitScript(() => { Object.defineProperty(navigator, 'webdriver', { get: () => undefined }); });
  const page = await ctx.newPage();

  let token = '';
  page.on('request', (req) => { if (/address-change/.test(req.url())) { const t = req.headers()['anti-csrftoken-a2z']; if (t) token = t; } });

  const sess = await checkSession(page);
  if (!sess.loggedIn) {
    await browser.close().catch(() => {});
    fs.writeFileSync(path.join(__dirname, 'secrets', 'SESSION_EXPIRED'), new Date().toISOString() + '\n');
    console.error('FATAL: Amazon Now session EXPIRED (greeting="' + sess.greeting + '"). Re-export cookies + import_cookies.js.');
    process.exit(3);
  }
  try { fs.unlinkSync(path.join(__dirname, 'secrets', 'SESSION_EXPIRED')); } catch (_) {}
  process.stderr.write('[session] OK — ' + sess.greeting + '\n');

  await mintToken(page, PINCODES[0] ? PINCODES[0].pincode : '560034');
  process.stderr.write('[token] ' + (token ? token.slice(0, 18) + '… minted' : 'NONE — will retry per-pincode') + '\n');

  const perPin = [];
  for (let i = 0; i < PINCODES.length; i++) {
    const rec = PINCODES[i];
    const ts = Date.now();
    let res = await fastSetAndSearch(page, rec.pincode, token, QUERY, 1);
    if (!res.glow.includes(rec.pincode)) {
      await mintToken(page, rec.pincode);
      res = await fastSetAndSearch(page, rec.pincode, token, QUERY, 1);
    }
    const matched = res.glow.includes(rec.pincode);

    // accumulate Now-badged Jivo cards across pages (dedup by canonical)
    const seen = new Set();
    const rows = [];
    let anyNowCard = res.cards.some((c) => c.nowBadge);   // does Now operate here at all?
    if (matched) {
      let pageNo = 1; let pageRes = res;
      while (pageNo <= MAXPAGES) {
        for (const card of pageRes.cards) {
          if (!card.isJivo || !card.nowBadge) continue;   // marketplace-only card -> not Now -> skip
          const row = toRow(card, rec);
          if (seen.has(row.canonical)) continue;
          seen.add(row.canonical); rows.push(row);
        }
        if (!pageRes.hasNext || pageNo >= MAXPAGES) break;
        pageNo++;
        pageRes = await fastSetAndSearch(page, rec.pincode, token, QUERY, pageNo);
        if (pageRes.cards.some((c) => c.nowBadge)) anyNowCard = true;
        await sleep(250 + Math.random() * 300);
      }
    }
    const serviceable = matched && anyNowCard;
    perPin.push({ ...rec, store_id: null, store_name: 'Amazon Now', serviceable, amazon_now_page: res.amazonNowPage, glow: res.glow, matched, total_cards: res.total, rows });
    process.stderr.write(`[ok] ${rec.city} ${rec.pincode} ${matched ? '' : '(GLOW MISMATCH) '}svc=${serviceable} -> ${rows.length} jivo-now (${((Date.now() - ts) / 1000).toFixed(1)}s) [${i + 1}/${PINCODES.length}]\n`);
    await sleep(350 + Math.random() * 450);
  }
  await browser.close().catch(() => {});

  const allRows = perPin.flatMap((p) => p.rows);
  const tiers = {};
  for (const r of allRows) tiers[r.now_eta || '(none)'] = (tiers[r.now_eta || '(none)'] || 0) + 1;
  const summary = {
    pincodes_total: PINCODES.length,
    pincodes_serviceable: perPin.filter((p) => p.serviceable).length,
    pincodes_with_jivo: perPin.filter((p) => p.rows.length > 0).length,
    pincodes_mismatch: perPin.filter((p) => !p.matched).length,
    total_rows: allRows.length,
    unique_skus: new Set(allRows.map((r) => r.canonical)).size,
    now_tier_breakdown: tiers,
    wall_s: Math.round((Date.now() - t0) / 1000),
    captured_at: new Date().toISOString(),
  };
  process.stderr.write('[SUMMARY] ' + JSON.stringify(summary) + '\n');
  fs.writeFileSync(OUTFILE, JSON.stringify({ summary, perPin, allRows }, null, 2));
  console.log(JSON.stringify(summary));
})();
