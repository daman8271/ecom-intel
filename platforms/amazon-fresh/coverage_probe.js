// COVERAGE-DIAG probe (W2, amzcover-fresh) — READ-ONLY. For the 14 suspect Jivo ASINs
// that are carried at OTHER pincodes but ABSENT at 110095, decide per-ASIN:
//   REAL         = a DIRECT check confirms it is NOT Fresh-serviceable / not-stocked @110095
//   CAPTURE-MISS = a DIRECT check shows it IS Fresh-available @110095 but the broad
//                  /s?k=jivo&i=freshstore search dropped/missed it (Zepto-style)
//
// SAFETY: loads the logged-in storageState into a context but NEVER saves it back to disk
// (no storageState write) and performs NO cart mutations — pure GETs + the same GLOW
// address-change the live sweep already does every run. Output -> /tmp only. Run behind
// flock .amazon-fresh.lock.  node coverage_probe.js
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const STATE = path.join(__dirname, 'secrets', 'amazon-fresh.storageState.json');
const OUT = process.env.OUT_FILE || '/tmp/fresh_coverage_probe.json';
const PIN = process.env.PIN || '110095';
const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// EXACT copy of the live scraper's gate so the probe tests the real logic.
function isFreshSlot(slot) {
  const s = (slot || '').toLowerCase();
  if (!s) return false;
  if (/\bin\s+\d+\s*min/.test(s)) return true;
  if (/\d{1,2}\s*(?:am|pm)\s*[-–]\s*\d{1,2}\s*(?:am|pm)/.test(s)) return true;
  return false;
}

const SUSPECTS = [
  ['CANOLA 1+1L', 'B0152TWWSQ'], ['CANOLA 5L', 'B077ZN4G28'], ['COCONUT 1L', 'B0BZ8K3DQP'],
  ['COCONUT 500ML', 'B0CGN9Y3PT'], ['EXTRA LIGHT 1L', 'B09HZY97FR'], ['EXTRA VIRGIN 1L', 'B093BMGPQC'],
  ['GOLD 5L', 'B0C9Q1S6QG'], ['MUSTARD 1L', 'B09NYCSQLF'], ['MUSTARD 1L POUCH', 'B0DRYVRYYM'],
  ['RICE BRAN 1L', 'B0DBHQ2QWW'], ['SO OLIVE 1L', 'B0DC6JR4F3'], ['SOYABEAN 1L', 'B0B6HNNL5B'],
  ['SUNFLOWER 1L', 'B0B4SJTNF2'], ['YELLOW MUSTARD 1L', 'B0FF9P7XVX'],
];

async function passInterstitial(page) {
  const hit = await page.evaluate(() => /continue shopping/i.test(document.body.innerText || '') && !document.querySelector('#nav-link-accountList')).catch(() => false);
  if (!hit) return;
  try { await page.getByRole('button', { name: /continue shopping/i }).click({ timeout: 6000 }); } catch (_) {}
  await sleep(1500);
}

async function setLocation(page, pin) {
  await page.goto('https://www.amazon.in/?ref_=nav_signin', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await sleep(1200); await passInterstitial(page);
  try {
    await page.click('#nav-global-location-popover-link, #glow-ingress-block', { timeout: 8000 }); await sleep(1400);
    await page.fill('#GLUXZipUpdateInput', pin, { timeout: 8000 }); await sleep(400);
    try { await page.click('#GLUXZipUpdate input[type="submit"], #GLUXZipUpdate-announce', { timeout: 5000 }); } catch (_) {}
    await sleep(1800);
    try { await page.click('button[name="glowDoneButton"], .a-popover-footer #GLUXConfirmClose', { timeout: 4000 }); } catch (_) {}
    await sleep(1200);
  } catch (e) {}
  return page.evaluate(() => { const g = document.getElementById('glow-ingress-line2'); return g ? (g.innerText || '').replace(/\s+/g, ' ').trim() : ''; });
}

// Broad jivo freshstore search — capture EVERY jivo card (asin/title/slot/oos), the way the
// live scraper sees it, so we can tell if a suspect is in-search-but-dropped vs not-in-search.
async function broadSearch(page) {
  return page.evaluate(async () => {
    const res = await fetch('/s?k=jivo&i=freshstore', { headers: { accept: 'text/html' } });
    const html = await res.text();
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const T = (el) => el ? (el.textContent || '').replace(/\s+/g, ' ').trim() : '';
    const cards = [...doc.querySelectorAll('[data-component-type="s-search-result"][data-asin]')]
      .filter((c) => (c.getAttribute('data-asin') || '').length > 3);
    const glow = (html.match(/glow-ingress-line2[^>]*>\s*([^<]+?)\s*</) || [])[1] || '';
    return {
      glow, total: cards.length,
      jivo: cards.filter((c) => /jivo/i.test(T(c))).map((c) => ({
        asin: c.getAttribute('data-asin'),
        title: T(c.querySelector('[data-cy="title-recipe"], h2 a span')).slice(0, 90),
        slot: T(c.querySelector('[data-cy="delivery-recipe"], [class*="delivery" i], .udm-primary-delivery-message')).slice(0, 90),
        oos: /currently unavailable|out of stock|sold out/i.test(T(c)),
      })),
    };
  });
}

// DIRECT per-ASIN check #1: targeted search keyed on the ASIN string in the freshstore index.
async function directSearch(page, asin) {
  return page.evaluate(async ({ asin }) => {
    const res = await fetch('/s?k=' + asin + '&i=freshstore', { headers: { accept: 'text/html' } });
    const html = await res.text();
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const T = (el) => el ? (el.textContent || '').replace(/\s+/g, ' ').trim() : '';
    const card = [...doc.querySelectorAll('[data-component-type="s-search-result"][data-asin]')]
      .find((c) => (c.getAttribute('data-asin') || '').toUpperCase() === asin.toUpperCase());
    if (!card) return { found: false };
    return {
      found: true,
      title: T(card.querySelector('[data-cy="title-recipe"], h2 a span')).slice(0, 90),
      slot: T(card.querySelector('[data-cy="delivery-recipe"], [class*="delivery" i], .udm-primary-delivery-message')).slice(0, 90),
      price: T(card.querySelector('.a-price .a-offscreen')),
      oos: /currently unavailable|out of stock|sold out/i.test(T(card)),
    };
  }, { asin });
}

// DIRECT per-ASIN check #2: the product detail page — read the buybox / delivery block /
// availability so we know what a real customer at 110095 would actually see for this ASIN.
async function pdpCheck(page, asin) {
  try {
    await page.goto('https://www.amazon.in/dp/' + asin + '?th=1', { waitUntil: 'domcontentloaded', timeout: 45000 });
    await sleep(900); await passInterstitial(page);
    return await page.evaluate(() => {
      const T = (sel) => { const el = document.querySelector(sel); return el ? (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim() : ''; };
      const body = (document.body.innerText || '');
      const deliver = [
        T('#mir-layout-DELIVERY_BLOCK'), T('#deliveryBlockMessage'),
        T('#fast-track-message'), T('[data-csa-c-delivery-time]'),
        T('#exports_desktop_qualifiedBuybox_tabularDeliveryMessage'),
      ].filter(Boolean).join(' | ').slice(0, 260);
      return {
        title: T('#productTitle').slice(0, 90),
        availability: T('#availability').slice(0, 120),
        buyboxBtns: ['#add-to-cart-button', '#buy-now-button'].filter((s) => document.querySelector(s)).join(','),
        delivery: deliver,
        cannotDeliver: /cannot be (delivered|shipped) to your (selected )?(location|address)|doesn'?t deliver to|not available at your location/i.test(body),
        currentlyUnavailable: /currently unavailable/i.test(T('#availability') || body.slice(0, 4000)),
        soldByFreshHint: /amazon\s*fresh/i.test(body),
      };
    });
  } catch (e) { return { err: String(e.message).slice(0, 80) }; }
}

(async () => {
  const browser = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new', '--disable-blink-features=AutomationControlled'] })
    .catch(() => chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }));
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
  await ctx.addInitScript(() => { Object.defineProperty(navigator, 'webdriver', { get: () => undefined }); });
  const page = await ctx.newPage();

  // session sanity (read-only)
  await page.goto('https://www.amazon.in/?ref_=nav_signin', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await sleep(1200); await passInterstitial(page);
  const greeting = await page.evaluate(() => { const g = document.querySelector('#nav-link-accountList-nav-line-1, #nav-link-accountList .nav-line-1'); return g ? (g.innerText || '').trim() : ''; });
  const loggedIn = /hello,?\s+(?!sign)/i.test(greeting) && !/sign in/i.test(greeting);
  process.stderr.write(`[session] loggedIn=${loggedIn} greeting="${greeting}"\n`);
  if (!loggedIn) { await browser.close().catch(() => {}); fs.writeFileSync(OUT, JSON.stringify({ error: 'SESSION_NOT_LOGGED_IN', greeting }, null, 2)); process.exit(0); }

  const loc = await setLocation(page, PIN);
  process.stderr.write(`[loc] set ${PIN} -> glow="${loc}"\n`);

  const broad = await broadSearch(page);
  const broadByAsin = {}; for (const c of broad.jivo) broadByAsin[c.asin] = c;
  process.stderr.write(`[broad] glow="${broad.glow}" total=${broad.total} jivo=${broad.jivo.length}\n`);

  const results = [];
  for (const [name, asin] of SUSPECTS) {
    const inBroad = broadByAsin[asin] || null;
    const ds = await directSearch(page, asin); await sleep(700);
    const pdp = await pdpCheck(page, asin); await sleep(900);
    const dsFresh = ds.found ? isFreshSlot(ds.slot) : false;
    const broadFresh = inBroad ? isFreshSlot(inBroad.slot) : false;
    const pdpFresh = isFreshSlot(pdp.delivery || '');
    // Verdict: CAPTURE-MISS only if a DIRECT check independently shows a genuine Fresh slot
    // at 110095. Otherwise REAL (direct confirms no Fresh availability here).
    const directFreshAvailable = dsFresh || pdpFresh;
    const verdict = directFreshAvailable ? 'CAPTURE-MISS' : 'REAL';
    const rec = { name, asin, verdict,
      broad: inBroad ? { slot: inBroad.slot, freshSlot: broadFresh, oos: inBroad.oos } : 'NOT-IN-BROAD-SEARCH',
      directSearch: ds.found ? { slot: ds.slot, freshSlot: dsFresh, price: ds.price, oos: ds.oos } : 'NOT-FOUND',
      pdp: { availability: pdp.availability, delivery: pdp.delivery, buyboxBtns: pdp.buyboxBtns, cannotDeliver: pdp.cannotDeliver, currentlyUnavailable: pdp.currentlyUnavailable, pdpFresh, err: pdp.err },
    };
    results.push(rec);
    process.stderr.write(`[${name}] ${asin} => ${verdict} | broad=${inBroad ? (broadFresh ? 'FRESH' : 'mkt:' + JSON.stringify(inBroad.slot)) : 'absent'} | dsearch=${ds.found ? (dsFresh ? 'FRESH:' + ds.slot : 'nofresh:' + ds.slot) : 'notfound'} | pdp.avail="${(pdp.availability || '').slice(0, 40)}" pdp.deliv="${(pdp.delivery || '').slice(0, 50)}"\n`);
  }

  await browser.close().catch(() => {});
  fs.writeFileSync(OUT, JSON.stringify({ ts: new Date().toISOString(), pin: PIN, loc, greeting, broad: { glow: broad.glow, total: broad.total, jivo: broad.jivo }, results }, null, 2));
  process.stderr.write(`[done] -> ${OUT}\n`);
})();
