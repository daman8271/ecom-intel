const { chromium } = require('playwright');
const fs = require('fs');

// ---------------------------------------------------------------------------
// FLIPKART MARKETPLACE scraper.  STATUS: WORKING from this datacenter VPS IP
// (HTTP 200, no captcha, no login needed).  Unlike the quick-commerce platforms,
// marketplace pricing is NATIONAL (a listing's price is the same regardless of
// pincode; only delivery date/serviceability vary, which search doesn't expose).
// So we scrape the full Jivo catalog ONCE by paginating the search results and
// tag every row city="All India" — iterating 40 pincodes would return identical
// prices.  Output shape stays Blinkit-compatible so build_excel.py works.
// pincodes.json is intentionally unused here.
// ---------------------------------------------------------------------------

const SEARCH = 'https://www.flipkart.com/search?q=jivo';
const MAX_PAGES = 6;
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

// handles "1 L", "500 ml", "5 Ltr", and multipacks "3 x 1 L" / "2 x 1000 ml"
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

// Each search-result card is a ~268x439 element. Lines: [name, pack, rating,
// "₹SALE₹MRP NN% off", badge].  Returns array of line-arrays.
async function scrapePage(page, url) {
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 35000 });
  await page.waitForTimeout(3500);
  try { await page.keyboard.press('Escape'); } catch (e) {} // dismiss login popup
  return page.evaluate(() => {
    const out = [];
    const seen = new Set();
    document.querySelectorAll('div, a').forEach((el) => {
      const t = el.innerText || '';
      if (!/jivo/i.test(t) || !/₹/.test(t)) return;
      const r = el.getBoundingClientRect();
      if (r.width < 200 || r.width > 340) return;
      if (r.height < 380 || r.height > 520) return;
      const key = t.slice(0, 80);
      if (seen.has(key)) return;
      seen.add(key);
      // Read each price from its OWN node ("₹1,463") to avoid the glued innerText.
      // A "save extra ₹20" badge is one node "Buy 2 items, save extra ₹20" -> no match.
      const prices = [...el.querySelectorAll('*')]
        .map((n) => (n.textContent || '').replace(/\s/g, ''))
        .filter((s) => /^₹[\d,]+$/.test(s))
        .map((s) => parseInt(s.replace(/[₹,]/g, ''), 10))
        .filter((n) => n > 0);
      const discTxt = [...el.querySelectorAll('*')].map((n) => (n.textContent || '').trim()).find((x) => /^\d{1,2}%\s*off$/i.test(x)) || '';
      out.push({
        lines: t.split('\n').map((s) => s.trim()).filter(Boolean),
        prices,
        disc: (discTxt.match(/(\d{1,2})/) || [])[1] || '',
      });
    });
    return out;
  });
}

function parseCard(card) {
  const lines = card.lines;
  const joined = lines.join(' ');
  const inStock = !/out of stock|currently unavailable|sold out|coming soon|notify me/i.test(joined);
  const nameLine = lines.find((l) => /jivo/i.test(l)) || lines[0] || '';
  const name = nameLine.replace(/\(pack of \d+\)/i, '').replace(/\s+/g, ' ').trim();
  // pack: a line that is mostly a quantity (incl. multipack), no letters beyond units
  const packLine = lines.find((l) => /^(\d[\d.]*\s*x\s*)?\d[\d.]*\s*(ml|l|ltr|litre|kg|g)$/i.test(l.trim()));
  const pack = packLine ? packLine.trim() : '';
  const sale = card.prices.length ? Math.min(...card.prices) : null;
  const mrp = card.prices.length ? Math.max(...card.prices) : sale;
  return { name, pack, sale, mrp, disc: card.disc, inStock };
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
  let rows = [];
  for (let p = 1; p <= MAX_PAGES; p++) {
    let cards = [];
    try { cards = await scrapePage(page, `${SEARCH}&page=${p}`); }
    catch (e) { process.stderr.write(`[err] page ${p}: ${e.message}\n`); }
    let added = 0;
    for (const card of cards) {
      const c = parseCard(card);
      if (!/jivo/i.test(c.name) || !c.sale) continue;
      rows.push({
        city: 'All India', pincode: '-', locality: 'Flipkart marketplace (national)',
        store_id: '', store_name: 'Flipkart',
        sku_raw: c.name, canonical: canonical(c.name, c.pack), pack: c.pack || '',
        vol_ml: parseVolMl(c.pack), sale: c.sale, mrp: c.mrp,
        discount_pct: (c.mrp && c.sale && c.mrp >= c.sale) ? Math.round(((c.mrp - c.sale) / c.mrp) * 1000) / 10 : (c.disc ? parseFloat(c.disc) : null),
        per_litre: parseVolMl(c.pack) ? Math.round((c.sale / (parseVolMl(c.pack) / 1000)) * 100) / 100 : null,
        eta_min: null,
        in_stock: c.inStock ? 1 : 0,
      });
      added++;
    }
    process.stderr.write(`[ok] page ${p} -> ${added} jivo cards (running total ${rows.length})\n`);
    if (added === 0 && p > 1) break; // no more results
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
  const perPin = [{ city: 'All India', pincode: '-', locality: 'Flipkart marketplace (national)', tier: 0, store_id: '', store_name: 'Flipkart', rows }];
  process.stderr.write('[SUMMARY] ' + JSON.stringify(summary) + '\n');
  fs.writeFileSync(__dirname + '/result.json', JSON.stringify({ summary, perPin, allRows: rows }, null, 2));
  console.log(JSON.stringify(summary));
})();
