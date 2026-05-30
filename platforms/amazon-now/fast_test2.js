// Capture a real anti-csrftoken-a2z from a live glow request (open the popover once),
// then reuse it for raw-fetch location sets. Verify the location actually changes.
const { chromium } = require('playwright');
const path = require('path');
const STATE = path.join(__dirname, 'secrets/amazon-now.storageState.json');
const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function setPinFast(page, pin, token) {
  return page.evaluate(async ({ pin, token }) => {
    const r = await fetch('/portal-migration/hz/glow/address-change?actionSource=glow', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'anti-csrftoken-a2z': token, 'x-requested-with': 'XMLHttpRequest' },
      body: JSON.stringify({ locationType: 'LOCATION_INPUT', zipCode: pin, deviceType: 'web', storeContext: 'generic', pageType: 'Gateway', actionSource: 'glow' }),
    });
    let body = ''; try { body = await r.text(); } catch (_) {}
    return { status: r.status, body: body.slice(0, 100) };
  }, { pin, token });
}
async function searchGlow(page) {
  return page.evaluate(async () => {
    const r = await fetch('/s?k=jivo&i=nowstore', { headers: { accept: 'text/html' } });
    const html = await r.text();
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const T = (el) => el ? (el.textContent || '').replace(/\s+/g, ' ').trim() : '';
    const cards = [...doc.querySelectorAll('[data-component-type="s-search-result"][data-asin]')];
    const jivo = cards.filter((c) => /jivo/i.test(T(c)));  // looser: textContent concatenates "JIVOCold"
    return { glow: (html.match(/glow-ingress-line2[^>]*>\s*([^<]+?)\s*</) || [])[1] || '', cards: cards.length, jivo: jivo.length };
  });
}

(async () => {
  let b; try { b = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new'] }); } catch (_) { b = await chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }); }
  const ctx = await b.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
  const page = await ctx.newPage();
  let token = '';
  page.on('request', (req) => { const t = req.headers()['anti-csrftoken-a2z']; if (t && /glow|address/.test(req.url())) token = t; });

  await page.goto('https://www.amazon.in/?ref_=nav_signin', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await sleep(1500);
  // open the location popover ONCE to make the widget fire a glow request carrying the token
  try { await page.click('#nav-global-location-popover-link', { timeout: 8000 }); await sleep(2000); } catch (_) {}
  console.log('captured token:', token ? token.slice(0, 24) + '… (' + token.length + ')' : 'NONE');

  for (const pin of ['400017', '700001', '174001', '110001']) {
    const t0 = Date.now();
    const set = await setPinFast(page, pin, token);
    const s = await searchGlow(page);
    console.log(`[${pin}] ${((Date.now() - t0) / 1000).toFixed(1)}s setHTTP=${set.status} glow="${s.glow}" cards=${s.cards} jivo=${s.jivo}  body=${set.body}`);
  }
  await b.close();
})();
