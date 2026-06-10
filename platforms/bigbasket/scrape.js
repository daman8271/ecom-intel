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
const { loadBBCookies, DEFAULT_COOKIE_PATH } = require('./import_cookies');
chromium.use(StealthPlugin());

const OUTFILE = process.env.OUT_FILE || path.join(__dirname, 'result.json');
// LOGGED-IN MEMBER MODE. We inject a transplanted bigbasket.com session
// (secrets/bb_cookies.json, gitignored) so the listing-svc returns MEMBER prices
// — what a logged-in customer actually pays — instead of logged-out public prices.
// If the cookie file is present but the session is EXPIRED/invalid, we do NOT
// silently fall back to guest prices: we write BB_SESSION_EXPIRED and emit an
// empty result so review.py marks the run BROKEN and self-heal escalates.
const COOKIE_PATH = process.env.BB_COOKIE_PATH || DEFAULT_COOKIE_PATH;
const EXPIRED_MARKER = path.join(__dirname, 'secrets', 'BB_SESSION_EXPIRED');
const BUCKET_ID = process.env.BB_BUCKET_ID || '32';
const MAX_PAGES = parseInt(process.env.BB_MAX_PAGES || '5', 10);
// RATE-LIMIT RESILIENCE (reliability > speed). BigBasket 429-throttles a fast burst
// of queries (seen: 5/6 queries 429'd in one ~9s run -> collapsed to 11 partial rows).
// We (a) space queries well apart so the burst doesn't trip the limit in the first
// place, and (b) retry any throttle/transient status with exponential backoff so a
// 429 never silently drops a query. A slower run that gets the full catalogue beats a
// fast one throttled to garbage — the cron is serial and has the time.
const RETRYABLE = new Set([429, 503, 502, 408]);
const MAX_RETRIES = parseInt(process.env.BB_MAX_RETRIES || '5', 10);
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
  const s = String(pack).toLowerCase();
  const toMl = (n, u) => {
    if (u === 'ml' || u === 'g') return n;
    if (u === 'l' || u === 'ltr' || u === 'litre' || u === 'kg') return n * 1000;
    return null;
  };
  // Combo packs come in BOTH orders ("1 L x 2" and "2 x 1 L" are the same 2L pack —
  // same fix as zepto 2026-06-10); they must run BEFORE the single-quantity match,
  // which would otherwise read only the first "1 L" and halve the volume (2x Rs/L).
  let m = s.match(/([\d.]+)\s*(ml|l|ltr|litre|kg|g)\b\s*[x×]\s*([\d.]+)/);          // unit-first "N unit X M"
  if (m) { const base = toMl(parseFloat(m[1]), m[2]); return base != null ? base * parseFloat(m[3]) : null; }
  m = s.match(/([\d.]+)\s*[x×]\s*([\d.]+)\s*(ml|l|ltr|litre|kg|g)\b/);              // multiplier-first "M x N unit"
  if (m) { const base = toMl(parseFloat(m[2]), m[3]); return base != null ? parseFloat(m[1]) * base : null; }
  m = s.match(/([\d.]+)\s*(ml|l|ltr|litre|kg|g)\b/);                                // single quantity (unchanged)
  if (!m) return null;
  return toMl(parseFloat(m[1]), m[2]);
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
  // REAL EAN-13 only (GS1-India prefix 890 + 10 digits). BigBasket's ean_code field
  // often just echoes the internal 8-digit sku id (e.g. id=40249992, ean_code='40249992')
  // — that is NOT an EAN and must never be recorded as one. Additive + fail-safe: on any
  // error/non-match the row is built exactly as before (the key is simply omitted).
  let ean = '';
  try {
    const e = String(p.ean_code || '');
    if (/^890\d{10}$/.test(e)) ean = e;
  } catch (_) { ean = ''; }
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
    ...(ean ? { ean } : {}),
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

// One raw page fetch via the in-page session. Returns parsed JSON, or
// { __err, __status } where __status is the HTTP code (0 = network/abort).
async function fetchPageOnce(page, slug, pg) {
  return page.evaluate(async ({ slug, pg, bucket }) => {
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
      if (r.status !== 200) return { __err: 'HTTP ' + r.status, __status: r.status };
      return await r.json();
    } catch (e) { return { __err: e.message, __status: 0 }; } finally { clearTimeout(tid); }
  }, { slug, pg, bucket: BUCKET_ID });
}

async function fetchQuery(page, query) {
  const slug = encodeURIComponent(query.toLowerCase().trim());
  const all = [];
  for (let pg = 1; pg <= MAX_PAGES; pg++) {
    // Retry the SAME page on 429/503/502/408 with exponential backoff + jitter, so a
    // throttle never silently drops the query. Non-retryable statuses (404, etc.) and
    // exhausted retries fall through to the warn+break below.
    let res = null;
    for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
      res = await fetchPageOnce(page, slug, pg);
      if (!res || !res.__err) break;                              // success
      const st = res.__status || 0;
      if (!RETRYABLE.has(st) || attempt === MAX_RETRIES) break;   // non-retryable / out of retries
      const wait = Math.min(30000, 3000 * Math.pow(2, attempt)) + Math.floor(Math.random() * 1500); // 3s,6s,12s,24s,30s(+jitter)
      process.stderr.write(`[retry] q="${query}" p${pg}: HTTP ${st} -> backoff ${Math.round(wait / 1000)}s (attempt ${attempt + 1}/${MAX_RETRIES})\n`);
      await page.waitForTimeout(wait);
    }

    if (res && res.__err) { process.stderr.write(`[warn] q="${query}" p${pg}: ${res.__err} (gave up after ${MAX_RETRIES} retries)\n`); break; }
    const rows = parseProducts(res);
    all.push(...rows);
    const pi = (res.tabs && res.tabs[0] && res.tabs[0].product_info) || {};
    const np = pi.number_of_pages || 1;
    process.stderr.write(`[ok] q="${query}" p${pg}/${np} -> +${rows.length} jivo (total_count=${pi.total_count != null ? pi.total_count : '?'})\n`);
    if (rows.length === 0) break; // generic-category fallback or natural end — don't keep paginating a non-Jivo result set
    if (pg >= np) break;
    await page.waitForTimeout(900 + Math.random() * 800); // inter-page: gentle (was 300-700ms)
  }
  return all;
}

// Ask the site who we are. /ui-svc/v1/header/ returns member_info{id,email,...}
// for a logged-in session; for a guest it has no real member id. This is the
// authoritative live login check (cookies merely *present* is not enough — they
// can be expired). Returns { member, info } where info is the trimmed member_info.
async function verifyMember(page) {
  const res = await page.evaluate(async () => {
    try {
      const r = await fetch('/ui-svc/v1/header/', {
        headers: { accept: 'application/json, text/plain, */*', 'x-requested-with': 'XMLHttpRequest' },
      });
      if (r.status !== 200) return { __err: 'HTTP ' + r.status };
      const j = await r.json();
      const mi = j && j.member_info;
      if (!mi || !mi.id) return { member: false };
      return {
        member: true,
        id: mi.id, email: mi.email || '', mobile: mi.mobile_no || '',
        name: mi.full_name || '', is_bbstar: !!mi.is_bbstar_member, is_vip: !!mi.is_vip,
      };
    } catch (e) { return { __err: e.message }; }
  });
  if (res && res.__err) { process.stderr.write(`[warn] member check failed: ${res.__err}\n`); return { member: false, info: null }; }
  if (res && res.member) {
    // Never print tokens; member id/name/flags are non-secret and prove the session.
    process.stderr.write(`[member] logged in as id=${res.id} "${res.name}" bbstar=${res.is_bbstar} vip=${res.is_vip}\n`);
    return { member: true, info: res };
  }
  return { member: false, info: null };
}

async function openSession(browser) {
  // Load + inject the transplanted logged-in cookies (if the secrets file exists).
  let cookies = null;
  let cookiesPresent = false;
  try {
    const loaded = loadBBCookies(COOKIE_PATH);
    cookies = loaded.cookies;
    cookiesPresent = true;
    process.stderr.write(`[cookies] loaded ${cookies.length} cookies from secrets (critical: ${loaded.haveCritical.join(',') || 'NONE'})\n`);
    if (loaded.missing.length) process.stderr.write(`[cookies] WARNING missing critical: ${loaded.missing.join(',')}\n`);
  } catch (e) {
    process.stderr.write(`[cookies] no usable cookie file at ${COOKIE_PATH} (${e.message}) — running LOGGED OUT (guest prices)\n`);
  }

  const ctx = await browser.newContext({
    userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata',
    viewport: { width: 1280, height: 900 },
    extraHTTPHeaders: { 'accept-language': 'en-IN,en;q=0.9' },
  });
  if (cookies && cookies.length) {
    try { await ctx.addCookies(cookies); } catch (e) { process.stderr.write(`[cookies] addCookies failed: ${e.message}\n`); }
  }
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

  // Confirm the injected session is genuinely logged in (only when we supplied cookies).
  let member = false;
  let memberInfo = null;
  if (ok && cookiesPresent) {
    const v = await verifyMember(page);
    member = v.member;
    memberInfo = v.info;
  }
  return { ctx, page, ok, cookiesPresent, member, memberInfo };
}

// Write result.json + summary EXACTLY once. Called on the happy path, on the
// watchdog timeout, and on any unhandled rejection — so run.sh always gets a
// valid result.json (review.py then decides OK/BROKEN). Never throws upward.
function writeResult(rows, sessionOk, t0, opts = {}) {
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
    // logged-in member context (member prices, not guest). member_id/email/etc are
    // non-secret identity proof; the auth tokens themselves are never written here.
    member: !!opts.member,
    pricing_mode: opts.member ? 'member' : 'guest',
    session_expired: !!opts.sessionExpired,
    member_id: opts.memberInfo ? opts.memberInfo.id : null,
    member_email: opts.memberInfo ? opts.memberInfo.email : null,
    member_is_bbstar: opts.memberInfo ? opts.memberInfo.is_bbstar : null,
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
// Bumped 240s -> 360s to give the rate-limit backoff/retries room (a throttled run
// can legitimately take longer now). The cron is serial with hours of headroom.
const WATCHDOG_MS = parseInt(process.env.BB_WATCHDOG_MS || '360000', 10);
// Armed only when run directly: a `require` (offline volparse test) must never start a
// timer that overwrites result.json with an empty result. clearTimeout(null) is a no-op.
const watchdog = (require.main !== module) ? null : setTimeout(() => {
  if (DONE) return;
  DONE = true;
  process.stderr.write(`[FATAL] watchdog: scrape exceeded ${WATCHDOG_MS}ms — emitting empty result\n`);
  try { writeResult([], false, T0); } catch (_) {}
  process.exit(0);
}, WATCHDOG_MS);

// Exported for the offline volparse test (same pattern as zepto/amazon-fresh); the scrape
// only runs when invoked directly, so `require`-ing this file never launches a browser.
module.exports = { parseVolMl, canonical, volMl };

if (require.main === module) (async () => {
  const browser = await chromium.launch({
    headless: true,
    timeout: 60000,
    executablePath: require('playwright').chromium.executablePath(),
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-blink-features=AutomationControlled'],
  });

  let rows = [];
  let sessionOk = false;
  let member = false;
  let memberInfo = null;
  try {
    const { ctx, page, ok, cookiesPresent, member: isMember, memberInfo: mi } = await openSession(browser);
    sessionOk = ok;
    member = isMember;
    memberInfo = mi;

    // EXPIRED-SESSION GUARD: cookies were supplied but we could NOT establish a
    // logged-in member session. Two shapes seen in practice:
    //   (a) homepage loaded 200 but /ui-svc header has no member -> token expired;
    //   (b) homepage never reached 200 -> a stale/garbled auth cookie makes BB's
    //       edge reject the request (or a generic Akamai block).
    // Either way: do NOT publish guest prices mislabeled as member prices. Write the
    // BB_SESSION_EXPIRED marker (a clear, actionable breadcrumb) and emit an empty
    // result so review.py marks the run BROKEN and self-heal escalates (re-import
    // cookies). The next successful member run clears the marker. This is the
    // "never silently publish wrong data" guarantee.
    if (cookiesPresent && !member) {
      const reason = ok
        ? 'homepage loaded but session is NOT logged in — auth token expired; re-import cookies'
        : 'homepage did not load 200 while cookies were present — likely expired/garbled auth cookie (or an Akamai block); verify cookies + IP';
      process.stderr.write(`[FATAL] no member session: ${reason} — refusing to publish guest prices as member prices\n`);
      try {
        fs.mkdirSync(path.dirname(EXPIRED_MARKER), { recursive: true });
        fs.writeFileSync(EXPIRED_MARKER, `BigBasket member session FAILED at ${new Date().toISOString()}\nreason: ${reason}\nfix: re-export bigbasket.com cookies from a logged-in browser into secrets/bb_cookies.json (see SKILL.md "Refreshing the login cookies").\n`);
      } catch (_) {}
      try { await ctx.close(); } catch (_) {}
      try { await browser.close(); } catch (_) {}
      if (!DONE) { DONE = true; clearTimeout(watchdog); writeResult([], false, T0, { member: false, sessionExpired: true }); }
      return;
    }
    // Valid member session (or, only if no cookie file exists at all, guest mode):
    // clear any stale expiry marker so a recovered session doesn't keep alarming.
    if (member) { try { fs.existsSync(EXPIRED_MARKER) && fs.unlinkSync(EXPIRED_MARKER); } catch (_) {} }

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
        // Gentle spacing between queries so the burst doesn't trip BigBasket's rate
        // limit in the FIRST place (the primary fix; the per-page retry is the safety
        // net). Reliability > speed — the cron is serial and has the time.
        await page.waitForTimeout(3000 + Math.random() * 2500);
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

  if (!DONE) { DONE = true; clearTimeout(watchdog); writeResult(rows, sessionOk, T0, { member, memberInfo }); }
})().catch((e) => {
  // Last-resort guard: any unhandled rejection (incl. failures in the result
  // write/IO path) must NOT exit non-zero, or run.sh's `set -e` aborts the run.
  process.stderr.write(`[FATAL] unhandled: ${e && e.message}\n`);
  if (!DONE) { DONE = true; try { clearTimeout(watchdog); writeResult([], false, T0); } catch (_) {} }
  process.exit(0);
});
