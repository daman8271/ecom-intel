// BigBasket recon step 2: stealth browser + XHR capture
// Uses playwright-extra + puppeteer-extra-plugin-stealth
// Run: node recon_step2.js 2>&1 | tee recon_step2.log

const { chromium } = require('playwright-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
chromium.use(StealthPlugin());

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const PINCODE = '110001';

async function main() {
  console.log('[1] Launching stealth chromium...');
  const browser = await chromium.launch({
    headless: true,
    executablePath: require('playwright').chromium.executablePath(),
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-blink-features=AutomationControlled',
      '--disable-web-security',
    ],
  });

  const ctx = await browser.newContext({
    userAgent: UA,
    locale: 'en-IN',
    timezoneId: 'Asia/Kolkata',
    viewport: { width: 1280, height: 900 },
    extraHTTPHeaders: { 'accept-language': 'en-IN,en;q=0.9' },
  });

  const page = await ctx.newPage();

  // Capture ALL API calls
  const capturedReqs = [];
  page.on('request', (req) => {
    const u = req.url();
    if (u.includes('bigbasket') && (
        u.includes('/api/') || u.includes('listing-svc') || u.includes('search') ||
        u.includes('serviceability') || u.includes('address') || u.includes('location') ||
        u.includes('pincode') || u.includes('product') || u.includes('custompage') ||
        u.includes('order') || u.includes('cart') || u.includes('catalog')
    )) {
      capturedReqs.push({
        type: 'REQ',
        method: req.method(),
        url: u,
        headers: req.headers(),
        body: req.postData(),
      });
      console.log(`  REQ: ${req.method()} ${u.slice(0, 120)}`);
    }
  });

  page.on('response', async (res) => {
    const u = res.url();
    const st = res.status();
    if (u.includes('bigbasket') && (
        u.includes('/api/') || u.includes('listing-svc') || u.includes('search') ||
        u.includes('serviceability') || u.includes('address') || u.includes('location') ||
        u.includes('pincode') || u.includes('product') || u.includes('custompage') ||
        u.includes('catalog')
    )) {
      let body = '';
      try { const t = await res.text(); body = t.slice(0, 3000); } catch (_) {}
      capturedReqs.push({ type: 'RES', status: st, url: u, body });
      console.log(`  RES: ${st} ${u.slice(0, 120)}`);
      if (body && !body.startsWith('<') && body.length > 10) {
        console.log(`    body[:300]: ${body.slice(0, 300)}`);
      }
    }
  });

  // Block images/fonts/media
  await ctx.route('**/*', (route) => {
    const t = route.request().resourceType();
    if (['image', 'font', 'media'].includes(t)) return route.abort();
    return route.continue();
  });

  console.log('[2] Navigating to BigBasket homepage...');
  let homeStatus = 'unknown';
  try {
    const resp = await page.goto('https://www.bigbasket.com/', {
      waitUntil: 'domcontentloaded',
      timeout: 45000,
    });
    homeStatus = resp ? resp.status() : 'no-response';
    console.log(`[2] Homepage status: ${homeStatus}`);
  } catch (e) {
    console.log(`[2] Error: ${e.message}`);
    homeStatus = 'error';
  }

  await page.waitForTimeout(4000);

  // Check cookies
  const cookies = await ctx.cookies();
  const cookieMap = {};
  for (const c of cookies) cookieMap[c.name] = c.value;
  console.log('\n[3] ALL COOKIES:');
  for (const c of cookies) {
    console.log(`  ${c.name}=${c.value.slice(0, 100)}`);
  }

  const pageTitle = await page.title().catch(() => 'N/A');
  const bodyText = await page.evaluate(() => document.body ? document.body.innerText.slice(0, 400) : '').catch(() => '');
  console.log(`\n[3] Page title: ${pageTitle}`);
  console.log(`[3] Body snippet: ${bodyText.slice(0, 300)}`);

  // Check for block indicators
  const isBlocked = homeStatus === 403 ||
    bodyText.toLowerCase().includes('access denied') ||
    bodyText.toLowerCase().includes('blocked') ||
    pageTitle.toLowerCase().includes('access denied');
  console.log(`\n[3] BLOCKED: ${isBlocked}`);

  if (isBlocked) {
    console.log('[4] BLOCKED — stealth did not bypass Akamai on this IP');
    await browser.close();
    return;
  }

  console.log('\n[4] Site loaded — attempting location set to ' + PINCODE);
  await page.waitForTimeout(2000);

  // Try to find delivery location UI
  const pageHTML = await page.content();
  console.log('[4] Page has location/pincode input:',
    pageHTML.includes('pincode') || pageHTML.includes('location') || pageHTML.includes('delivery'));

  // Navigate to the search page with pincode in URL — common BB pattern
  console.log('\n[5] Testing location URL patterns...');
  try {
    const r = await page.goto(`https://www.bigbasket.com/pd/Delhi/?type=ps&q=jivo`, {
      waitUntil: 'domcontentloaded', timeout: 30000
    });
    console.log(`[5] /pd/Delhi/ status: ${r ? r.status() : 'N/A'}`);
    await page.waitForTimeout(3000);
  } catch (e) {
    console.log(`[5] /pd/Delhi/ error: ${e.message}`);
  }

  // Try the search API directly in page context
  console.log('\n[6] Testing search API via in-page fetch...');
  const results = await page.evaluate(async (pin) => {
    const out = {};
    // 1. listing-svc v2
    try {
      const r = await fetch(`/listing-svc/v2/products?type=ps&slug=jivo&start=0&sz=10`, {
        headers: {
          'accept': 'application/json, text/plain, */*',
          'x-requested-with': 'XMLHttpRequest',
        }
      });
      out.listingSvc = { status: r.status, body: (await r.text()).slice(0, 1000) };
    } catch (e) { out.listingSvc = { err: e.message }; }

    // 2. custompage getsearchdata
    try {
      const r = await fetch(`/custompage/getsearchdata/?q=jivo&page=1`, {
        headers: {
          'accept': 'application/json, text/plain, */*',
          'x-requested-with': 'XMLHttpRequest',
        }
      });
      out.customPage = { status: r.status, body: (await r.text()).slice(0, 1000) };
    } catch (e) { out.customPage = { err: e.message }; }

    return out;
  }, PINCODE);
  console.log('[6] API test results:', JSON.stringify(results, null, 2));

  // Navigate to the BigBasket search results page for "jivo"
  console.log('\n[7] Navigating to search results page for jivo...');
  try {
    const r = await page.goto('https://www.bigbasket.com/ps/?q=jivo', {
      waitUntil: 'domcontentloaded', timeout: 30000
    });
    console.log(`[7] Search page status: ${r ? r.status() : 'N/A'}`);
    await page.waitForTimeout(5000);
  } catch (e) {
    console.log(`[7] Search error: ${e.message}`);
  }

  const searchTitle = await page.title().catch(() => 'N/A');
  const searchBody = await page.evaluate(() => document.body ? document.body.innerText.slice(0, 500) : '').catch(() => '');
  console.log(`[7] Search page title: ${searchTitle}`);
  console.log(`[7] Search body: ${searchBody.slice(0, 300)}`);

  await browser.close();

  console.log('\n=== FINAL CAPTURED REQUESTS ===');
  for (const r of capturedReqs) {
    if (r.type === 'REQ') console.log(`REQ ${r.method} ${r.url}`);
    else console.log(`RES ${r.status} ${r.url}`);
  }
}

main().catch(e => { console.error('FATAL:', e); process.exit(1); });
