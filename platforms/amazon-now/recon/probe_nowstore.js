// RECON — fully characterize the no-login Amazon NOW storefront (i=nowstore).
// Runs a set of Jivo queries against ?i=nowstore, captures per-card asin/title/
// price/ETA/stock, plus the seller link (ctnow proxy). Modest pacing (~3s).
// Saves a JSON dump under recon/. Reuses the proven interstitial-pass pattern.
//
//   node probe_nowstore.js                 # default location (Mumbai 400017)
//   PIN=110001 node probe_nowstore.js      # set a pincode via GLOW first
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const PIN = process.env.PIN || '';
const GAP = parseInt(process.env.GAP || '3200', 10); // spacing between live hits

const QUERIES = (process.env.QUERIES || [
  'jivo', 'jivo oil', 'jivo olive oil', 'jivo canola', 'jivo ghee',
  'jivo honey', 'jivo chia', 'jivo mustard', 'jivo sunflower', 'jivo groundnut',
].join('|')).split('|');

async function passInterstitial(page) {
  await page.goto('https://www.amazon.in/', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await page.waitForTimeout(2000);
  try { await page.getByRole('button', { name: /continue shopping/i }).click({ timeout: 7000 }); } catch (e) {}
  await page.waitForTimeout(2500);
}

// Set delivery pincode through the GLOW widget. Returns the resulting glow text.
async function setPincode(page, pin) {
  try {
    await page.goto('https://www.amazon.in/', { waitUntil: 'domcontentloaded', timeout: 45000 });
    await page.waitForTimeout(1500);
    await page.click('#glow-ingress-block, #nav-global-location-popover-link', { timeout: 8000 });
    await page.waitForTimeout(1800);
    await page.fill('#GLUXZipUpdateInput', pin, { timeout: 8000 });
    await page.waitForTimeout(600);
    // apply
    try { await page.click('#GLUXZipUpdate input[type="submit"], #GLUXZipUpdate-announce', { timeout: 5000 }); } catch (e) {}
    await page.waitForTimeout(1800);
    // confirm / continue dialog
    try { await page.click('button[name="glowDoneButton"], .a-popover-footer #GLUXConfirmClose, input[name="glowDoneButton"]', { timeout: 4000 }); } catch (e) {}
    await page.waitForTimeout(1500);
    try { await page.click('.a-button-input[aria-labelledby*="GLUXConfirmClose"]', { timeout: 2500 }); } catch (e) {}
    await page.waitForTimeout(1500);
  } catch (e) {
    return { err: e.message };
  }
  const glow = await page.evaluate(() => {
    const T = (el) => (el ? (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim() : '');
    return T(document.getElementById('glow-ingress-line2'));
  });
  return { glow };
}

async function searchNowstore(page, q) {
  const url = `https://www.amazon.in/s?k=${encodeURIComponent(q)}&i=nowstore`;
  let r;
  // 503 / interstitial are transient throttles on this datacenter IP. Retry up
  // to 3x, re-passing the "Continue shopping" interstitial between tries.
  for (let attempt = 1; attempt <= 3; attempt++) {
    try { r = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 35000 }); }
    catch (e) { return { q, url, err: 'nav:' + e.message }; }
    await page.waitForTimeout(2400);
    const code = r ? r.status() : null;
    const stuck = await page.evaluate(() => /continue shopping/i.test(document.body.innerText || '') && document.querySelectorAll('[data-component-type="s-search-result"][data-asin]').length === 0);
    if (code === 200 && !stuck) break;
    if (attempt < 3) { await passInterstitial(page); await page.waitForTimeout(3500); }
  }

  const d = await page.evaluate(() => {
    const T = (el) => (el ? (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim() : '');
    const body = (document.body && document.body.innerText) || '';
    const cards = [...document.querySelectorAll('[data-component-type="s-search-result"][data-asin]')]
      .filter((c) => (c.getAttribute('data-asin') || '').length > 3);
    const items = cards.map((c) => {
      const full = T(c);
      const priceEl = c.querySelector('.a-price .a-offscreen');
      const mrpEl = c.querySelector('.a-price.a-text-price .a-offscreen, span[data-a-strike="true"] .a-offscreen');
      const sellerLink = c.querySelector('a[href*="almBrandId=ctnow"], a[href*="seller=A3DRET2ZTE1T2S"]');
      // any delivery / ETA promise text on the card
      const promiseEl = c.querySelector('[class*="delivery" i], .udm-primary-delivery-message, [data-cy="delivery-recipe"]');
      return {
        asin: c.getAttribute('data-asin'),
        brand: T(c.querySelector('h2.a-size-mini span, .a-size-base-plus.a-color-base')).slice(0, 30),
        title: T(c.querySelector('a.a-link-normal .a-text-normal, h2 a span, [data-cy="title-recipe"] h2 span, .a-size-base-plus')).slice(0, 110),
        price: T(priceEl),
        mrp: T(mrpEl),
        ctnow: !!sellerLink,
        ctnowHref: sellerLink ? sellerLink.getAttribute('href').slice(0, 120) : '',
        promise: T(promiseEl).slice(0, 80),
        oos: /currently unavailable|out of stock|temporarily out of stock|sold out/i.test(full),
        etaMins: /in \d+\s*(min|hour)|get it today|same.?day|tatkal|within \d+\s*(min|hour)/i.test(full),
      };
    });
    return {
      finalUrl: location.href,
      loginWall: /sign-?in|ap\/signin/i.test(location.href) || !!document.getElementById('ap_password'),
      captcha: /enter the characters you see below|type the characters|not a robot|automated access/i.test(body),
      interstitial: /continue shopping/i.test(body) && cards.length === 0,
      glow: T(document.getElementById('glow-ingress-line2')),
      resultHdr: T(document.querySelector('[data-component-type="s-result-info-bar"], .s-breadcrumb, .a-section.a-spacing-small.a-spacing-top-small')).slice(0, 120),
      count: cards.length,
      bodyLen: body.length,
      items,
    };
  });
  return { q, url, http: r ? r.status() : null, ...d };
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({
    userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata',
    viewport: { width: 1366, height: 900 },
  });
  await ctx.route('**/*', (route) => {
    const t = route.request().resourceType();
    if (['image', 'font', 'media'].includes(t)) return route.abort();
    return route.continue();
  });
  const page = await ctx.newPage();
  await passInterstitial(page);

  let pinResult = { glow: 'default' };
  if (PIN) {
    pinResult = await setPincode(page, PIN);
    process.stderr.write(`[pin] set ${PIN} -> ${JSON.stringify(pinResult)}\n`);
    await page.waitForTimeout(GAP);
  }

  const out = { pin: PIN || 'default', pinResult, ts: new Date().toISOString(), probes: [] };
  for (const q of QUERIES) {
    const res = await searchNowstore(page, q);
    out.probes.push(res);
    const flag = res.err ? `ERR ${res.err}` : `http=${res.http} n=${res.count} login=${res.loginWall} captcha=${res.captcha} inter=${res.interstitial}`;
    process.stderr.write(`\n[q] "${q}" ${flag} glow=${JSON.stringify(res.glow)} hdr=${JSON.stringify(res.resultHdr)}\n`);
    (res.items || []).forEach((it) => process.stderr.write(
      `    ${it.asin} ₹${it.price || '-'}/${it.mrp || '-'} ctnow=${it.ctnow} oos=${it.oos} eta=${it.etaMins} promise="${it.promise}" "${it.title.slice(0,46)}"\n`));
    await page.waitForTimeout(GAP);
  }

  const fn = path.join(__dirname, `nowstore.${PIN || 'default'}.json`);
  fs.writeFileSync(fn, JSON.stringify(out, null, 2));
  process.stderr.write(`\n[done] wrote ${fn}\n`);
  await browser.close();
})();
