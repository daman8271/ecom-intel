// TEMPORARY investigation #2 — set a known Fresh/Now-serviceable pincode via the
// GLOW widget, then re-inspect /dp pages for a Fresh/Now offer + vendor + price.
// Also directly probe the Now/Fresh storefront + nowstore search.
const { chromium } = require('playwright');
const fs = require('fs');

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const PINCODE = process.env.PINCODE || '560001'; // Bengaluru central — Now/Fresh metro
// a few sample ASINs spanning grocery-ish categories likely on Fresh/Now
const ASINS = ['B0C8Z7SZG6', 'B091XPD9J3', 'B0B2RW9N9F', 'B0FJG5CFFD', 'B0D8TN56P9'];

async function passInterstitial(page) {
  await page.goto('https://www.amazon.in/', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await page.waitForTimeout(2000);
  try { await page.getByRole('button', { name: /continue shopping/i }).click({ timeout: 7000 }); } catch (e) {}
  await page.waitForTimeout(2000);
}

async function setPincode(page, pin) {
  try {
    await page.click('#nav-global-location-popover-link', { timeout: 8000 });
    await page.waitForTimeout(1500);
    await page.fill('#GLUXZipUpdateInput', pin, { timeout: 8000 });
    await page.click('#GLUXZipUpdate input[type="submit"], #GLUXZipUpdate-announce, input[aria-labelledby="GLUXZipUpdate-announce"]', { timeout: 8000 }).catch(()=>{});
    await page.waitForTimeout(2000);
    // confirm/done button
    await page.click('button[name="glowDoneButton"], .a-popover-footer #GLUXConfirmClose-announce, [data-action="GLUXConfirmAction"] input', { timeout: 4000 }).catch(()=>{});
    await page.waitForTimeout(2000);
  } catch (e) { return 'pincode-set-error:' + e.message; }
  return 'ok';
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

  const setRes = await setPincode(page, PINCODE);
  await page.goto('https://www.amazon.in/', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(1500);
  const glow = await page.evaluate(() => {
    const a = document.getElementById('glow-ingress-line1'); const b = document.getElementById('glow-ingress-line2');
    return ((a?a.innerText:'')+' | '+(b?b.innerText:'')).replace(/\s+/g,' ').trim();
  });
  console.log(`PINCODE set=${PINCODE} setRes=${setRes} -> GLOW now: ${JSON.stringify(glow)}`);

  // ---- per-ASIN: capture buying-options (AOD) panel, which lists ALL offers incl. Fresh/Now ----
  for (const asin of ASINS) {
    await page.goto(`https://www.amazon.in/dp/${asin}`, { waitUntil: 'domcontentloaded', timeout: 35000 });
    await page.waitForTimeout(1500);
    const base = await page.evaluate(() => {
      const T = (el) => (el ? (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim() : '');
      const html = document.documentElement.innerHTML;
      // search for any element whose text mentions Fresh/Now as a DELIVERY OPTION
      const freshShelf = T(document.getElementById('freshShelfLifeMessage_feature_div'));
      const buyboxGroup = T(document.getElementById('buyBoxAccordion')) || T(document.getElementById('newAccordionRow_0'));
      // alm price nodes (alm = Amazon fresh/now pricing engine)
      const almTax = T(document.getElementById('almTaxExclusivePrice_feature_div'));
      const almPrime = T(document.getElementById('almPrimeSavings_feature_div'));
      // delivery options block (sometimes lists "Amazon Fresh" / "Tatkal")
      const delivery = T(document.querySelector('#mir-layout-DELIVERY_BLOCK, #deliveryBlockMessage'));
      const title = T(document.getElementById('productTitle'));
      const avail = T(document.querySelector('#availability'));
      return {
        title, avail, freshShelf, buyboxGroup, almTax, almPrime, delivery,
        hasFreshOfferText: /amazon fresh|amazon now/i.test(document.body.innerText),
        bodyMentionsFreshLine: (document.body.innerText.match(/.{0,40}(amazon fresh|amazon now).{0,40}/gi) || []).slice(0,5),
      };
    });

    // open "See all buying options" (AOD) if present, to enumerate every offer (incl. Fresh/Now)
    let aod = null;
    try {
      const link = await page.$('#buybox-see-all-buying-choices a, #buybox-see-all-buying-choices-announce, a[title*="buying"]');
      if (link) {
        await link.click({ timeout: 5000 });
        await page.waitForTimeout(2500);
        aod = await page.evaluate(() => {
          const T = (el) => (el ? (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim() : '');
          const offers = [...document.querySelectorAll('#aod-offer, #all-offers-display-scroller #aod-offer, .aod-offer')].map(o => ({
            price: T(o.querySelector('.a-price .a-offscreen, .aok-offscreen')),
            soldBy: T(o.querySelector('#aod-offer-soldBy .a-fixed-left-grid-col, [id^="aod-offer-soldBy"] a, .aod-offer-soldBy a')),
            shipsFrom: T(o.querySelector('#aod-offer-shipsFrom .a-fixed-left-grid-col, [id^="aod-offer-shipsFrom"]')),
            delivery: T(o.querySelector('[id^="aod-offer-delivery"], .aod-delivery-promise')),
            full: T(o).slice(0, 260),
          }));
          const pinnedSoldBy = T(document.querySelector('#aod-pinned-offer #aod-offer-soldBy, #pinned-offer-top-id #aod-offer-soldBy'));
          return { count: offers.length, pinnedSoldBy, offers: offers.slice(0, 8) };
        });
      }
    } catch (e) { aod = { err: e.message }; }

    console.log(`\n[${asin}] ${(base.title||'').slice(0,45)} avail="${(base.avail||'').slice(0,30)}"`);
    console.log(`  freshShelf=${JSON.stringify(base.freshShelf)} delivery=${JSON.stringify((base.delivery||'').slice(0,80))}`);
    console.log(`  almTax=${JSON.stringify(base.almTax)} almPrime=${JSON.stringify(base.almPrime)}`);
    console.log(`  freshLines=${JSON.stringify(base.bodyMentionsFreshLine)}`);
    console.log(`  AOD=${JSON.stringify(aod)}`);
  }

  // ---- direct Now/Fresh storefront + nowstore search probes ----
  const probes = [
    'https://www.amazon.in/fresh',
    'https://www.amazon.in/alm/storefront?almBrandId=ctnow',
    'https://www.amazon.in/s?k=jivo&i=nowstore',
    'https://www.amazon.in/s?k=jivo+oil&rh=p_n_marketplace%3AHYPERLOCAL',
  ];
  for (const u of probes) {
    try {
      const r = await page.goto(u, { waitUntil: 'domcontentloaded', timeout: 30000 });
      await page.waitForTimeout(1800);
      const d = await page.evaluate(() => {
        const T = (el) => (el ? (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim() : '');
        const results = document.querySelectorAll('[data-component-type="s-search-result"], [data-asin]:not([data-asin=""])');
        const titles = [...document.querySelectorAll('[data-component-type="s-search-result"] h2, .s-title-instructions-style')].slice(0,6).map(e=>T(e).slice(0,40));
        return {
          finalUrl: location.href,
          resultCount: results.length,
          loginWall: /sign-?in|enter.*password|ap\/signin/i.test(location.href) || !!document.getElementById('ap_password'),
          glow: T(document.getElementById('glow-ingress-line2')),
          titles,
          bodySnippet: T(document.body).slice(0, 160),
        };
      });
      console.log(`\nPROBE ${u}\n  http=${r?r.status():'?'} -> ${JSON.stringify(d)}`);
    } catch (e) { console.log(`\nPROBE ${u}\n  ERR ${e.message}`); }
  }

  await browser.close();
})();
