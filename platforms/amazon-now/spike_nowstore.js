// RECON SPIKE #2 — does the Amazon Now storefront carry Jivo at all, and is
// there any LINK from a marketplace /dp page to a Now offer? Decisive test for
// whether a per-ASIN Now signal can be read off /dp.
const { chromium } = require('playwright');

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

async function passInterstitial(page) {
  await page.goto('https://www.amazon.in/', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await page.waitForTimeout(2000);
  try { await page.getByRole('button', { name: /continue shopping/i }).click({ timeout: 7000 }); } catch (e) {}
  await page.waitForTimeout(2500);
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 } });
  await ctx.route('**/*', (route) => {
    const t = route.request().resourceType();
    if (['image', 'font', 'media'].includes(t)) return route.abort();
    return route.continue();
  });
  const page = await ctx.newPage();
  await passInterstitial(page);

  const probes = [
    'https://www.amazon.in/s?k=jivo&i=nowstore',
    'https://www.amazon.in/s?k=jivo+oil&i=nowstore',
    'https://www.amazon.in/s?k=jivo+oil',
  ];
  for (const u of probes) {
    try {
      const r = await page.goto(u, { waitUntil: 'domcontentloaded', timeout: 30000 });
      await page.waitForTimeout(2000);
      const d = await page.evaluate(() => {
        const T = (el) => (el ? (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim() : '');
        const cards = [...document.querySelectorAll('[data-component-type="s-search-result"][data-asin], [data-asin]:not([data-asin=""])')];
        const items = cards.slice(0, 12).map((c) => ({
          asin: c.getAttribute('data-asin'),
          title: T(c.querySelector('h2, .a-size-base-plus, .a-size-medium')).slice(0, 50),
          price: T(c.querySelector('.a-price .a-offscreen')),
          // any per-card delivery / now / fast promise?
          promise: T(c.querySelector('[class*="delivery" i], .a-row.a-size-base.a-color-secondary')).slice(0, 60),
          mentionsNow: /amazon now|in \d+\s*(min|hour)|today|same.?day|tatkal/i.test(T(c)),
        }));
        return {
          finalUrl: location.href,
          loginWall: /sign-?in|ap\/signin/i.test(location.href) || !!document.getElementById('ap_password'),
          glow: T(document.getElementById('glow-ingress-line2')),
          count: cards.length,
          items,
        };
      });
      console.log(`\nPROBE ${u}\n  http=${r ? r.status() : '?'} count=${d.count} loginWall=${d.loginWall} glow=${JSON.stringify(d.glow)} final=${d.finalUrl}`);
      d.items.forEach((it) => console.log(`    ${it.asin} ₹${it.price || '-'} now=${it.mentionsNow} "${it.title}" promise="${it.promise}"`));
    } catch (e) { console.log(`\nPROBE ${u}\n  ERR ${e.message}`); }
    await page.waitForTimeout(1200);
  }

  await browser.close();
})();
