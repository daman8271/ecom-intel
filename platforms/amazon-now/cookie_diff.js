// Find which cookie(s) encode the delivery pincode: set location A, snapshot cookies;
// set location B, snapshot; diff. If a per-request location cookie exists, we can inject
// it per-context (no account-syncing GLOW call) and parallelize safely.
const { chromium } = require('playwright');
const path = require('path');
const STATE = path.join(__dirname, 'secrets/amazon-now.storageState.json');
const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function setpin(page, pin) {
  await page.goto('https://www.amazon.in/?ref_=nav_signin', { waitUntil: 'domcontentloaded', timeout: 45000 }); await sleep(1200);
  try {
    await page.click('#nav-global-location-popover-link', { timeout: 8000 }); await sleep(1400);
    await page.fill('#GLUXZipUpdateInput', pin, { timeout: 8000 }); await sleep(400);
    try { await page.click('#GLUXZipUpdate input[type="submit"], #GLUXZipUpdate-announce', { timeout: 5000 }); } catch (_) {}
    await sleep(1600);
    try { await page.click('button[name="glowDoneButton"], .a-popover-footer #GLUXConfirmClose', { timeout: 4000 }); } catch (_) {}
    await sleep(1000);
  } catch (e) {}
  return page.evaluate(() => { const g = document.getElementById('glow-ingress-line2'); return g ? g.innerText.replace(/\s+/g, ' ').trim() : ''; });
}

(async () => {
  let b; try { b = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new'] }); } catch (_) { b = await chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }); }
  const ctx = await b.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
  const page = await ctx.newPage();

  const g1 = await setpin(page, '400017');
  const c1 = Object.fromEntries((await ctx.cookies()).map((c) => [c.name, c.value]));
  const g2 = await setpin(page, '110001');
  const c2 = Object.fromEntries((await ctx.cookies()).map((c) => [c.name, c.value]));

  console.log('glow1 (400017):', g1);
  console.log('glow2 (110001):', g2);
  console.log('=== cookies that CHANGED between the two pincodes ===');
  const names = new Set([...Object.keys(c1), ...Object.keys(c2)]);
  for (const n of names) {
    if (c1[n] !== c2[n]) console.log(`  ${n}:\n    A=${(c1[n] || '(absent)').slice(0, 80)}\n    B=${(c2[n] || '(absent)').slice(0, 80)}`);
  }
  await b.close();
})();
