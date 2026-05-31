// THE speed-lever test: is Amazon's delivery location COOKIE-scoped (per browser
// context => parallel-safe, flipkart-style) or SESSION-scoped server-side (shared
// across contexts that share session-id => parallel collides, must stay sequential)?
//
// Method: 3 isolated contexts from the SAME storageState, each sets a DIFFERENT pincode
// CONCURRENTLY, then each re-reads its own glow label. If each keeps its own city =>
// cookie-scoped => we can parallelize Fresh. If they stomp each other (all show one
// city) => session-scoped => Fresh stays sequential like Now.
// Read-only beyond setting location (which the Now sweep already does 332x). Gentle: 3 ctx.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const STATE = path.join(__dirname, 'secrets', 'amazon-now.storageState.json');
const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const PINS = [
  { city: 'Delhi', pincode: '110001' },
  { city: 'Bengaluru', pincode: '560034' },
  { city: 'Kolkata', pincode: '700019' },
];

async function passInterstitial(page) {
  const hit = await page.evaluate(() => /continue shopping/i.test(document.body.innerText || '') && !document.querySelector('#nav-link-accountList')).catch(() => false);
  if (!hit) return;
  try { await page.getByRole('button', { name: /continue shopping/i }).click({ timeout: 6000 }); } catch (_) {}
  await page.waitForLoadState('domcontentloaded', { timeout: 20000 }).catch(() => {});
  await sleep(1000);
}
async function mintToken(page, pin) {
  let token = '';
  page.on('request', (req) => { if (/address-change/.test(req.url())) { const t = req.headers()['anti-csrftoken-a2z']; if (t) token = t; } });
  await page.goto('https://www.amazon.in/?ref_=nav_signin', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await sleep(900); await passInterstitial(page);
  try {
    await page.click('#nav-global-location-popover-link, #glow-ingress-block', { timeout: 8000 }); await sleep(1100);
    await page.fill('#GLUXZipUpdateInput', pin, { timeout: 8000 }); await sleep(300);
    try { await page.click('#GLUXZipUpdate input[type="submit"], #GLUXZipUpdate-announce', { timeout: 5000 }); } catch (_) {}
    await sleep(1300);
    try { await page.click('button[name="glowDoneButton"], .a-popover-footer #GLUXConfirmClose', { timeout: 4000 }); } catch (_) {}
    await sleep(700);
  } catch (_) {}
  return token;
}
async function setAndRead(page, pin, token) {
  return page.evaluate(async ({ pin, token }) => {
    await fetch('/portal-migration/hz/glow/address-change?actionSource=glow', {
      method: 'POST', headers: { 'content-type': 'application/json', 'anti-csrftoken-a2z': token, 'x-requested-with': 'XMLHttpRequest' },
      body: JSON.stringify({ locationType: 'LOCATION_INPUT', zipCode: pin, deviceType: 'web', storeContext: 'generic', pageType: 'Gateway', actionSource: 'glow' }),
    }).catch(() => null);
    const g = await (await fetch('/', { headers: { accept: 'text/html' } })).text();
    return (g.match(/glow-ingress-line2[^>]*>\s*([^<]+?)\s*</) || [])[1] || '';
  }, { pin, token });
}

(async () => {
  let browser;
  try { browser = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new'] }); }
  catch (_) { browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }); }

  // 3 isolated contexts, same session jar
  const workers = await Promise.all(PINS.map(async (p) => {
    const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
    const page = await ctx.newPage();
    const token = await mintToken(page, p.pincode);
    return { p, ctx, page, token };
  }));

  // CONCURRENTLY set each context to its own pincode, then read back
  const reads = await Promise.all(workers.map(async (w) => {
    const glow = await setAndRead(w.page, w.p.pincode, w.token);
    return { city: w.p.city, pincode: w.p.pincode, glow, ok: glow.includes(w.p.pincode) };
  }));
  // second read AFTER all sets are done — to catch last-writer-wins server-side state
  const reread = await Promise.all(workers.map(async (w) => {
    const g = await w.page.evaluate(async () => (await (await fetch('/', { headers: { accept: 'text/html' } })).text()).match(/glow-ingress-line2[^>]*>\s*([^<]+?)\s*</)?.[1] || '');
    return { pincode: w.p.pincode, glow_after: g, still_ok: g.includes(w.p.pincode) };
  }));

  for (const w of workers) await w.ctx.close().catch(() => {});
  await browser.close().catch(() => {});

  const verdict = reads.every((r) => r.ok) && reread.every((r) => r.still_ok)
    ? 'COOKIE_SCOPED — parallel SAFE (each context kept its own location)'
    : 'SESSION_SCOPED — parallel COLLIDES (must stay sequential)';
  console.log(JSON.stringify({ verdict, reads, reread }, null, 2));
})().catch((e) => { console.error('FATAL', e.message); process.exit(1); });
