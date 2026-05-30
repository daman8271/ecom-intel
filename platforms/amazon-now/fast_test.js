// Prove the FAST recipe: set pincode via a raw fetch (no UI), pull nowstore search as
// raw HTML (server-rendered), parse without a full page render. Target ~2s/pincode vs ~15s.
const { chromium } = require('playwright');
const path = require('path');
const STATE = path.join(__dirname, 'secrets/amazon-now.storageState.json');
const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function getToken(page) {
  return page.evaluate(async () => {
    try {
      const r = await fetch('/portal-migration/hz/glow/get-rendered-address-selections?deviceType=desktop&pageType=Gateway&storeContext=NoStoreName&actionSource=desktop', { headers: { 'anti-csrftoken-a2z-request': 'true' } });
      const t = await r.text();
      const m = t.match(/CSRF_TOKEN\s*:\s*"([^"]+)"/) || t.match(/anti-csrftoken-a2z["']?\s*[:=]\s*["']([^"']+)["']/) || t.match(/name="anti-csrftoken-a2z"\s+value="([^"]+)"/);
      return m ? m[1] : '';
    } catch (e) { return 'ERR:' + e.message; }
  });
}

async function setPinFast(page, pin, token) {
  return page.evaluate(async ({ pin, token }) => {
    const r = await fetch('/portal-migration/hz/glow/address-change?actionSource=glow', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'anti-csrftoken-a2z': token, 'x-requested-with': 'XMLHttpRequest' },
      body: JSON.stringify({ locationType: 'LOCATION_INPUT', zipCode: pin, deviceType: 'web', storeContext: 'generic', pageType: 'Gateway', actionSource: 'glow' }),
    });
    let body = ''; try { body = await r.text(); } catch (_) {}
    return { status: r.status, body: body.slice(0, 120) };
  }, { pin, token });
}

async function searchFast(page) {
  return page.evaluate(async () => {
    const r = await fetch('/s?k=jivo&i=nowstore', { headers: { accept: 'text/html' } });
    const html = await r.text();
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const T = (el) => el ? (el.textContent || '').replace(/\s+/g, ' ').trim() : '';
    const cards = [...doc.querySelectorAll('[data-component-type="s-search-result"][data-asin]')];
    const jivo = cards.filter((c) => /\bjivo\b/i.test(T(c)));
    return {
      htmlLen: html.length,
      total: cards.length,
      jivo: jivo.length,
      glowInHtml: (html.match(/glow-ingress-line2[^>]*>\s*([^<]+?)\s*</) || [])[1] || '',
      sample: jivo.slice(0, 2).map((c) => ({
        asin: c.getAttribute('data-asin'),
        title: T(c.querySelector('[data-cy="title-recipe"]')).slice(0, 46),
        price: T(c.querySelector('.a-price .a-offscreen')),
        slot: T(c.querySelector('[class*="delivery" i]')).slice(0, 34),
      })),
    };
  });
}

(async () => {
  let b; try { b = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new'] }); } catch (_) { b = await chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }); }
  const ctx = await b.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
  const page = await ctx.newPage();
  await page.goto('https://www.amazon.in/?ref_=nav_signin', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await sleep(1500);
  const token = await getToken(page);
  console.log('token:', token ? token.slice(0, 24) + '… (' + token.length + ')' : 'NONE');

  for (const pin of ['400017', '700001', '174001', '110001']) {
    const t0 = Date.now();
    const set = await setPinFast(page, pin, token);
    const s = await searchFast(page);
    const dt = ((Date.now() - t0) / 1000).toFixed(1);
    console.log(`[${pin}] ${dt}s setHTTP=${set.status} glow="${s.glowInHtml}" htmlLen=${s.htmlLen} cards=${s.total} jivo=${s.jivo}`);
    s.sample.forEach((x) => console.log(`     ${x.asin} ₹${x.price} "${x.title}" [${x.slot}]`));
  }
  await b.close();
})();
