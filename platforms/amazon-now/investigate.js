// TEMPORARY investigation — NOT a production scraper.
// Goal: on a sample of ASINs, WITHOUT login, find out what Amazon Now / Fresh
// data is reachable from /dp/<ASIN> at the default location, and whether the
// Now/Fresh storefront lists these ASINs.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const products = JSON.parse(fs.readFileSync(path.join('/opt/ecom-intel/platforms/amazon/products.json'), 'utf8'));
const SAMPLE = parseInt(process.env.SAMPLE || '12', 10);
const targets = products.slice(0, SAMPLE);

async function passInterstitial(page) {
  await page.goto('https://www.amazon.in/', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await page.waitForTimeout(2000);
  try { await page.getByRole('button', { name: /continue shopping/i }).click({ timeout: 7000 }); } catch (e) {}
  await page.waitForTimeout(2500);
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({
    userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata',
    viewport: { width: 1366, height: 900 },
  });
  await ctx.route('**/*', (route) => {
    const t = route.request().resourceType();
    if (['image', 'font', 'media'].includes(t)) return route.abort();
    return route.continue();
  });

  const warm = await ctx.newPage();
  await passInterstitial(warm);

  // Report on the default delivery location (GLOW)
  const glow = await warm.evaluate(() => {
    const el = document.getElementById('glow-ingress-line2') || document.getElementById('nav-global-location-popover-link');
    return el ? (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim() : '(no glow widget)';
  });
  console.log('DEFAULT LOCATION (GLOW):', JSON.stringify(glow));
  await warm.close();

  const page = await ctx.newPage();
  const out = [];
  for (const m of targets) {
    const url = `https://www.amazon.in/dp/${m.asin}`;
    let http = null;
    try {
      const resp = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 35000 });
      http = resp ? resp.status() : null;
    } catch (e) { out.push({ asin: m.asin, http: null, err: e.message }); continue; }
    await page.waitForTimeout(1500);

    const info = await page.evaluate(() => {
      const T = (el) => (el ? (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim() : '');
      const bodyText = (document.body && document.body.innerText) || '';
      const lower = bodyText.toLowerCase();

      // ----- main buybox price/seller (the marketplace offer) -----
      const mainPriceEl = document.querySelector('.priceToPay .a-offscreen, span.apexPriceToPay .a-offscreen, #corePriceDisplay_desktop_feature_div .a-offscreen');
      const mainPrice = T(mainPriceEl);

      // ----- look for ALL offer-display feature names present -----
      const offerNames = [...new Set([...document.querySelectorAll('[offer-display-feature-name]')].map(e => e.getAttribute('offer-display-feature-name')))];

      // ----- "Other sellers / buying options" -----
      const buyingOptions = !!document.querySelector('#aod-ingress-link, #buybox-see-all-buying-choices, [data-action="show-all-offers-display"]');

      // ----- Now / Fresh / quick-commerce signals on the page -----
      const signals = {};
      const checks = {
        'amazon fresh': /amazon fresh/i,
        'get it.*fresh': /get it.*fresh/i,
        'amazon now': /amazon now/i,
        'quick commerce|in 2 hours|in 15|delivered in|fast delivery|tatkal|sub-?same-?day': /in 2 hours|delivered in \d|fast delivery|same-day|tatkal/i,
        'fresh badge node': null,
        'nowstore': /nowstore/i,
        'almBrandId|ctnow': /almbrandid|ctnow/i,
        'morning|today by': /get it by|order within|delivery by/i,
      };
      for (const [k, re] of Object.entries(checks)) {
        if (re) signals[k] = re.test(bodyText) || re.test(document.documentElement.innerHTML.slice(0, 200000));
      }

      // any DOM nodes mentioning fresh/now badges (alm)
      const almNodes = [...document.querySelectorAll('[class*="alm"], [id*="alm"], [class*="fresh"], [id*="fresh"], [data-csa-c-content-id*="fresh" i]')]
        .slice(0, 10).map(e => (e.id || e.className || '').toString().slice(0, 80));

      // delivery / availability block
      const avail = T(document.querySelector('#availability'));
      const deliveryBlock = T(document.querySelector('#deliveryBlockMessage, #mir-layout-DELIVERY_BLOCK, #delivery-block-msg, #amazonGlobal_feature_div'));

      // "Other Buying Choices" / used-new offers count
      const aodCount = T(document.querySelector('#aod-ingress-link .a-size-base, #buybox-see-all-buying-choices'));

      // raw HTML contains alm/fresh/now/hyperlocal as a substring?
      const html = document.documentElement.innerHTML;
      const htmlHas = {
        nowstore: /nowstore/i.test(html),
        ctnow: /ctnow/i.test(html),
        hyperlocal: /hyperlocal/i.test(html),
        almBrandId: /almBrandId/i.test(html),
        amazonFresh: /amazon ?fresh/i.test(html),
        almStorefront: /alm\/storefront/i.test(html),
        f3StoreFront: /f3StoreFront|f3-storefront/i.test(html),
      };

      const title = T(document.getElementById('productTitle'));
      return { title, mainPrice, avail, deliveryBlock, aodCount, buyingOptions, offerNames, signals, almNodes, htmlHas };
    });
    out.push({ asin: m.asin, http, cat: m.category, ...info });
    console.log(`${m.asin} http=${http} price=${info.title ? (info.mainPrice||'-') : 'NO-TITLE'} fresh=${info.htmlHas.amazonFresh} nowstore=${info.htmlHas.nowstore} ctnow=${info.htmlHas.ctnow} hyperlocal=${info.htmlHas.hyperlocal} alm=${info.htmlHas.almStorefront} offers=[${(info.offerNames||[]).join(',')}] buyOpts=${info.buyingOptions}`);
    await page.waitForTimeout(900);
  }

  fs.writeFileSync(path.join(__dirname, 'investigate.dp.json'), JSON.stringify(out, null, 2));
  await browser.close();
  console.log('\nWROTE investigate.dp.json');
})();
