const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

// ---------------------------------------------------------------------------
// AMAZON marketplace scraper — TARGETED product-detail scrape.
//
// Previous version did a broad `?k=jivo` SEARCH which dragged in junk
// (eyeliner / weighing scales that merely mention "jivo"). This version walks
// a CURATED list of ASINs (products.json, 314 entries) and visits
//   https://www.amazon.in/dp/<asin>
// for each, capturing price + MRP + discount, the SELLER ("Sold by"), the
// "Ships from", and the STOCK status (in/out, raw text, units-left).
//
// STATUS: amazon.in serves datacenter IPs an HTTP-202 interstitial with a
// "Continue shopping" button; click it once, then product pages load (200)
// with NO login. Raw un-clicked requests get 503 throttles, so the
// passInterstitial() bypass below is REQUIRED and is reused unchanged.
//
// Marketplace pricing is NATIONAL -> every row is tagged city="All India";
// pincodes.json is unused. Output JSON shape stays Blinkit-compatible
// (summary + perPin + allRows) so build_excel.py keeps working, with the new
// seller / availability_text / units_left / asin / category fields added.
//
// BLOCK TEST: set AMAZON_SAMPLE=<n> to scrape only the first n ASINs and emit
// a block-rate report instead of grinding all 314 (Amazon blocks datacenter
// IPs hard — don't burn the IP if the sample is dirty). Default = full 314.
//   AMAZON_SAMPLE=10 node scrape.js     # block test on first 10
//   node scrape.js                      # full production run (run.sh path)
// ---------------------------------------------------------------------------

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const CONCURRENCY = parseInt(process.env.AMAZON_CONCURRENCY || '2', 10); // modest: Amazon blocks hard
const SAMPLE = process.env.AMAZON_SAMPLE ? parseInt(process.env.AMAZON_SAMPLE, 10) : 0; // 0 => full run
const PER_PRODUCT_DELAY_MS = parseInt(process.env.AMAZON_DELAY_MS || '900', 10);
const MAX_RETRIES = 1;

// --- volume / canonical helpers (kept compatible with the old output) -------
// parseVolMl now lives in ./volparse.js and SUMS additive combos ("5LTR + 1LTR"
// -> 6000) instead of reading only the first token (the per_litre-inflation bug,
// fixed 2026-06-05). See volparse.js for the root-cause note + test_volparse.js.
const { parseVolMl } = require('./volparse.js');

// Plausibility ceiling for Rs/L (oils). A correctly-parsed Jivo oil tops out
// well under this even for premium 200 ml packs (~₹1645/L observed); a value
// above it means a volume mis-parse slipped through -> publish null, never a
// garbage outlier. Pure safety net; it does not fire on current clean data.
const PRICE_PER_L_MAX = 6000;

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

// pass the "Continue shopping" interstitial amazon.in shows datacenter IPs
async function passInterstitial(page) {
  await page.goto('https://www.amazon.in/', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await page.waitForTimeout(2000);
  try { await page.getByRole('button', { name: /continue shopping/i }).click({ timeout: 7000 }); } catch (e) {}
  await page.waitForTimeout(2500);
}

// ---------------------------------------------------------------------------
// Visit a single /dp/<asin> page and extract everything we need.
// Returns { status, fields... }. status is one of:
//   'ok'        -> a real product page parsed
//   'notfound'  -> page loaded but is a dog / 404 / no product title
//   'blocked'   -> captcha / robot-check / 503 / 202 interstitial / empty
// ---------------------------------------------------------------------------
async function scrapeAsin(page, asin) {
  const url = `https://www.amazon.in/dp/${asin}`;
  let resp;
  try {
    resp = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 35000 });
  } catch (e) {
    return { status: 'blocked', reason: 'nav:' + e.message, http: null };
  }
  const http = resp ? resp.status() : null;
  await page.waitForTimeout(1200);

  const probe = await page.evaluate(() => {
    const t = (document.body && document.body.innerText) || '';
    return {
      text: t.slice(0, 4000),
      hasTitle: !!document.getElementById('productTitle'),
      hasContinue: /continue shopping/i.test(t),
      hasCaptcha: /enter the characters you see below|type the characters|not a robot|automated access|api-services-support@amazon/i.test(t),
      title: (document.getElementById('productTitle') || {}).innerText || '',
    };
  });

  // Detect bot walls / throttles BEFORE trusting any content.
  if (http === 503 || http === 429) return { status: 'blocked', reason: 'http' + http, http };
  if (probe.hasCaptcha) return { status: 'blocked', reason: 'captcha', http };
  if (probe.hasContinue && !probe.hasTitle) return { status: 'blocked', reason: 'interstitial', http };
  if (!probe.text || probe.text.length < 50) return { status: 'blocked', reason: 'empty', http };

  // 404 / dog page / product simply gone.
  if (!probe.hasTitle) {
    if (http === 404 || /page you were looking for|sorry.+can.?t find that page|looking for something\?/i.test(probe.text)) {
      return { status: 'notfound', reason: 'no-title-404', http };
    }
    return { status: 'notfound', reason: 'no-title', http };
  }

  // Real product page -> pull structured fields in the DOM.
  const data = await page.evaluate(() => {
    const txt = (el) => (el ? (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim() : '');
    const toRs = (s) => {
      if (s == null) return null;
      const m = String(s).replace(/\s/g, '').match(/₹?([\d,]+(?:\.\d+)?)/);
      if (!m) return null;
      const n = Math.round(parseFloat(m[1].replace(/,/g, '')));
      return Number.isFinite(n) && n > 0 ? n : null;
    };

    const title = txt(document.getElementById('productTitle'));

    // ----- SALE PRICE -----
    // Amazon's current price lives in #corePrice / .priceToPay / apexPriceToPay.
    // The hidden .a-offscreen carries the clean "₹379.00" string.
    let sale = null;
    const saleSel = [
      '#corePriceDisplay_desktop_feature_div .priceToPay .a-offscreen',
      '#corePrice_feature_div .priceToPay .a-offscreen',
      '.priceToPay .a-offscreen',
      'span.apexPriceToPay .a-offscreen',
      '#corePriceDisplay_desktop_feature_div span.a-price-whole',
      '#price_inside_buybox',
      '#newBuyBoxPrice',
      '#tp_price_block_total_price_ww .a-offscreen',
    ];
    for (const s of saleSel) {
      const el = document.querySelector(s);
      const v = toRs(el && (el.textContent || el.innerText));
      if (v) { sale = v; break; }
    }

    // ----- MRP / list price (the struck-through "M.R.P.:") -----
    let mrp = null;
    const mrpSel = [
      '#corePriceDisplay_desktop_feature_div .basisPrice .a-offscreen',
      '#corePriceDisplay_desktop_feature_div span[data-a-strike="true"] .a-offscreen',
      'span.a-price.a-text-price[data-a-strike="true"] .a-offscreen',
      '.basisPrice .a-offscreen',
      '#priceblock_listprice',
      '#listPrice',
    ];
    for (const s of mrpSel) {
      const el = document.querySelector(s);
      const v = toRs(el && (el.textContent || el.innerText));
      if (v) { mrp = v; break; }
    }
    // Fallback: any struck text price on the page.
    if (!mrp) {
      const strike = document.querySelector('span.a-text-price .a-offscreen, .a-text-strike');
      const v = toRs(strike && (strike.textContent || strike.innerText));
      if (v) mrp = v;
    }

    // discount % shown on page (e.g. "-42%") as a cross-check.
    let savingsPct = null;
    const sp = document.querySelector('.savingsPercentage, #corePriceDisplay_desktop_feature_div .savingPriceOverride');
    if (sp) { const m = txt(sp).match(/(\d+(?:\.\d+)?)\s*%/); if (m) savingsPct = parseFloat(m[1]); }

    // ----- SELLER ("Sold by") and "Ships from" -----
    // Modern layout = #merchantInfoFeature_div / #tabular-buybox rows with
    // labels "Ships from" / "Sold by". Older = #merchant-info text + #sellerProfileTriggerId.
    let seller = '', shipsFrom = '';
    const buyboxRows = document.querySelectorAll('#tabular-buybox .tabular-buybox-text, .tabular-buybox-container .a-row');
    buyboxRows.forEach((row) => {
      const label = txt(row.querySelector('.tabular-buybox-text-message, .a-text-bold')) || txt(row);
      const val = txt(row);
    });
    // Robust label/value scan over the buybox / merchant feature blocks.
    const scanBlocks = ['#merchantInfoFeature_div', '#tabular-buybox', '#tabular_feature_div', '#buybox', '#merchant-info'];
    for (const sel of scanBlocks) {
      const block = document.querySelector(sel);
      if (!block) continue;
      // offer-display rows: each .a-row has an "offer-display-feature-label" + value
      block.querySelectorAll('.offer-display-feature-text, .a-row, .tabular-buybox-text').forEach(() => {});
    }
    // Direct, reliable selectors:
    const soldByEl = document.querySelector('#sellerProfileTriggerId')
      || document.querySelector('#merchant-info a')
      || document.querySelector('[offer-display-feature-name="desktop-merchant-info"] .offer-display-feature-text-message')
      || document.querySelector('#fulfillerInfoFeature_div .offer-display-feature-text-message');
    if (soldByEl) seller = txt(soldByEl);

    // "Ships from" value (label-driven).
    const featureBlocks = document.querySelectorAll('.offer-display-feature-name, .offer-display-feature-text, .tabular-buybox-text');
    // tabular buybox: label cell + value cell pattern
    const tab = document.querySelector('#tabular-buybox');
    if (tab) {
      const cells = [...tab.querySelectorAll('.tabular-buybox-text')];
      for (let i = 0; i < cells.length; i++) {
        const label = txt(cells[i]).toLowerCase();
        const valEl = cells[i].nextElementSibling || cells[i + 1];
        const val = txt(valEl);
        if (/ships from/.test(label) && val) shipsFrom = shipsFrom || val;
        if (/sold by/.test(label) && val && !seller) seller = val;
      }
    }
    // offer-display feature blocks (current desktop layout): the label and the
    // value are SEPARATE elements that share the same offer-display-feature-name
    // (e.g. "desktop-fulfiller-info" -> "Ships from" then "Amazon";
    //       "desktop-merchant-info" -> "Sold by" then "RK World Infocom Pvt Ltd").
    // So per feature-name collect the message texts and take the one that ISN'T
    // the bare label.
    const offerVals = {};
    document.querySelectorAll('[offer-display-feature-name]').forEach((el) => {
      const name = (el.getAttribute('offer-display-feature-name') || '').toLowerCase();
      const msg = txt(el.querySelector('.offer-display-feature-text-message')) || txt(el);
      if (!msg) return;
      (offerVals[name] = offerVals[name] || []).push(msg);
    });
    for (const [name, vals] of Object.entries(offerVals)) {
      const value = vals.find((v) => !/^(ships from|sold by)$/i.test(v.trim())) || '';
      if (/fulfiller|ships/.test(name) && value && !shipsFrom) shipsFrom = value;
      if (/merchant|sold/.test(name) && value && !seller) seller = value;
    }
    // legacy fallback: "Sold by SELLERNAME" inside #merchant-info
    if (!seller) {
      const mi = txt(document.querySelector('#merchant-info'));
      const m = mi.match(/sold by\s+(.+?)(?:\s+and\s+|\.|$)/i);
      if (m) seller = m[1].trim();
    }
    seller = seller.replace(/^sold by\s*/i, '').replace(/\s*\(.*?\)\s*$/, '').trim();
    shipsFrom = shipsFrom.replace(/^ships from\s*/i, '').trim();

    // ----- AVAILABILITY / STOCK -----
    const availEl = document.querySelector('#availability span, #availability, #outOfStock, #availabilityInsideBuyBox_feature_div .a-color-state');
    let availability_text = txt(availEl);
    if (!availability_text) {
      // sometimes only the add-to-cart / buy-now state tells us
      const buyable = document.querySelector('#add-to-cart-button, #buy-now-button');
      availability_text = buyable ? 'In stock' : '';
    }
    // strip trailing UI/script cruft that bleeds into #availability: an inline
    // JSON state blob ("In stock {"isInternal":...}"), the delivery/location
    // widget, and the wishlist/cart buttons.
    availability_text = availability_text
      .replace(/\s*\{.*$/s, '')
      .replace(/\s*delivering to.*$/i, '')
      .replace(/\s*update location.*$/i, '')
      .replace(/\s*add to (wish ?list|cart).*$/i, '')
      .replace(/\s*see all buying options.*$/i, '')
      .trim();
    const lower = availability_text.toLowerCase();
    let units_left = null;
    const um = lower.match(/only\s+(\d+)\s+left/);
    if (um) units_left = parseInt(um[1], 10);

    const oosWords = /currently unavailable|out of stock|temporarily out of stock|unavailable|sold out|not available/i;
    const inWords = /in stock|only \d+ left|left in stock|usually (dispatched|ships)|order soon|available/i;
    let in_stock;
    if (oosWords.test(availability_text)) in_stock = 0;
    else if (inWords.test(availability_text)) in_stock = 1;
    else in_stock = document.querySelector('#add-to-cart-button, #buy-now-button') ? 1 : 0;

    return { title, sale, mrp, savingsPct, seller, shipsFrom, availability_text, units_left, in_stock };
  });

  if (!data.title) return { status: 'notfound', reason: 'empty-title', http };
  return { status: 'ok', http, ...data };
}

// build a Blinkit-shaped row from a product meta + a scrape result
function buildRow(meta, res) {
  const pack = meta.pack || '';
  const vol_ml = parseVolMl(pack);
  const canonName = meta.name || res.title || '';
  let sale = res.status === 'ok' ? res.sale : null;
  let mrp = res.status === 'ok' ? res.mrp : null;
  if (mrp != null && sale != null && mrp < sale) mrp = sale; // never let MRP undercut sale
  if (sale != null && mrp == null) mrp = sale;               // no struck price => no discount

  let discount_pct = 0;
  if (mrp && sale && mrp > sale) discount_pct = Math.round(((mrp - sale) / mrp) * 1000) / 10;

  // per_litre only meaningful for oils with a known volume. The sanity bound
  // nulls any implausible Rs/L (a residual volume mis-parse) rather than
  // publishing a garbage outlier like the old combo bug's ₹10575/L.
  let per_litre = (meta.is_oil && vol_ml && sale != null)
    ? Math.round((sale / (vol_ml / 1000)) * 100) / 100 || null
    : null;
  if (per_litre != null && (per_litre <= 0 || per_litre > PRICE_PER_L_MAX)) per_litre = null;

  let availability_text, in_stock, units_left, seller, ships_from;
  if (res.status === 'ok') {
    availability_text = res.availability_text || (res.in_stock ? 'In stock' : 'Currently unavailable');
    in_stock = res.in_stock;
    units_left = res.units_left != null ? res.units_left : null;
    seller = res.seller || '';
    ships_from = res.shipsFrom || '';
  } else {
    availability_text = res.status === 'notfound' ? 'NOT FOUND' : 'BLOCKED';
    in_stock = 0;
    units_left = null;
    seller = '';
    ships_from = '';
  }

  return {
    // --- fields the pipeline already relies on (Blinkit-compatible) ---
    city: 'All India', pincode: '-', locality: 'Amazon marketplace (national)',
    store_id: '', store_name: 'Amazon',
    sku_raw: res.title || canonName,
    canonical: canonical(canonName, pack),
    pack: pack || '',
    vol_ml,
    sale,
    mrp,
    discount_pct,
    per_litre,
    eta_min: null,
    in_stock,
    // --- NEW fields requested: retailer name + stock + identity/metadata ---
    asin: meta.asin,
    seller,                 // the merchant ("Sold by ...")
    ships_from,             // "Ships from ..." when shown
    availability_text,      // raw stock text / NOT FOUND / BLOCKED
    units_left,             // int when "Only N left in stock"
    category: meta.category || '',
    sub_category: meta.sub_category || '',
    is_oil: !!meta.is_oil,
    sap_code: meta.sap_code || null,
    http_status: res.http != null ? res.http : null,
    status: res.status,     // ok | notfound | blocked
  };
}

(async () => {
  const t0 = Date.now();
  const products = JSON.parse(fs.readFileSync(path.join(__dirname, 'products.json'), 'utf8'));
  const targets = SAMPLE > 0 ? products.slice(0, SAMPLE) : products;
  process.stderr.write(`[start] ${targets.length}/${products.length} ASINs · concurrency=${CONCURRENCY}${SAMPLE ? ' · SAMPLE/BLOCK-TEST MODE' : ' · FULL RUN'}\n`);

  const browser = await chromium.launch({ headless: true });
  // NOTE: to route through the residential proxy if Amazon starts blocking,
  // this is the SAME 2-line change zepto uses:
  //   const getProxy = require('../../tools/proxy'); const proxy = getProxy();
  //   chromium.launch({ headless: true, ...(proxy ? { proxy } : {}) });
  const ctx = await browser.newContext({
    userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata',
    viewport: { width: 1366, height: 900 },
  });
  await ctx.route('**/*', (route) => {
    const t = route.request().resourceType();
    if (['image', 'font', 'media'].includes(t)) return route.abort();
    return route.continue();
  });

  // one warm-up page passes the interstitial; the cookies it sets are shared
  // across the context, so the worker pages inherit the bypass.
  const warm = await ctx.newPage();
  await passInterstitial(warm);
  await warm.close();

  const counts = { ok: 0, notfound: 0, blocked: 0 };
  const rows = [];
  const queue = targets.map((m, i) => ({ m, i }));
  let cursor = 0;

  async function worker(wid) {
    const page = await ctx.newPage();
    while (cursor < queue.length) {
      const { m, i } = queue[cursor++];
      let res = null;
      for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
        res = await scrapeAsin(page, m.asin);
        if (res.status !== 'blocked') break;
        // a transient throttle: re-pass interstitial and retry once
        if (attempt < MAX_RETRIES) { await passInterstitial(page); await page.waitForTimeout(1500); }
      }
      counts[res.status] = (counts[res.status] || 0) + 1;
      rows[i] = buildRow(m, res);
      const tag = res.status === 'ok'
        ? `Rs${res.sale || '?'}/${res.mrp || '?'} ${res.seller ? 'sold-by:' + res.seller.slice(0, 24) : 'no-seller'} ${res.availability_text ? '[' + res.availability_text.slice(0, 22) + ']' : ''}`
        : `${res.status.toUpperCase()} (${res.reason || res.http || ''})`;
      process.stderr.write(`[w${wid}] ${String(i + 1).padStart(3)}/${queue.length} ${m.asin} -> ${tag}\n`);
      await page.waitForTimeout(PER_PRODUCT_DELAY_MS + Math.floor(Math.random() * 500));
    }
    await page.close();
  }

  await Promise.all(Array.from({ length: CONCURRENCY }, (_, k) => worker(k + 1)));
  await browser.close();

  const dense = rows.filter(Boolean);
  const attempted = dense.length;
  const blockRate = attempted ? Math.round((counts.blocked / attempted) * 1000) / 10 : 0;

  // ---- BLOCK TEST short-circuit -------------------------------------------
  if (SAMPLE > 0) {
    const report = {
      mode: 'BLOCK-TEST', sample_size: attempted,
      ok: counts.ok, notfound: counts.notfound, blocked: counts.blocked,
      block_rate_pct: blockRate,
      verdict: counts.blocked >= Math.ceil(attempted / 2)
        ? 'BLOCKED — Amazon needs the residential proxy; do NOT grind all 314'
        : 'CLEAN — safe to run the full 314 direct',
      wall_s: Math.round((Date.now() - t0) / 1000),
    };
    process.stderr.write('[BLOCK-TEST] ' + JSON.stringify(report) + '\n');
    // write a small sample result so it can be eyeballed, but DON'T overwrite
    // a good production result.json with a tiny sample.
    fs.writeFileSync(path.join(__dirname, 'result.sample.json'),
      JSON.stringify({ report, rows: dense }, null, 2));
    console.log(JSON.stringify(report));
    return;
  }

  // ---- FULL RUN: write the national-shape result.json ---------------------
  const summary = {
    pincodes_total: 1,
    pincodes_with_jivo: counts.ok ? 1 : 0,
    total_rows: dense.length,
    unique_skus: new Set(dense.map((r) => r.asin)).size, // ASIN is the true unique key now
    asins_targeted: targets.length,
    captured_ok: counts.ok,
    not_found: counts.notfound,
    blocked: counts.blocked,
    block_rate_pct: blockRate,
    wall_s: Math.round((Date.now() - t0) / 1000),
    captured_at: new Date().toISOString(),
  };
  const perPin = [{
    city: 'All India', pincode: '-', locality: 'Amazon marketplace (national)',
    tier: 0, store_id: '', store_name: 'Amazon', rows: dense,
  }];
  process.stderr.write('[SUMMARY] ' + JSON.stringify(summary) + '\n');
  fs.writeFileSync(path.join(__dirname, 'result.json'),
    JSON.stringify({ summary, perPin, allRows: dense }, null, 2));
  console.log(JSON.stringify(summary));
})();
