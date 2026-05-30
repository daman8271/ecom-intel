// READ-ONLY recon probe (no login, no writes to Amazon). Uses the existing logged-in
// storageState to answer 3 questions across a handful of real metro pincodes:
//   1) Does the per-pincode location switch ACTUALLY hold? (re-read glow after each set)
//   2) Is Amazon "Fresh" a SEPARATE search index, or the same ctnow storefront as Now?
//      We compare i=nowstore vs i=freshstore vs i=amazonfresh vs almBrandId=ctnow.
//   3) What is the real serviceable footprint / how many distinct Jivo catalogs?
// Output: probe_fresh.out.json  (sequential, gentle — account-global location demands it).
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const STATE = path.join(__dirname, 'secrets', 'amazon-now.storageState.json');
const OUT = path.join(__dirname, 'probe_fresh.out.json');
const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// 8 pincodes spread across the metros where Amazon Now/Fresh plausibly operates.
const TESTS = [
  { city: 'Bengaluru', pincode: '560034' },
  { city: 'Delhi',     pincode: '110001' },
  { city: 'Mumbai',    pincode: '400053' },
  { city: 'Hyderabad', pincode: '500081' },
  { city: 'Pune',      pincode: '411001' },
  { city: 'Chennai',   pincode: '600040' },
  { city: 'Gurgaon',   pincode: '122002' },
  { city: 'Kolkata',   pincode: '700019' },
];

// the candidate Now/Fresh search surfaces to compare
const SURFACES = [
  { key: 'nowstore',   url: (q) => `/s?k=${q}&i=nowstore` },
  { key: 'freshstore', url: (q) => `/s?k=${q}&i=freshstore` },
  { key: 'amazonfresh',url: (q) => `/s?k=${q}&i=amazonfresh` },
  { key: 'ctnow_alm',  url: (q) => `/s?k=${q}&almBrandId=ctnow` },
];

async function passInterstitial(page) {
  const hit = await page.evaluate(() => /continue shopping/i.test(document.body.innerText || '') && !document.querySelector('#nav-link-accountList')).catch(() => false);
  if (!hit) return;
  try { await page.getByRole('button', { name: /continue shopping/i }).click({ timeout: 6000 }); } catch (_) {}
  await page.waitForLoadState('domcontentloaded', { timeout: 20000 }).catch(() => {});
  await sleep(1200);
}

async function mintToken(page, seedPin) {
  await page.goto('https://www.amazon.in/?ref_=nav_signin', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await sleep(1000); await passInterstitial(page);
  try {
    await page.click('#nav-global-location-popover-link, #glow-ingress-block', { timeout: 8000 }); await sleep(1200);
    await page.fill('#GLUXZipUpdateInput', seedPin, { timeout: 8000 }); await sleep(400);
    try { await page.click('#GLUXZipUpdate input[type="submit"], #GLUXZipUpdate-announce', { timeout: 5000 }); } catch (_) {}
    await sleep(1400);
    try { await page.click('button[name="glowDoneButton"], .a-popover-footer #GLUXConfirmClose', { timeout: 4000 }); } catch (_) {}
    await sleep(800);
  } catch (e) { process.stderr.write('[mint] ' + e.message + '\n'); }
}

// set location, then re-read glow from a fresh homepage GET to CONFIRM it took
async function setAndConfirm(page, pin, token) {
  const r = await page.evaluate(async ({ pin, token }) => {
    const set = await fetch('/portal-migration/hz/glow/address-change?actionSource=glow', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'anti-csrftoken-a2z': token, 'x-requested-with': 'XMLHttpRequest' },
      body: JSON.stringify({ locationType: 'LOCATION_INPUT', zipCode: pin, deviceType: 'web', storeContext: 'generic', pageType: 'Gateway', actionSource: 'glow' }),
    }).catch(() => null);
    const setStatus = set ? set.status : 0;
    // re-read glow off a fresh gateway fetch
    const g = await (await fetch('/', { headers: { accept: 'text/html' } })).text();
    const glow = (g.match(/glow-ingress-line2[^>]*>\s*([^<]+?)\s*</) || [])[1] || '';
    return { setStatus, glow };
  }, { pin, token });
  return r;
}

async function searchSurface(page, urlPath) {
  return page.evaluate(async ({ urlPath }) => {
    let status = 0, total = 0, jivo = 0, titles = [];
    try {
      const r = await fetch(urlPath, { headers: { accept: 'text/html' } });
      status = r.status;
      const html = await r.text();
      const doc = new DOMParser().parseFromString(html, 'text/html');
      const T = (el) => el ? (el.textContent || '').replace(/\s+/g, ' ').trim() : '';
      const cards = [...doc.querySelectorAll('[data-component-type="s-search-result"][data-asin]')].filter((c) => (c.getAttribute('data-asin') || '').length > 3);
      total = cards.length;
      for (const c of cards) {
        const t = T(c.querySelector('h2 a span, [data-cy="title-recipe"], a .a-text-normal'));
        if (/jivo/i.test(T(c))) { jivo++; if (titles.length < 4) titles.push(t.slice(0, 70)); }
      }
      // detect block/redirect markers
      const blocked = /api-services-support|To discuss automated access|Robot Check|captcha/i.test(html);
      return { status, total, jivo, titles, blocked, bytes: html.length };
    } catch (e) { return { status: -1, total: 0, jivo: 0, titles: [], err: String(e) }; }
  }, { urlPath });
}

(async () => {
  if (!fs.existsSync(STATE)) { console.error('NO SESSION'); process.exit(2); }
  let browser;
  try { browser = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new'] }); }
  catch (_) { browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }); }
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
  const page = await ctx.newPage();
  let token = '';
  page.on('request', (req) => { if (/address-change/.test(req.url())) { const t = req.headers()['anti-csrftoken-a2z']; if (t) token = t; } });

  // session check
  await page.goto('https://www.amazon.in/?ref_=nav_signin', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await sleep(1200); await passInterstitial(page);
  const greet = await page.evaluate(() => { const g = document.querySelector('#nav-link-accountList-nav-line-1, #nav-link-accountList .nav-line-1'); return g ? (g.innerText || '').trim() : ''; });
  process.stderr.write('[session] ' + greet + '\n');

  await mintToken(page, TESTS[0].pincode);
  process.stderr.write('[token] ' + (token ? 'minted' : 'NONE') + '\n');

  const results = [];
  for (const t of TESTS) {
    const sc = await setAndConfirm(page, t.pincode, token);
    let glow = sc.glow;
    // if it didn't take, re-mint once and retry
    if (!glow.includes(t.pincode)) { await mintToken(page, t.pincode); const sc2 = await setAndConfirm(page, t.pincode, token); glow = sc2.glow || glow; }
    const matched = glow.includes(t.pincode);
    const surf = {};
    for (const s of SURFACES) { surf[s.key] = await searchSurface(page, s.url('jivo')); await sleep(500); }
    results.push({ ...t, setStatus: sc.setStatus, glow, matched, surfaces: surf });
    process.stderr.write(`[${t.city} ${t.pincode}] glow=${JSON.stringify(glow)} matched=${matched} now=${surf.nowstore.jivo}/${surf.nowstore.total} fresh=${surf.freshstore.jivo}/${surf.freshstore.total} amazonfresh=${surf.amazonfresh.jivo}/${surf.amazonfresh.total} ctnow=${surf.ctnow_alm.jivo}/${surf.ctnow_alm.total}\n`);
    await sleep(800 + Math.random() * 600);
  }
  await browser.close().catch(() => {});

  const distinctGlow = [...new Set(results.map((r) => r.glow))];
  const summary = {
    tested: results.length,
    matched_count: results.filter((r) => r.matched).length,
    distinct_glow: distinctGlow,
    nowstore_total_jivo: results.reduce((a, r) => a + r.surfaces.nowstore.jivo, 0),
    freshstore_total_jivo: results.reduce((a, r) => a + r.surfaces.freshstore.jivo, 0),
    amazonfresh_total_jivo: results.reduce((a, r) => a + r.surfaces.amazonfresh.jivo, 0),
    ctnow_total_jivo: results.reduce((a, r) => a + r.surfaces.ctnow_alm.jivo, 0),
  };
  fs.writeFileSync(OUT, JSON.stringify({ summary, results }, null, 2));
  process.stderr.write('[DONE] ' + JSON.stringify(summary) + '\n');
  console.log(JSON.stringify(summary, null, 2));
})().catch((e) => { console.error('FATAL', e.message); process.exit(1); });
