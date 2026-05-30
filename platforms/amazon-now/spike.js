// RECON SPIKE (temporary) — determine whether a per-ASIN "Amazon Now / fast
// quick-commerce delivery" signal is reliably readable off the regular
// amazon.in /dp/<asin> page WITHOUT login.
//
// The prior probe (investigate.dp.json) used delivery selectors
// "#deliveryBlockMessage, #mir-layout-DELIVERY_BLOCK" and got an EMPTY block.
// Those are legacy IDs. This spike dumps a MUCH wider set of delivery / promise
// / fulfilment containers (raw text + which selector matched), plus opens
// "See all buying options" (AOD) to enumerate every offer (a Now/Fresh offer,
// if present, shows up here). Runs at the default location and, optionally,
// after setting a Now-serviceable metro pincode via the GLOW widget.
//
//   SAMPLE=8 node spike.js                 # default location only
//   PINCODE=400017 SAMPLE=8 node spike.js  # also set a metro pincode first
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const products = JSON.parse(fs.readFileSync('/opt/ecom-intel/platforms/amazon/products.json', 'utf8'));
const SAMPLE = parseInt(process.env.SAMPLE || '8', 10);
const PINCODE = process.env.PINCODE || ''; // empty => leave the default Mumbai 400017
// Bias the sample toward grocery-ish (oil/ghee/coffee) ASINs, which are the
// most likely Now/Fresh candidates, but keep it small.
const targets = products.slice(0, SAMPLE);

async function passInterstitial(page) {
  await page.goto('https://www.amazon.in/', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await page.waitForTimeout(2000);
  try { await page.getByRole('button', { name: /continue shopping/i }).click({ timeout: 7000 }); } catch (e) {}
  await page.waitForTimeout(2500);
}

async function setPincode(page, pin) {
  try {
    await page.click('#nav-global-location-popover-link', { timeout: 8000 });
    await page.waitForTimeout(1500);
    await page.fill('#GLUXZipUpdateInput', pin, { timeout: 8000 });
    await page.click('#GLUXZipUpdate input[type="submit"], #GLUXZipUpdate-announce, input[aria-labelledby="GLUXZipUpdate-announce"]', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(2500);
    await page.click('button[name="glowDoneButton"], .a-popover-footer #GLUXConfirmClose-announce, [data-action="GLUXConfirmAction"] input', { timeout: 4000 }).catch(() => {});
    await page.waitForTimeout(2000);
  } catch (e) { return 'pincode-set-error:' + e.message; }
  return 'ok';
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

  const page = await ctx.newPage();
  await passInterstitial(page);

  let glow = await page.evaluate(() => {
    const a = document.getElementById('glow-ingress-line1'); const b = document.getElementById('glow-ingress-line2');
    return ((a ? a.innerText : '') + ' | ' + (b ? b.innerText : '')).replace(/\s+/g, ' ').trim();
  });
  console.log('DEFAULT LOCATION (GLOW):', JSON.stringify(glow));

  let setRes = 'skipped';
  if (PINCODE) {
    setRes = await setPincode(page, PINCODE);
    await page.goto('https://www.amazon.in/', { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(1500);
    glow = await page.evaluate(() => {
      const a = document.getElementById('glow-ingress-line1'); const b = document.getElementById('glow-ingress-line2');
      return ((a ? a.innerText : '') + ' | ' + (b ? b.innerText : '')).replace(/\s+/g, ' ').trim();
    });
    console.log(`PINCODE set=${PINCODE} setRes=${setRes} -> GLOW now: ${JSON.stringify(glow)}`);
  }

  const out = [];
  for (const m of targets) {
    const url = `https://www.amazon.in/dp/${m.asin}`;
    let http = null;
    try {
      const resp = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 35000 });
      http = resp ? resp.status() : null;
    } catch (e) { out.push({ asin: m.asin, http: null, err: e.message }); continue; }
    await page.waitForTimeout(1800);

    const info = await page.evaluate(() => {
      const T = (el) => (el ? (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim() : '');
      const body = (document.body && document.body.innerText) || '';

      const title = T(document.getElementById('productTitle'));
      const avail = T(document.querySelector('#availability'));

      // ---- WIDE delivery / promise / fulfilment container sweep ----
      // record which selector matched + its text, so we can pin the right one.
      const deliverySelectors = [
        '#mir-layout-DELIVERY_BLOCK',
        '#deliveryBlockMessage',
        '#delivery-block-msg',
        '#fast-track',
        '#fulfillment',
        '#fulfillmentExpander_feature_div',
        '#deliveryMessageMirId',
        '#dynamicDeliveryMessage',
        '#primeDeliveryMessage_feature_div',
        '#contextualIngressPtLabel_deliveryShortLine',
        '[data-csa-c-content-id="DEXUnifiedCXPDM"]',
        '[data-csa-c-content-id*="DeliveryMessage"]',
        '#amazonGlobal_feature_div',
        '#mir-layout-DELIVERY_BLOCK-slot-SECONDARY_DELIVERY_MESSAGE_LARGE',
      ];
      const deliveryHits = [];
      for (const s of deliverySelectors) {
        const el = document.querySelector(s);
        const t = T(el);
        if (el && t) deliveryHits.push({ sel: s, text: t.slice(0, 220) });
      }
      // Also: every element under the buybox column whose text smells like a
      // delivery promise.
      const promiseRe = /(get it|delivery|deliver(ed|y) by|order within|arrives|today|tomorrow|same.?day|in \d+\s*(min|hour|hr)|tatkal|fastest)/i;
      const promiseNodes = [];
      const scope = document.querySelector('#rightCol, #centerCol, #buybox, #desktop_buybox') || document.body;
      scope.querySelectorAll('div,span,a').forEach((el) => {
        if (el.children.length > 2) return; // leaf-ish only
        const t = T(el);
        if (t && t.length < 120 && promiseRe.test(t) && !/add to|wish list|buying option|see all/i.test(t)) {
          promiseNodes.push(t);
        }
      });
      const uniqPromise = [...new Set(promiseNodes)].slice(0, 12);

      // ---- offer-display feature names present in the main buybox ----
      const offerNames = [...new Set([...document.querySelectorAll('[offer-display-feature-name]')].map((e) => e.getAttribute('offer-display-feature-name')))];

      // ---- targeted Now/Fast signal regexes over the full HTML ----
      const html = document.documentElement.innerHTML;
      const signals = {
        amazon_now_text: /amazon now/i.test(body),
        amazon_fresh_text: /amazon fresh/i.test(body),
        get_it_today: /get it today|delivery today|arrives today|today \d{1,2}\s*[ap]m/i.test(body),
        same_day: /same.?day delivery/i.test(body),
        in_hours: /in \d+\s*hours?|within \d+\s*hours?|in \d+\s*min/i.test(body),
        morning_delivery: /morning delivery|by \d{1,2}\s*[ap]m/i.test(body),
        tatkal: /tatkal/i.test(body),
        // structural identifiers
        nowstore_html: /nowstore/i.test(html),
        ctnow_html: /ctnow/i.test(html),
        hyperlocal_html: /hyperlocal/i.test(html),
        almBrandId_html: /almBrandId/i.test(html),
        alm_storefront_html: /alm\/storefront/i.test(html),
        // a Now/Fresh fulfilment badge would surface as an alm fulfilment node
        alm_fulfillment_node: !!document.querySelector('[id*="almDelivery" i],[class*="almDelivery" i],[id*="freshDelivery" i],[data-csa-c-content-id*="fresh" i]'),
      };

      // ---- snippets of body text around any now/fresh/today mention ----
      const ctxLines = (body.match(/.{0,45}(amazon now|amazon fresh|get it today|same.?day|in \d+\s*(hours?|min)).{0,45}/gi) || []).slice(0, 6);

      // ---- is there a "see all buying options" / AOD ingress? ----
      const aodIngress = !!document.querySelector('#buybox-see-all-buying-choices, #aod-ingress-link, [data-action="show-all-offers-display"]');

      return { title, avail, deliveryHits, uniqPromise, offerNames, signals, ctxLines, aodIngress };
    });

    // ---- open AOD (all offers display) and enumerate offers incl. Now/Fresh ----
    let aod = null;
    try {
      const link = await page.$('#buybox-see-all-buying-choices a, #buybox-see-all-buying-choices-announce, #aod-ingress-link, a[title*="buying" i]');
      if (link) {
        await link.click({ timeout: 5000 });
        await page.waitForTimeout(2500);
        aod = await page.evaluate(() => {
          const T = (el) => (el ? (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim() : '');
          const offers = [...document.querySelectorAll('#aod-offer, .aod-offer, #aod-pinned-offer')].map((o) => ({
            price: T(o.querySelector('.a-price .a-offscreen, .aok-offscreen')),
            soldBy: T(o.querySelector('[id^="aod-offer-soldBy"] a, .aod-offer-soldBy a')),
            delivery: T(o.querySelector('[id^="aod-offer-delivery"], .aod-delivery-promise, [class*="delivery" i]')),
            mentionsNow: /amazon now|amazon fresh|today|same.?day|in \d+\s*(hours?|min)/i.test(T(o)),
            full: T(o).slice(0, 200),
          }));
          return { count: offers.length, offers: offers.slice(0, 8) };
        });
      }
    } catch (e) { aod = { err: e.message }; }

    const rec = { asin: m.asin, http, cat: m.category, ...info, aod };
    out.push(rec);
    console.log(`\n[${m.asin}] ${(info.title || 'NO-TITLE').slice(0, 48)}  avail="${(info.avail || '').slice(0, 26)}"  http=${http}`);
    console.log(`  deliveryHits=${JSON.stringify(info.deliveryHits)}`);
    console.log(`  promiseNodes=${JSON.stringify(info.uniqPromise)}`);
    console.log(`  signals=${JSON.stringify(info.signals)}`);
    console.log(`  ctxLines=${JSON.stringify(info.ctxLines)}`);
    console.log(`  offerNames=${JSON.stringify(info.offerNames)}  aodIngress=${info.aodIngress}`);
    console.log(`  AOD=${JSON.stringify(aod)}`);
    await page.waitForTimeout(1000 + Math.floor(Math.random() * 600));
  }

  const tag = PINCODE ? `pin${PINCODE}` : 'default';
  fs.writeFileSync(path.join(__dirname, `spike.${tag}.json`), JSON.stringify({ glow, setRes, out }, null, 2));
  await browser.close();
  console.log(`\nWROTE spike.${tag}.json`);
})();
