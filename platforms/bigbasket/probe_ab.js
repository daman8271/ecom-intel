// A/B probe: in ONE run, fetch the same listing-svc query as a GUEST (no cookies)
// and as the logged-in MEMBER (cookies injected), back to back, to isolate the
// login effect on price from time-of-day drift. Manual verification tool only.
const { chromium } = require('playwright-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
const { loadBBCookies } = require('./import_cookies');
chromium.use(StealthPlugin());
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

async function fetchJivo(page) {
  return page.evaluate(async () => {
    const out = {};
    for (let pg = 1; pg <= 2; pg++) {
      const r = await fetch(`/listing-svc/v2/products?type=ps&slug=jivo&page=${pg}&bucket_id=32`, {
        headers: { accept: 'application/json, text/plain, */*', 'x-requested-with': 'XMLHttpRequest', referer: 'https://www.bigbasket.com/ps/?q=jivo' },
      });
      if (r.status !== 200) break;
      const j = await r.json();
      const pi = (j.tabs && j.tabs[0] && j.tabs[0].product_info) || {};
      const flat = [];
      for (const p of (pi.products || [])) { flat.push(p); for (const c of (p.children || [])) flat.push(c); }
      for (const p of flat) {
        const b = (p.brand && p.brand.name || '').trim();
        if (!/^jivo$/i.test(b)) continue;
        const d = (p.pricing && p.pricing.discount) || {};
        const prim = d.prim_price || {};
        out[String(p.id)] = { name: (p.desc || '').slice(0, 34), w: p.w, sp: prim.sp, mrp: d.mrp };
      }
      if (pg >= (pi.number_of_pages || 1)) break;
    }
    return out;
  });
}

async function session(browser, cookies) {
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1280, height: 900 }, extraHTTPHeaders: { 'accept-language': 'en-IN,en;q=0.9' } });
  if (cookies) await ctx.addCookies(cookies);
  const page = await ctx.newPage();
  await page.goto('https://www.bigbasket.com/', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await page.waitForTimeout(2500);
  const data = await fetchJivo(page);
  await ctx.close();
  return data;
}

(async () => {
  const { cookies } = loadBBCookies();
  const browser = await chromium.launch({ headless: true, timeout: 60000, executablePath: require('playwright').chromium.executablePath(), args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-blink-features=AutomationControlled'] });
  console.log('--- GUEST (no cookies) ---');
  const guest = await session(browser, null);
  console.log('--- MEMBER (cookies) ---');
  const member = await session(browser, cookies);
  await browser.close();

  const ids = [...new Set([...Object.keys(guest), ...Object.keys(member)])];
  console.log(`\nguest SKUs=${Object.keys(guest).length} member SKUs=${Object.keys(member).length}`);
  console.log('id'.padStart(10), '| name'.padEnd(36), '| pack'.padEnd(8), '| guest_sp'.padStart(10), '| member_sp'.padStart(10), '| diff');
  let changed = 0;
  for (const id of ids) {
    const g = guest[id], m = member[id];
    const gs = g ? g.sp : null, ms = m ? m.sp : null;
    const name = (m || g).name, w = (m || g).w;
    const diff = (gs != null && ms != null) ? (parseFloat(ms) - parseFloat(gs)).toFixed(2) : (g ? 'MEMBER-ONLY-MISSING' : 'GUEST-ONLY-MISSING');
    if (gs !== ms) changed++;
    console.log(String(id).padStart(10), '|', name.padEnd(34), '|', String(w).padEnd(6), '|', String(gs).padStart(8), '|', String(ms).padStart(8), '|', diff);
  }
  console.log(`\nSKUs with sp differing guest vs member: ${changed}/${ids.length}`);
})().catch((e) => { console.error('FATAL', e.message); process.exit(1); });
