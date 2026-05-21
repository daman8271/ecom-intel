const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

// ---------------------------------------------------------------------------
// FLIPKART MARKETPLACE scraper.  STATUS: WORKING from this datacenter VPS IP.
//
// MODEL: we scrape ONLY Jivo's official Flipkart catalogue, defined in
// skus.master.tsv (one row per real SKU, with its Flipkart FSN/PID in column
// "FORMAT SKU Code").  We do NOT search "jivo" and grab whatever matches
// (that pulled in JIVOTTAM, random combos, and other sellers' noise).  Instead
// we hit each SKU's product page directly by pid and read the embedded
// JSON-LD (schema.org/Product): offers.price = sale, description "Rs.X" = MRP,
// offers.availability = stock, sku = the FSN (so we verify we landed right).
// JSON-LD is stable across Flipkart's rotating obfuscated CSS classes.
//
// Marketplace pricing is NATIONAL (same price regardless of pincode; only
// delivery date varies), so every row is tagged city="All India".  Output
// shape stays Blinkit-compatible so build_excel.py works; extra identity
// fields (fsn, item, sap_code, category, brand, ...) ride along in result.json.
// ---------------------------------------------------------------------------

const MASTER_TSV = path.join(__dirname, 'skus.master.tsv');
const CONCURRENCY = parseInt(process.env.FK_CONCURRENCY || '4', 10);
const LIMIT = parseInt(process.env.FK_LIMIT || '0', 10); // 0 = all; >0 = first N (for testing)
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

// ---- master catalogue -----------------------------------------------------
function loadMaster() {
  const raw = fs.readFileSync(MASTER_TSV, 'utf8').replace(/\r/g, '');
  const lines = raw.split('\n').filter((l) => l.trim());
  const header = lines[0].split('\t');
  const col = (name) => header.indexOf(name);
  const ci = {
    fsn: col('FORMAT SKU Code'), name: col('Product Name'), item: col('ITEM'),
    sap: col('SKU SAP Code'), sapName: col('SKU SAP NAME'), cat: col('Category'),
    sub: col('Sub Category'), perUnit: col('Per UNIT'), itemHead: col('Item Head'),
    brand: col('Brand'), uom: col('UOM'), perUnitVal: col('Per UNIT Value'),
    catHead: col('Category Head'), isOil: col('IS LITRE OIL'),
  };
  const seen = new Set();
  const out = [];
  for (const line of lines.slice(1)) {
    const f = line.split('\t');
    const fsn = (f[ci.fsn] || '').trim();
    if (!/^[A-Z0-9]{16}$/.test(fsn) || seen.has(fsn)) continue; // skip blanks + dupes
    seen.add(fsn);
    const perUnitVal = parseFloat(f[ci.perUnitVal]);
    out.push({
      fsn,
      name: (f[ci.name] || '').trim(),
      item: (f[ci.item] || '').trim(),
      sap_code: (f[ci.sap] || '').trim(),
      sap_name: (f[ci.sapName] || '').trim(),
      category: (f[ci.cat] || '').trim(),
      sub_category: (f[ci.sub] || '').trim(),
      pack: (f[ci.perUnit] || '').trim(),
      item_head: (f[ci.itemHead] || '').trim(),
      brand: (f[ci.brand] || '').trim() || 'JIVO',
      uom: (f[ci.uom] || '').trim(),
      litres: Number.isFinite(perUnitVal) ? perUnitVal : null,
      is_oil: (f[ci.isOil] || '').trim().toUpperCase() === 'Y',
    });
  }
  return out;
}

// pack -> ml (fallback only; we prefer the master's authoritative litres)
function packToMl(m) {
  if (m.litres != null && /LTR|MLS|LITRE|L|ML/i.test(m.uom + m.pack)) return Math.round(m.litres * 1000);
  const g = (m.pack || '').match(/([\d.]+)\s*(g|gm|gms|kg)/i);
  if (g) { let n = parseFloat(g[1]); if (/kg/i.test(g[2])) n *= 1000; return n; }
  return null;
}

// ---- per-product scrape ----------------------------------------------------
async function scrapeOne(page, m) {
  const url = `https://www.flipkart.com/x/p/itme?pid=${m.fsn}`;
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 35000 });
  // JSON-LD <script> is never "visible"; wait for it ATTACHED. Then wait for a
  // rendered ₹ price (covers variant pages whose price is DOM-only, no offers).
  try { await page.waitForSelector('script[type="application/ld+json"]', { state: 'attached', timeout: 4500 }); } catch (e) {}
  // returns instantly once a ₹ price renders (priced pages); only price-less
  // pages wait the full timeout, so keep it short.
  try { await page.waitForFunction(() => /₹/.test(document.body.innerText || ''), { timeout: 2500 }); } catch (e) {}
  await page.waitForTimeout(250);

  const data = await page.evaluate(() => {
    const node = document.querySelector('script[type="application/ld+json"]');
    let ld = null;
    if (node) {
      try {
        const parsed = JSON.parse(node.textContent);
        const arr = Array.isArray(parsed) ? parsed : [parsed];
        ld = arr.find((o) => o && (o.offers || o.sku || o['@type'] === 'Product')) || arr[0] || null;
      } catch (e) { /* malformed */ }
    }
    // DOM price block fallback: leaf nodes whose whole text is a ₹ amount, in
    // document order (the main buy-box price comes before cross-sell carousels).
    const domPrices = [];
    document.querySelectorAll('div, span').forEach((el) => {
      if (el.children.length) return;
      const t = (el.textContent || '').replace(/\s/g, '');
      if (/^₹[\d,]+$/.test(t)) { const n = parseInt(t.replace(/[₹,]/g, ''), 10); if (n > 0) domPrices.push(n); }
    });
    const body = (document.body && document.body.innerText) || '';
    const discTxt = (body.match(/(\d{1,2})%\s*off/i) || [])[1] || '';
    const looksGone = /This product is no longer available|page you were looking for|isn't available|currently out of stock|sold out|coming soon|notify me|out of stock/i.test(body);
    const hasBuy = /add to cart|buy now|go to cart/i.test(body);
    // Flipkart's transient throttle/error interstitial -> retry, don't record.
    const errPage = /something went wrong|please try again later|\bE002\b/i.test(body) || body.length < 120;
    return { ld, domPrices: domPrices.slice(0, 8), discTxt, looksGone, hasBuy, errPage, title: document.title, hasBody: body.length > 200 };
  });
  if (data.errPage) throw new Error('fk_error_page');

  const ld = data.ld;
  const row = {
    fsn: m.fsn, sku_landed: ld && ld.sku ? String(ld.sku) : '',
    fk_name: ld && ld.name ? ld.name : data.title.split(' Price in India')[0] || '',
    sale: null, mrp: null, availability: '', rating: null, rating_count: null,
    fk_category: ld && ld.category ? ld.category : '',
    price_src: '', status: 'ok',
  };
  // ---- sale price: JSON-LD offers first, else DOM buy-box price ----
  if (ld && ld.offers) {
    const o = Array.isArray(ld.offers) ? ld.offers[0] : ld.offers;
    if (o && o.price != null) { row.sale = Math.round(parseFloat(o.price)); row.price_src = 'ldjson'; }
    row.availability = (o && o.availability) || '';
  }
  if (row.sale == null && data.domPrices.length) { row.sale = data.domPrices[0]; row.price_src = 'dom'; }
  // ---- MRP: JSON-LD description ("for Rs.1650.0"), else a higher DOM price ----
  if (ld && ld.description) {
    const mm = ld.description.match(/for\s*Rs\.?\s*([\d,]+(?:\.\d+)?)/i);
    if (mm) row.mrp = Math.round(parseFloat(mm[1].replace(/,/g, '')));
  }
  if ((row.mrp == null || (row.sale != null && row.mrp < row.sale)) && row.sale != null) {
    const higher = data.domPrices.slice(0, 3).filter((p) => p > row.sale);
    if (higher.length) row.mrp = Math.max(...higher);
  }
  if (ld && ld.aggregateRating) {
    row.rating = ld.aggregateRating.ratingValue ?? null;
    row.rating_count = ld.aggregateRating.ratingCount ?? null;
  }
  // ---- stock: JSON-LD availability first, then page heuristics ----
  const avail = (row.availability || '').toLowerCase();
  let inStock;
  if (avail) inStock = avail.includes('instock');
  else inStock = data.hasBuy && !data.looksGone && row.sale != null;
  if (avail.includes('outofstock') || avail.includes('soldout') || avail.includes('discontinued')) inStock = false;

  if (!ld && !data.hasBody) row.status = 'no_page';
  else if (!ld && !data.domPrices.length) row.status = 'no_jsonld';
  else if (row.sale == null) row.status = 'no_price';
  row.in_stock = inStock ? 1 : 0;
  row.disc_txt = data.discTxt;
  return row;
}

async function withRetry(page, m, tries = 2) {
  let last;
  for (let i = 0; i < tries; i++) {
    try { return await scrapeOne(page, m); }
    catch (e) { last = e; await page.waitForTimeout(700 + Math.random() * 600); }
  }
  return { fsn: m.fsn, status: 'error', err: last ? last.message : 'unknown', sale: null, mrp: null, in_stock: 0, sku_landed: '', fk_name: '', availability: '', fk_category: '', price_src: '' };
}

(async () => {
  let master = loadMaster();
  if (LIMIT > 0) master = master.slice(0, LIMIT);
  process.stderr.write(`[start] ${master.length} master SKUs, concurrency=${CONCURRENCY}\n`);

  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 } });
  await ctx.route('**/*', (route) => {
    const t = route.request().resourceType();
    if (['image', 'font', 'media', 'stylesheet'].includes(t)) return route.abort();
    return route.continue();
  });

  const t0 = Date.now();
  const results = new Array(master.length);
  let next = 0, done = 0;

  async function worker(wid) {
    const page = await ctx.newPage();
    while (true) {
      const idx = next++;
      if (idx >= master.length) break;
      const m = master[idx];
      const r = await withRetry(page, m);
      results[idx] = { m, r };
      done++;
      if (done % 20 === 0 || done === master.length) process.stderr.write(`[progress] ${done}/${master.length}\n`);
    }
    await page.close();
  }
  await Promise.all(Array.from({ length: CONCURRENCY }, (_, i) => worker(i)));
  await browser.close();

  // ---- assemble Blinkit-compatible rows ----
  const rows = results.map(({ m, r }) => {
    const vol = packToMl(m);
    const sale = r.sale;
    // keep (sale, mrp, disc) internally consistent: prefer an explicit MRP>sale;
    // else reconstruct MRP from the on-page "% off"; else MRP=sale, no discount.
    let mrp = (r.mrp != null && sale != null && r.mrp > sale) ? r.mrp : null;
    let disc = null;
    if (mrp != null && sale != null) {
      disc = Math.round(((mrp - sale) / mrp) * 1000) / 10;
    } else if (r.disc_txt && sale != null) {
      const d = parseFloat(r.disc_txt);
      if (d > 0 && d < 95) { disc = d; mrp = Math.round(sale / (1 - d / 100)); }
    }
    if (mrp == null) mrp = sale;
    const perL = m.is_oil && m.litres ? Math.round((sale / m.litres) * 100) / 100 : null;
    const mismatch = r.sku_landed && r.sku_landed !== m.fsn ? 1 : 0;
    return {
      city: 'All India', pincode: '-', locality: 'Flipkart marketplace (national)',
      store_id: '', store_name: 'Flipkart',
      sku_raw: m.item || m.name, canonical: m.fsn.toLowerCase(),
      pack: m.pack || '', vol_ml: vol,
      sale, mrp,
      discount_pct: disc,
      per_litre: perL, eta_min: null, in_stock: r.in_stock,
      // ---- rich identity (ignored by build_excel, kept for vault/history/review) ----
      fsn: m.fsn, item: m.item, product_name: m.name, sap_code: m.sap_code,
      brand: m.brand, category: m.category, sub_category: m.sub_category,
      is_oil: m.is_oil ? 1 : 0, fk_name: r.fk_name, fk_category: r.fk_category,
      availability: r.availability, rating: r.rating, rating_count: r.rating_count,
      price_src: r.price_src, scrape_status: r.status, sku_mismatch: mismatch,
    };
  });

  const priced = rows.filter((r) => r.sale != null);
  const summary = {
    pincodes_total: 1,
    pincodes_with_jivo: priced.length ? 1 : 0,
    total_rows: rows.length,
    unique_skus: new Set(rows.map((r) => r.canonical)).size,
    in_stock: rows.filter((r) => r.in_stock).length,
    out_of_stock: rows.filter((r) => !r.in_stock).length,
    priced: priced.length,
    no_price: rows.filter((r) => r.scrape_status === 'no_price').length,
    errors: rows.filter((r) => ['error', 'no_page', 'no_jsonld'].includes(r.scrape_status)).length,
    sku_mismatches: rows.filter((r) => r.sku_mismatch).length,
    wall_s: Math.round((Date.now() - t0) / 1000),
    captured_at: new Date().toISOString(),
  };
  const perPin = [{ city: 'All India', pincode: '-', locality: 'Flipkart marketplace (national)', tier: 0, store_id: '', store_name: 'Flipkart', rows }];
  process.stderr.write('[SUMMARY] ' + JSON.stringify(summary) + '\n');
  fs.writeFileSync(path.join(__dirname, 'result.json'), JSON.stringify({ summary, perPin, allRows: rows }, null, 2));
  console.log(JSON.stringify(summary));
})();
