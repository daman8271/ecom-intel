// BigBasket recon step 3: dump full listing-svc JSON + test location API
// Run: node recon_step3.js 2>&1 | tee recon_step3.log

const { chromium } = require('playwright-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
chromium.use(StealthPlugin());

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const fs = require('fs');

async function main() {
  const browser = await chromium.launch({
    headless: true,
    executablePath: require('playwright').chromium.executablePath(),
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-blink-features=AutomationControlled'],
  });

  const ctx = await browser.newContext({
    userAgent: UA,
    locale: 'en-IN',
    timezoneId: 'Asia/Kolkata',
    viewport: { width: 1280, height: 900 },
    extraHTTPHeaders: { 'accept-language': 'en-IN,en;q=0.9' },
  });

  const page = await ctx.newPage();

  // Capture location-change API calls
  const locationCalls = [];
  page.on('request', (req) => {
    const u = req.url();
    if (u.includes('bigbasket') && (
      u.includes('address') || u.includes('location') || u.includes('pincode') ||
      u.includes('serviceability') || u.includes('delivery') || u.includes('sa-svc') ||
      u.includes('hub-svc') || u.includes('set-loc') || u.includes('geo')
    )) {
      locationCalls.push({ type: 'REQ', method: req.method(), url: u, body: req.postData() });
      console.log(`  LOC-REQ: ${req.method()} ${u}`);
      if (req.postData()) console.log(`    body: ${req.postData().slice(0, 300)}`);
    }
  });
  page.on('response', async (res) => {
    const u = res.url();
    if (u.includes('bigbasket') && (
      u.includes('address') || u.includes('location') || u.includes('pincode') ||
      u.includes('serviceability') || u.includes('delivery') || u.includes('sa-svc') ||
      u.includes('hub-svc') || u.includes('set-loc') || u.includes('geo')
    )) {
      let body = '';
      try { body = (await res.text()).slice(0, 2000); } catch (_) {}
      locationCalls.push({ type: 'RES', status: res.status(), url: u, body });
      console.log(`  LOC-RES: ${res.status()} ${u}`);
      if (body && !body.startsWith('<')) console.log(`    body: ${body.slice(0, 500)}`);
    }
  });

  // Block images/fonts/media
  await ctx.route('**/*', (route) => {
    const t = route.request().resourceType();
    if (['image', 'font', 'media'].includes(t)) return route.abort();
    return route.continue();
  });

  // Load homepage
  console.log('[1] Loading homepage...');
  await page.goto('https://www.bigbasket.com/', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await page.waitForTimeout(3000);

  const cookies1 = await ctx.cookies();
  console.log('[1] Cookies after homepage:');
  for (const c of cookies1) {
    if (c.name.startsWith('_bb') || c.name === 'csrftoken' || c.name === 'csurftoken' || c.name === 'x-channel') {
      console.log(`  ${c.name}=${c.value.slice(0, 100)}`);
    }
  }

  // Check current location (city defaults to Bangalore)
  const headerData = await page.evaluate(async () => {
    try {
      const r = await fetch('/ui-svc/v2/header/?send_door_info=true&send_address_set_by_user=true&i=' + Date.now(), {
        headers: { 'accept': 'application/json' }
      });
      return { status: r.status, body: await r.text() };
    } catch (e) { return { err: e.message }; }
  });
  console.log('\n[2] Header API (location state):');
  console.log(JSON.stringify(JSON.parse(headerData.body || '{}'), null, 2).slice(0, 2000));

  // Try setting pincode via the location-change API (educated guesses based on patterns)
  console.log('\n[3] Testing location change API endpoints...');

  // BB uses /api/v1/tb-location/ or /cityapi/detect-city/ or address service
  const testEndpoints = [
    { method: 'GET', url: '/api/v1/tb-location/?city=110001&force_verify=1' },
    { method: 'GET', url: '/api/v1/tb-location/?pincode=110001' },
    { method: 'POST', url: '/api/v1/address/detect-city/', body: JSON.stringify({ pincode: '110001' }) },
    { method: 'GET', url: '/cityapi/detect-city/?pincode=110001' },
    { method: 'GET', url: '/hub-svc/v1/hubs/?pin_code=110001' },
  ];

  for (const ep of testEndpoints) {
    const result = await page.evaluate(async (ep) => {
      try {
        const opts = {
          method: ep.method,
          headers: { 'accept': 'application/json', 'x-requested-with': 'XMLHttpRequest' }
        };
        if (ep.body) {
          opts.headers['content-type'] = 'application/json';
          opts.body = ep.body;
        }
        const r = await fetch(ep.url, opts);
        return { status: r.status, body: (await r.text()).slice(0, 500) };
      } catch (e) { return { err: e.message }; }
    }, ep);
    console.log(`  ${ep.method} ${ep.url}: ${result.status || result.err}`);
    if (result.body && !result.body.startsWith('<') && result.status === 200) {
      console.log(`    body: ${result.body}`);
    }
  }

  // Navigate to the actual search page and capture the listing-svc response in full
  console.log('\n[4] Navigating to search page for jivo...');
  let fullListingJson = null;

  // Intercept the listing-svc call to capture full body
  page.on('response', async (res) => {
    const u = res.url();
    if (u.includes('listing-svc/v2/products') && u.includes('jivo')) {
      try {
        const body = await res.text();
        fullListingJson = body;
        console.log(`  [4] CAPTURED listing-svc response (${body.length} bytes)`);
        fs.writeFileSync('/opt/ecom-intel/platforms/bigbasket/listing_raw.json', body);
      } catch (_) {}
    }
  });

  await page.goto('https://www.bigbasket.com/ps/?q=jivo', {
    waitUntil: 'domcontentloaded', timeout: 30000
  });
  await page.waitForTimeout(5000);

  // Also try via in-page fetch to get the full response including bucket_id
  const searchResult = await page.evaluate(async () => {
    try {
      const r = await fetch('/listing-svc/v2/products?type=ps&slug=jivo&page=1&bucket_id=32', {
        headers: {
          'accept': 'application/json, text/plain, */*',
          'x-requested-with': 'XMLHttpRequest',
          'referer': 'https://www.bigbasket.com/ps/?q=jivo',
        }
      });
      return { status: r.status, body: await r.text() };
    } catch (e) { return { err: e.message }; }
  });
  console.log(`\n[4] In-page fetch listing-svc status: ${searchResult.status}`);
  if (searchResult.body) {
    fs.writeFileSync('/opt/ecom-intel/platforms/bigbasket/listing_inpage.json', searchResult.body);
    console.log(`  Saved ${searchResult.body.length} bytes to listing_inpage.json`);

    // Parse and show structure
    try {
      const j = JSON.parse(searchResult.body);
      console.log('  Top-level keys:', Object.keys(j));
      const tabs = j.tabs || [];
      console.log('  tabs.length:', tabs.length);
      if (tabs[0]) {
        const pi = tabs[0].product_info || {};
        console.log('  tabs[0].product_info keys:', Object.keys(pi));
        const products = pi.products || [];
        console.log('  products count:', products.length);
        if (products[0]) {
          console.log('\n  FIRST PRODUCT fields:');
          console.log(JSON.stringify(products[0], null, 2).slice(0, 3000));
        }
      }
    } catch (e) {
      console.log('  Parse error:', e.message);
      console.log('  Raw (first 500):', searchResult.body.slice(0, 500));
    }
  }

  // Try to set location to Delhi (pincode 110001) via cookie manipulation
  console.log('\n[5] Testing cookie-based location override...');
  // BigBasket stores location in cookies: _bb_nhid (hub id), _bb_cid (city id), _bb_dsid
  // City IDs: Bangalore=1, Delhi=2, Mumbai=3 (typical)
  // Let's check the header API to see what sa_list contains for default location
  const headerFull = await page.evaluate(async () => {
    try {
      const r = await fetch('/ui-svc/v2/header/?send_door_info=true&send_address_set_by_user=true&i=' + Date.now());
      return await r.text();
    } catch (e) { return e.message; }
  });
  try {
    const hj = JSON.parse(headerFull);
    console.log('[5] Header full:');
    console.log(JSON.stringify(hj, null, 2).slice(0, 3000));
    fs.writeFileSync('/opt/ecom-intel/platforms/bigbasket/header_api.json', headerFull);
  } catch (e) {
    console.log('[5] Header (raw):', headerFull.slice(0, 1000));
  }

  // Try setting location via the pincode input UI - simulate typing in search
  // First, look for the address/location widget
  console.log('\n[6] Looking for location widget...');
  const locWidget = await page.evaluate(() => {
    const all = document.querySelectorAll('input');
    const inputs = [];
    for (const el of all) {
      inputs.push({ type: el.type, placeholder: el.placeholder, id: el.id, name: el.name, class: el.className.slice(0, 50) });
    }
    return inputs.slice(0, 20);
  });
  console.log('[6] Form inputs:', JSON.stringify(locWidget));

  // Try clicking the location widget
  try {
    // Common BB location selector
    await page.click('[data-test-id="location-widget"]', { timeout: 3000 });
    console.log('[6] Clicked location widget');
    await page.waitForTimeout(2000);
    // Watch for API calls...
  } catch (_) {
    console.log('[6] Location widget click failed, trying other selectors...');
    try {
      // Try the address area
      const locBtns = await page.evaluate(() => {
        const btns = document.querySelectorAll('[class*="location"], [class*="address"], [class*="pincode"], [class*="deliver"]');
        return Array.from(btns).slice(0, 5).map(el => ({
          tag: el.tagName, text: el.textContent.slice(0, 50), class: el.className.slice(0, 80)
        }));
      });
      console.log('[6] Location-related elements:', JSON.stringify(locBtns));
    } catch (e2) { console.log('[6]', e2.message); }
  }

  // Test if the delivery location cookie can be set for Delhi
  // BigBasket uses _bb_nhid for the dark store / hub ID
  // Let's see if we can find a delivery address API
  const deliveryTest = await page.evaluate(async () => {
    // Try the typical BB address API
    try {
      const r = await fetch('/api/v1/delivery-address/?pincode=110001', {
        headers: { 'accept': 'application/json' }
      });
      return { status: r.status, body: (await r.text()).slice(0, 1000) };
    } catch (e) { return { err: e.message }; }
  });
  console.log('\n[7] Delivery address API:', JSON.stringify(deliveryTest));

  // Try the sa-svc (store availability service)
  const saTest = await page.evaluate(async () => {
    try {
      const r = await fetch('/sa-svc/v1/service-areas/?pincode=110001', {
        headers: { 'accept': 'application/json' }
      });
      return { status: r.status, body: (await r.text()).slice(0, 1000) };
    } catch (e) { return { err: e.message }; }
  });
  console.log('[7] SA-SVC:', JSON.stringify(saTest));

  await browser.close();
  console.log('\n[DONE] Check listing_inpage.json, listing_raw.json, header_api.json for full responses');
}

main().catch(e => { console.error('FATAL:', e); process.exit(1); });
