// MAKE-OR-BREAK test of the logged-in cookie-transplant plan for Flipkart Minutes.
//
// Loads secrets/flipkart-minutes.storageState.json (a real logged-in session exported on the
// user's clean machine) and tests whether we can do the WHOLE flow as fast API calls — set the
// delivery location for a pincode, then search "jivo" — WITHOUT the slow per-pincode browser
// GPS/click dance. If this works for several pincodes inside ONE context, the production
// scraper becomes ~seconds (one session looping 345 pincodes via fetch, high concurrency).
//
//   node probe_session.js
//
// Each call goes via page.evaluate(fetch(..., credentials:'include')) so it inherits the
// transplanted cookies (T + at + ...) and the browser picks CORS/DC routing automatically.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const STATE = path.join(__dirname, 'secrets', 'flipkart-minutes.storageState.json');
const UA = process.env.UA ||
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 FKUA/msite/0.0.4/msite/Mobile';

// Test pincodes with full addressInfo (so location/update has what it needs). Mix of metros.
const TESTS = [
  { pincode: '201304', city: 'Noida', state: 'Uttar Pradesh', locality: 'Sector 106', lat: 28.5355, lon: 77.391 },
  { pincode: '400069', city: 'Mumbai', state: 'Maharashtra', locality: 'Andheri East', lat: 19.1136, lon: 72.8697 },
  { pincode: '560066', city: 'Bengaluru', state: 'Karnataka', locality: 'Whitefield', lat: 12.9698, lon: 77.7499 },
];

function dcCandidates() {
  // Prefer the DC from the at JWT's z field; fall back to brute-forcing 1..4.
  try {
    const st = JSON.parse(fs.readFileSync(STATE, 'utf8'));
    const at = (st.cookies || []).find((c) => c.name === 'at');
    const z = JSON.parse(Buffer.from(at.value.split('.')[1], 'base64').toString('utf8')).z;
    const map = { CH: 1, HYD: 2, MUM: 3, KOL: 4 };
    const n = map[z];
    if (n) return [n, ...[1, 2, 3, 4].filter((x) => x !== n)];
  } catch (_) {}
  return [1, 2, 3, 4];
}

// Runs inside the page (browser) context — uses the transplanted cookies via credentials:'include'.
async function apiCall(page, url, body) {
  return page.evaluate(async ({ url, body }) => {
    try {
      const r = await fetch(url, {
        method: 'POST', credentials: 'include',
        headers: {
          'flipkart_secure': 'true',
          'content-type': 'application/json',
          'accept-language': 'en-IN,en;q=0.9',
          'x-user-agent': navigator.userAgent,
        },
        body: JSON.stringify(body),
      });
      const t = await r.text();
      let j = null; try { j = JSON.parse(t); } catch (_) {}
      return { status: r.status, json: j, text: t.slice(0, 400) };
    } catch (e) { return { status: -1, error: String(e) }; }
  }, { url, body });
}

function extractJivo(searchJson) {
  const out = [];
  const slots = (searchJson && (searchJson.RESPONSE || searchJson).slots) || [];
  for (const s of slots) {
    const prods = (((s.widget || {}).data || {}).products) || [];
    for (const p of prods) {
      const v = ((p.productInfo || {}).value) || {};
      const title = ((v.titles || {}).title) || '';
      if (!/jivo/i.test(title) && !/jivo/i.test(v.productBrand || '')) continue;
      const pricing = v.pricing || {};
      const sale = (pricing.finalPrice || {}).value;
      const mrp = ((pricing.prices || []).find((x) => x.priceType === 'MRP') || {}).value;
      const inStock = ((v.availability || {}).displayState) === 'IN_STOCK';
      out.push({ title, sale, mrp, inStock });
    }
  }
  return out;
}

(async () => {
  if (!fs.existsSync(STATE)) { console.error('no storageState at ' + STATE + ' — run import_cookies.js first'); process.exit(1); }
  let browser;
  try { browser = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox'] }); }
  catch (_) { browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] }); }
  const ctx = await browser.newContext({
    userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata',
    viewport: { width: 1366, height: 900 }, storageState: STATE,
  });
  const page = await ctx.newPage();

  // 1) establish flipkart.com origin + confirm we're logged in
  await page.goto('https://www.flipkart.com/', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(2500);
  const loggedIn = await page.evaluate(() => !/Login/i.test((document.querySelector('a[href*="login"]') || {}).innerText || '') &&
    document.cookie.includes('at=') || document.body.innerText.length > 0).catch(() => false);
  console.log('origin established; cookies carry at=' + (await ctx.cookies()).some((c) => c.name === 'at'));

  const dcs = dcCandidates();
  let N = null;

  for (const t of TESTS) {
    const result = { pincode: t.pincode, city: t.city };
    // 2) set delivery location for this pincode (the step that 302'd as a guest)
    const locBody = {
      geoLocation: { latitude: String(t.lat), longitude: String(t.lon) },
      addressInfo: { addressLine1: t.locality, city: t.city, state: t.state, pincode: t.pincode },
      redirectionUrl: '/flipkart-minutes-store?marketplace=HYPERLOCAL',
      marketplace: 'HYPERLOCAL',
    };
    let loc;
    for (const n of (N ? [N] : dcs)) {
      loc = await apiCall(page, `https://${n}.rome.api.flipkart.com/api/4/location/update`, locBody);
      if (loc.status !== 406) { N = n; break; }
    }
    result.locStatus = loc.status;
    result.currentPincode = loc.json && (loc.json.currentPincode || (loc.json.RESPONSE || {}).currentPincode);

    // 3) search jivo at the now-set location
    const searchBody = {
      pageUri: '/search?q=jivo&marketplace=HYPERLOCAL',
      locationContext: { pincode: parseInt(t.pincode, 10), changed: false },
      pageContext: { trackingContext: { context: { eVar51: 'direct_browse', eVar61: 'direct_browse' } }, fetchSeoData: true, networkSpeed: 9400 },
      requestContext: { type: 'BROWSE_PAGE' },
    };
    const srch = await apiCall(page, `https://${N || dcs[0]}.rome.api.flipkart.com/api/4/page/fetch?cacheFirst=false`, searchBody);
    result.searchStatus = srch.status;
    const redirect = srch.json && (((srch.json.RESPONSE || srch.json).pageMeta || {}).redirectionObject || {}).statusCode;
    result.redirected302 = redirect === 302;
    const jivo = redirect === 302 ? [] : extractJivo(srch.json || {});
    result.jivoCount = jivo.length;
    result.sample = jivo.slice(0, 3).map((j) => `${j.title} = Rs.${j.sale}/${j.mrp} ${j.inStock ? 'IN' : 'OOS'}`);
    console.log(JSON.stringify(result));
    await page.waitForTimeout(800);
  }

  await browser.close();
  console.log('\nVERDICT: if jivoCount>0 (not redirected302) for multiple pincodes in this ONE session, the logged-in pure-API loop WORKS -> scraper becomes ~seconds.');
})().catch((e) => { console.error('probe failed:', e); process.exit(1); });
