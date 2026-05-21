const { chromium } = require('playwright');
const fs = require('fs');

// ---------------------------------------------------------------------------
// ZEPTO scraper.  STATUS: BLOCKED from this datacenter VPS IP (CloudFront 403).
// See BLOCKED.md.  The card-extraction logic below is UNVERIFIED — the page
// never loaded from this IP, so selectors are the portable geometry heuristic
// carried over from Blinkit, NOT confirmed against a real Zepto DOM.
// When a residential proxy is available: run `./run.sh zepto`, watch the log.
// The 403 guard will fail loudly if still blocked; otherwise tune the parser.
// ---------------------------------------------------------------------------

const PINCODES = JSON.parse(fs.readFileSync(__dirname + '/pincodes.json', 'utf8'));
const CONCURRENCY = 4;
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
    // Zepto resolves the dark store from the browser's GPS position, so we
    // feed real coords per pincode instead of a localStorage override.
    geolocation: { latitude: rec.lat, longitude: rec.lon },
    permissions: ['geolocation'],
  });
  const page = await ctx.newPage();
  await ctx.route('**/*', (route) => {
    const t = route.request().resourceType();
    if (['image', 'font', 'media'].includes(t)) return route.abort();
    return route.continue();
  });
  let rows = [];
  let store = {};
  try {
    const resp = await page.goto('https://www.zeptonow.com/', { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(3000);
    // --- block guard: bail loudly on the CloudFront WAF 403 ---
    const body0 = await page.evaluate(() => (document.body && document.body.innerText) || '');
    if ((resp && resp.status() === 403) || /403 ERROR|Request blocked/i.test(body0)) {
      throw new Error('BLOCKED: CloudFront 403 (datacenter IP) — needs residential proxy');
    }
    await page.goto('https://www.zeptonow.com/search?query=jivo', { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(5000);
    // Zepto exposes the resolved store id in localStorage (key name unverified).
    store = await page.evaluate(() => {
      for (const k of ['storeId', 'store_id', 'store']) {
        const v = localStorage.getItem(k);
        if (v) return { id: v, name: '' };
      }
      return {};
    });
    // Portable geometry-based card extraction (same approach proven on Blinkit).
    const cards = await page.evaluate(() => {
      const out = [];
      const seen = new Set();
      document.querySelectorAll('a, div').forEach((el) => {
        const t = el.innerText || '';
        if (!/jivo/i.test(t) || !/₹/.test(t)) return;
        const r = el.getBoundingClientRect();
        if (r.width < 100 || r.width > 460) return;
        if (r.height < 150 || r.height > 640) return;
        const key = t.slice(0, 90);
        if (seen.has(key)) return;
        seen.add(key);
        out.push(t.replace(/\s+/g, ' ').trim());
      });
      return out;
    });
    for (const c of cards) {
      const inStock = !/out of stock|sold out|notify/i.test(c);
      const eta = (c.match(/(\d+)\s*MINS?/i) || [])[1];
      const disc = (c.match(/(\d+)%\s*OFF/i) || [])[1];
      const prices = [...c.matchAll(/₹\s*([\d,]+)/g)].map((m) => parseInt(m[1].replace(/,/g, ''), 10));
      const sale = prices.length ? prices[0] : null;
      const mrp = prices.length > 1 ? prices[1] : sale;
      let name = c.replace(/^\d+%\s*OFF\s*/i, '').replace(/^.*?\d+\s*MINS?\s*/i, '');
      name = name.replace(/Out of Stock|Sold Out/i, '').trim();
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
  process.stderr.write(`[ok] ${rec.city} ${rec.pincode} -> ${rows.length} jivo SKUs (${((Date.now() - t0) / 1000).toFixed(1)}s) store=${store.name || store.id || 'n/a'}\n`);
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
  fs.writeFileSync(__dirname + '/result.json', JSON.stringify({ summary, perPin, allRows }, null, 2));
  console.log(JSON.stringify(summary));
})();
