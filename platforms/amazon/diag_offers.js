// diag_offers.js — DIAGNOSTIC ONLY. For ASINs whose main buybox is empty, hit the
// offer-listing page (all third-party offers) and read the lowest NEW offer price.
// Tells us whether "Currently unavailable" ASINs are actually buyable from other
// sellers (price recoverable) or genuinely offerless.
const { chromium } = require('playwright');
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const ASINS = process.argv.slice(2);

async function passInterstitial(page) {
  await page.goto('https://www.amazon.in/', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await page.waitForTimeout(2000);
  try { await page.getByRole('button', { name: /continue shopping/i }).click({ timeout: 7000 }); } catch (e) {}
  await page.waitForTimeout(2000);
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 } });
  await ctx.route('**/*', (r) => (['image', 'font', 'media'].includes(r.request().resourceType()) ? r.abort() : r.continue()));
  const warm = await ctx.newPage(); await passInterstitial(warm); await warm.close();
  const page = await ctx.newPage();

  for (const asin of ASINS) {
    const url = `https://www.amazon.in/gp/offer-listing/${asin}/ref=dp_olp_NEW?condition=new`;
    let http = null;
    try { const resp = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 35000 }); http = resp ? resp.status() : null; }
    catch (e) { console.log(JSON.stringify({ asin, error: 'nav:' + e.message })); continue; }
    await page.waitForTimeout(1500);
    const info = await page.evaluate(() => {
      const txt = (el) => (el ? (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim() : '');
      // modern offer-listing uses #aod-offer rows; legacy uses .olpOffer
      const rows = [...document.querySelectorAll('#aod-offer, .olpOffer, [id^="aod-offer"]')];
      const prices = [];
      rows.forEach((row) => {
        const p = row.querySelector('.a-price .a-offscreen, .olpOfferPrice, #aod-offer-price .a-offscreen');
        const seller = txt(row.querySelector('#aod-offer-soldBy a, .olpSellerName a, #aod-offer-soldBy .a-col-right'));
        if (p) prices.push({ price: txt(p), seller: seller.slice(0, 30) });
      });
      // pinned/featured offer at the top of AOD
      const pinned = document.querySelector('#aod-pinned-offer .a-price .a-offscreen, #pinned-offer-price .a-offscreen');
      const t = (document.body && document.body.innerText) || '';
      return {
        offer_rows: rows.length,
        offers: prices.slice(0, 5),
        pinned_price: pinned ? txt(pinned) : null,
        no_offers_text: /currently, there are no sellers|no offers are currently available|are no buying options/i.test(t),
        body_head: t.slice(0, 120).replace(/\s+/g, ' '),
      };
    });
    console.log(JSON.stringify({ asin, http, ...info }));
    await page.waitForTimeout(1000 + Math.floor(Math.random() * 600));
  }
  await browser.close();
})();
