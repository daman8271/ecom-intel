// Compare the almBrandId=ctnow search surface vs the old i=nowstore at the SAME location,
// and inspect the exact delivery/ETA wording per card — to decide if ctnow is the real
// Amazon Now (minute/hour ETAs) and whether it carries more SKUs / true Now prices.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const STATE = path.join(__dirname, 'secrets', 'amazon-now.storageState.json');
const OUT = path.join(__dirname, 'secrets');
const PIN = process.env.PIN || '560034';
const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const SURFACES = {
  ctnow: '/s?k=jivo&almBrandId=ctnow',
  nowstore: '/s?k=jivo&i=nowstore',
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
  return page.evaluate(() => { const g = document.getElementById('glow-ingress-line2'); return g ? (g.innerText || '').replace(/\s+/g, ' ').trim() : ''; });
}

async function fetchSurface(page, urlPath, tag) {
  const r = await page.evaluate(async ({ urlPath }) => {
    const res = await fetch(urlPath, { headers: { accept: 'text/html' } });
    return { status: res.status, html: await res.text() };
  }, { urlPath });
  fs.writeFileSync(path.join(OUT, `html_${tag}.html`), r.html);
  // parse in page context
  const parsed = await page.evaluate(({ html }) => {
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const T = (el) => el ? (el.textContent || '').replace(/\s+/g, ' ').trim() : '';
    const cards = [...doc.querySelectorAll('[data-component-type="s-search-result"][data-asin]')].filter((c) => (c.getAttribute('data-asin') || '').length > 3);
    const jivo = cards.filter((c) => /jivo/i.test(T(c)));
    const rows = jivo.map((c) => ({
      asin: c.getAttribute('data-asin'),
      title: T(c.querySelector('h2 a span, [data-cy="title-recipe"]')).slice(0, 70),
      price: T(c.querySelector('.a-price .a-offscreen')),
      mrp: T(c.querySelector('[data-a-strike="true"] .a-offscreen')),
      delivery: T(c.querySelector('[data-cy="delivery-recipe"]')).slice(0, 90),
      deliv2: T(c.querySelector('[class*="delivery" i], .udm-primary-delivery-message')).slice(0, 90),
      cardhead: T(c).slice(0, 120),
    }));
    const count = T(doc.querySelector('[data-component-type="s-result-info-bar"], .s-breadcrumb')).slice(0, 80);
    // collect distinct ETA-ish strings anywhere in the doc
    const body = doc.body ? doc.body.textContent : '';
    const etaHits = [...new Set((body.match(/\b(?:in|within|get it in)\s+\d+\s*(?:min|minute|mins|minutes|hour|hours|hr|hrs)/gi) || []))].slice(0, 12);
    return {
      jivoCount: jivo.length, totalCards: cards.length, count,
      mentions_amazon_now: /amazon\s*now/i.test(html),
      etaHits, rows,
    };
  }, { html: r.html });
  return { status: r.status, htmlBytes: r.html.length, ...parsed };
}

(async () => {
  if (!fs.existsSync(STATE)) { console.error('no session'); process.exit(2); }
  let browser;
  try { browser = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new', '--disable-blink-features=AutomationControlled'] }); }
  catch (_) { browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }); }
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
  await ctx.addInitScript(() => { Object.defineProperty(navigator, 'webdriver', { get: () => undefined }); });
  const page = await ctx.newPage();

  const out = { ts: new Date().toISOString(), pin: PIN, location: '', surfaces: {} };
  out.location = await setLocation(page, PIN);
  process.stderr.write(`[loc] "${out.location}"\n`);

  for (const [tag, urlPath] of Object.entries(SURFACES)) {
    try {
      const res = await fetchSurface(page, urlPath, tag);
      out.surfaces[tag] = res;
      process.stderr.write(`[${tag}] jivo=${res.jivoCount}/${res.totalCards} now=${res.mentions_amazon_now} etaHits=${JSON.stringify(res.etaHits)} count="${res.count}"\n`);
    } catch (e) { out.surfaces[tag] = { err: e.message }; process.stderr.write(`[${tag}] ERR ${e.message}\n`); }
    await sleep(1200);
  }

  await browser.close().catch(() => {});
  fs.writeFileSync(path.join(OUT, 'probe_ctnow.json'), JSON.stringify(out, null, 2));
  process.stderr.write('[done] -> secrets/probe_ctnow.json (+ html_ctnow.html, html_nowstore.html)\n');
})();
