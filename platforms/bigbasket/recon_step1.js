// BigBasket recon step 1: anti-bot test + capture location + search XHR
// Run from /opt/ecom-intel/platforms/bigbasket/
// Usage: node recon_step1.js 2>&1 | tee recon_step1.log

const { chromium } = require('playwright');

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

// Known-Jivo pincode in Delhi
const PINCODE = '110001';

async function main() {
  console.log('[1] Launching headless chromium...');
  const browser = await chromium.launch({
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-blink-features=AutomationControlled',
    ],
  });

  const ctx = await browser.newContext({
    userAgent: UA,
    locale: 'en-IN',
    timezoneId: 'Asia/Kolkata',
    viewport: { width: 1280, height: 900 },
    extraHTTPHeaders: { 'accept-language': 'en-IN,en;q=0.9' },
  });

  // Stealth: hide webdriver marker
  await ctx.addInitScript(() => {
    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
    window.chrome = { runtime: {} };
    Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3, 4, 5] });
    Object.defineProperty(navigator, 'languages', { get: () => ['en-IN', 'en'] });
  });

  const page = await ctx.newPage();

  // Capture ALL network requests/responses
  const capturedRequests = [];
  page.on('request', (req) => {
    const u = req.url();
    // Filter for interesting API calls
    if (u.includes('/api/') || u.includes('listing-svc') || u.includes('search') ||
        u.includes('serviceability') || u.includes('address') || u.includes('location') ||
        u.includes('pincode') || u.includes('product') || u.includes('custompage')) {
      capturedRequests.push({
        type: 'request',
        method: req.method(),
        url: u,
        headers: req.headers(),
        postData: req.postData(),
      });
    }
  });

  page.on('response', async (res) => {
    const u = res.url();
    const status = res.status();
    if (u.includes('/api/') || u.includes('listing-svc') || u.includes('search') ||
        u.includes('serviceability') || u.includes('address') || u.includes('location') ||
        u.includes('pincode') || u.includes('product') || u.includes('custompage')) {
      let body = null;
      try {
        const text = await res.text();
        // Only keep small responses, truncate large ones
        body = text.length < 50000 ? text : text.slice(0, 2000) + '...[TRUNCATED]';
      } catch (_) {}
      capturedRequests.push({
        type: 'response',
        status,
        url: u,
        body,
      });
    }
  });

  // Block images/fonts/media to speed things up
  await ctx.route('**/*', (route) => {
    const t = route.request().resourceType();
    if (['image', 'font', 'media'].includes(t)) return route.abort();
    return route.continue();
  });

  console.log('[2] Loading BigBasket homepage...');
  let homeStatus = 'unknown';
  try {
    const resp = await page.goto('https://www.bigbasket.com/', {
      waitUntil: 'domcontentloaded',
      timeout: 40000,
    });
    homeStatus = resp ? resp.status() : 'no-response';
    console.log(`[2] Homepage status: ${homeStatus}`);
  } catch (e) {
    console.log(`[2] Homepage load error: ${e.message}`);
    homeStatus = 'error:' + e.message;
  }

  await page.waitForTimeout(3000);

  // Check cookies
  const cookies = await ctx.cookies();
  const cookieNames = cookies.map(c => c.name);
  console.log('\n[3] COOKIES SET:');
  for (const c of cookies) {
    if (['_abck','bm_sz','ak_bmsc','_bb_addressinfo','_bb_pin_code','_bb_cid','_bb_loid','csurftoken','x-channel','x-tracker'].includes(c.name) || c.name.startsWith('_bb')) {
      console.log(`  ${c.name} = ${c.value.slice(0, 80)}...`);
    }
  }
  console.log(`  All cookie names: ${cookieNames.join(', ')}`);

  // Check for Akamai markers in page
  const pageTitle = await page.title().catch(() => 'N/A');
  const pageText = await page.evaluate(() => document.body ? document.body.innerText.slice(0, 500) : '').catch(() => '');
  console.log(`\n[3] Page title: ${pageTitle}`);
  console.log(`[3] Page text snippet: ${pageText.slice(0, 200)}`);

  // Check if we're blocked / got Akamai challenge
  const hasAkamai = cookieNames.some(n => ['_abck', 'bm_sz', 'ak_bmsc'].includes(n));
  const isChallenged = pageText.toLowerCase().includes('access denied') ||
                       pageText.toLowerCase().includes('blocked') ||
                       pageText.toLowerCase().includes('captcha') ||
                       pageTitle.toLowerCase().includes('access denied');
  console.log(`\n[3] Akamai cookies present: ${hasAkamai}`);
  console.log(`[3] Appears challenged/blocked: ${isChallenged}`);

  // Check if site loaded normally
  const hasBBContent = pageText.toLowerCase().includes('bigbasket') ||
                       pageText.toLowerCase().includes('grocery') ||
                       pageTitle.toLowerCase().includes('bigbasket');
  console.log(`[3] BigBasket content loaded: ${hasBBContent}`);

  // Wait longer for React to hydrate
  await page.waitForTimeout(5000);

  // Dump captured API calls so far
  console.log('\n[4] CAPTURED API REQUESTS/RESPONSES (so far):');
  for (const r of capturedRequests) {
    if (r.type === 'request') {
      console.log(`  REQ ${r.method} ${r.url}`);
      if (r.postData) console.log(`    body: ${r.postData.slice(0, 200)}`);
    } else {
      console.log(`  RES ${r.status} ${r.url}`);
      if (r.body && r.body.length < 500) console.log(`    body: ${r.body}`);
    }
  }

  // Now try to set pincode by navigating to URL with pincode
  // BigBasket has a URL pattern /pd/<city>/ and uses cookies for location
  console.log('\n[5] Attempting to set location pincode 110001 (New Delhi)...');

  // First try direct API call from page context to check serviceability
  const servicResult = await page.evaluate(async (pin) => {
    try {
      // Try the serviceability check endpoint
      const r = await fetch(`/api/v1/tb-location/?city=${pin}&force_verify=1`, {
        headers: { 'accept': 'application/json, text/plain, */*', 'x-requested-with': 'XMLHttpRequest' }
      });
      return { status: r.status, body: await r.text().then(t => t.slice(0, 1000)) };
    } catch (e) { return { err: e.message }; }
  }, PINCODE);
  console.log('[5] Serviceability check:', JSON.stringify(servicResult, null, 2));

  // Try direct search without location first to see what we get
  console.log('\n[6] Trying search API calls (various candidates)...');

  // Candidate 1: listing-svc
  const listingSvcResult = await page.evaluate(async () => {
    try {
      const r = await fetch('/listing-svc/v2/products?type=ps&slug=jivo&start=0&sz=10', {
        headers: {
          'accept': 'application/json, text/plain, */*',
          'x-requested-with': 'XMLHttpRequest',
          'referer': 'https://www.bigbasket.com/ps/?q=jivo',
        }
      });
      const text = await r.text();
      return { status: r.status, body: text.slice(0, 2000) };
    } catch (e) { return { err: e.message }; }
  });
  console.log('[6] /listing-svc/v2/products:', JSON.stringify(listingSvcResult).slice(0, 500));

  // Candidate 2: custompage search
  const customPageResult = await page.evaluate(async () => {
    try {
      const r = await fetch('/custompage/getsearchdata/?slug=jivo&page=1', {
        headers: {
          'accept': 'application/json, text/plain, */*',
          'x-requested-with': 'XMLHttpRequest',
          'referer': 'https://www.bigbasket.com/ps/?q=jivo',
        }
      });
      const text = await r.text();
      return { status: r.status, body: text.slice(0, 2000) };
    } catch (e) { return { err: e.message }; }
  });
  console.log('[6] /custompage/getsearchdata:', JSON.stringify(customPageResult).slice(0, 500));

  await browser.close();

  // Final summary
  console.log('\n=== FINAL SUMMARY ===');
  console.log(`Homepage status: ${homeStatus}`);
  console.log(`Akamai detected: ${hasAkamai}`);
  console.log(`Blocked: ${isChallenged}`);
  console.log(`Content loaded: ${hasBBContent}`);
  console.log('Total API interactions captured:', capturedRequests.length);
}

main().catch(e => { console.error('FATAL:', e); process.exit(1); });
