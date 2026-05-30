// Capture the change-token from ONE UI set, then raw-POST each pincode and read the
// resulting location from the nowstore search HTML. Confirms raw fast-set actually works.
const { chromium } = require('playwright');
const path = require('path');
const STATE = path.join(__dirname, 'secrets/amazon-now.storageState.json');
const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function rawSetAndSearch(page, pin, token) {
  return page.evaluate(async ({ pin, token }) => {
    const sr = await fetch('/portal-migration/hz/glow/address-change?actionSource=glow', {
      method: 'POST', headers: { 'content-type': 'application/json', 'anti-csrftoken-a2z': token, 'x-requested-with': 'XMLHttpRequest' },
      body: JSON.stringify({ locationType: 'LOCATION_INPUT', zipCode: pin, deviceType: 'web', storeContext: 'generic', pageType: 'Gateway', actionSource: 'glow' }),
    });
    const setStatus = sr.status;
    const r = await fetch('/s?k=jivo&i=nowstore', { headers: { accept: 'text/html' } });
    const html = await r.text();
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const T = (el) => el ? (el.textContent || '').replace(/\s+/g, ' ').trim() : '';
    const cards = [...doc.querySelectorAll('[data-component-type="s-search-result"][data-asin]')];
    const jivo = cards.filter((c) => /jivo/i.test(T(c)));
    return { setStatus, glow: (html.match(/glow-ingress-line2[^>]*>\s*([^<]+?)\s*</) || [])[1] || '', cards: cards.length, jivo: jivo.length };
  }, { pin, token });
}

(async () => {
  let b; try { b = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new'] }); } catch (_) { b = await chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }); }
  const ctx = await b.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
  const page = await ctx.newPage();
  let token = '';
  page.on('request', (req) => { if (/address-change/.test(req.url())) { const t = req.headers()['anti-csrftoken-a2z']; if (t) token = t; } });

  await page.goto('https://www.amazon.in/?ref_=nav_signin', { waitUntil: 'domcontentloaded', timeout: 45000 }); await sleep(1500);
  // one real UI set to capture a change-token
  try {
    await page.click('#nav-global-location-popover-link', { timeout: 8000 }); await sleep(1500);
    await page.fill('#GLUXZipUpdateInput', '560001', { timeout: 8000 }); await sleep(400);
    try { await page.click('#GLUXZipUpdate input[type="submit"], #GLUXZipUpdate-announce', { timeout: 5000 }); } catch (_) {}
    await sleep(1800);
    try { await page.click('button[name="glowDoneButton"], .a-popover-footer #GLUXConfirmClose', { timeout: 4000 }); } catch (_) {}
    await sleep(1000);
  } catch (e) {}
  console.log('change-token:', token ? token.slice(0, 22) + '…' : 'NONE');

  for (const pin of ['400017', '700001', '174001', '110001', '600001']) {
    const t0 = Date.now();
    const r = await rawSetAndSearch(page, pin, token);
    const ok = r.glow.includes(pin) ? 'OK' : '** MISMATCH **';
    console.log(`[${pin}] ${((Date.now() - t0) / 1000).toFixed(1)}s set=${r.setStatus} glow="${r.glow}" cards=${r.cards} jivo=${r.jivo}  ${ok}`);
  }
  await b.close();
})();
