// ---------------------------------------------------------------------------
// ZEPTO scraper.  STATUS: LIVE (2026-05-29) via the public BFF API gateway.
//
// The Zepto WEBSITE edge (www / api.zeptonow.com on CloudFront dist d3kfwk7jfmwo3t)
// hard-403s this datacenter IP. BUT the app's API gateway, bff-gateway.zeptonow.com
// (Kong), is reachable from this IP with NO proxy. The web app authenticates guest
// browsing with `x-without-bearer: true` (no login/token needed). Two calls per pincode:
//   1) GET  serviceability-service/api/v1/serviceability?lat=&long=  -> { serviceable, storeId }
//   2) POST user-search-service/api/v3/search { query, pageNumber, mode } + store_id headers
// Recipe reconstructed from public repos (tanishq-y/android, DebadityaHait/ShopLense,
// vedant-2525/QuickCompare, Garvitx/assigment-node) and verified live from this host.
//
// Prices are returned in PAISE (mrp:46000 == Rs 460.00) -> divide by 100.
// We keep only products whose product.brand == "Jivo" (excludes "Jivika"/"Tata" etc).
// Output schema is identical to Blinkit so build_excel.py works unchanged.
//
// FRESHNESS (2026-06-03): the owner saw the API lag a real price change by ~1 day. Recon
// confirmed there is NO read-only PDP/product-price route on this gateway (every product/
// inventory/pdp path 404s "no Route matched"; only cart-service exists and needs a stateful
// guest-cart mutation — unfit for a 332-store loop). BUT the search response is itself
// authoritative when its per-product `cached` flag is false (then it equals the live app
// price), and it already carries the structured per-tier price in pricingData. So the fix is:
//   (1) record the price from pricingData.pricingEntityPrices[tier] (the exact app-rendered
//       tier price) instead of the ambiguous top-level fallback chain;
//   (2) capture the per-store realtime signal (is_realtime_model_data_fetched / reason, the true
//       lag indicator — NOT the always-false `cached` flag) into summary.freshness; and
//   (3) raise a staleness alarm (tools/review.py): SUSPECT when a SKU's modal price is frozen
//       across many runs while stores are served from the non-realtime (snapshot) path.
// ---------------------------------------------------------------------------

const { execFile } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const uuid = () => crypto.randomUUID();

// PINCODES_FILE / OUT_FILE let a caller scrape a subset to a separate output
// (used for the parallel split-scrape); both default to the in-folder files so
// the cron call `node scrape.js` keeps running the full default set unchanged.
const PFILE = process.env.PINCODES_FILE || (__dirname + '/pincodes.json');
const OUTFILE = process.env.OUT_FILE || (__dirname + '/result.json');
const PINCODES = JSON.parse(fs.readFileSync(PFILE, 'utf8'));
const CONCURRENCY = parseInt(process.env.CONCURRENCY || '3', 10);
const MAX_PAGES = 4;            // page 0..3 for the bare-brand query; all in-stock Jivo ranks on page 0
// The bare-brand "jivo" search is gated to IN-STOCK products (oos_products_shown_count=0), so it
// silently omits chronically-OOS Jivo SKUs: Extra Virgin Olive Oil 1L, Pomace Olive Oil 5L, the
// single-2L Pomace bottle, the Extra Light 2L, Canola combo, etc. Those reappear under SECONDARY
// queries that add a category/size term. We use BRAND-SCOPED queries ("jivo olive oil", "jivo 5l",
// …) rather than bare-category ones ("olive oil"): brand-scoped keeps Jivo on page 0-1 (reliable +
// cheap, ~8 results), whereas bare-category buries Jivo on pages 5-6 of 7 amid hundreds of competitor
// products (unreliable + expensive — empirically it missed Pomace 5L / EV 1L at the Saket store the
// brand-scoped set recovered). Set matches A1's live-verified minimal recovery set. Each query is
// full-swept to its first empty page (no early-break) up to CAT_MAX_PAGES; deduped per-store by
// canonical against the bare-"jivo" results, so in-stock prices are untouched and OOS SKUs only ADD.
// Override/disable via env (ZEPTO_CATEGORY_QUERIES='' turns the secondary sweep off, brand-only).
const CAT_QUERIES = (process.env.ZEPTO_CATEGORY_QUERIES !== undefined
  ? process.env.ZEPTO_CATEGORY_QUERIES : 'jivo olive oil,jivo oil 5 litre,jivo 5l,jivo 2l,jivo pomace')
  .split(',').map(s => s.trim()).filter(Boolean);
const CAT_MAX_PAGES = parseInt(process.env.ZEPTO_CAT_MAX_PAGES || '6', 10);
// SEED VARIANTS — the catalog-completeness fix (2026-06-04, zcat).
// Zepto's search (Algolia) HIDES whole pack-size variants: it collapses a product's pack-size
// siblings into ONE representative variant (variant-rollup) and the bare-brand query is in-stock-
// gated. So large/OOS/rollup-hidden SKUs never surface in search under ANY query — e.g. the owner's
// Kachi Ghani Mustard 5 L (in stock, MRP 1250), Sunflower 5 L, Canola 5 L, Gold blend, Rice Bran,
// So-Olive, etc. We recover them deterministically: jivo_variants.json holds their (catalog-global)
// variantIds, and for each serviceable store we hit the PDP route get_page?page_type=PDP&product_
// variant_id=<id> (Agent-1's endpoint) for AUTHORITATIVE per-store price + availableQuantity, incl.
// OOS. variantIds come from the public zepto.com /pvid/<id> index + live PDP verification (no proxy,
// no login; the gateway PDP route is reachable from the DC IP). Rows merge with the search rows and
// dedup BY VARIANT ID (PDP wins — it also corrects search's wrong oos:true / stale price on the few
// large variants search does surface, e.g. Pomace 5 L). Disable with ZEPTO_SEED_VARIANTS=0.
const SEED_ENABLED = process.env.ZEPTO_SEED_VARIANTS !== '0';
let SEED_VARIANTS = [];
if (SEED_ENABLED) {
  try {
    const sv = JSON.parse(fs.readFileSync(__dirname + '/jivo_variants.json', 'utf8'));
    SEED_VARIANTS = (sv && Array.isArray(sv.variants) ? sv.variants : []).filter(v => v && v.variantId);
  } catch (e) { process.stderr.write(`[warn] seed variants not loaded: ${e.message}\n`); }
}
const GW = 'https://bff-gateway.zeptonow.com';
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';
const COMPAT = 'CONVENIENCE_FEE,RAIN_FEE,EXTERNAL_COUPONS,STANDSTILL,BUNDLE,MULTI_SELLER_ENABLED,PIP_V1,ROLLUPS,SCHEDULED_DELIVERY,SAMPLING_ENABLED,HOMEPAGE_V2,NEW_ETA_BANNER,SUPER_SAVER:1,PROMO_CASH:0,24X7_ENABLED_V1,HP_V4_FEED,NEW_ROLLUPS_ENABLED,PLP_ON_SEARCH,DYNAMIC_FILTERS,NEW_FEE_STRUCTURE,NEW_BILL_INFO,SUPERSTORE_V1,MARKETPLACE_REPLACEMENT';
// Zepto runs TWO storefronts over the SAME catalogue at the SAME store, with DIFFERENT
// prices for the identical SKU, selected purely by the `marketplace_type` header:
//   SUPER_SAVER  = scheduled delivery, cheaper  (e.g. Canola combo 469)  <- the price the app shows by default
//   ZEPTO_NOW    = instant ~10-min delivery     (e.g. Canola combo 485)
// We track SUPER_SAVER because that is the price customers (and our reference checks)
// actually see. Override with ZEPTO_MARKETPLACE=ZEPTO_NOW to capture the instant tier.
const MARKETPLACE = process.env.ZEPTO_MARKETPLACE || 'SUPER_SAVER';

// ---- COMPETITOR MODE (env-gated; additive; 2026-06-30) ---------------------------
// OFF by default. When process.env.COMPETITOR_MODE === '1' the scraper STOPS being
// jivo-only: it (1) runs extra bare-CATEGORY search queries IN ADDITION to the normal
// 'jivo' + brand-scoped sweeps, (2) keeps any row whose clean brand field OR name
// matches the competitor whitelist regex (tools/competitor/competitor_brands.json)
// instead of jivo-only, (3) tags every kept row brand+category+sub_grade+rank+is_ad,
// and (4) writes ONLY under tools/competitor/data/ (never the mailer-globbed jivo
// result.json). With the flag UNSET every branch below is skipped and behavior is
// byte-for-byte the live jivo path. Never cron-wired; see tools/competitor/COMPETITOR-PLAN.md.
const COMPETITOR = process.env.COMPETITOR_MODE === '1';
// IST calendar date drives the dated output filename + the history CSV date_ist column.
const COMP_DATE_IST = new Date(Date.now() + 5.5 * 3600 * 1000).toISOString().slice(0, 10);
const COMP_DIR = __dirname + '/../../tools/competitor/data';
let COMP_WHITELIST = /jivo/i;
let COMP_QUERIES = ['olive oil', 'mustard oil', 'sunflower oil', 'canola oil',
  'rice bran oil', 'groundnut oil', 'soyabean oil', 'blended oil'];
if (COMPETITOR) {
  try {
    const cb = JSON.parse(fs.readFileSync(__dirname + '/../../tools/competitor/competitor_brands.json', 'utf8'));
    if (cb && cb.whitelist_regex) COMP_WHITELIST = new RegExp(cb.whitelist_regex, 'i');
  } catch (e) { process.stderr.write(`[competitor] brand whitelist load failed (${e.message}); falling back to /jivo/i\n`); }
  try {
    const cq = JSON.parse(fs.readFileSync(__dirname + '/../../tools/competitor/category_queries.json', 'utf8'));
    if (cq && Array.isArray(cq.queries) && cq.queries.length) COMP_QUERIES = cq.queries.slice();
  } catch (e) { process.stderr.write(`[competitor] category_queries load failed (${e.message}); using built-in list\n`); }
}
const COMP_DENSITY = { oil: 0.916, ghee: 0.91 };
// brand: trust the clean product.brand; fall back to the first whitelist hit in the name.
function compBrand(brand, name) {
  const b = (brand || '').trim();
  if (b) return b;
  const m = COMP_WHITELIST.exec((name || '').toLowerCase());
  return m ? m[0].replace(/\s+/g, ' ').trim() : '';
}
// category: prefer the category the surfacing query implies; else infer from the name.
function compCategory(name, queryCat) {
  if (queryCat) return queryCat;
  const s = (name || '').toLowerCase();
  if (/olive/.test(s)) return 'olive';
  if (/mustard|kachi ?ghani|sarso(n)?/.test(s)) return 'mustard';
  if (/sunflower/.test(s)) return 'sunflower';
  if (/canola/.test(s)) return 'canola';
  if (/rice ?bran/.test(s)) return 'rice_bran';
  if (/groundnut|peanut/.test(s)) return 'groundnut';
  if (/soyabean|soybean|soya/.test(s)) return 'soyabean';
  if (/sesame|gingelly|\btil\b/.test(s)) return 'sesame';
  if (/ghee/.test(s)) return 'ghee';
  if (/blend|so-?olive|\bgold\b/.test(s)) return 'blended';
  return '';
}
// olive splits into price tiers that must never be compared across; null for non-olive.
function compSubGrade(name, category) {
  if (category !== 'olive') return null;
  const s = (name || '').toLowerCase();
  if (/extra ?virgin/.test(s)) return 'extra_virgin';
  if (/extra ?light|extralight/.test(s)) return 'extra_light';
  if (/pomace/.test(s)) return 'pomace';
  if (/\bpure\b/.test(s)) return 'pure';
  return null;
}
// unit of the pack AS LABELLED: grams when it carries g/kg and no ml/l token, else ml.
function compUnit(pack) {
  const s = (pack || '').toLowerCase();
  if (/\b(kg|g|gram|grams|kilogram)\b/.test(s) && !/\b(ml|l|ltr|litre|litres)\b/.test(s)) return 'g';
  return 'ml';
}
// best-effort sponsored-listing flag: probe the product node + its search-result parent for an
// ad/sponsored marker. Honest default 0 (Zepto's live ad field is unconfirmed from this host).
function compDetectAd(pr) {
  const hit = (o) => {
    if (!o || typeof o !== 'object') return false;
    for (const k of Object.keys(o)) {
      if (/^(is_?ad|isad|sponsored|is_?sponsored|ad_?id|adid)$/i.test(k)) {
        const v = o[k];
        if (v === true || (typeof v === 'number' && v > 0) || (typeof v === 'string' && v && v !== 'false')) return true;
      }
    }
    return false;
  };
  return (hit(pr) || hit(pr && pr.meta) || hit(pr && pr.__node)) ? 1 : 0;
}
// Project an internal row to the shared COMPETITOR ROW CONTRACT, converting grams->ml by
// oil/ghee density so per_litre reflects ACTUAL contents (the 910 g-as-1L pack-deflation trap).
function toCompetitorRow(row) {
  const unit = compUnit(row.pack);
  const cat = row.category || '';
  const density = cat === 'ghee' ? COMP_DENSITY.ghee : COMP_DENSITY.oil;
  let volMl = row.vol_ml;
  if (unit === 'g' && volMl != null) volMl = Math.round(volMl / density);
  const sale = row.sale != null ? row.sale : null;
  const perLitre = (volMl && sale != null) ? Math.round((sale / (volMl / 1000)) * 100) / 100 : null;
  return {
    platform: 'zepto',
    city: row.city, pincode: row.pincode,
    store_id: row.store_id, store_name: row.store_name || '',
    brand: row.brand || '', name: row.sku_raw || '', canonical: row.canonical,
    category: cat, sub_grade: (row.sub_grade != null ? row.sub_grade : null),
    pack: row.pack, vol_ml: volMl, unit,
    per_litre: perLitre, mrp: row.mrp != null ? row.mrp : null, sale,
    discount_pct: row.discount_pct != null ? row.discount_pct : null,
    in_stock: row.in_stock ? 1 : 0,
    rank: row.rank != null ? row.rank : null, is_ad: row.is_ad ? 1 : 0,
    captured_at: row.captured_at || new Date().toISOString(),
  };
}
// Write the competitor run result + append the rolling history CSV. ONLY tools/competitor/data/
// (never result.json / data|vault|reviews|baselines, which the cron git-adds).
function writeCompetitorOutputs(summary, allRows, partial) {
  try { fs.mkdirSync(COMP_DIR, { recursive: true }); } catch (_) { /* already exists */ }
  const compRows = allRows.map(toCompetitorRow);
  const runId = 'zepto-' + new Date(Date.now() + 5.5 * 3600 * 1000).toISOString().replace(/[-:T]/g, '').slice(0, 14);
  const byBrand = {};
  for (const r of compRows) { const b = r.brand || 'unknown'; byBrand[b] = (byBrand[b] || 0) + 1; }
  const compSummary = Object.assign({}, summary, {
    platform: 'zepto', mode: 'competitor', run_id: runId, date_ist: COMP_DATE_IST, partial,
    competitor_rows: compRows.length,
    brands: Array.from(new Set(compRows.map(r => r.brand).filter(Boolean))).sort(),
    categories: Array.from(new Set(compRows.map(r => r.category).filter(Boolean))).sort(),
    rows_by_brand: byBrand,
  });
  const outPath = COMP_DIR + '/zepto_competitor_' + COMP_DATE_IST + '.json';
  fs.writeFileSync(outPath, JSON.stringify({ summary: compSummary, allRows: compRows }, null, 2));
  process.stderr.write(`[competitor] wrote ${compRows.length} rows -> ${outPath}\n`);
  const csvPath = COMP_DIR + '/competitor_history.csv';
  const header = 'run_id,date_ist,platform,brand,category,canonical,city,pincode,store_id,pack,vol_ml,per_litre,mrp,sale,discount_pct,in_stock,rank,is_ad\n';
  const esc = (v) => {
    if (v == null) return '';
    const s = String(v);
    return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
  };
  const lines = compRows.map(r => [runId, COMP_DATE_IST, 'zepto', r.brand, r.category, r.canonical,
    r.city, r.pincode, r.store_id, r.pack, r.vol_ml, r.per_litre, r.mrp, r.sale, r.discount_pct,
    r.in_stock, r.rank, r.is_ad].map(esc).join(','));
  fs.appendFileSync(csvPath, (fs.existsSync(csvPath) ? '' : header) + (lines.length ? lines.join('\n') + '\n' : ''));
  process.stderr.write(`[competitor] appended ${lines.length} rows -> ${csvPath}\n`);
}
// ---------------------------------------------------------------------------------

// ---- Hardening (Wave-1 coverage pilot, 2026-06-29) -------------------------------
// At up to 1,885 pincodes a run is long, so it MUST survive interruption and rate-
// limiting without losing work or throwing. Three additions, all opt-in / fail-safe,
// mirroring the proven Blinkit pilot (commit c4ab885d5) but adapted to Zepto's
// curl/BFF-API structure (no browser — blocks show up as HTTP status + body markers):
//   (1) checkpoint/resume — per-pincode result cached in .progress.<date>.json; a
//       re-run the same day skips finished pincodes and resumes where it stopped.
//   (2) block-detection + exponential backoff — a 403/429/503 or an Akamai/"access
//       denied"/captcha body on the per-pincode entry calls (store-resolution +
//       primary search) is treated as a block: back off (capped) and retry a few
//       times, then record 0 rows and flag the run partial (NEVER evade — owner rule).
//   (3) partial tolerance — one pincode can never kill the run; result.json always
//       gets written with a top-level `partial` flag so the batch wrapper sees it.
// SIM hooks (ZEPTO_SIM / ZEPTO_BLOCK_SIM) drive the hermetic fault-injection tests in
// test_hardening.md without hitting Zepto live.
const PROG = `${__dirname}/.progress.${COMPETITOR ? 'competitor.' : ''}${new Date().toISOString().slice(0, 10)}.json`;
const MAX_BLOCK_RETRIES = parseInt(process.env.ZEPTO_BLOCK_RETRIES || '4', 10);
// Body signatures of a block page. Deliberately specific (NOT bare "403"/"429",
// which could legitimately appear in JSON payloads) — HTTP status carries those.
const BLOCK_RE = /access denied|akamai|reference #\s*\d|too many requests|rate[\s-]?limit|are you a human|captcha|forbidden|cloudfront|request blocked/i;
// A blocked HTTP status (curl returns the code as a string). 429 is the gateway's
// rate-limit; 403/503 are the CloudFront/WAF block the DC IP already sees on the edge.
function isBlockStatus(s) { return s === '403' || s === '429' || s === '503'; }
// Classify an HTTP result {status, body} as blocked. Returns a reason string or null.
function classifyBlock(status, body) {
  if (isBlockStatus(status)) return `http ${status}`;
  if (body && BLOCK_RE.test(String(body).slice(0, 5000))) return 'block-signature';
  return null;
}

async function backoff(attempt) {
  const ms = Math.min(60000, 2000 * Math.pow(2, attempt)) + Math.floor(Math.random() * 1000);
  process.stderr.write(`[backoff] attempt ${attempt} -> sleeping ${Math.round(ms)}ms\n`);
  await new Promise((r) => setTimeout(r, ms));
}

function loadProgress() {
  try { return fs.existsSync(PROG) ? JSON.parse(fs.readFileSync(PROG, 'utf8')) : {}; }
  catch (_) { return {}; }
}
function saveProgress(done) {
  try { fs.writeFileSync(PROG, JSON.stringify(done)); }
  catch (e) { process.stderr.write(`[progress] write failed: ${e.message}\n`); }
}

// --- price/pack helpers (same conventions as the other platforms) ---
function parseVolMl(pack) {
  if (!pack) return null;
  const s = pack.toLowerCase();
  // 'm' = Zepto's truncated 'ml' (it clips formattedPacksize at a fixed width, so "200 ml"
  // renders as "200 m"). Placed LAST in every alternation so it never shadows 'ml'/'l'.
  const toMl = (n, u) => {
    if (u === 'ml' || u === 'm' || u === 'g') return n;
    if (u === 'l' || u === 'ltr' || u === 'litre' || u === 'litres' || u === 'kg') return n * 1000;
    return null;
  };
  // Multiplier packs ("combos"): "N L X M" / "N ml x M" => N*M of the unit (e.g. 1 L X 2 = 2 L).
  // Must run BEFORE the single-quantity match, which would otherwise read only the first "1 L".
  let m = s.match(/([\d.]+)\s*(ml|l|ltr|litre|litres|kg|g|m)\b\s*[x×]\s*([\d.]+)/);
  if (m) { const base = toMl(parseFloat(m[1]), m[2]); return base != null ? base * parseFloat(m[3]) : null; }
  // Multiplier-FIRST combos: "M x N unit" ("2 x 1 L", "2x1L", "3 x 500 ml") => M*N of the unit.
  // Zepto renders the SAME variant either way depending on the store ("1 L X 2" vs "2 x 1 L"),
  // so both orders are required; reviewers' parse_total_vol_ml already handles both.
  m = s.match(/([\d.]+)\s*[x×]\s*([\d.]+)\s*(ml|l|ltr|litre|litres|kg|g|m)\b/);
  if (m) { const base = toMl(parseFloat(m[2]), m[3]); return base != null ? parseFloat(m[1]) * base : null; }
  // Additive packs: "A+B L" / "1L+1L+1L" / "1 + 1 + 1 Litres" => sum of ALL addends
  // (Jivo sells 2- and 3-oil packs; a 1+1+1 legitimately price-matches a 3 L). A term
  // without its own unit inherits the chain's trailing unit ("1+1 Litres").
  m = s.match(/(?:[\d.]+\s*(?:ml|ltr|litres|litre|l|kg|g|m)?\s*\+\s*)+[\d.]+\s*(ml|ltr|litres|litre|l|kg|g|m)\b/);
  if (m) {
    let tot = 0;
    for (const t of m[0].split('+')) {
      const tm = t.trim().match(/^([\d.]+)\s*(ml|ltr|litres|litre|l|kg|g|m)?\s*$/);
      const add = tm ? toMl(parseFloat(tm[1]), tm[2] || m[1]) : null;
      if (add == null) { tot = null; break; }
      tot += add;
    }
    if (tot) return tot;
  }
  // Single quantity: "1 L", "200 ml", "1 pc (1 L)", "1 Pack(200 m)".
  m = s.match(/([\d.]+)\s*(ml|l|ltr|litre|litres|kg|g|m)\b/);
  if (m) return toMl(parseFloat(m[1]), m[2]);
  return null;
}
// Volume from the variant's STRUCTURED fields (packsize + unitOfMeasure), which are immune to
// the display-string truncation that breaks formattedPacksize (e.g. "1 Pack(200 m)"). packsize
// is USUALLY the TOTAL volume in unitOfMeasure units ("1 L X 2" reports packsize=2/LITER) — but
// some store catalogs report the UNIT size instead (packsize=1/LITER on "2 x 1 L"; held the
// 2026-06-10 sheets: vol 1000 ml on a 2 L combo split the canonical and doubled per_litre). The
// display string can only ever UNDERSTATE (truncation), never overstate, so when both sources
// parse, the larger one is the true total.
function volFromVariant(v, pack) {
  const ps = v && v.packsize;
  const u = v && String(v.unitOfMeasure || '').toLowerCase();
  let structured = null;
  if (ps != null && u) {
    if (/^milli/.test(u) || u === 'ml') structured = ps;            // MILLILITRE
    else if (/^lit(er|re)/.test(u) || u === 'l') structured = ps * 1000; // LITER / LITRE
    else if (/^gram/.test(u) || u === 'g') structured = ps;              // GRAM
    else if (/^kilo/.test(u) || u === 'kg') structured = ps * 1000;      // KILOGRAM
  }
  const parsed = parseVolMl(pack);
  if (structured != null && parsed != null) return Math.max(structured, parsed);
  return structured != null ? structured : parsed;
}
// Canonical slug = slugify(product.name) + volume tag. The vol is precomputed (see volFromVariant)
// so the tag is correct even when the display pack string is truncated. NOTE: distinct products that
// share a volume (single 2L bottle vs 2x1L combo, both -> "2l") stay separate ONLY via their names
// ("Daily" vs "Combo"), which Zepto returns consistently per product.
function canonical(name, vol) {
  const base = (name || '').toLowerCase().replace(/\(.*?\)/g, '').replace(/[^a-z0-9 ]/g, '')
    .replace(/\s+/g, ' ').trim().replace(/\s/g, '-');
  const volTag = vol ? (vol >= 1000 ? (vol / 1000) + 'l' : vol + 'ml') : 'na';
  return `${base}-${volTag}`.replace(/--+/g, '-');
}

// --- low-level: run curl, return {status, body} (Node fetch is flaky on this host) ---
function curl(args) {
  return new Promise((resolve) => {
    execFile('curl', args, { maxBuffer: 128 * 1024 * 1024, encoding: 'utf8' }, (err, stdout) => {
      const out = stdout || '';
      const i = out.lastIndexOf('__HTTP__');
      resolve({ status: i >= 0 ? out.slice(i + 8).trim() : (err ? 'ERR' : '?'), body: i >= 0 ? out.slice(0, i) : out });
    });
  });
}
function commonHeaders(storeId, lat, lon) {
  const sid = uuid(), did = uuid(), rid = uuid();
  const h = {
    'accept': 'application/json, text/plain, */*', 'accept-language': 'en-US,en;q=0.9',
    'app_sub_platform': 'WEB', 'app_version': '12.64.1', 'appversion': '12.64.1',
    'auth_revamp_flow': 'v2', 'compatible_components': COMPAT, 'content-type': 'application/json',
    'device_id': did, 'deviceid': did, 'marketplace_type': MARKETPLACE,
    'origin': 'https://www.zeptonow.com', 'platform': 'WEB', 'referer': 'https://www.zeptonow.com/',
    'request_id': rid, 'requestid': rid, 'session_id': sid, 'sessionid': sid,
    'tenant': 'ZEPTO', 'x-without-bearer': 'true', 'user-agent': UA,
    'x-latitude': String(lat), 'x-longitude': String(lon), 'latitude': String(lat), 'longitude': String(lon),
  };
  if (storeId) {
    h['store_id'] = storeId; h['store_ids'] = storeId; h['storeid'] = storeId;
    h['store_etas'] = `{"${storeId}":10}`;
  }
  return h;
}
function hdrArgs(h) { const a = []; for (const [k, v] of Object.entries(h)) a.push('-H', `${k}: ${v}`); return a; }

async function resolveStore(lat, lon) {
  const url = `${GW}/serviceability-service/api/v1/serviceability?lat=${lat}&long=${lon}`;
  const args = ['-s', '--max-time', '25', '-w', '\n__HTTP__%{http_code}', ...hdrArgs(commonHeaders(null, lat, lon)), url];
  const r = await curl(args);
  if (r.status !== '200') {
    // A 403/429/503 (or a block-signature body) on the per-pincode ENTRY call means the
    // gateway is blocking/rate-limiting this IP — surface it so scrapeWithBackoff retries.
    const blocked = classifyBlock(r.status, r.body);
    return { ok: false, status: r.status, blocked };
  }
  let j; try { j = JSON.parse(r.body); } catch { return { ok: false, status: 'badjson' }; }
  // Response shape: { errors:[], data:{ serviceable:bool, stores:[{storeId, serviceable, storeConstruct}] } }
  const data = j.data || {};
  const serviceable = !!data.serviceable;
  let storeId = null;
  if (Array.isArray(data.stores)) {
    const s = data.stores.find(x => x && x.serviceable && /PRIMARY/i.test(x.storeConstruct || ''))
      || data.stores.find(x => x && x.serviceable)
      || data.stores[0];
    storeId = s && s.storeId;
  }
  return { ok: !!(serviceable && storeId), serviceable, storeId };
}

// Pull the response-level freshness markers Zepto's search service emits. These tell us whether
// the catalogue we just read came from a live fetch or a cache/snapshot:
//   is_realtime_model_data_fetched / realtime_model_not_enabled_reason / algoliaTimeOut
function findMarkers(j) {
  const m = {};
  (function walk(o, depth) {
    if (!o || typeof o !== 'object' || depth > 6) return;
    for (const k of Object.keys(o)) {
      if (/^(is_realtime_model_data_fetched|realtime_model_not_enabled_reason|algoliaTimeOut)$/.test(k)
        && !(k in m)) m[k] = o[k];
      const v = o[k];
      if (v && typeof v === 'object' && k !== 'productResponse') walk(v, depth + 1);
    }
  })(j, 0);
  return m;
}

async function searchPage(storeId, lat, lon, query, pageNumber) {
  const url = `${GW}/user-search-service/api/v3/search`;
  // The gateway 429-rate-limits aggressive bursts (~>5 req/s). The multi-query category sweep
  // multiplies request volume, so retry 429s with exponential backoff before giving up.
  let r;
  for (let attempt = 0; attempt < 4; attempt++) {
    const body = JSON.stringify({ query, pageNumber, intentId: uuid(), mode: 'AUTOSUGGEST', userSessionId: uuid() });
    const args = ['-s', '--max-time', '30', '-X', 'POST', '-w', '\n__HTTP__%{http_code}',
      ...hdrArgs(commonHeaders(storeId, lat, lon)), '--data', body, url];
    r = await curl(args);
    if (r.status !== '429') break;
    await new Promise(res => setTimeout(res, 1500 * (attempt + 1) + Math.random() * 1500));
  }
  if (r.status !== '200') return { ok: false, status: r.status, items: [], blocked: classifyBlock(r.status, r.body) };
  let j; try { j = JSON.parse(r.body); } catch { return { ok: false, status: 'badjson', items: [] }; }
  const items = [];
  (function walk(o) {
    if (!o || typeof o !== 'object') return;
    const pr = o.productResponse;
    if (pr && pr.product && pr.product.name) {
      // competitor mode only: stash the search-result parent node (non-enumerable, so it never
      // serializes) so compDetectAd can probe it for a sponsored/ad marker. No-op when OFF.
      if (COMPETITOR) { try { Object.defineProperty(pr, '__node', { value: o, enumerable: false, configurable: true }); } catch (_) { /* frozen */ } }
      items.push(pr);
    }
    for (const k of Object.keys(o)) { const v = o[k]; if (v && typeof v === 'object') walk(v); }
  })(j);
  return { ok: true, items, markers: findMarkers(j) };
}

// Fetch a single variant's PDP (the catalog-completeness recovery path). Returns the productInfo
// object { product, productVariant, storeProduct } or null. A 404 ("Product not found in store")
// means this store does not carry the variant -> null (no row, correctly). 429-backoff like search.
async function fetchPdp(storeId, lat, lon, variantId) {
  const url = `${GW}/lms/api/v2/get_page?page_type=PDP&product_variant_id=${variantId}`
    + `&latitude=${lat}&longitude=${lon}&store_id=${storeId}`;
  let r;
  for (let attempt = 0; attempt < 4; attempt++) {
    const args = ['-s', '--max-time', '30', '-w', '\n__HTTP__%{http_code}',
      ...hdrArgs(commonHeaders(storeId, lat, lon)), url];
    r = await curl(args);
    if (r.status !== '429') break;
    await new Promise(res => setTimeout(res, 1500 * (attempt + 1) + Math.random() * 1500));
  }
  if (r.status !== '200') return null;          // 404 = not carried at this store; other = transient
  let j; try { j = JSON.parse(r.body); } catch { return null; }
  const widgets = (j.pageLayout && j.pageLayout.widgets) || [];
  const w = widgets.find(x => x && x.widgetType === 'PRODUCT_INFO');
  const pi = w && w.data && w.data.productInfo;
  return (pi && pi.productVariant) ? pi : null;
}

// Authoritative per-tier price from the PDP storeProduct (same shape/precedence as tierPrice for
// search, but the pricingData lives under storeProduct here).
function tierPriceSP(sp, mk) {
  const pe = (sp.pricingData && sp.pricingData.pricingEntityPrices) || [];
  const hit = pe.find(x => x && x.pricingEntity === mk && x.discountedSellingPrice != null);
  return hit ? hit.discountedSellingPrice : null;
}

// Build a row from a PDP productInfo. Stock is authoritative: availableQuantity > 0 == in stock
// (there is NO outOfStock bool in the PDP payload). OOS variants keep their listed price but are
// flagged in_stock=0 (build_excel's cheapest picker / review's price-band check both skip OOS rows).
function pdpToRow(pi, rec, storeId, seed) {
  const p = pi.product || {}, v = pi.productVariant || {}, sp = pi.storeProduct || {};
  const name = p.name || (seed && seed.name) || '';
  const pack = v.formattedPacksize || (seed && seed.pack) || '';
  const mrp = sp.mrp != null ? sp.mrp / 100 : null;
  let sale = tierPriceSP(sp, MARKETPLACE);
  let priceSource = sale != null ? 'pdp:pricingData:' + MARKETPLACE : null;
  if (sale == null && MARKETPLACE === 'SUPER_SAVER' && sp.superSaverSellingPrice != null) {
    sale = sp.superSaverSellingPrice; priceSource = 'pdp:superSaverSellingPrice';
  }
  if (sale == null && sp.discountedSellingPrice != null) {
    sale = sp.discountedSellingPrice; priceSource = 'pdp:discountedSellingPrice';
  }
  const saleR = sale != null ? sale / 100 : null;
  const vol = volFromVariant(v, pack);
  const inStock = (sp.availableQuantity != null && sp.availableQuantity > 0) ? 1 : 0;
  const row = {
    city: rec.city, pincode: rec.pincode, locality: rec.locality,
    store_id: storeId, store_name: '',
    product_id: (p && p.id) || (seed && seed.productId) || null, variant_id: v.id || (seed && seed.variantId) || null,
    sku_raw: name, canonical: canonical(name, vol), pack,
    vol_ml: vol, sale: saleR, mrp,
    discount_pct: (mrp && saleR && mrp >= saleR) ? Math.round(((mrp - saleR) / mrp) * 1000) / 10
      : (sp.discountPercent != null ? sp.discountPercent : null),
    per_litre: (vol && saleR) ? Math.round((saleR / (vol / 1000)) * 100) / 100 : null,
    eta_min: null,
    in_stock: inStock,
    cached: false,            // PDP is a live per-store fetch, never the search cache
    price_source: priceSource,
    source: 'pdp_seed',       // provenance: recovered via the seed-variant PDP pass (vs search)
  };
  if (COMPETITOR) {
    // PDP rows are not from a ranked search response -> no rank / ad signal.
    const category = compCategory(name, null);
    row.brand = compBrand((p && p.brand) || '', name);
    row.category = category;
    row.sub_grade = compSubGrade(name, category);
    row.rank = null;
    row.is_ad = 0;
    row.captured_at = new Date().toISOString();
  }
  return row;
}

// Authoritative per-tier price. Zepto's response carries pricingData.pricingEntityPrices —
// an explicit { pricingEntity, discountedSellingPrice } per storefront tier (SUPER_SAVER /
// ULTRA_SAVER / ...). That is the structured price the app actually renders for the selected
// tier, so we PREFER it over the ambiguous top-level discountedSellingPrice fallback chain
// (which is tier-dependent and easy to mis-read). This removes the "wrong tier" class of error.
function tierPrice(pr, mk) {
  const pe = (pr.pricingData && pr.pricingData.pricingEntityPrices) || [];
  const hit = pe.find(x => x && x.pricingEntity === mk && x.discountedSellingPrice != null);
  return hit ? hit.discountedSellingPrice : null;
}

function toRow(pr, rec, storeId, ctx) {
  const p = pr.product, v = pr.productVariant || {};
  const name = p.name;
  const pack = v.formattedPacksize || '';
  const mrp = pr.mrp != null ? pr.mrp / 100 : (v.mrp != null ? v.mrp / 100 : null);
  // Price source, most-authoritative first: explicit tier price -> tier-specific field
  // (superSaver) -> generic discounted/selling chain. price_source records which one we used
  // so a stale/odd value can be traced back to its origin field.
  let sale = tierPrice(pr, MARKETPLACE);
  let priceSource = sale != null ? 'pricingData:' + MARKETPLACE : null;
  if (sale == null && MARKETPLACE === 'SUPER_SAVER' && pr.superSaverSellingPrice != null) {
    sale = pr.superSaverSellingPrice; priceSource = 'superSaverSellingPrice';
  }
  if (sale == null) {
    sale = pr.discountedSellingPrice != null ? pr.discountedSellingPrice
      : pr.sellingPrice != null ? pr.sellingPrice : pr.superSaverSellingPrice;
    priceSource = pr.discountedSellingPrice != null ? 'discountedSellingPrice'
      : pr.sellingPrice != null ? 'sellingPrice' : 'superSaverSellingPrice';
  }
  const saleR = sale != null ? sale / 100 : null;
  const vol = volFromVariant(v, pack);
  const inStock = pr.outOfStock === true ? 0 : 1;
  const row = {
    city: rec.city, pincode: rec.pincode, locality: rec.locality,
    store_id: storeId, store_name: '',
    // Stable Zepto identifiers, persisted for traceability / future variantId-keyed canonicalization.
    product_id: (p && p.id) || null, variant_id: v.id || null,
    sku_raw: name, canonical: canonical(name, vol), pack,
    vol_ml: vol, sale: saleR, mrp,
    discount_pct: (mrp && saleR && mrp >= saleR) ? Math.round(((mrp - saleR) / mrp) * 1000) / 10
      : (pr.discountPercent != null ? pr.discountPercent : null),
    per_litre: (vol && saleR) ? Math.round((saleR / (vol / 1000)) * 100) / 100 : null,
    eta_min: null,
    in_stock: inStock,
    // Freshness signal: Zepto sets cached=true when this product was served from its search
    // cache (a stale-price risk) and false when it was fetched live. Recorded so the review
    // step can raise a staleness alarm. price_source aids debugging odd values.
    cached: pr.cached === true,
    price_source: priceSource,
  };
  if (COMPETITOR) {
    // ctx carries the surfacing query's implied category + the 1-based search rank + ad flag.
    const category = compCategory(name, ctx && ctx.category);
    row.brand = compBrand((p && p.brand) || '', name);
    row.category = category;
    row.sub_grade = compSubGrade(name, category);
    row.rank = ctx && ctx.rank != null ? ctx.rank : null;
    row.is_ad = ctx && ctx.isAd ? 1 : 0;
    row.captured_at = new Date().toISOString();
  }
  return row;
}

// Run one search query across its pages, appending genuine-Jivo rows into `rows` and deduping by
// per-store canonical against `seenCanon` (shared across all queries for the store, so a SKU seen
// under "jivo" is not re-added by a category query). Returns the page-0 freshness markers.
//   opts.maxPages   how many pages to walk
//   opts.earlyBreak stop once a page (after page 0) adds no NEW Jivo SKU (cheap; for the brand query
//                   where everything is on page 0). OFF for category queries, where Jivo is sparse
//                   and interleaved with blank pages, so we must full-sweep to the empty page.
async function collectQuery(rec, storeId, query, opts, seenCanon, rows) {
  let firstMarkers = null, blocked = null;
  const qCat = COMPETITOR ? compCategory(query) : null;  // category implied by a bare-category sweep
  let rank = 0;                                           // 1-based search position across the query's pages
  for (let pn = 0; pn < opts.maxPages; pn++) {
    const res = await searchPage(storeId, rec.lat, rec.lon, query, pn);
    if (pn === 0) { firstMarkers = res.markers || {}; blocked = res.blocked || null; }
    if (!res.ok || !res.items.length) break;
    let added = 0;
    for (const pr of res.items) {
      if (COMPETITOR) rank++;  // count EVERY returned item so rank reflects true search position
      // keep only genuine Jivo products (brand == Jivo, or name contains the
      // word "jivo"); excludes fuzzy matches like "Jivika", "Tata", "Saffola".
      const nm = (pr.product && pr.product.name) || '';
      const br = ((pr.product && pr.product.brand) || '').toLowerCase();
      if (COMPETITOR) {
        // competitor mode: keep any whitelisted brand (clean brand field OR name match)
        if (!COMP_WHITELIST.test(br) && !COMP_WHITELIST.test(nm)) continue;
      } else {
        if (br !== 'jivo' && !/\bjivo\b/i.test(nm)) continue;
      }
      const row = COMPETITOR
        ? toRow(pr, rec, storeId, { category: qCat, rank, isAd: compDetectAd(pr) })
        : toRow(pr, rec, storeId);
      const key = `${storeId}|${row.canonical}`;
      if (seenCanon.has(key)) continue;
      seenCanon.add(key); rows.push(row); added++;
    }
    if (opts.earlyBreak && added === 0 && pn > 0) break; // brand query: no new Jivo SKUs on this page
    await new Promise(r => setTimeout(r, 250 + Math.random() * 400));
  }
  return { markers: firstMarkers, blocked };
}

async function scrapeOne(rec) {
  const t0 = Date.now();
  // SIM hooks (tests only; never active in production runs — gated on env vars):
  //   ZEPTO_BLOCK_SIM=1 -> every pincode reports blocked (drives the backoff/partial test)
  //   ZEPTO_SIM=1       -> return a synthetic serviceable row without any network call (resume test)
  if (process.env.ZEPTO_BLOCK_SIM === '1') {
    await new Promise((r) => setTimeout(r, 10));
    return { ...rec, store_id: '', store_name: '', serviceable: false, blocked: 'sim-block', rows: [], freshness: { cached_rows: 0, markers: {} } };
  }
  if (process.env.ZEPTO_SIM === '1') {
    await new Promise((r) => setTimeout(r, 10));
    const rows = [{
      city: rec.city, pincode: rec.pincode, locality: rec.locality,
      store_id: 'sim', store_name: '', product_id: 'sim', variant_id: 'sim',
      sku_raw: 'Jivo Sim Oil', canonical: 'jivo-sim-oil-1l', pack: '1 L', vol_ml: 1000,
      sale: 199, mrp: 250, discount_pct: 20.4, per_litre: 199, eta_min: null,
      in_stock: 1, cached: false, price_source: 'sim', source: 'sim',
    }];
    return { ...rec, store_id: 'sim', store_name: '', serviceable: true, blocked: null, rows, freshness: { cached_rows: 0, markers: {} } };
  }
  let rows = [], storeId = '', serviceable = false, markers = {}, blocked = null;
  try {
    const st = await resolveStore(rec.lat, rec.lon);
    serviceable = st.serviceable; storeId = st.storeId || '';
    // The gateway blocked the per-pincode entry call -> propagate so scrapeWithBackoff retries.
    if (st.blocked) {
      blocked = st.blocked;
      process.stderr.write(`[blocked] ${rec.city} ${rec.pincode} -> ${blocked} on store-resolution\n`);
      return { ...rec, store_id: '', store_name: '', serviceable, blocked, rows: [], freshness: { cached_rows: 0, markers: {} } };
    }
    if (st.ok) {
      const seenCanon = new Set();
      // 1) Primary brand query — returns all in-stock Jivo SKUs (on page 0); keep the cheap early-break.
      //    Its page-0 markers are the store's freshness signal (unchanged from before).
      const primary = (await collectQuery(rec, storeId, 'jivo', { maxPages: MAX_PAGES, earlyBreak: true }, seenCanon, rows)) || {};
      markers = primary.markers || {};
      if (primary.blocked) {
        // A block on the primary search (after a clean store-resolve) is still a block:
        // surface it so we back off + retry rather than silently recording 0 Jivo SKUs.
        blocked = primary.blocked;
        process.stderr.write(`[blocked] ${rec.city} ${rec.pincode} -> ${blocked} on primary search\n`);
        return { ...rec, store_id: storeId, store_name: '', serviceable, blocked, rows: [], freshness: { cached_rows: 0, markers } };
      }
      // 2) Brand-scoped secondary queries — recover the chronically-OOS Jivo SKUs the bare-brand
      //    query suppresses (Extra Virgin 1L, Pomace 5L, single-2L Pomace bottle, …). Full-sweep to
      //    the first empty page (no early-break) so a SKU on page 1 isn't missed; deduped per-store.
      for (const cq of CAT_QUERIES) {
        await collectQuery(rec, storeId, cq, { maxPages: CAT_MAX_PAGES, earlyBreak: false }, seenCanon, rows);
      }
      // 2b) COMPETITOR sweep (env-gated) — bare-CATEGORY queries (olive oil, mustard oil, …) that
      //     surface rival brands in the SAME ranked response we already read for Jivo. Full-swept,
      //     deduped per-store by canonical (brand is encoded in the name -> dedup stays brand-safe).
      if (COMPETITOR) {
        for (const cq of COMP_QUERIES) {
          await collectQuery(rec, storeId, cq, { maxPages: CAT_MAX_PAGES, earlyBreak: false }, seenCanon, rows);
        }
      }
      // 3) SEED-VARIANT PDP PASS — recover rollup-hidden / OOS / large-pack variants that Zepto's
      //    search never emits under ANY query (Mustard 5 L, Sunflower 5 L, Canola 5 L, Gold blend,
      //    Rice Bran, So-Olive, …). For each known variantId hit the PDP route for authoritative
      //    per-store price + availableQuantity (incl. OOS). Dedup BY VARIANT ID, PDP overriding any
      //    search row for the same variant (PDP also corrects search's wrong oos/stale price on the
      //    few large variants search does surface, e.g. Pomace 5 L).
      if (SEED_VARIANTS.length) {
        const byVid = new Map();
        for (const r of rows) if (r.variant_id) byVid.set(r.variant_id, r);
        for (const seed of SEED_VARIANTS) {
          const pi = await fetchPdp(storeId, rec.lat, rec.lon, seed.variantId);
          if (!pi) continue;                                   // 404 -> not carried at this store
          const nm = (pi.product && pi.product.name) || seed.name || '';
          const br = ((pi.product && pi.product.brand) || '').toLowerCase();
          if (COMPETITOR) {
            if (!COMP_WHITELIST.test(br) && !COMP_WHITELIST.test(nm)) continue; // competitor whitelist
          } else {
            if (br !== 'jivo' && !/\bjivo\b/i.test(nm)) continue; // safety: only genuine Jivo
          }
          const row = pdpToRow(pi, rec, storeId, seed);
          const existing = byVid.get(seed.variantId);
          if (existing) Object.assign(existing, row);           // PDP wins (authoritative)
          else { rows.push(row); byVid.set(seed.variantId, row); }
          await new Promise(r => setTimeout(r, 220 + Math.random() * 300));
        }
      }
    }
  } catch (e) {
    // An error whose message carries a block signature is treated as a block (so the caller
    // backs off); any other error is just a per-pincode failure (0 rows). Never rethrown.
    if (BLOCK_RE.test(String(e && e.message))) blocked = 'block-error';
    process.stderr.write(`[err] ${rec.city} ${rec.pincode}: ${e.message}${blocked ? ' (block)' : ''}\n`);
  }
  const cachedRows = rows.filter(r => r.cached).length;
  const seedRows = rows.filter(r => r.source === 'pdp_seed').length;
  process.stderr.write(`[ok] ${rec.city} ${rec.pincode} serviceable=${serviceable} -> ${rows.length} jivo SKUs (${((Date.now() - t0) / 1000).toFixed(1)}s) store=${storeId || 'n/a'}${seedRows ? ` SEED=${seedRows}` : ''}${cachedRows ? ` CACHED=${cachedRows}` : ''}\n`);
  return { ...rec, store_id: storeId, store_name: '', serviceable, blocked, rows, freshness: { cached_rows: cachedRows, markers } };
}

// Scrape one pincode with block-aware exponential backoff. A blocked attempt backs off and
// retries up to MAX_BLOCK_RETRIES; if still blocked we record 0 rows and tag the result
// `partial_block` (the run is then marked partial). NEVER evades — it only waits and retries
// politely, then gives up honestly. Mirrors the Blinkit pilot.
async function scrapeWithBackoff(rec) {
  for (let attempt = 0; ; attempt++) {
    const res = await scrapeOne(rec);
    if (!res.blocked) return res;
    if (attempt >= MAX_BLOCK_RETRIES) {
      process.stderr.write(`[blocked] ${rec.city} ${rec.pincode} still blocked after ${attempt} retr${attempt === 1 ? 'y' : 'ies'} (${res.blocked}); recording 0 rows, run is partial\n`);
      return { ...res, partial_block: true };
    }
    await backoff(attempt);
  }
}

async function pool(items, n, fn) {
  const results = []; let i = 0;
  async function worker() {
    while (i < items.length) {
      const idx = i++;
      results[idx] = await fn(items[idx], idx);
      await new Promise(r => setTimeout(r, 500 + Math.random() * 900));
    }
  }
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, worker));
  return results;
}

// Exported for the offline volparse test (same pattern as amazon-fresh); the scrape
// only runs when invoked directly, so `require`-ing this file never hits the network.
module.exports = { parseVolMl, volFromVariant, canonical };

if (require.main === module) (async () => {
  const t0 = Date.now();
  // Resume: reload any per-pincode results already captured for TODAY and skip them, so a
  // kill/restart finishes the run with no duplicate work and a complete result.json.
  const done = loadProgress();
  const doneCount = Object.keys(done).length;
  if (doneCount) process.stderr.write(`[resume] ${doneCount} pincodes already done in ${PROG}; resuming\n`);
  let partial = false;
  const perPin = await pool(PINCODES, CONCURRENCY, async (rec) => {
    if (done[rec.pincode]) return done[rec.pincode];          // checkpoint hit — skip
    const res = await scrapeWithBackoff(rec);
    if (res.blocked || res.partial_block) partial = true;     // any unresolved block => partial run
    done[rec.pincode] = res;
    saveProgress(done);                                       // checkpoint AFTER each pincode
    return res;
  });
  const allRows = perPin.flatMap(p => p.rows);
  // Freshness aggregate for the review/staleness alarm. The REAL lag signal is NOT the per-product
  // `cached` flag (Zepto leaves it false even when serving a stale MongoDB snapshot) — it is the
  // per-store `is_realtime_model_data_fetched`: when false (reason e.g. mongo_data_exists) the store
  // was served from a NON-realtime snapshot that can lag the live catalogue. We aggregate the share
  // of serviceable stores served that way (pct_non_realtime) plus the reason histogram; the review
  // step uses this to GATE the frozen-price alarm. (pct_cached kept too, for completeness.)
  const cachedRows = allRows.filter(r => r.cached).length;
  const servStores = perPin.filter(p => p.serviceable);
  let storesNonRealtime = 0;
  const reasonCounts = {};
  for (const p of servStores) {
    const m = (p.freshness && p.freshness.markers) || {};
    if (m.is_realtime_model_data_fetched === false) {
      storesNonRealtime++;
      const reason = m.realtime_model_not_enabled_reason;
      if (reason) reasonCounts[reason] = (reasonCounts[reason] || 0) + 1;
    }
  }
  const summary = {
    pincodes_total: PINCODES.length,
    pincodes_serviceable: perPin.filter(p => p.serviceable).length,
    pincodes_with_jivo: perPin.filter(p => p.rows.length > 0).length,
    pincodes_blocked: perPin.filter(p => p.blocked || p.partial_block).length,
    total_rows: allRows.length,
    unique_skus: new Set(allRows.map(r => r.canonical)).size,
    rows_in_stock: allRows.filter(r => r.in_stock).length,
    rows_oos: allRows.filter(r => !r.in_stock).length,
    rows_seed_pdp: allRows.filter(r => r.source === 'pdp_seed').length,
    skus_via_seed: new Set(allRows.filter(r => r.source === 'pdp_seed').map(r => r.canonical)).size,
    wall_s: Math.round((Date.now() - t0) / 1000),
    partial,
    captured_at: new Date().toISOString(),
    marketplace: MARKETPLACE,
    freshness: {
      rows_total: allRows.length,
      rows_cached: cachedRows,
      pct_cached: allRows.length ? Math.round((cachedRows / allRows.length) * 1000) / 10 : 0,
      stores_total: servStores.length,
      stores_non_realtime: storesNonRealtime,
      pct_non_realtime: servStores.length ? Math.round((storesNonRealtime / servStores.length) * 1000) / 10 : 0,
      realtime_not_enabled_reasons: reasonCounts,
    },
  };
  process.stderr.write('[SUMMARY] ' + JSON.stringify(summary) + '\n');
  if (COMPETITOR) {
    // competitor mode: write ONLY under tools/competitor/data/ — never the mailer-globbed result.json
    writeCompetitorOutputs(summary, allRows, partial);
  } else {
    fs.writeFileSync(OUTFILE, JSON.stringify({ summary, perPin, allRows, partial }, null, 2));
  }
  console.log(JSON.stringify(summary));
})();
