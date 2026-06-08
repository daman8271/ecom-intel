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
// NOW vs FRESH/MARKETPLACE inside the storefront (CORRECTED 2026-06-04):
//   * The pincode is Now-serviceable ONLY if the page is genuinely Amazon-Now-branded
//     (`amazonNowPage` — "Continue shopping on Amazon Now" / <img alt="Amazon Now">). Where
//     it's absent there is NO Now storefront (e.g. Chandigarh, Ludhiana) — proven live.
//   * A blue speed BADGE alone is NOT proof of Now: the IDENTICAL "Tomorrow"/"Overnight"/
//     "Today" chips render on the SAME ASINs in non-Now cities, where they are Amazon FRESH /
//     generic scheduled slots. Only an INSTANT minute promise ("in N minutes" → tier '10 min')
//     is exclusive to genuine Now (0/238 non-Now pincodes ever showed it).
//   * So a row is kept ONLY when amazonNowPage AND the card is an instant-minute tier; every
//     scheduled tier (tomorrow/today-window/overnight/dated) is Fresh and dropped. The kept
//     tier is recorded in `now_eta`. See isInstantNow() and ROOTCAUSE-AmazonNow-2026-06-01.md.
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

// THE genuine-Now discriminator (fixed 2026-06-04 — see NOW/FRESH mislabel fix).
// A blue speed chip alone does NOT mean Amazon Now: the IDENTICAL "Tomorrow"/"Overnight"/
// "Today" chips render on the SAME ASINs in cities with NO Now storefront (proven live:
// Chandigarh 160001 & Ludhiana 141001 — amazon_now_page=false, only scheduled chips, those
// are Amazon FRESH/generic scheduled slots). The ONLY signal exclusive to genuine Amazon Now
// is an INSTANT minute-based delivery promise ("in N minutes" → tier '10 min'); live probing
// found it appears ONLY where amazon_now_page=true (0/238 non-Now pincodes ever showed it).
// So: a card is genuine Now ⇔ the page is Now-branded AND the offer is an instant-minute tier.
// Scheduled tiers (tomorrow / today-window / overnight / dated) are Fresh and are EXCLUDED.
function isInstantNow(card) {
  return nowTier(card.badge, card.deliv) === '10 min';
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
  let failedPins = 0;
  for (let i = 0; i < PINCODES.length; i++) {
    const rec = PINCODES[i];
    // Per-pincode resilience: a transient blip (e.g. page.evaluate "Failed to fetch") on ONE
    // pincode must never crash the whole sweep. On a thrown error we record this pincode as a
    // 0-row/failed entry (same shape as a genuinely-empty pincode so downstream is unaffected)
    // and continue. The final result.json with all SUCCEEDED pincodes is still written below.
    try {
      const ts = Date.now();
      let res = await fastSetAndSearch(page, rec.pincode, token, QUERY, 1);
      if (!res.glow.includes(rec.pincode)) {
        await mintToken(page, rec.pincode);
        res = await fastSetAndSearch(page, rec.pincode, token, QUERY, 1);
      }
      const matched = res.glow.includes(rec.pincode);
      // Genuine-Now gate: the page must be Amazon-Now-branded. amazon_now_page is the real
      // discriminator — false here means NO Now storefront at this pincode (any speed chips are
      // Fresh/marketplace scheduled slots), so the pincode is NOT Now-serviceable and yields 0 rows.
      const nowPage = res.amazonNowPage;

      // accumulate genuine-INSTANT-Now Jivo cards across pages (dedup by canonical)
      const seen = new Set();
      const rows = [];
      if (matched && nowPage) {
        let pageNo = 1; let pageRes = res;
        while (pageNo <= MAXPAGES) {
          for (const card of pageRes.cards) {
            // Only genuine Now: Jivo AND an instant-minute tier. Scheduled (tomorrow/today/
            // overnight) chips are Amazon FRESH and are dropped — they are NOT Amazon Now.
            if (!card.isJivo || !isInstantNow(card)) continue;
            const row = toRow(card, rec);
            if (seen.has(row.canonical)) continue;
            seen.add(row.canonical); rows.push(row);
          }
          if (!pageRes.hasNext || pageNo >= MAXPAGES) break;
          pageNo++;
          pageRes = await fastSetAndSearch(page, rec.pincode, token, QUERY, pageNo);
          await sleep(250 + Math.random() * 300);
        }
      }
      // Serviceable ⇔ location resolved AND the ctnow page is genuinely Amazon-Now-branded
      // AND at least one genuine instant-Now Jivo row was found. amazon_now_page alone is NOT
      // fully reliable: a few pincodes render the Now page but only offer SCHEDULED slots (e.g.
      // Mysuru 570016/570020) — those are not genuine instant Now, so requiring rows.length>0
      // drops them and aligns the footprint to the true ~90 instant-Now pincodes (W5 tightening).
      const serviceable = matched && nowPage && rows.length > 0;
      perPin.push({ ...rec, store_id: null, store_name: 'Amazon Now', serviceable, amazon_now_page: nowPage, glow: res.glow, matched, total_cards: res.total, rows });
      process.stderr.write(`[ok] ${rec.city} ${rec.pincode} ${matched ? '' : '(GLOW MISMATCH) '}nowPage=${nowPage} svc=${serviceable} -> ${rows.length} jivo-now (${((Date.now() - ts) / 1000).toFixed(1)}s) [${i + 1}/${PINCODES.length}]\n`);
      await sleep(350 + Math.random() * 450);
    } catch (err) {
      process.stderr.write(`[skip] ${rec.pincode} ${err && err.message ? err.message : err}\n`);
      perPin.push({ ...rec, store_id: null, store_name: 'Amazon Now', serviceable: false, amazon_now_page: false, glow: '', matched: false, total_cards: 0, rows: [] });
      failedPins++;
      continue;
    }
  }
  process.stderr.write(`[done] ${PINCODES.length} pincodes, ${failedPins} failed (skipped)\n`);
  // Catastrophic guard: do NOT silently ship a mostly-empty run, but do NOT hard-exit either
  // (that would reintroduce the crash). Still write result.json — review.py's baseline/row-collapse
  // check then correctly marks it SUSPECT/BROKEN — but emit a loud alarm so logs show it.
  if (failedPins > PINCODES.length / 2) process.stderr.write('[ALARM] majority of pincodes failed\n');
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
