const { chromium } = require('playwright');
const fs = require('fs');

// ---------------------------------------------------------------------------
// FLIPKART MINUTES scraper.  STATUS: WORKING from this datacenter VPS IP
// (HTTP 200, no captcha, no login needed).  Location is resolved via the
// "Use my current location" button using the per-pincode GPS coords (Flipkart
// needs the real serviceability resolution — setting localStorage `mypin`
// alone bounces to the preview page).  Products live in the HYPERLOCAL
// marketplace: /search?q=jivo&marketplace=HYPERLOCAL .
//
// FINDING (2026-05-21): Jivo IS carried on Flipkart Minutes. First full run:
// 30/40 pincodes serviceable, 27 carry Jivo, ~111 rows, ~38 SKUs in ~3 min.
// Jivo absent at Bandra/Mumbai but present in Gurgaon, Delhi, Kanpur, etc.
// ~10 pincodes don't resolve the GPS location in time (serviceable=false) =>
// real coverage is a bit higher than what one run captures.  See SKILL.md.
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

// Resolve the Minutes delivery location for this context via GPS. Returns the
// resolved address string, or '' if it stayed on the preview/unserviceable page.
async function resolveLocation(page) {
  await page.goto('https://www.flipkart.com/flipkart-minutes-store?marketplace=HYPERLOCAL', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(3000);
  try {
    await page.getByText(/use my current location/i).first().click({ timeout: 8000 });
  } catch (e) { /* button absent => maybe already resolved */ }
  // poll up to ~14s for the preview picker to disappear
  for (let i = 0; i < 7; i++) {
    await page.waitForTimeout(2000);
    const onPreview = await page.evaluate(() =>
      /Select delivery address/i.test(document.body.innerText) && /Use my current location/i.test(document.body.innerText));
    if (!onPreview) break;
  }
  const addr = await page.evaluate(() => {
    const t = (document.body.innerText || '').replace(/\s+/g, ' ').trim();
    if (/Select delivery address/i.test(t) && /Use my current location/i.test(t)) return '';
    // first line is usually the resolved address + eta
    return t.slice(0, 80);
  });
  return addr;
}

async function scrapeOne(browser, rec) {
  const t0 = Date.now();
  const ctx = await browser.newContext({
    userAgent: UA,
    locale: 'en-IN',
    timezoneId: 'Asia/Kolkata',
    viewport: { width: 1280, height: 900 },
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
  let serviceable = false;
  try {
    const addr = await resolveLocation(page);
    serviceable = !!addr;
    const pin = await page.evaluate(() => localStorage.getItem('mypin') || '');
    store = { id: pin, name: addr };
    if (serviceable) {
      await page.goto('https://www.flipkart.com/search?q=jivo&marketplace=HYPERLOCAL', { waitUntil: 'domcontentloaded', timeout: 30000 });
      await page.waitForTimeout(5000);
      await page.evaluate(() => window.scrollBy(0, 1400));
      await page.waitForTimeout(2000);
      // Each Minutes product card is a ~300x424 element. Tight geometry bounds
      // avoid catching a multi-product row wrapper (which would mix prices/ETA
      // across SKUs). Return the card's text split into lines for clean parsing.
      const cards = await page.evaluate(() => {
        const out = [];
        const seen = new Set();
        document.querySelectorAll('a, div').forEach((el) => {
          const t = el.innerText || '';
          if (!/jivo/i.test(t) || !/₹/.test(t)) return;
          const r = el.getBoundingClientRect();
          if (r.width < 150 || r.width > 380) return;
          if (r.height < 300 || r.height > 560) return;
          const key = t.slice(0, 90);
          if (seen.has(key)) return;
          seen.add(key);
          out.push(t.split('\n').map((s) => s.trim()).filter(Boolean));
        });
        return out;
      });
      // Card line layout: [AD] [NN%] [Off] [N L] NAME ₹MRP ₹SALE Add
      //   or for OOS:      Currently unavailable [N L] NAME ₹PRICE
      for (const lines of cards) {
        const inStock = !lines.some((l) => /currently unavailable|out of stock|sold out|notify me/i.test(l));
        const disc = (lines.join(' ').match(/(\d+)%\s*off/i) || [])[1];
        const packLine = lines.find((l) => /^\d[\d.]*\s*(ml|l|ltr|litre|kg|g)$/i.test(l));
        const pack = packLine || '';
        const nameLine = lines.find((l) => /jivo/i.test(l)) || '';
        const name = nameLine.replace(/\(pack of \d+\)/i, '').replace(/\s+/g, ' ').trim();
        const prices = lines.filter((l) => /^₹/.test(l)).map((l) => parseInt(l.replace(/[₹,\s]/g, ''), 10)).filter((n) => n > 0);
        const sale = prices.length ? Math.min(...prices) : null;
        const mrp = prices.length ? Math.max(...prices) : sale;
        if (!/jivo/i.test(name) || !sale) continue;
        rows.push({
          city: rec.city, pincode: rec.pincode, locality: rec.locality,
          store_id: store.id || '', store_name: store.name || '',
          sku_raw: name, canonical: canonical(name, pack), pack: pack || '',
          vol_ml: parseVolMl(pack), sale, mrp,
          discount_pct: (mrp && sale && mrp >= sale) ? Math.round(((mrp - sale) / mrp) * 1000) / 10 : (disc ? parseFloat(disc) : null),
          per_litre: parseVolMl(pack) ? Math.round((sale / (parseVolMl(pack) / 1000)) * 100) / 100 : null,
          eta_min: null,
          in_stock: inStock ? 1 : 0,
        });
      }
      const dd = new Map();
      for (const r of rows) {
        const k = `${r.store_id}|${r.canonical}`;
        if (!dd.has(k)) dd.set(k, r);
      }
      rows = [...dd.values()];
    }
  } catch (e) {
    process.stderr.write(`[err] ${rec.city} ${rec.pincode}: ${e.message}\n`);
  } finally {
    await ctx.close();
  }
  process.stderr.write(`[ok] ${rec.city} ${rec.pincode} -> ${rows.length} jivo SKUs (${((Date.now() - t0) / 1000).toFixed(1)}s) serviceable=${serviceable} store=${store.name || 'n/a'}\n`);
  return { ...rec, store_id: store.id || '', store_name: store.name || '', serviceable, rows };
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
    pincodes_serviceable: perPin.filter((p) => p.serviceable).length,
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
