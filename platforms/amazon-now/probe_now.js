// With the transplanted logged-in session, probe whether Amazon Now (quick-commerce)
// availability/price/ETA is now visible — the question that got Amazon-Now closed as
// "not feasible without login". Tests two surfaces, lightly (a few requests):
//   1. /dp/<asin> for known Now ASINs — does the delivery block now show a Now/today offer?
//   2. the i=nowstore storefront search for "jivo" — does it return results now (vs 503)?
// Also reads the current active delivery location (GLOW).
//
//   node probe_now.js
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const STATE = path.join(__dirname, 'secrets', 'amazon-now.storageState.json');
const OUT = path.join(__dirname, 'secrets');
const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Known Now-storefront Jivo ASINs (from BLOCKED.md) + one marketplace-only control.
const ASINS = ['B09MJ6QDX7', 'B093BMGPQC', 'B0DC6JR4F3', 'B0152TWWSQ'];

async function passInterstitial(page) {
  const hit = await page.evaluate(() => /continue shopping/i.test(document.body.innerText || '') && !document.querySelector('#nav-link-accountList')).catch(() => false);
  if (!hit) return;
  try { await page.getByRole('button', { name: /continue shopping/i }).click({ timeout: 6000 }); } catch (_) {}
  await sleep(2000);
}

(async () => {
  let browser;
  try { browser = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new'] }); }
  catch (_) { browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }); }
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
  const page = await ctx.newPage();
  const out = { ts: new Date().toISOString(), location: '', dp: [], nowstore: {} };

  // current active delivery location
  await page.goto('https://www.amazon.in/?ref_=nav_signin', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await sleep(2000); await passInterstitial(page);
  out.location = await page.evaluate(() => {
    const g = document.getElementById('glow-ingress-line2');
    return g ? (g.innerText || '').replace(/\s+/g, ' ').trim() : '';
  });
  process.stderr.write(`[loc] deliver-to: "${out.location}"\n`);

  // 1) /dp probe
  for (const asin of ASINS) {
    try {
      await page.goto(`https://www.amazon.in/dp/${asin}`, { waitUntil: 'domcontentloaded', timeout: 40000 });
      await sleep(2200); await passInterstitial(page);
      const d = await page.evaluate(() => {
        const T = (el) => (el ? (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim() : '');
        const body = document.body.innerText || '';
        const deliv = T(document.querySelector('#mir-layout-DELIVERY_BLOCK, #deliveryBlockMessage, [data-csa-c-content-id="DEXUnifiedCXPDM"]'));
        const fast = T(document.querySelector('#fast-track-message, #exports_desktop_qcInfoBlock, [data-csa-c-content-id*="GLUXPrime"], #amazon-now, [id*="qcInfo" i], [class*="quick" i]'));
        const price = T(document.querySelector('#corePrice_feature_div .a-offscreen, .priceToPay .a-offscreen, #priceblock_ourprice'));
        return {
          title: (document.title || '').slice(0, 60),
          price,
          delivery: deliv.slice(0, 160),
          fastTrack: fast.slice(0, 160),
          nowHit: /amazon\s*now|get it (today|in \d+\s*(hour|min))|same.?day|in \d+\s*(hours|mins|minutes)|tatkal|10[- ]?min|quick commerce/i.test(body),
          ctnow: !!document.querySelector('a[href*="almBrandId=ctnow"], a[href*="seller=A3DRET2ZTE1T2S"]'),
          oos: /currently unavailable|out of stock/i.test(body),
        };
      });
      out.dp.push({ asin, ...d });
      process.stderr.write(`[dp] ${asin} ₹${d.price||'-'} nowHit=${d.nowHit} ctnow=${d.ctnow} oos=${d.oos}\n      delivery="${d.delivery}"\n      fast="${d.fastTrack}"\n`);
    } catch (e) { out.dp.push({ asin, err: e.message }); process.stderr.write(`[dp] ${asin} ERR ${e.message}\n`); }
    await sleep(1800);
  }

  // 2) nowstore storefront search (503'd when logged out)
  try {
    const r = await page.goto('https://www.amazon.in/s?k=jivo&i=nowstore', { waitUntil: 'domcontentloaded', timeout: 40000 });
    await sleep(2500); await passInterstitial(page);
    out.nowstore = await page.evaluate(() => {
      const T = (el) => (el ? (el.innerText || '').replace(/\s+/g, ' ').trim() : '');
      const cards = [...document.querySelectorAll('[data-component-type="s-search-result"][data-asin]')].filter((c) => (c.getAttribute('data-asin') || '').length > 3);
      return {
        http503: /503|rush hour and traffic|service unavailable/i.test(document.body.innerText || ''),
        count: cards.length,
        items: cards.slice(0, 10).map((c) => ({
          asin: c.getAttribute('data-asin'),
          title: T(c.querySelector('h2, .a-size-base-plus')).slice(0, 50),
          price: T(c.querySelector('.a-price .a-offscreen')),
          promise: T(c.querySelector('[class*="delivery" i]')).slice(0, 50),
        })),
      };
    });
    out.nowstore.http = r ? r.status() : null;
    process.stderr.write(`[nowstore] http=${out.nowstore.http} 503=${out.nowstore.http503} results=${out.nowstore.count}\n`);
    (out.nowstore.items || []).forEach((it) => process.stderr.write(`    ${it.asin} ₹${it.price||'-'} "${it.title}" [${it.promise}]\n`));
    await page.screenshot({ path: path.join(OUT, 'probe_nowstore.png') }).catch(() => {});
  } catch (e) { out.nowstore = { err: e.message }; process.stderr.write(`[nowstore] ERR ${e.message}\n`); }

  fs.writeFileSync(path.join(OUT, 'probe_now.result.json'), JSON.stringify(out, null, 2));
  process.stderr.write('[done] wrote secrets/probe_now.result.json\n');
  await browser.close().catch(() => {});
})();
