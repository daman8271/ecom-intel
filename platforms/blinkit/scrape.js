const { chromium } = require('playwright');
const fs = require('fs');

const PFILE = process.env.PINCODES_FILE || (__dirname + '/pincodes.json');
const PINCODES = JSON.parse(fs.readFileSync(PFILE, 'utf8'));
const CONCURRENCY = parseInt(process.env.CONCURRENCY || '4', 10);
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

function parseVolMl(pack) {
  if (!pack) return null;
  const m = pack.toLowerCase().match(/([\d.]+)\s*(ml|l|ltr|litre|kg|g)/);
  if (!m) return null;
  const n = parseFloat(m[1]);
  const u = m[2];
  if (u === 'ml' || u === 'g') return n;
  if (u === 'l' || u === 'ltr' || u === 'litre' || u === 'kg') return n * 1000;
  return null;
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

async function scrapeOne(browser, rec) {
  const t0 = Date.now();
  const ctx = await browser.newContext({
    userAgent: UA,
    locale: 'en-IN',
    timezoneId: 'Asia/Kolkata',
    viewport: { width: 1280, height: 900 },
  });
  const page = await ctx.newPage();
  // block heavy assets for speed/bandwidth
  await ctx.route('**/*', (route) => {
    const t = route.request().resourceType();
    if (['image', 'font', 'media'].includes(t)) return route.abort();
    return route.continue();
  });
  let rows = [];
  let store = {};
  try {
    await page.goto('https://blinkit.com/', { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(2500);
    await page.evaluate((r) => {
      localStorage.setItem('location', JSON.stringify({
        coords: { isDefault: false, lat: r.lat, lon: r.lon, locality: r.locality, id: 1, isTopCity: true, cityName: r.city, landmark: r.landmark, addressId: null }
      }));
    }, rec);
    await page.goto('https://blinkit.com/s/?q=jivo', { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(4500);
    store = JSON.parse((await page.evaluate(() => localStorage.getItem('merchant'))) || '{}');
    const cards = await page.evaluate(() => {
      const out = [];
      const seen = new Set();
      document.querySelectorAll('div').forEach((el) => {
        const t = el.innerText || '';
        if (!/jivo/i.test(t) || !/₹/.test(t)) return;
        const r = el.getBoundingClientRect();
        if (r.width < 100 || r.width > 420) return;
        if (r.height < 180 || r.height > 620) return;
        const key = t.slice(0, 90);
        if (seen.has(key)) return;
        seen.add(key);
        out.push(t.replace(/\s+/g, ' ').trim());
      });
      return out;
    });
    for (const c of cards) {
      // pattern: [disc% OFF] [eta MINS] NAME PACK ₹SALE ₹MRP ADD/OutofStock
      const inStock = !/out of stock/i.test(c);
      const eta = (c.match(/(\d+)\s*MINS?/i) || [])[1];
      const disc = (c.match(/(\d+)%\s*OFF/i) || [])[1];
      const prices = [...c.matchAll(/₹\s*([\d,]+)/g)].map((m) => parseInt(m[1].replace(/,/g, ''), 10));
      const sale = prices.length ? prices[0] : null;
      const mrp = prices.length > 1 ? prices[1] : sale;
      // name: between the MINS/OFF prefix and the first ₹ / pack
      let name = c.replace(/^\d+%\s*OFF\s*/i, '').replace(/^.*?\d+\s*MINS?\s*/i, '');
      name = name.replace(/Out of Stock/i, '').trim();
      const packM = name.match(/(\d[\d.]*\s*(?:ml|l|ltr|litre|kg|g))/i);
      const pack = packM ? packM[1] : '';
      name = name.replace(/₹.*$/, '').replace(/ADD\s*$/i, '');
      if (pack) name = name.split(pack)[0];
      name = name.trim();
      if (!/jivo/i.test(name) || !sale) continue;
      rows.push({
        city: rec.city, pincode: rec.pincode, locality: rec.locality,
        store_id: store.id || '', store_name: store.name || '',
        sku_raw: name, canonical: canonical(name, pack), pack: pack || '',
        vol_ml: parseVolMl(pack), sale, mrp,
        discount_pct: (mrp && sale && mrp >= sale) ? Math.round(((mrp - sale) / mrp) * 1000) / 10 : (disc ? parseFloat(disc) : null),
        per_litre: parseVolMl(pack) ? Math.round((sale / (parseVolMl(pack) / 1000)) * 100) / 100 : null,
        eta_min: eta ? parseInt(eta, 10) : null,
        in_stock: inStock ? 1 : 0,
      });
    }
    // dedup on (store_id, canonical)
    const dd = new Map();
    for (const r of rows) {
      const k = `${r.store_id}|${r.canonical}`;
      if (!dd.has(k)) dd.set(k, r);
    }
    rows = [...dd.values()];
  } catch (e) {
    process.stderr.write(`[err] ${rec.city} ${rec.pincode}: ${e.message}\n`);
  } finally {
    await ctx.close();
  }
  process.stderr.write(`[ok] ${rec.city} ${rec.pincode} -> ${rows.length} jivo SKUs (${((Date.now() - t0) / 1000).toFixed(1)}s) store=${store.name || 'n/a'}\n`);
  return { ...rec, store_id: store.id || '', store_name: store.name || '', rows };
}

async function pool(items, n, fn) {
  const results = [];
  let i = 0;
  async function worker() {
    while (i < items.length) {
      const idx = i++;
      results[idx] = await fn(items[idx], idx);
      await new Promise((r) => setTimeout(r, 800 + Math.random() * 1500));
    }
  }
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, worker));
  return results;
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const t0 = Date.now();
  const perPin = await pool(PINCODES, CONCURRENCY, (rec) => scrapeOne(browser, rec));
  await browser.close();
  const allRows = perPin.flatMap((p) => p.rows);
  const summary = {
    pincodes_total: PINCODES.length,
    pincodes_with_jivo: perPin.filter((p) => p.rows.length > 0).length,
    total_rows: allRows.length,
    unique_skus: new Set(allRows.map((r) => r.canonical)).size,
    wall_s: Math.round((Date.now() - t0) / 1000),
    captured_at: new Date().toISOString(),
  };
  process.stderr.write('[SUMMARY] ' + JSON.stringify(summary) + '\n');
  fs.writeFileSync(process.env.OUT_FILE || (__dirname + '/result.json'), JSON.stringify({ summary, perPin, allRows }, null, 2));
  console.log(JSON.stringify(summary));
})();
