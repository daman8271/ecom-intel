// Swiggy Instamart scraper — modeled on platforms/blinkit/scrape.js.
//
// How it works (proven by recon spike, see SKILL.md):
//  1. A stealth browser context (navigator.webdriver=undefined,
//     --disable-blink-features=AutomationControlled) loads the Instamart home
//     with the pincode's geolocation granted. Swiggy resolves a dark-store and
//     fires /api/instamart/home/v2?storeId=<id> — we capture <id> + DOM ETA.
//  2. We POST /api/instamart/search/v2 from the page's own JS context (so it
//     carries the real session cookies/headers) with {query:'jivo',...} and the
//     storeId. This returns the full product JSON (data.cards[].GridWidget).
//     NOTE: the SPA's own GET search/v2 is soft-blocked (x-rate-limit:
//     SignalAutomatedBrowser -> empty body); the stealth POST is NOT blocked.
//  3. Parse variations -> rows in the canonical shape build_excel.py expects.
const { chromium } = require('playwright');
const fs = require('fs');

const PFILE = process.env.PINCODES_FILE || (__dirname + '/pincodes.json');
const PINCODES = JSON.parse(fs.readFileSync(PFILE, 'utf8'));
const CONCURRENCY = parseInt(process.env.CONCURRENCY || '3', 10);
const ONLY = process.env.ONLY_PINCODE || '';        // single-pincode test path
const LIMIT = parseInt(process.env.LIMIT || '0', 10); // cap pincodes (test path)
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

// Pull every Jivo variation out of a /search/v2 JSON response.
function parseSearch(json) {
  const out = [];
  const cards = (json && json.data && json.data.cards) || [];
  for (const c of cards) {
    const inner = c && c.card && c.card.card;
    if (!inner || !String(inner['@type'] || '').endsWith('GridWidget')) continue;
    const items = ((inner.gridElements || {}).infoWithStyle || {}).items || [];
    for (const it of items) {
      const brand = it.brand || '';
      const topName = it.displayName || '';
      if (!/jivo/i.test(brand + ' ' + topName)) continue;
      for (const v of (it.variations || [])) {
        const price = v.price || {};
        const mrp = price.mrp && price.mrp.units != null ? parseInt(price.mrp.units, 10) : null;
        const sale = price.offerPrice && price.offerPrice.units != null ? parseInt(price.offerPrice.units, 10) : mrp;
        const discTxt = (price.offerApplied && price.offerApplied.listingDescription) || '';
        const discFromTxt = (discTxt.match(/(\d+(?:\.\d+)?)\s*%/) || [])[1];
        const inStock = (v.inventory && typeof v.inventory.inStock === 'boolean') ? v.inventory.inStock : (it.inStock !== false);
        out.push({
          name: v.displayName || topName,
          pack: v.quantityDescription || '',
          sale, mrp,
          disc: discFromTxt ? parseFloat(discFromTxt) : null,
          inStock: inStock ? 1 : 0,
          pod: v.podId || '',
          skuId: v.skuId || '',
        });
      }
    }
  }
  return out;
}

async function scrapeOne(browser, rec) {
  const t0 = Date.now();
  let ctx = null;
  let storeId = null;
  let rows = [];
  let eta = null;
  try {
    ctx = await browser.newContext({
      userAgent: UA,
      locale: 'en-IN',
      timezoneId: 'Asia/Kolkata',
      viewport: { width: 1280, height: 900 },
      geolocation: { latitude: rec.lat, longitude: rec.lon },
      permissions: ['geolocation'],
      extraHTTPHeaders: { 'accept-language': 'en-IN,en;q=0.9' },
    });
    // stealth: hide automation markers that trip Swiggy's WAF on search/v2
    await ctx.addInitScript(() => {
      Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
      window.chrome = { runtime: {} };
      Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3, 4, 5] });
      Object.defineProperty(navigator, 'languages', { get: () => ['en-IN', 'en'] });
    });
    const page = await ctx.newPage();
    await ctx.route('**/*', (route) => {
      const t = route.request().resourceType();
      if (['image', 'font', 'media'].includes(t)) return route.abort();
      return route.continue();
    });
    page.on('request', (req) => {
      const u = req.url();
      if (u.includes('/instamart/home/v2')) {
        try { const sid = new URL(u).searchParams.get('storeId'); if (sid) storeId = sid; } catch (_) {}
      }
    });

    await page.goto(`https://www.swiggy.com/instamart?lat=${rec.lat}&lng=${rec.lon}`, { waitUntil: 'domcontentloaded', timeout: 40000 });
    await page.waitForTimeout(5000);
    // ETA (e.g. "18 Mins") from the home DOM — store-level, best-effort
    try {
      const head = await page.evaluate(() => document.body.innerText.slice(0, 200));
      const m = head.match(/(\d+)\s*Min/i);
      if (m) eta = parseInt(m[1], 10);
    } catch (_) {}

    if (storeId) {
      // POST from the page's JS context so it inherits real session cookies/headers.
      const json = await page.evaluate(async (sid) => {
        try {
          const r = await fetch(`/api/instamart/search/v2?offset=0&storeId=${sid}&primaryStoreId=${sid}`, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify({ query: 'jivo', pageType: 'INSTAMART_SEARCH', queryType: 'GLOBAL' }),
          });
          if (r.status !== 200) return { __err: 'status ' + r.status };
          return await r.json();
        } catch (e) { return { __err: e.message }; }
      }, storeId);

      if (json && json.__err) {
        process.stderr.write(`[warn] ${rec.city} ${rec.pincode}: search ${json.__err}\n`);
      } else {
        const items = parseSearch(json);
        for (const p of items) {
          if (!p.sale) continue;
          const vol = parseVolMl(p.pack);
          rows.push({
            city: rec.city, pincode: rec.pincode, locality: rec.locality,
            store_id: p.pod || storeId, store_name: `Instamart ${rec.city}`,
            sku_raw: p.name, canonical: canonical(p.name, p.pack), pack: p.pack || '',
            vol_ml: vol, sale: p.sale, mrp: p.mrp,
            discount_pct: (p.mrp && p.sale && p.mrp >= p.sale) ? Math.round(((p.mrp - p.sale) / p.mrp) * 1000) / 10 : p.disc,
            per_litre: vol ? Math.round((p.sale / (vol / 1000)) * 100) / 100 : null,
            eta_min: eta,
            in_stock: p.inStock,
          });
        }
      }
    } else {
      process.stderr.write(`[warn] ${rec.city} ${rec.pincode}: no storeId (not serviceable?)\n`);
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
    if (ctx) { try { await ctx.close(); } catch (_) {} }
  }
  process.stderr.write(`[ok] ${rec.city} ${rec.pincode} -> ${rows.length} jivo SKUs (${((Date.now() - t0) / 1000).toFixed(1)}s) store=${storeId || 'n/a'} eta=${eta || '-'}\n`);
  return { ...rec, store_id: (rows[0] && rows[0].store_id) || storeId || '', store_name: `Instamart ${rec.city}`, rows };
}

async function pool(items, n, fn) {
  const results = [];
  let i = 0;
  async function worker() {
    while (i < items.length) {
      const idx = i++;
      results[idx] = await fn(items[idx], idx);
      await new Promise((r) => setTimeout(r, 1000 + Math.random() * 1800));
    }
  }
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, worker));
  return results;
}

(async () => {
  let targets = PINCODES;
  if (ONLY) targets = PINCODES.filter((p) => String(p.pincode) === String(ONLY));
  if (LIMIT > 0) targets = targets.slice(0, LIMIT);

  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-blink-features=AutomationControlled'],
  });
  const t0 = Date.now();
  const perPin = await pool(targets, CONCURRENCY, (rec) => scrapeOne(browser, rec));
  await browser.close();
  const allRows = perPin.flatMap((p) => p.rows);
  const summary = {
    pincodes_total: targets.length,
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
