// GROUND-TRUTH probe for the NOW/FRESH mislabel fix (agent-1).
// For each pincode: set location via GLOW UI, fetch the ctnow surface, and dump
// per-Jivo-card discriminators: blue speed badge text, delivery-recipe text,
// nowBadge flag, plus page-level signals (amazonNowPage regex, result-info-bar,
// any "in N minutes"/"amazon now" mentions). Read-only; no result.json written.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const STATE = path.join(__dirname, 'secrets', 'amazon-now.storageState.json');
const OUT = path.join(__dirname, 'secrets', 'groundtruth.json');
const PINS = (process.env.PINS || '560034,160001,160011,160014,141001').split(',').map((s) => s.trim()).filter(Boolean);
const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

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

async function probe(page, pin) {
  const loc = await setLocation(page, pin);
  const parsed = await page.evaluate(async () => {
    const r = await fetch('/s?k=jivo&almBrandId=ctnow', { headers: { accept: 'text/html' } });
    const html = await r.text();
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const T = (el) => el ? (el.textContent || '').replace(/\s+/g, ' ').trim() : '';
    const cards = [...doc.querySelectorAll('[data-component-type="s-search-result"][data-asin]')].filter((c) => (c.getAttribute('data-asin') || '').length > 3);
    const jivo = cards.filter((c) => /jivo/i.test(T(c)));
    const rows = jivo.map((c) => {
      const badgeEl = c.querySelector('.dex-text-slanted-blue-highlight');
      return {
        asin: c.getAttribute('data-asin'),
        title: T(c.querySelector('h2 a span, [data-cy="title-recipe"]')).slice(0, 60),
        badge: T(badgeEl),
        nowBadge: !!(badgeEl && T(badgeEl)),
        deliv: T(c.querySelector('[data-cy="delivery-recipe"]')).slice(0, 100),
        udmBadge: T(c.querySelector('.udm-badge-block')).slice(0, 60),
      };
    });
    const body = doc.body ? doc.body.textContent : '';
    const minHits = [...new Set((body.match(/\b(?:in|within|get it in)\s+\d+\s*(?:min|minute|mins|minutes|hour|hours|hr|hrs)/gi) || []))].slice(0, 12);
    // where does "amazon now" appear? grab small contexts
    const nowCtx = [...new Set((html.match(/.{0,25}amazon\s*now.{0,25}/gi) || []).map((s) => s.replace(/\s+/g, ' ').trim()))].slice(0, 6);
    return {
      amazonNowPage: /amazon\s*now/i.test(html),
      nowContexts: nowCtx,
      resultBar: T(doc.querySelector('[data-component-type="s-result-info-bar"], .s-breadcrumb')).slice(0, 90),
      totalCards: cards.length, jivoCount: jivo.length,
      minHits, rows,
    };
  });
  return { pin, location: loc, ...parsed };
}

(async () => {
  if (!fs.existsSync(STATE)) { console.error('no session'); process.exit(2); }
  let browser;
  try { browser = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new', '--disable-blink-features=AutomationControlled'] }); }
  catch (_) { browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }); }
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
  await ctx.addInitScript(() => { Object.defineProperty(navigator, 'webdriver', { get: () => undefined }); });
  const page = await ctx.newPage();

  const out = { ts: new Date().toISOString(), results: [] };
  for (const pin of PINS) {
    try {
      const res = await probe(page, pin);
      out.results.push(res);
      const tiers = {};
      for (const r of res.rows) { const b = (r.badge || '(none)'); tiers[b] = (tiers[b] || 0) + 1; }
      process.stderr.write(`[${pin}] loc="${res.location}" nowPage=${res.amazonNowPage} jivo=${res.jivoCount}/${res.totalCards} minHits=${JSON.stringify(res.minHits)} badges=${JSON.stringify(tiers)}\n`);
    } catch (e) { out.results.push({ pin, err: e.message }); process.stderr.write(`[${pin}] ERR ${e.message}\n`); }
    await sleep(1500);
  }
  await browser.close().catch(() => {});
  fs.writeFileSync(OUT, JSON.stringify(out, null, 2));
  process.stderr.write('[done] -> ' + OUT + '\n');
})();
