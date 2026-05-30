// RECON #1 — capture ALL network traffic while loading the no-login Now/Fresh
// storefront search for "jivo", to find a backend JSON endpoint that returns
// the product/price/availability data, and to find the GLOW location-set call.
//
// Run from this folder so `playwright` resolves:
//   cd /opt/ecom-intel/platforms/amazon-now && node recon/capture.js
//
// Outputs:
//   recon/net.<label>.jsonl   — one JSON line per request/response pair
//   recon/cookies.<label>.json — context cookies after the run
//   recon/body.<label>.<n>.txt — first ~4KB of interesting JSON/XHR bodies
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const OUT = __dirname;

async function passInterstitial(page) {
  await page.goto('https://www.amazon.in/', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await page.waitForTimeout(2000);
  try { await page.getByRole('button', { name: /continue shopping/i }).click({ timeout: 7000 }); } catch (e) {}
  await page.waitForTimeout(2500);
}

// keep only resource types likely to carry data; ignore the noise
function interesting(req) {
  const t = req.resourceType();
  const u = req.url();
  if (['image', 'font', 'media', 'stylesheet'].includes(t)) return false;
  if (/\.(png|jpg|jpeg|gif|svg|woff2?|css|ico)(\?|$)/i.test(u)) return false;
  return true;
}

(async () => {
  const label = process.argv[2] || 'now';
  const url = process.argv[3] || 'https://www.amazon.in/s?k=jivo&i=nowstore';

  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 } });
  // abort heavy assets to keep traffic modest, but DON'T abort xhr/fetch/doc
  await ctx.route('**/*', (route) => {
    const t = route.request().resourceType();
    if (['image', 'font', 'media'].includes(t)) return route.abort();
    return route.continue();
  });

  const page = await ctx.newPage();
  const lines = [];
  let bodyN = 0;

  page.on('response', async (resp) => {
    try {
      const req = resp.request();
      if (!interesting(req)) return;
      const ct = (resp.headers()['content-type'] || '');
      const rec = {
        url: resp.url(),
        method: req.method(),
        type: req.resourceType(),
        status: resp.status(),
        ct,
        post: req.method() === 'POST' ? (req.postData() || '').slice(0, 600) : undefined,
      };
      // dump bodies for json / xhr / fetch
      const isData = /json|javascript|text\/plain/i.test(ct) || ['xhr', 'fetch'].includes(req.resourceType());
      if (isData && resp.status() < 400) {
        let body = '';
        try { body = await resp.text(); } catch (e) { body = '<<no-body>>'; }
        rec.bodyLen = body.length;
        rec.bodyHead = body.slice(0, 300).replace(/\s+/g, ' ');
        // save full-ish body for anything that smells like product/price/glow data
        if (/jivo|asin|priceToPay|a-price|glow|portal-migration|address|pincode|deliver|nowstore|freshstore|csm|widget/i.test(body) || /\/data\/|\/api\/|graphql|address-change|glow/i.test(resp.url())) {
          const f = path.join(OUT, `body.${label}.${bodyN++}.txt`);
          fs.writeFileSync(f, `URL: ${resp.url()}\nMETHOD: ${req.method()}\nSTATUS: ${resp.status()}\nCT: ${ct}\nPOST: ${rec.post || ''}\n\n${body.slice(0, 8000)}`);
          rec.savedBody = path.basename(f);
        }
      }
      lines.push(rec);
    } catch (e) { /* ignore */ }
  });

  await passInterstitial(page);

  console.error(`[capture] navigating ${url}`);
  const r = await page.goto(url, { waitUntil: 'networkidle', timeout: 45000 }).catch((e) => { console.error('nav err', e.message); return null; });
  await page.waitForTimeout(3000);

  // scroll to trigger any lazy/pagination XHR
  await page.evaluate(() => window.scrollBy(0, 3000)).catch(() => {});
  await page.waitForTimeout(2500);

  const summary = await page.evaluate(() => {
    const T = (el) => (el ? (el.innerText || '').replace(/\s+/g, ' ').trim() : '');
    const cards = [...document.querySelectorAll('[data-asin]:not([data-asin=""])')];
    return {
      finalUrl: location.href,
      glow: T(document.getElementById('glow-ingress-line2')),
      loginWall: /ap\/signin/i.test(location.href),
      cardCount: cards.length,
      firstAsins: cards.slice(0, 6).map((c) => c.getAttribute('data-asin')),
    };
  }).catch((e) => ({ err: e.message }));

  fs.writeFileSync(path.join(OUT, `net.${label}.jsonl`), lines.map((l) => JSON.stringify(l)).join('\n'));
  const cookies = await ctx.cookies();
  fs.writeFileSync(path.join(OUT, `cookies.${label}.json`), JSON.stringify(cookies, null, 2));

  console.error(`[capture] http=${r ? r.status() : '?'} reqs=${lines.length} bodiesSaved=${bodyN}`);
  console.error('[summary] ' + JSON.stringify(summary));
  console.error('[cookies] ' + cookies.map((c) => c.name).join(','));

  await browser.close();
})();
