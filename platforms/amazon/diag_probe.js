// diag_probe.js — DIAGNOSTIC ONLY (untracked). Live-fetch a sample of ASINs the
// production scraper marked "Currently unavailable / sale=null" and dump what is
// ACTUALLY on the page: main buybox price, struck MRP, the "Other Sellers on
// Amazon" / "See All Buying Options" price (#aod-price / olp), offer count, and
// the raw availability text. Tells us if these are genuinely offerless or if the
// scraper is missing a price that lives outside the main buybox.
//
//   node diag_probe.js B0XXXX B0YYYY ...      # probe given ASINs
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
    const url = `https://www.amazon.in/dp/${asin}`;
    let http = null;
    try { const resp = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 35000 }); http = resp ? resp.status() : null; }
    catch (e) { console.log(JSON.stringify({ asin, error: 'nav:' + e.message })); continue; }
    await page.waitForTimeout(1500);

    const info = await page.evaluate(() => {
      const txt = (el) => (el ? (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim() : '');
      const q = (s) => document.querySelector(s);
      const price = (s) => { const el = q(s); return el ? txt(el) : null; };
      const t = (document.body && document.body.innerText) || '';
      // count "Other Sellers / buying options" affordances
      const buyingOptionsBtn = !!(q('#buybox-see-all-buying-choices a, #buybox-see-all-buying-choices, [data-action="show-all-offers-display"], a[href*="/gp/offer-listing/"]'));
      const aodPrice = price('#aod-price-0 .a-offscreen, #aod-price .a-offscreen, #all-offers-display .a-price .a-offscreen');
      const olpPrice = price('#olpLinkWidget_feature_div .a-color-price, #usedBuySection .a-color-price, .olp-padding-right .a-color-price');
      // any a-offscreen price anywhere on the page (broad net)
      const anyOffscreen = [...document.querySelectorAll('.a-price .a-offscreen')].map(e => txt(e)).filter(Boolean).slice(0, 6);
      const partial = /currently unavailable|we don.?t know when/i.test(t);
      return {
        title: txt(q('#productTitle')).slice(0, 60),
        buybox_sale: price('#corePriceDisplay_desktop_feature_div .priceToPay .a-offscreen, .priceToPay .a-offscreen, span.apexPriceToPay .a-offscreen'),
        availability: txt(q('#availability')).slice(0, 50),
        has_atc: !!q('#add-to-cart-button, #buy-now-button'),
        see_all_buying_options: buyingOptionsBtn,
        aod_price: aodPrice,
        olp_price: olpPrice,
        offer_count_text: txt(q('#buybox-see-all-buying-choices, #olpLinkWidget_feature_div')).slice(0, 60),
        any_price_on_page: anyOffscreen,
        looks_currently_unavailable: partial,
      };
    });
    console.log(JSON.stringify({ asin, http, ...info }));
    await page.waitForTimeout(1000 + Math.floor(Math.random() * 600));
  }
  await browser.close();
})();
