// Decisive test: capture the token from a REAL address-change request (via one UI set),
// then check if it's REUSABLE for raw-fetch POSTs to other pincodes.
const { chromium } = require('playwright');
const path = require('path');
const STATE = path.join(__dirname, 'secrets/amazon-now.storageState.json');
const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function glowNow(page) {
  return page.evaluate(async () => {
    const r = await fetch('/portal-migration/hz/glow/get-location-label?storeContext=generic&pageType=Gateway&actionSource=desktop-modal');
    const t = await r.text();
    return (t.match(/>([^<]*\d{6}[^<]*)</) || [])[1] || t.slice(0, 60);
  });
}
async function rawSet(page, pin, token) {
  return page.evaluate(async ({ pin, token }) => {
    const r = await fetch('/portal-migration/hz/glow/address-change?actionSource=glow', {
      method: 'POST', headers: { 'content-type': 'application/json', 'anti-csrftoken-a2z': token, 'x-requested-with': 'XMLHttpRequest' },
      body: JSON.stringify({ locationType: 'LOCATION_INPUT', zipCode: pin, deviceType: 'web', storeContext: 'generic', pageType: 'Gateway', actionSource: 'glow' }),
    });
    return { status: r.status, len: (await r.text()).length };
  }, { pin, token });
}

(async () => {
  let b; try { b = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new'] }); } catch (_) { b = await chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }); }
  const ctx = await b.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
  const page = await ctx.newPage();
  let changeToken = '';
  page.on('request', (req) => { if (/address-change/.test(req.url())) { const t = req.headers()['anti-csrftoken-a2z']; if (t) changeToken = t; } });

  await page.goto('https://www.amazon.in/?ref_=nav_signin', { waitUntil: 'domcontentloaded', timeout: 45000 }); await sleep(1500);
  // one REAL UI set of 110001 -> fires address-change, captures its token, changes location
  try {
    await page.click('#nav-global-location-popover-link', { timeout: 8000 }); await sleep(1500);
    await page.fill('#GLUXZipUpdateInput', '110001', { timeout: 8000 }); await sleep(400);
    try { await page.click('#GLUXZipUpdate input[type="submit"], #GLUXZipUpdate-announce', { timeout: 5000 }); } catch (_) {}
    await sleep(1800);
    try { await page.click('button[name="glowDoneButton"], .a-popover-footer #GLUXConfirmClose', { timeout: 4000 }); } catch (_) {}
    await sleep(1200);
  } catch (e) { console.log('ui set err', e.message); }
  console.log('UI set 110001 -> glow:', await glowNow(page), '| change-token:', changeToken ? changeToken.slice(0, 20) + '…' : 'NONE');

  // now reuse that token for raw POSTs to other pincodes
  for (const pin of ['400017', '700001']) {
    const r = await rawSet(page, pin, changeToken);
    await sleep(400);
    console.log(`raw set ${pin} -> http=${r.status} len=${r.len} | glow now:`, await glowNow(page));
  }
  await b.close();
})();
