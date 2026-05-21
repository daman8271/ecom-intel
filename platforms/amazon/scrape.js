const { chromium } = require('playwright');
const fs = require('fs');

// ---------------------------------------------------------------------------
// AMAZON marketplace scraper.  STATUS: WORKING from this datacenter VPS IP, but
// only after passing a bot interstitial: amazon.in returns HTTP 202 with a
// "Continue shopping" button; click it, then the site + search work (200) with
// NO login.  Raw un-clicked requests get 503 throttles, so the bypass is required.
//
// Like Flipkart, marketplace pricing is NATIONAL -> scrape the Jivo catalog once
// (paginated) and tag rows city="All India"; pincodes.json is unused.  Output
// shape stays Blinkit-compatible so build_excel.py works.
// ---------------------------------------------------------------------------

const SEARCH = 'https://www.amazon.in/s?k=jivo';
const MAX_PAGES = 5;
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

function parseVolMl(pack) {
  if (!pack) return null;
  const p = pack.toLowerCase();
  const mult = p.match(/([\d.]+)\s*x\s*([\d.]+)\s*(ml|l|ltr|litre|kg|g)/);
  if (mult) {
    const count = parseFloat(mult[1]);
    let v = parseFloat(mult[2]);
    const u = mult[3];
    if (u === 'l' || u === 'ltr' || u === 'litre' || u === 'kg') v *= 1000;
    return count * v;
  }
  const m = p.match(/([\d.]+)\s*(ml|l|ltr|litre|kg|g)/);
  if (!m) return null;
  let n = parseFloat(m[1]);
  const u = m[2];
  if (u === 'l' || u === 'ltr' || u === 'litre' || u === 'kg') n *= 1000;
  return n;
}

function canonical(name, pack) {
  const base = (name || '').toLowerCase()
    .replace(/\(.*?\)/g, '')
    .replace(/[^a-z0-9 ]/g, '')
    .replace(/\s+/g, ' ').trim()
    .replace(/\s/g, '-');
  const vol = parseVolMl(pack);
  const volTag = vol ? (vol >= 1000 ? (vol / 1000) + 'l' : vol + 'ml') : 'na';
  return `${base}-${volTag}`.replace(/--+/g, '-');
}

// pass the "Continue shopping" interstitial that amazon.in shows datacenter IPs
async function passInterstitial(page) {
  await page.goto('https://www.amazon.in/', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await page.waitForTimeout(2000);
  try { await page.getByRole('button', { name: /continue shopping/i }).click({ timeout: 7000 }); } catch (e) {}
  await page.waitForTimeout(3000);
}

async function scrapePage(page, url) {
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 35000 });
  await page.waitForTimeout(3000);
  return page.evaluate(() => {
    const toInt = (s) => { const m = (s || '').match(/₹\s*([\d,]+)/); return m ? parseInt(m[1].replace(/,/g, ''), 10) : null; };
    const out = [];
    document.querySelectorAll('[data-component-type="s-search-result"]').forEach((el) => {
      const all = el.textContent || '';
      if (!/jivo/i.test(all)) return;
      const titleEl = el.querySelector('[data-cy="title-recipe"]') || el.querySelector('h2');
      const title = (titleEl ? titleEl.innerText : '').replace(/\s+/g, ' ').trim();
      // sale = the first .a-price (main current price). mrp = the largest integer
      // ₹ value in the card (the struck M.R.P.). Per-unit prices (e.g. ₹247.80)
      // carry a decimal so the ^₹[\d,]+$ test drops them; coupons sit below sale
      // so they can't beat the max. Fall back to sale when no higher MRP exists.
      const intPrices = [...el.querySelectorAll('span')]
        .map((n) => (n.textContent || '').replace(/\s/g, ''))
        .filter((s) => /^₹[\d,]+$/.test(s))
        .map((s) => parseInt(s.replace(/[₹,]/g, ''), 10))
        .filter((n) => n > 0);
      const sale = toInt((el.querySelector('.a-price .a-offscreen') || {}).textContent) || (intPrices.length ? Math.min(...intPrices) : null);
      const mrp = intPrices.length ? Math.max(...intPrices) : sale;
      const rating = (all.match(/(\d\.\d)\s*out of 5/i) || [])[1] || '';
      const oos = /currently unavailable|out of stock|temporarily out of stock/i.test(all);
      out.push({ title, sale, mrp, rating, oos });
    });
    return out;
  });
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
  const t0 = Date.now();
  await passInterstitial(page);

  let rows = [];
  for (let p = 1; p <= MAX_PAGES; p++) {
    let cards = [];
    try { cards = await scrapePage(page, `${SEARCH}&page=${p}`); }
    catch (e) { process.stderr.write(`[err] page ${p}: ${e.message}\n`); }
    let added = 0;
    for (const c of cards) {
      // strip leading badges, keep the part before the first "|" descriptor
      const name = (c.title || '')
        .replace(/^(sponsored|amazon's choice|overall pick|best ?seller|limited time deal)\s*/i, '')
        .split('|')[0].replace(/\(pack of \d+\)/i, '').replace(/\s+/g, ' ').trim();
      if (!/jivo/i.test(name) || !c.sale) continue;
      const packM = name.match(/(\d[\d.]*\s*x\s*\d[\d.]*\s*(?:ml|l|ltr|litres?|kg|g)|\d[\d.]*\s*(?:ml|l|ltr|litres?|kg|g))\b/i);
      const pack = packM ? packM[1].replace(/\s+/g, ' ').trim() : '';
      let sale = c.sale;
      let mrp = c.mrp && c.mrp >= sale ? c.mrp : sale; // struck MRP, else no discount
      rows.push({
        city: 'All India', pincode: '-', locality: 'Amazon marketplace (national)',
        store_id: '', store_name: 'Amazon',
        sku_raw: name, canonical: canonical(name, pack), pack: pack || '',
        vol_ml: parseVolMl(pack), sale, mrp,
        discount_pct: (mrp && sale && mrp >= sale && mrp > sale) ? Math.round(((mrp - sale) / mrp) * 1000) / 10 : 0,
        per_litre: parseVolMl(pack) ? Math.round((sale / (parseVolMl(pack) / 1000)) * 100) / 100 : null,
        eta_min: null,
        in_stock: c.oos ? 0 : 1,
      });
      added++;
    }
    process.stderr.write(`[ok] page ${p} -> ${added} jivo cards (running total ${rows.length})\n`);
    if (added === 0 && p > 1) break;
  }
  await browser.close();

  // dedup on canonical (national catalog -> one row per SKU)
  const dd = new Map();
  for (const r of rows) if (!dd.has(r.canonical)) dd.set(r.canonical, r);
  rows = [...dd.values()];

  const summary = {
    pincodes_total: 1,
    pincodes_with_jivo: rows.length ? 1 : 0,
    total_rows: rows.length,
    unique_skus: new Set(rows.map((r) => r.canonical)).size,
    wall_s: Math.round((Date.now() - t0) / 1000),
    captured_at: new Date().toISOString(),
  };
  const perPin = [{ city: 'All India', pincode: '-', locality: 'Amazon marketplace (national)', tier: 0, store_id: '', store_name: 'Amazon', rows }];
  process.stderr.write('[SUMMARY] ' + JSON.stringify(summary) + '\n');
  fs.writeFileSync(__dirname + '/result.json', JSON.stringify({ summary, perPin, allRows: rows }, null, 2));
  console.log(JSON.stringify(summary));
})();
