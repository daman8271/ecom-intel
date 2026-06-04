// ---------------------------------------------------------------------------
// BIGBASKET scraper.  STATUS: LIVE (2026-05-31) via the web listing-svc API.
//
// MODEL — NATIONAL (like Flipkart, not like Blinkit/Zepto/).
//   BigBasket's main storefront ("BB", scheduled delivery) prices Jivo
//   NATIONALLY: the listing-svc search API returns the same catalogue + prices
//   regardless of the session's city/hub. (Verified in recon: the old per-city
//   location APIs are decommissioned/404, and overriding the hub cookie doesn't
//   change Jivo pricing.) So we do ONE scrape and tag every row city="All India"
//   — we do NOT loop pincodes. pincodes.json is intentionally unused (kept for
//   shape-consistency with the other platforms).
//
// ANTI-BOT — STEALTH REQUIRED.
//   www.bigbasket.com is behind Akamai Bot Manager. Plain headless Chromium —
//   and any raw node/curl client — gets HTTP 403 from this datacenter IP. A
//   stealth browser (playwright-extra + puppeteer-extra-plugin-stealth) loads at
//   HTTP 200, and an IN-PAGE fetch() (inheriting the real session cookies + TLS
//   fingerprint) reaches the JSON API. Mirrors the  recipe already
//   proven on this VPS. No proxy needed.
//
// API:  GET /listing-svc/v2/products?type=ps&slug=<query>&page=<n>&bucket_id=32
//       -> { tabs:[{ product_info:{ products:[...], number_of_pages, total_count }}]}
//   p.id                                  -> sku id
//   p.desc                                -> name
//   p.brand.name (trim)                   -> brand  (keep only "Jivo")
//   p.w                                   -> pack ("5 L", "200 ml")
//   p.magnitude + p.unit                  -> numeric volume (magnitude already in ml)
//   p.pricing.discount.mrp                -> MRP (string)
//   p.pricing.discount.prim_price.sp      -> selling price (string) — the DISPLAYED pack
//                                            price, verified live to the paisa (JSON-LD
//                                            offers.price + DOM). This is the CORRECT field;
//                                            base_price/rsp are NOT the displayed price.
//   p.pricing.discount.camp_detail.d_v    -> discount % (fallback)
//   p.pricing.discount.prim_price.base_price/base_unit -> per-unit (per-L/ml) secondary fig.
//   p.children[]                          -> sibling packs nested under a parent that may
//                                            never surface as their own top-level result
//                                            (each is a full product obj) — walked too.
//   p.availability.avail_status === '001' -> in stock (else 002/004 = OOS/not-serviceable)
//
// PRICE FIELD — the SP source is prim_price.sp (the displayed price). We do NOT fall back to
//   MRP when sp is missing (that would silently report a full-price item); instead we try
//   sp -> rsp -> subscription_price -> offer.offer_sp and, if all are absent, tag the row
//   sp_source='MISSING' and SKIP it. Paise-level decimal SPs (e.g. 835.43) are BigBasket's
//   genuine to-the-paisa pack price (NOT rounded on the live site), so we keep them as-is.
//
// Output schema is Blinkit/Flipkart-compatible so build_excel.py works unchanged.
// ZERO LLM in the loop. Full recon notes: platforms/bigbasket/RECON.md.
// ---------------------------------------------------------------------------

const { chromium } = require('playwright-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
const fs = require('fs');
const path = require('path');
chromium.use(StealthPlugin());

const OUTFILE = process.env.OUT_FILE || path.join(__dirname, 'result.json');
const BUCKET_ID = process.env.BB_BUCKET_ID || '32';
const MAX_PAGES = parseInt(process.env.BB_MAX_PAGES || '5', 10);
// Multiple queries, deduped, to maximise Jivo recall across categories (oils,
// juices, vinegar, ...). "jivo" alone returns the whole brand catalogue today;
// the extra terms are cheap insurance if search ranking ever truncates it.
// The broad "jivo" brand search returns the whole Jivo catalogue (capped ~35
// results/page); the category terms backfill any SKU the cap ranks out, across
// the categories Jivo actually sells. Non-matching terms hit BB's generic
// category fallback (e.g. "jivo honey" -> 1500-item honey list with 0 Jivo) —
// the strict brand filter rejects those and fetchQuery's zero-Jivo-page guard
// stops them paginating, so each costs just one request.
const QUERIES = (process.env.BB_QUERIES
  ? process.env.BB_QUERIES.split(',')
  : ['jivo', 'jivo oil', 'jivo olive oil', 'jivo juice', 'jivo vinegar', 'jivo honey']
).map((s) => s.trim()).filter(Boolean);
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

// --- price/pack helpers (same conventions as the other platforms) ----------
function parseVolMl(pack) {
  if (!pack) return null;
  const m = String(pack).toLowerCase().match(/([\d.]+)\s*(ml|l|ltr|litre|kg|g)\b/);
  if (!m) return null;
  const n = parseFloat(m[1]); const u = m[2];
  if (u === 'ml' || u === 'g') return n;
  if (u === 'l' || u === 'ltr' || u === 'litre' || u === 'kg') return n * 1000;
  return null;
}
function canonical(name, pack) {
  const base = (name || '').toLowerCase().replace(/\(.*?\)/g, '').replace(/[^a-z0-9 ]/g, '')
    .replace(/\s+/g, ' ').trim().replace(/\s/g, '-');
  const vol = parseVolMl(pack);
  const volTag = vol ? (vol >= 1000 ? (vol / 1000) + 'l' : vol + 'ml') : 'na';
  return `${base}-${volTag}`.replace(/--+/g, '-');
}
function num(v) {
  if (v == null) return null;
  const n = parseFloat(String(v).replace(/[^\d.]/g, ''));
  return Number.isFinite(n) ? n : null;
}
const r1 = (n) => Math.round(n * 10) / 10;
const r2 = (n) => Math.round(n * 100) / 100;

// volume in ml: prefer the human pack string ("5 L"); fall back to magnitude+unit
// (BigBasket's magnitude is already expressed in ml for ml/g units, e.g. "5000").
function volMl(p, pack) {
  const v = parseVolMl(pack);
  if (v != null) return v;
  const mag = num(p.magnitude);
  if (mag == null) return null;
  const u = String(p.unit || '').toLowerCase();
  if (u === 'l' || u === 'ltr' || u === 'litre' || u === 'kg') return mag * 1000;
  return mag; // ml / g / already-ml
}

// Build a canonical row from ONE listing-svc product object (top-level OR a child).
// Returns null if the product isn't Jivo or has no usable selling price (we never
// invent a price by falling back to MRP — see sp_source below).
function buildRow(p) {
  const brand = (p.brand && p.brand.name && String(p.brand.name).trim()) || '';
  // strict brand match — excludes substring noise (Jivika / JIVOTTAM / etc.)
  if (!/^jivo$/i.test(brand)) return null;
  const disc = (p.pricing && p.pricing.discount) || {};
  const prim = disc.prim_price || {};
  const mrp = num(disc.mrp);
  // SP source = the DISPLAYED selling price. prim_price.sp is the headline pack price
  // (verified live to the paisa). If it's ever absent, try the other genuine price
  // fields in order — but NEVER fall back to MRP (that would silently mislabel a
  // missing price as a real full-price item). If none exist, tag MISSING and skip.
  let sale = num(prim.sp);
  let sp_source = 'sp';
  if (sale == null) { sale = num(prim.rsp); sp_source = 'rsp'; }
  if (sale == null) { sale = num(disc.subscription_price); sp_source = 'subscription'; }
  if (sale == null && p.pricing && p.pricing.offer) { sale = num(p.pricing.offer.offer_sp); sp_source = 'offer'; }
  if (sale == null) { sp_source = 'MISSING'; }
  if (sale == null) return null; // unpriced -> skip; do NOT emit MRP-as-SP
  const pack = p.w || '';
  const vol = volMl(p, pack);
  const av = p.availability || {};
  const inStock = (av.avail_status === '001' && !av.not_for_sale) ? 1 : (av.avail_status ? 0 : 1);
  const dctFromMrp = (mrp && sale && mrp > sale) ? r1(((mrp - sale) / mrp) * 100) : null;
  const dcampRaw = disc.camp_detail && disc.camp_detail.d_v;
  const dcamp = (dcampRaw != null && Number.isFinite(parseFloat(dcampRaw))) ? r1(parseFloat(dcampRaw)) : null;
  // buy-N "Har Din Sasta" dual pricing: sale is then a multi-unit price (footnote in report)
  const dualPricing = !!(disc.camp_detail && disc.camp_detail.dual_pricing);
  return {
    city: 'All India', pincode: '-', locality: 'BigBasket (national)',
    store_id: '', store_name: 'BigBasket',
    sku_raw: p.desc || '', canonical: canonical(p.desc, pack), pack,
    vol_ml: vol, sale, mrp,
    discount_pct: dctFromMrp != null ? dctFromMrp : (dcamp != null ? dcamp : 0),
    per_litre: vol ? r2(sale / (vol / 1000)) : null,
    eta_min: null, in_stock: inStock,
    // ---- rich identity (ignored by build_excel; kept for vault/history/review) ----
    sku_id: String(p.id || ''), brand,
    avail_status: av.avail_status || '', avail_button: av.button || '',
    base_price: num(prim.base_price), base_unit: prim.base_unit || '',
    category: (p.category && (p.category.tlc_name || p.category.mlc_name)) || '',
    absolute_url: p.absolute_url || '',
    sp_source, dual_pricing: dualPricing,
  };
}

// Pull every Jivo product out of one listing-svc response into canonical rows.
// Walks both the top-level products[] AND each product's children[] (sibling packs
// that may exist ONLY nested under a parent and never appear as their own top-level
// result — e.g. Mango Wheatgrass 200ml, Mustard 1L, Canola Cold-Pressed 5L). Dedup
// on sku_id happens upstream (the seen-set in the main loop), so a child that also
// appears top-level is not double-counted.
function parseProducts(json) {
  const out = [];
  const tabs = (json && json.tabs) || [];
  for (const tab of tabs) {
    const pi = (tab && tab.product_info) || {};
    for (const p of (pi.products || [])) {
      const row = buildRow(p);
      if (row) out.push(row);
      for (const c of (p.children || [])) {
        const cr = buildRow(c);
        if (cr) out.push(cr);
      }
    }
  }
  return out;
}

async function fetchQuery(page, query) {
  const slug = encodeURIComponent(query.toLowerCase().trim());
  const all = [];
  for (let pg = 1; pg <= MAX_PAGES; pg++) {
    const res = await page.evaluate(async ({ slug, pg, bucket }) => {
      const ctrl = new AbortController();
      const tid = setTimeout(() => ctrl.abort(), 20000); // never let a single fetch hang the run
      try {
        const url = `/listing-svc/v2/products?type=ps&slug=${slug}&page=${pg}&bucket_id=${bucket}`;
        const r = await fetch(url, {
          signal: ctrl.signal,
          headers: {
            accept: 'application/json, text/plain, */*',
            'x-requested-with': 'XMLHttpRequest',
            referer: `https://www.bigbasket.com/ps/?q=${slug}`,
          },
        });
        if (r.status !== 200) return { __err: 'HTTP ' + r.status };
        return await r.json();
      } catch (e) { return { __err: e.message }; } finally { clearTimeout(tid); }
    }, { slug, pg, bucket: BUCKET_ID });

    if (res && res.__err) { process.stderr.write(`[warn] q="${query}" p${pg}: ${res.__err}\n`); break; }
    const rows = parseProducts(res);
    all.push(...rows);
    const pi = (res.tabs && res.tabs[0] && res.tabs[0].product_info) || {};
    const np = pi.number_of_pages || 1;
    process.stderr.write(`[ok] q="${query}" p${pg}/${np} -> +${rows.length} jivo (total_count=${pi.total_count != null ? pi.total_count : '?'})\n`);
    if (rows.length === 0) break; // generic-category fallback or natural end — don't keep paginating a non-Jivo result set
    if (pg >= np) break;
    await page.waitForTimeout(300 + Math.random() * 400);
  }
  return all;
}

async function openSession(browser) {
  const ctx = await browser.newContext({
    userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata',
    viewport: { width: 1280, height: 900 },
    extraHTTPHeaders: { 'accept-language': 'en-IN,en;q=0.9' },
  });
  const page = await ctx.newPage();
  await ctx.route('**/*', (route) => {
    const t = route.request().resourceType();
    if (['image', 'font', 'media'].includes(t)) return route.abort();
    return route.continue();
  });
  let ok = false;
  for (let i = 0; i < 3 && !ok; i++) {
    try {
      const resp = await page.goto('https://www.bigbasket.com/', { waitUntil: 'domcontentloaded', timeout: 45000 });
      const status = resp ? resp.status() : 0;
      if (status === 200) { ok = true; break; }
      process.stderr.write(`[warn] homepage status ${status} (try ${i + 1}/3)\n`);
    } catch (e) {
      process.stderr.write(`[warn] homepage error "${e.message}" (try ${i + 1}/3)\n`);
    }
    await page.waitForTimeout(1500 + Math.random() * 1500);
  }
  if (ok) await page.waitForTimeout(2500); // let Akamai sensor + cookies settle
  return { ctx, page, ok };
}

// Write result.json + summary EXACTLY once. Called on the happy path, on the
// watchdog timeout, and on any unhandled rejection — so run.sh always gets a
// valid result.json (review.py then decides OK/BROKEN). Never throws upward.
function writeResult(rows, sessionOk, t0) {
  const inStock = rows.filter((r) => r.in_stock).length;
  const summary = {
    pincodes_total: 1,
    pincodes_with_jivo: rows.length ? 1 : 0,
    total_rows: rows.length,
    unique_skus: new Set(rows.map((r) => r.canonical)).size,
    in_stock: inStock,
    out_of_stock: rows.length - inStock,
    queries: QUERIES,
    session_ok: sessionOk,
    wall_s: Math.round((Date.now() - t0) / 1000),
    captured_at: new Date().toISOString(),
  };
  const perPin = [{ city: 'All India', pincode: '-', locality: 'BigBasket (national)', tier: 0, store_id: '', store_name: 'BigBasket', rows }];
  process.stderr.write('[SUMMARY] ' + JSON.stringify(summary) + '\n');
  fs.writeFileSync(OUTFILE, JSON.stringify({ summary, perPin, allRows: rows }, null, 2));
  console.log(JSON.stringify(summary));
}

const T0 = Date.now();
let DONE = false;
// Hard watchdog: if the whole scrape ever hangs (unresponsive site, stuck
// browser), emit an empty result and exit 0 so review.py marks it BROKEN and
// self-heal retries — instead of blocking the parallel cron sweep forever.
const WATCHDOG_MS = parseInt(process.env.BB_WATCHDOG_MS || '240000', 10);
const watchdog = setTimeout(() => {
  if (DONE) return;
  DONE = true;
  process.stderr.write(`[FATAL] watchdog: scrape exceeded ${WATCHDOG_MS}ms — emitting empty result\n`);
  try { writeResult([], false, T0); } catch (_) {}
  process.exit(0);
}, WATCHDOG_MS);

(async () => {
  const browser = await chromium.launch({
    headless: true,
    timeout: 60000,
    executablePath: require('playwright').chromium.executablePath(),
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-blink-features=AutomationControlled'],
  });

  let rows = [];
  let sessionOk = false;
  try {
    const { ctx, page, ok } = await openSession(browser);
    sessionOk = ok;
    if (ok) {
      const seen = new Set();
      for (const q of QUERIES) {
        let qr = [];
        try { qr = await fetchQuery(page, q); } catch (e) { process.stderr.write(`[err] q="${q}": ${e.message}\n`); }
        for (const r of qr) {
          // dedup on BB's unique product id (canonical = name+pack can collide
          // across two genuinely distinct SKUs; sku_id never does). Fall back to
          // canonical only if an id is somehow missing.
          const key = r.sku_id || r.canonical;
          if (seen.has(key)) continue;
          seen.add(key); rows.push(r);
        }
        await page.waitForTimeout(500 + Math.random() * 600);
      }
    } else {
      process.stderr.write('[err] could not load BigBasket homepage (Akamai block?) — emitting empty result\n');
    }
    try { await ctx.close(); } catch (_) {}
  } catch (e) {
    process.stderr.write(`[err] fatal: ${e.message}\n`);
  } finally {
    try { await browser.close(); } catch (_) {}
  }

  if (!DONE) { DONE = true; clearTimeout(watchdog); writeResult(rows, sessionOk, T0); }
})().catch((e) => {
  // Last-resort guard: any unhandled rejection (incl. failures in the result
  // write/IO path) must NOT exit non-zero, or run.sh's `set -e` aborts the run.
  process.stderr.write(`[FATAL] unhandled: ${e && e.message}\n`);
  if (!DONE) { DONE = true; try { clearTimeout(watchdog); writeResult([], false, T0); } catch (_) {} }
  process.exit(0);
});
