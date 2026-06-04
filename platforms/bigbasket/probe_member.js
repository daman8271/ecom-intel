// Recon probe: inject the logged-in cookies, confirm the session is a genuine
// member, and dump member prices for a few Jivo SKUs to compare against the
// logged-out baseline. NOT part of the cron pipeline — a manual verification tool.
const { chromium } = require('playwright-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
const { loadBBCookies } = require('./import_cookies');
chromium.use(StealthPlugin());

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

(async () => {
  const { cookies, haveCritical, loggedIn } = loadBBCookies();
  console.log(`[cookies] usable=${cookies.length} critical=${haveCritical.join(',')} loggedIn=${loggedIn}`);
  const browser = await chromium.launch({
    headless: true, timeout: 60000,
    executablePath: require('playwright').chromium.executablePath(),
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-blink-features=AutomationControlled'],
  });
  const ctx = await browser.newContext({
    userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata',
    viewport: { width: 1280, height: 900 },
    extraHTTPHeaders: { 'accept-language': 'en-IN,en;q=0.9' },
  });
  await ctx.addCookies(cookies);
  const page = await ctx.newPage();
  const resp = await page.goto('https://www.bigbasket.com/', { waitUntil: 'domcontentloaded', timeout: 45000 });
  console.log(`[nav] homepage status ${resp ? resp.status() : 0}, final url ${page.url()}`);
  await page.waitForTimeout(3000);

  // 1) Member identity probe: BigBasket exposes the logged-in member via the
  //    member-svc. Try a couple of likely endpoints and report which return member data.
  const memberProbe = await page.evaluate(async () => {
    const tryUrl = async (u) => {
      try {
        const r = await fetch(u, { headers: { accept: 'application/json, text/plain, */*', 'x-requested-with': 'XMLHttpRequest' } });
        const txt = await r.text();
        return { u, status: r.status, redirected: r.redirected, finalUrl: r.url, body: txt.slice(0, 600) };
      } catch (e) { return { u, err: e.message }; }
    };
    const urls = [
      '/member-svc/v2/member/',
      '/member-svc/v1/active-orders/',
      '/ui-svc/v1/header/',
      '/account/',
    ];
    const out = [];
    for (const u of urls) out.push(await tryUrl(u));
    return out;
  });
  console.log('[member-probe]');
  for (const m of memberProbe) console.log('  ', JSON.stringify(m).slice(0, 700));

  // 2) Member prices: same listing-svc call the scraper uses.
  const listing = await page.evaluate(async () => {
    const r = await fetch('/listing-svc/v2/products?type=ps&slug=jivo&page=1&bucket_id=32', {
      headers: { accept: 'application/json, text/plain, */*', 'x-requested-with': 'XMLHttpRequest', referer: 'https://www.bigbasket.com/ps/?q=jivo' },
    });
    if (r.status !== 200) return { __err: 'HTTP ' + r.status };
    return await r.json();
  });
  if (listing.__err) {
    console.log('[listing] ERROR', listing.__err);
  } else {
    const pi = (listing.tabs && listing.tabs[0] && listing.tabs[0].product_info) || {};
    const prods = pi.products || [];
    console.log(`[listing] total_count=${pi.total_count} products_on_page=${prods.length}`);
    const flat = [];
    for (const p of prods) { flat.push(p); for (const c of (p.children || [])) flat.push(c); }
    for (const p of flat) {
      const b = (p.brand && p.brand.name || '').trim();
      if (!/^jivo$/i.test(b)) continue;
      const d = (p.pricing && p.pricing.discount) || {};
      const prim = d.prim_price || {};
      console.log(`  ${String(p.id).padStart(10)} | ${(p.desc || '').slice(0, 38).padEnd(38)} | ${String(p.w || '').padEnd(7)} | sp=${prim.sp} mrp=${d.mrp} memberSp=${prim.member_sp || ''} d_v=${d.camp_detail && d.camp_detail.d_v}`);
    }
    // also dump the full pricing block of one discounted SKU so we can see if a
    // distinct member field exists
    const sample = flat.find((p) => /^jivo$/i.test((p.brand && p.brand.name || '').trim()) && p.pricing && p.pricing.discount);
    if (sample) console.log('[sample pricing block]', JSON.stringify(sample.pricing).slice(0, 1200));
  }

  await ctx.close();
  await browser.close();
})().catch((e) => { console.error('FATAL', e.message); process.exit(1); });
