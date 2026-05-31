// BigBasket proof-of-concept scraper — Jivo olive oil search
// Proven by live recon 2026-05-31.
//
// HOW IT WORKS:
//   1. Stealth browser (playwright-extra + puppeteer-extra-plugin-stealth) bypasses
//      Akamai Bot Manager on www.bigbasket.com. Plain headless Chromium gets HTTP 403.
//   2. Load the BigBasket homepage (sets session cookies incl. csurftoken, x-channel).
//   3. Use in-page fetch (inherits all session cookies) to call:
//        GET /listing-svc/v2/products?type=ps&slug=<query>&page=1&bucket_id=32
//      Returns JSON: { tabs: [{ product_info: { products: [...], total_count, number_of_pages } }] }
//   4. Parse products: brand is in p.brand.name, pack in p.w, MRP in
//      p.pricing.discount.mrp, selling price in p.pricing.discount.prim_price.sp,
//      in-stock via p.availability.avail_status ('001' = in stock).
//
// LOCATION:  BigBasket is a SCHEDULED delivery (BB) platform — national catalog.
//   Prices are NATIONAL (not hyperlocal) so a single stealth session returns the
//   canonical Jivo catalog regardless of city. The browser session defaults to
//   Bangalore (hub_id/sa_id set by cookies) but the listing-svc returns the same
//   product set and pricing for all serviceable cities.
//   If per-city availability matters: the cookie `_bb_nhid` (hub id) and `_bb_cid`
//   (city id) control the location. These can be manipulated by overwriting them
//   before the listing-svc call (not needed for price intel; prices are uniform).
//
// Run:  cd /opt/ecom-intel/platforms/bigbasket && node poc.js

const { chromium } = require('playwright-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
chromium.use(StealthPlugin());

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const QUERY = process.env.BB_QUERY || 'jivo olive oil';

// ---- helpers ----
function parseVolMl(pack) {
  if (!pack) return null;
  const m = pack.toLowerCase().match(/([\d.]+)\s*(ml|l|ltr|litre|kg|g)\b/);
  if (!m) return null;
  const n = parseFloat(m[1]); const u = m[2];
  if (u === 'ml' || u === 'g') return n;
  if (u === 'l' || u === 'ltr' || u === 'litre' || u === 'kg') return n * 1000;
  return null;
}

function canonical(name, pack) {
  const base = (name || '').toLowerCase()
    .replace(/\(.*?\)/g, '').replace(/[^a-z0-9 ]/g, '')
    .replace(/\s+/g, ' ').trim().replace(/\s/g, '-');
  const vol = parseVolMl(pack);
  const volTag = vol ? (vol >= 1000 ? (vol / 1000) + 'l' : vol + 'ml') : 'na';
  return `${base}-${volTag}`.replace(/--+/g, '-');
}

function parseProducts(json) {
  const rows = [];
  const tabs = (json && json.tabs) || [];
  const pi = (tabs[0] && tabs[0].product_info) || {};
  const products = pi.products || [];
  for (const p of products) {
    const brandName = (p.brand && p.brand.name && p.brand.name.trim()) || '';
    // Filter: keep only Jivo brand
    if (!/^jivo$/i.test(brandName)) continue;
    const disc = (p.pricing && p.pricing.discount) || {};
    const mrp = disc.mrp ? parseFloat(disc.mrp) : null;
    const sp = disc.prim_price && disc.prim_price.sp ? parseFloat(disc.prim_price.sp) : mrp;
    const pack = p.w || '';
    const vol = parseVolMl(pack);
    // in_stock: avail_status '001' = available; anything else (002, 004) = OOS/not-for-sale
    const inStock = !p.availability || (p.availability.avail_status === '001' && !p.availability.not_for_sale) ? 1 : 0;
    rows.push({
      sku_id: String(p.id || ''),
      name: p.desc || '',
      brand: brandName,
      pack,
      vol_ml: vol,
      mrp,
      sale: sp,
      discount_pct: (mrp && sp && mrp > sp) ? Math.round(((mrp - sp) / mrp) * 1000) / 10 : 0,
      per_litre: vol ? Math.round((sp / (vol / 1000)) * 100) / 100 : null,
      in_stock: inStock,
      avail_status: (p.availability && p.availability.avail_status) || '',
      canonical: canonical(p.desc, pack),
    });
  }
  return rows;
}

async function main() {
  process.stderr.write(`[bb] Launching stealth browser for query="${QUERY}"...\n`);
  const browser = await chromium.launch({
    headless: true,
    executablePath: require('playwright').chromium.executablePath(),
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-blink-features=AutomationControlled',
    ],
  });

  let rows = [];
  try {
    const ctx = await browser.newContext({
      userAgent: UA,
      locale: 'en-IN',
      timezoneId: 'Asia/Kolkata',
      viewport: { width: 1280, height: 900 },
      extraHTTPHeaders: { 'accept-language': 'en-IN,en;q=0.9' },
    });

    const page = await ctx.newPage();

    // Block images/fonts/media — speed optimisation
    await ctx.route('**/*', (route) => {
      const t = route.request().resourceType();
      if (['image', 'font', 'media'].includes(t)) return route.abort();
      return route.continue();
    });

    // 1. Load homepage — establishes session cookies (csurftoken, csrftoken, x-channel, _bb_*)
    process.stderr.write('[bb] Loading homepage to establish session...\n');
    await page.goto('https://www.bigbasket.com/', {
      waitUntil: 'domcontentloaded',
      timeout: 45000,
    });
    await page.waitForTimeout(2500);

    // 2. Call listing-svc via in-page fetch (inherits all cookies → avoids extra WAF checks)
    //    URL pattern confirmed by live XHR capture:
    //      /listing-svc/v2/products?type=ps&slug=<query>&page=1&bucket_id=32
    //    bucket_id=32 is the default bucket the BB React app uses for search.
    process.stderr.write(`[bb] Calling listing-svc for "${QUERY}"...\n`);
    const slug = encodeURIComponent(QUERY.toLowerCase().trim());
    const result = await page.evaluate(async (slug) => {
      try {
        const url = `/listing-svc/v2/products?type=ps&slug=${slug}&page=1&bucket_id=32`;
        const r = await fetch(url, {
          headers: {
            'accept': 'application/json, text/plain, */*',
            'x-requested-with': 'XMLHttpRequest',
            'referer': `https://www.bigbasket.com/ps/?q=${slug}`,
          },
        });
        if (r.status !== 200) return { __err: `HTTP ${r.status}` };
        return await r.json();
      } catch (e) { return { __err: e.message }; }
    }, slug);

    if (result && result.__err) {
      process.stderr.write(`[bb] listing-svc error: ${result.__err}\n`);
    } else {
      rows = parseProducts(result);
      const totalProducts = (result.tabs && result.tabs[0] && result.tabs[0].product_info && result.tabs[0].product_info.total_count) || 0;
      process.stderr.write(`[bb] listing-svc returned ${totalProducts} total products, ${rows.length} Jivo rows\n`);
    }
  } finally {
    await browser.close();
  }

  // Print parsed rows to stdout
  if (rows.length === 0) {
    process.stderr.write('[bb] WARNING: 0 Jivo rows found\n');
  }
  for (const r of rows) {
    console.log(JSON.stringify(r));
  }
  process.stderr.write(`[bb] Done. ${rows.length} rows.\n`);
  return rows;
}

main().catch(e => { console.error('FATAL:', e); process.exit(1); });
