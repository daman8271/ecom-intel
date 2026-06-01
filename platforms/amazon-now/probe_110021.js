// DEEP-DIVE probe for pincode 110021 (Delhi) — ground-truth what Amazon Now actually
// shows vs what scrape.js captures. Sequential (one account, global location).
// Captures: (1) nowstore search for several queries WITHOUT dedup + full detail +
// pagination + Now-surface signals; (2) PDP-level price/delivery for target ASINs incl.
// the 1L sunflower & groundnut our search missed. Saves a JSON artifact + screenshots.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const STATE = path.join(__dirname, 'secrets', 'amazon-now.storageState.json');
const PIN = process.env.PIN || '110021';
const OUT = path.join(__dirname, 'secrets', `probe_${PIN}.json`);
const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const QUERIES = ['jivo', 'jivo sunflower oil', 'jivo groundnut oil'];
// target ASINs to open as PDPs: the two MISSING ones + a few present ones for price cross-check
const PDP_ASINS = {
  B0B4SJTNF2: 'Sunflower 1L (MISSING from search)',
  B0CKFFW9B6: 'Groundnut 1L (MISSING from search)',
  B0991VMDB1: 'Sunflower 5L (present)',
  B09HZY97FR: 'Extra Light Olive 1L (present, price diff)',
  B093BMGPQC: 'Extra Virgin Olive 1L (present, price diff)',
  B0821DNF2W: 'Pomace Olive 1L (present, price diff)',
};

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
  } catch (e) { process.stderr.write('[loc] ui err ' + e.message + '\n'); }
  return page.evaluate(() => {
    const g = document.getElementById('glow-ingress-line2');
    return g ? (g.innerText || '').replace(/\s+/g, ' ').trim() : '';
  });
}

async function searchSurface(page, query, pageNo) {
  const url = '/s?k=' + encodeURIComponent(query) + '&i=nowstore' + (pageNo > 1 ? '&page=' + pageNo : '');
  return page.evaluate(async ({ url }) => {
    const r = await fetch(url, { headers: { accept: 'text/html' } });
    const html = await r.text();
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const T = (el) => el ? (el.textContent || '').replace(/\s+/g, ' ').trim() : '';
    const cards = [...doc.querySelectorAll('[data-component-type="s-search-result"][data-asin]')]
      .filter((c) => (c.getAttribute('data-asin') || '').length > 3)
      .map((c) => ({
        asin: c.getAttribute('data-asin'),
        title: T(c.querySelector('h2 a span, [data-cy="title-recipe"]')).slice(0, 120),
        price: T(c.querySelector('.a-price .a-offscreen')),
        mrp: T(c.querySelector('[data-a-strike="true"] .a-offscreen')),
        slot: T(c.querySelector('[class*="delivery" i], .udm-primary-delivery-message')).slice(0, 90),
        isJivo: /jivo/i.test(T(c)),
      }));
    // result-count line + surface signals
    const countLine = T(doc.querySelector('[data-component-type="s-result-info-bar"], .s-breadcrumb, [cel_widget_id*="result-info"]')).slice(0, 140);
    const hasNext = !!doc.querySelector('a.s-pagination-next:not(.s-pagination-disabled)');
    const body = (doc.body && doc.body.textContent || '');
    const signals = {
      mentions_amazon_now: /amazon\s*now/i.test(html),
      mentions_get_in_hours: /get it in|within \d+ ?h|delivered in|\d+\s*hour/i.test(body),
      store_header: T(doc.querySelector('#nav-subnav, [data-csa-c-slot-id="nav-subnav"]')).slice(0, 120),
    };
    return { jivoCount: cards.filter((c) => c.isJivo).length, totalCards: cards.length, countLine, hasNext, signals, jivoCards: cards.filter((c) => c.isJivo) };
  }, { url });
}

async function pdp(page, asin) {
  await page.goto('https://www.amazon.in/dp/' + asin, { waitUntil: 'domcontentloaded', timeout: 40000 });
  await sleep(2000); await passInterstitial(page);
  return page.evaluate(() => {
    const T = (el) => (el ? (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim() : '');
    const body = document.body.innerText || '';
    return {
      title: (document.querySelector('#productTitle') ? T(document.querySelector('#productTitle')) : document.title).slice(0, 90),
      buybox_price: T(document.querySelector('#corePrice_feature_div .a-offscreen, .priceToPay .a-offscreen, #price_inside_buybox')),
      availability: T(document.querySelector('#availability')).slice(0, 80),
      delivery_block: T(document.querySelector('#mir-layout-DELIVERY_BLOCK, #deliveryBlockMessage, [data-csa-c-content-id="DEXUnifiedCXPDM"]')).slice(0, 200),
      seller: T(document.querySelector('#sellerProfileTriggerId, #merchant-info')).slice(0, 100),
      now_signal: /amazon\s*now|get it in \d|within \d+ ?h|delivered in \d/i.test(body),
      not_available: /currently unavailable|cannot be shipped to your|out of stock/i.test(body),
    };
  });
}

(async () => {
  if (!fs.existsSync(STATE)) { console.error('no session'); process.exit(2); }
  let browser;
  try { browser = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new'] }); }
  catch (_) { browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }); }
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
  const page = await ctx.newPage();
  const out = { ts: new Date().toISOString(), pin: PIN, location: '', searches: {}, pdps: {} };

  out.location = await setLocation(page, PIN);
  process.stderr.write(`[loc] resolved: "${out.location}"\n`);

  for (const q of QUERIES) {
    const p1 = await searchSurface(page, q, 1);
    await sleep(800);
    let p2 = null;
    if (p1.hasNext) { p2 = await searchSurface(page, q, 2); await sleep(800); }
    out.searches[q] = { page1: p1, page2: p2 };
    process.stderr.write(`[search] "${q}" -> ${p1.jivoCount} jivo (page1, total cards ${p1.totalCards}, next=${p1.hasNext})  count="${p1.countLine}"\n`);
  }
  try { await page.goto('/s?k=jivo&i=nowstore', { waitUntil: 'domcontentloaded', timeout: 40000 }); await sleep(1500); await page.screenshot({ path: path.join(__dirname, 'secrets', `probe_${PIN}_search.png`), fullPage: false }); } catch (_) {}

  for (const [asin, label] of Object.entries(PDP_ASINS)) {
    try { out.pdps[asin] = { label, ...(await pdp(page, asin)) }; }
    catch (e) { out.pdps[asin] = { label, error: e.message }; }
    process.stderr.write(`[pdp] ${asin} ${label} -> price="${out.pdps[asin].buybox_price || ''}" avail="${out.pdps[asin].availability || ''}" now=${out.pdps[asin].now_signal} na=${out.pdps[asin].not_available}\n`);
    await sleep(1000);
  }

  await browser.close().catch(() => {});
  fs.writeFileSync(OUT, JSON.stringify(out, null, 2));
  process.stderr.write('[done] wrote ' + OUT + '\n');
})();
