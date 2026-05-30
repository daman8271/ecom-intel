// Validate the per-pincode mechanism: with the logged-in session, set the GLOW delivery
// pincode to several test pincodes and re-run the nowstore "jivo" search, to confirm
//   (a) we can switch location programmatically,
//   (b) Now results/slots change per pincode (metro serviceable vs not).
// If GLOW-pincode alone doesn't reflect Now serviceability, we fall back to saved addresses.
//
//   node probe_pincode_switch.js
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const STATE = path.join(__dirname, 'secrets', 'amazon-now.storageState.json');
const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// metro (expect Now) + non-metro (expect no Now) mix
const PINS = process.env.PINS ? process.env.PINS.split(',') : ['400017', '560001', '700001', '174001'];

async function passInterstitial(page) {
  const hit = await page.evaluate(() => /continue shopping/i.test(document.body.innerText || '') && !document.querySelector('#nav-link-accountList')).catch(() => false);
  if (!hit) return;
  try { await page.getByRole('button', { name: /continue shopping/i }).click({ timeout: 6000 }); } catch (_) {}
  await sleep(1500);
}

async function setPincode(page, pin) {
  await page.goto('https://www.amazon.in/?ref_=nav_signin', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await sleep(1500); await passInterstitial(page);
  try {
    await page.click('#nav-global-location-popover-link, #glow-ingress-block', { timeout: 8000 });
    await sleep(1800);
    await page.fill('#GLUXZipUpdateInput', pin, { timeout: 8000 });
    await sleep(500);
    try { await page.click('#GLUXZipUpdate input[type="submit"], #GLUXZipUpdate-announce', { timeout: 5000 }); } catch (_) {}
    await sleep(1800);
    try { await page.click('button[name="glowDoneButton"], .a-popover-footer #GLUXConfirmClose, input[name="glowDoneButton"]', { timeout: 4000 }); } catch (_) {}
    await sleep(1500);
  } catch (e) { return { err: e.message }; }
  const glow = await page.evaluate(() => { const g = document.getElementById('glow-ingress-line2'); return g ? (g.innerText || '').replace(/\s+/g, ' ').trim() : ''; });
  return { glow };
}

async function searchNow(page) {
  const r = await page.goto('https://www.amazon.in/s?k=jivo&i=nowstore', { waitUntil: 'domcontentloaded', timeout: 40000 });
  await sleep(2200); await passInterstitial(page);
  const d = await page.evaluate(() => {
    const T = (el) => (el ? (el.innerText || '').replace(/\s+/g, ' ').trim() : '');
    const cards = [...document.querySelectorAll('[data-component-type="s-search-result"][data-asin]')].filter((c) => (c.getAttribute('data-asin') || '').length > 3);
    const promises = cards.map((c) => T(c.querySelector('[class*="delivery" i]')));
    const nowSlots = promises.filter((p) => /today|tomorrow|\d+\s*(am|pm)|in \d+\s*(hour|min)/i.test(p));
    return {
      count: cards.length,
      http503: /503|rush hour|service unavailable/i.test(document.body.innerText || ''),
      nowSlotCount: nowSlots.length,
      sampleSlot: nowSlots[0] || promises[0] || '',
      jivoAsins: cards.filter((c) => /jivo/i.test(T(c))).map((c) => c.getAttribute('data-asin')).slice(0, 8),
    };
  });
  return { http: r ? r.status() : null, ...d };
}

(async () => {
  let browser;
  try { browser = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new'] }); }
  catch (_) { browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }); }
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
  const page = await ctx.newPage();
  const out = [];
  for (const pin of PINS) {
    const set = await setPincode(page, pin);
    const res = await searchNow(page);
    out.push({ pin, glow: set.glow || set.err, ...res });
    process.stderr.write(`[pin ${pin}] glow="${set.glow || set.err}" http=${res.http} results=${res.count} nowSlots=${res.nowSlotCount} slot="${res.sampleSlot}"\n`);
    await sleep(2500);
  }
  fs.writeFileSync(path.join(__dirname, 'secrets', 'probe_pincode_switch.json'), JSON.stringify(out, null, 2));
  process.stderr.write('[done]\n');
  await browser.close().catch(() => {});
})();
