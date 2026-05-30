// RECON SPIKE #3 — load the /dp page of ASINs CONFIRMED present on the Now
// storefront (from i=nowstore search) and check whether their /dp page exposes
// ANY Now offer / price / badge / link. Decisive: if a known-Now ASIN's /dp
// page shows no Now signal, /dp simply does not carry it.
const { chromium } = require('playwright');

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
// ASINs seen in the i=nowstore Jivo search above:
const ASINS = ['B09MJ6QDX7', 'B093BMGPQC', 'B0DC6JR4F3', 'B0152TWWSQ'];

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

  for (const asin of ASINS) {
    await page.goto(`https://www.amazon.in/dp/${asin}`, { waitUntil: 'domcontentloaded', timeout: 35000 });
    await page.waitForTimeout(1800);
    const d = await page.evaluate(() => {
      const T = (el) => (el ? (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim() : '');
      const body = (document.body && document.body.innerText) || '';
      const html = document.documentElement.innerHTML;
      const delivery = T(document.querySelector('#mir-layout-DELIVERY_BLOCK, #deliveryBlockMessage, [data-csa-c-content-id="DEXUnifiedCXPDM"]'));
      // any link/anchor pointing into the Now/Fresh storefront from this /dp?
      const nowLinks = [...document.querySelectorAll('a[href*="nowstore" i], a[href*="ctnow" i], a[href*="/now" i], a[href*="alm/storefront" i], a[href*="hyperlocal" i]')]
        .slice(0, 5).map((a) => (a.getAttribute('href') || '').slice(0, 80));
      // is there a Now/Fresh OFFER tile anywhere in the buy area?
      const nowOffer = /amazon now|get it today|same.?day delivery|in \d+\s*(min|hours?)/i.test(body);
      return {
        title: T(document.getElementById('productTitle')).slice(0, 50),
        avail: T(document.querySelector('#availability')).slice(0, 30),
        delivery: delivery.slice(0, 120),
        nowOffer,
        nowLinks,
        nowstore_html: /nowstore/i.test(html),
        ctnow_html: /ctnow/i.test(html),
        almBrandId_html: /almBrandId/i.test(html),
      };
    });
    console.log(`[${asin}] "${d.title}" avail="${d.avail}"`);
    console.log(`   delivery="${d.delivery}"`);
    console.log(`   nowOffer=${d.nowOffer} nowLinks=${JSON.stringify(d.nowLinks)} nowstore_html=${d.nowstore_html} ctnow_html=${d.ctnow_html} almBrandId_html=${d.almBrandId_html}`);
    await page.waitForTimeout(1000);
  }
  await browser.close();
})();
