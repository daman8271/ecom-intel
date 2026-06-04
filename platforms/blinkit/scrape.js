const { chromium } = require('playwright');
const fs = require('fs');

const PFILE = process.env.PINCODES_FILE || (__dirname + '/pincodes.json');
const PINCODES = JSON.parse(fs.readFileSync(PFILE, 'utf8'));
// NOTE: keep this LOW (2). Blinkit rate-limits dark-store geocode/resolution per
// IP; at concurrency >=3 from the datacenter IP many pincodes never re-resolve
// off the Gurgaon default and get (correctly) dropped as unresolved — tanking
// genuine coverage. Concurrency 2 keeps resolution ~complete. See blinkit.fix.md.
const CONCURRENCY = parseInt(process.env.CONCURRENCY || '2', 10);
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

// Blinkit's DEFAULT/fallback dark store, served whenever our injected location
// has NOT re-resolved yet. When this fallback is active, Blinkit reverts
// localStorage.location to its own default (coords.isDefault=true, Gurugram
// 28.41/77.07, cityName "HR-NCR"). Capturing cards in that state records the
// Gurgaon catalog under the WRONG city (the 2026-06-04 contamination: 89/146
// pincodes mislabeled across 10 cities). See blinkit.verdict.md / blinkit.fix.md.
const DEFAULT_STORE_ID = 31719;       // "Super Store - Gurgaon Nirvana Country ES44"
const DEFAULT_COORDS = { lat: 28.4133, lon: 77.0728 }; // Gurugram, the default fallback
const COORD_EPS = 0.02;               // ~2 km — injected vs active-location coord tolerance
const NCR_BOX = 0.5;                  // ~55 km — pincodes this close to Gurugram may legitimately use the default store

// A request is genuinely near the Gurgaon default store, so resolving to it
// (id 31719 / "Nirvana Country") is a LEGITIMATE nearest-store fallback, not the
// contamination bug. Delhi/Gurgaon/Faridabad/Ghaziabad/Noida fall in this box.
function nearDefaultStore(rec) {
  return Math.abs(rec.lat - DEFAULT_COORDS.lat) < NCR_BOX && Math.abs(rec.lon - DEFAULT_COORDS.lon) < NCR_BOX;
}

// The active store is trustworthy ONLY when BOTH hold:
//  (1) Blinkit kept OUR injected location (coords.isDefault===false AND coords
//      still match the pincode we asked for) — on a failed/raced re-resolution
//      Blinkit reverts location to the Gurugram default, which this catches; and
//  (2) the active merchant is NOT the Gurgaon default store, UNLESS the request
//      is genuinely near Gurugram. This second clause closes a narrower race
//      where `location` has updated but `merchant` (and the rendered cards) are
//      still the stale default — a far-city request stuck on store 31719 is
//      rejected regardless of the location key's timing.
// A genuine Gurgaon/NCR pincode passes both (its coords match AND it's in-box),
// so legitimate nearest-store fallbacks are preserved.
function storeResolved(loc, store, rec) {
  const c = loc && loc.coords;
  if (!c) return false;
  if (c.isDefault !== false) return false;
  if (typeof c.lat !== 'number' || typeof c.lon !== 'number') return false;
  if (Math.abs(c.lat - rec.lat) > COORD_EPS) return false;
  if (Math.abs(c.lon - rec.lon) > COORD_EPS) return false;
  if (store && store.id === DEFAULT_STORE_ID && !nearDefaultStore(rec)) return false;
  return true;
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
  let resolved = false;
  const injectLocation = (r) => page.evaluate((rr) => {
    localStorage.setItem('location', JSON.stringify({
      coords: { isDefault: false, lat: rr.lat, lon: rr.lon, locality: rr.locality, id: 1, isTopCity: true, cityName: rr.city, landmark: rr.landmark, addressId: null }
    }));
  }, r);
  const readState = async () => {
    const loc = JSON.parse((await page.evaluate(() => localStorage.getItem('location'))) || '{}');
    const m = JSON.parse((await page.evaluate(() => localStorage.getItem('merchant'))) || '{}');
    return { loc, m };
  };
  try {
    await page.goto('https://blinkit.com/', { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(2000);
    // Inject the pincode's location, then re-load HOME (this is what makes
    // Blinkit re-resolve the dark store from the new coords) and POLL the
    // merchant until it leaves the Gurgaon default — search-page navigation
    // alone races and often renders the stale default store. Retry the whole
    // inject→home→poll up to 4x; this recovers genuinely-serviceable pincodes
    // that lost the race instead of recording the default catalog under them.
    let activeLoc = {};
    for (let attempt = 0; attempt < 4 && !resolved; attempt++) {
      // de-correlate retry bursts across concurrent workers so they don't all
      // re-hit Blinkit's geocode endpoint in lockstep (which slows resolution)
      if (attempt > 0) await page.waitForTimeout(1000 + attempt * 1000 + Math.random() * 1000);
      await injectLocation(rec);
      await page.goto('https://blinkit.com/', { waitUntil: 'domcontentloaded', timeout: 30000 });
      for (let poll = 0; poll < 6 && !resolved; poll++) {
        await page.waitForTimeout(1000);
        ({ loc: activeLoc, m: store } = await readState());
        resolved = storeResolved(activeLoc, store, rec);
      }
    }
    if (!resolved) {
      // Location never re-resolved — Blinkit is serving its default fallback
      // store. Do NOT record those cards (they'd be the Gurgaon catalog
      // mislabeled as rec.city). Treat the pincode as unresolved (no rows). A
      // genuinely serviceable pincode with no Jivo stock still resolves here
      // (rows just end up empty); only the default fallback is rejected.
      process.stderr.write(`[unresolved] ${rec.city} ${rec.pincode} -> store did not re-resolve (active store=${store.name || 'n/a'} id=${store.id || ''}); recording 0 rows\n`);
      return { ...rec, store_id: '', store_name: '', resolved: false, rows: [] };
    }
    // Resolved on home — now run the Jivo search, then RE-VERIFY the active
    // store didn't revert during the search navigation before trusting cards.
    await injectLocation(rec);
    await page.goto('https://blinkit.com/s/?q=jivo', { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(4500);
    ({ loc: activeLoc, m: store } = await readState());
    if (!storeResolved(activeLoc, store, rec)) {
      process.stderr.write(`[unresolved] ${rec.city} ${rec.pincode} -> store reverted on search (active store=${store.name || 'n/a'} id=${store.id || ''}); recording 0 rows\n`);
      return { ...rec, store_id: '', store_name: '', resolved: false, rows: [] };
    }
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
  return { ...rec, store_id: store.id || '', store_name: store.name || '', resolved, rows };
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
    pincodes_resolved: perPin.filter((p) => p.resolved).length,
    pincodes_unresolved: perPin.filter((p) => !p.resolved).length,
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
