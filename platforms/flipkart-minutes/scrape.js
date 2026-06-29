// Flipkart Minutes scraper — DIRECT-API mode (ridiculously fast).
//
// Flipkart binds the hyperlocal session to a browser-minted `T` fingerprint cookie, so a guest
// can't hit the API directly. We transplant a LOGGED-IN session (cookies exported on the user's
// clean machine via Cookie-Editor -> import_cookies.js -> secrets/flipkart-minutes.storageState.json).
// With that session, the whole flow is two fast JSON POSTs per pincode through Flipkart's BFF:
//   1) /api/4/location/update          (set the delivery pincode for this context)
//   2) /api/4/page/fetch  pageUri=/search?q=jivo&marketplace=HYPERLOCAL   (structured products)
// We run a pool of isolated browser contexts (each its own cookie jar -> no location cross-talk),
// each looping its share of the 345 pincodes via in-page fetch. ~30s for 345 vs ~37 min for the
// browser DOM flow, AND cleaner data (exact sale/MRP/per-litre/stock/pid from JSON).
//
// ROBUSTNESS: if the session is missing or expired, we fall back to scrape.browser.js (the
// login-free Playwright DOM scraper) so the cron never goes dark — and warn to re-export cookies.
//
// Env: FKM_CONCURRENCY (default 10) · PINCODES_FILE · OUT_FILE
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

// ---- COMPETITOR_MODE (env-gated, ADDITIVE — see task brief) ----------------------------
// Everything competitor-related activates ONLY when process.env.COMPETITOR_MODE === '1'.
// When it is unset, COMPETITOR_MODE is false, every competitor const collapses to a harmless
// default (null / {} / []), and NONE of the competitor branches execute — so the scraper's
// query (q=jivo), its jivo-only filter and its output path (result.json / OUT) stay
// byte-for-byte unchanged. Competitor data is written ONLY under tools/competitor/ — never
// under data/ vault/ reviews/ baselines/ (those are git-added by the cron), and the output
// filename never starts with "Jivo-" (the mailer auto-emails Jivo-*.xlsx).
const COMPETITOR_MODE = process.env.COMPETITOR_MODE === '1';
const COMP_DIR = path.join(__dirname, '..', '..', 'tools', 'competitor');
const COMP_DATE = process.env.COMPETITOR_DATE || new Date(Date.now() + 5.5 * 3600 * 1000).toISOString().slice(0, 10);

const PFILE = process.env.PINCODES_FILE || path.join(__dirname, 'pincodes.json');
const PINCODES = JSON.parse(fs.readFileSync(PFILE, 'utf8'));
const CONCURRENCY = parseInt(process.env.FKM_CONCURRENCY || '10', 10);
const OUT = process.env.OUT_FILE || path.join(__dirname, 'result.json');
const STATE = path.join(__dirname, 'secrets', 'flipkart-minutes.storageState.json');
// SIM hooks for the hermetic fault-injection tests (see test_hardening.md). Inert in
// production; declared early because the session/fallback check below consults it.
const SIM = process.env.FKM_SIM === '1' || process.env.FKM_BLOCK_SIM === '1';
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 FKUA/msite/0.0.4/msite/Mobile';

// addressInfo.state for the 26 cities in the pincode grid (location/update wants a state).
const STATE_OF = {
  Bengaluru: 'Karnataka', Mysuru: 'Karnataka', Bhopal: 'Madhya Pradesh', Indore: 'Madhya Pradesh',
  Chandigarh: 'Chandigarh', Delhi: 'Delhi', Faridabad: 'Haryana', Gurgaon: 'Haryana',
  Ghaziabad: 'Uttar Pradesh', Noida: 'Uttar Pradesh', Kanpur: 'Uttar Pradesh', Lucknow: 'Uttar Pradesh',
  Jaipur: 'Rajasthan', Kolkata: 'West Bengal', Ludhiana: 'Punjab', Mumbai: 'Maharashtra',
  Pune: 'Maharashtra', Nagpur: 'Maharashtra', Surat: 'Gujarat', Ahmedabad: 'Gujarat',
  Vadodara: 'Gujarat', Chennai: 'Tamil Nadu', Coimbatore: 'Tamil Nadu', Hyderabad: 'Telangana',
  Patna: 'Bihar', Visakhapatnam: 'Andhra Pradesh',
};

function fallbackToBrowser(reason) {
  process.stderr.write(`[fkm-api] ${reason}\n[fkm-api] FALLING BACK to browser scraper (scrape.browser.js). Re-export Flipkart cookies (import_cookies.js) to restore fast mode.\n`);
  try {
    require('child_process').execFileSync('node', [path.join(__dirname, 'scrape.browser.js')],
      { stdio: 'inherit', env: process.env });
  } catch (e) { process.stderr.write('[fkm-api] browser fallback also failed: ' + e.message + '\n'); process.exit(1); }
  process.exit(0);
}

// Direct-run only: a `require` (offline volparse test) must never be able to spawn the
// browser scraper. When run directly the behavior is unchanged.
// (SIM modes never touch the live session or the browser fallback — they short-circuit
// before any network call, so a missing storageState must not trigger the fallback.)
if (require.main === module && !SIM && !fs.existsSync(STATE)) fallbackToBrowser('no logged-in session at secrets/flipkart-minutes.storageState.json');

function dcN() {
  try {
    const at = JSON.parse(fs.readFileSync(STATE, 'utf8')).cookies.find((c) => c.name === 'at');
    const z = JSON.parse(Buffer.from(at.value.split('.')[1], 'base64').toString()).z;
    return { CH: 1, HYD: 2, MUM: 3, KOL: 4 }[z] || 2;
  } catch (_) { return 2; }
}
const N = dcN();
const LOC_URL = `https://${N}.rome.api.flipkart.com/api/4/location/update`;
const SEARCH_URL = `https://${N}.rome.api.flipkart.com/api/4/page/fetch?cacheFirst=false`;

// ---- Hardening (Wave-1 coverage pilot, 2026-06-29) -------------------------------
// At full 25-city scale a run loops far more pincodes, so it MUST survive interruption
// and rate-limiting without losing work or throwing. Three additions, mirroring the
// proven blinkit pilot (commit c4ab885d5), adapted to this direct-API/bucket scraper.
// All opt-in / fail-safe:
//   (1) checkpoint/resume — per-pincode result cached in .progress.<date>.json; a
//       re-run the same day skips finished pincodes and resumes where it stopped.
//   (2) block-detection + exponential backoff — a 403/429/503 on the BFF call, or an
//       Akamai/"access denied"/captcha body, is treated as a block: back off (capped)
//       and retry a few times, then record 0 rows and flag the run partial. NEVER
//       evade — polite wait+retry only (owner rule); no proxies, no fingerprint games.
//   (3) partial tolerance — one pincode can never kill the run; result.json always
//       gets written with a top-level `partial` flag so the batch wrapper sees it.
// SIM hooks (FKM_SIM / FKM_BLOCK_SIM) drive the hermetic fault-injection tests in
// test_hardening.md without launching a browser or hitting Flipkart live (declared above).
// In COMPETITOR_MODE the checkpoint lives under tools/competitor/data/ so a competitor
// re-run never resumes from (or overwrites) the jivo progress file, and never lands under
// a cron-git-added path. The jivo path is byte-for-byte unchanged.
const PROG = COMPETITOR_MODE
  ? `${COMP_DIR}/data/.progress.competitor.${path.basename(__dirname)}.${COMP_DATE}.json`
  : `${__dirname}/.progress.${new Date().toISOString().slice(0, 10)}.json`;
if (COMPETITOR_MODE) { try { fs.mkdirSync(path.dirname(PROG), { recursive: true }); } catch (_) { /* created lazily on write */ } }
const MAX_BLOCK_RETRIES = parseInt(process.env.FKM_BLOCK_RETRIES || '4', 10);
// Body signatures of a block page. Deliberately specific (NOT bare "403"/"429",
// which could appear in legitimate JSON text) — HTTP status carries those.
const BLOCK_RE = /access denied|akamai|reference #\s*\d|too many requests|rate[\s-]?limit|are you a human|captcha|forbidden/i;

async function backoff(attempt) {
  const ms = Math.min(60000, 2000 * Math.pow(2, attempt)) + Math.floor(Math.random() * 1000);
  process.stderr.write(`[backoff] attempt ${attempt} -> sleeping ${Math.round(ms)}ms\n`);
  await new Promise((r) => setTimeout(r, ms));
}

// Classify a BFF api() response as blocked. Returns a short reason string or null.
// Status 403/429/503 is an IP-level block; an Akamai/captcha HTML body (served instead
// of JSON when walled) is caught by BLOCK_RE. A plain non-200 (e.g. 302 redirect, 404)
// is NOT a block — it is handled by the normal serviceability logic.
function respBlocked(resp) {
  if (!resp) return null;
  const s = resp.status;
  if (s === 403 || s === 429 || s === 503) return `http ${s}`;
  const text = resp.text || (resp.json ? '' : (resp.error || ''));
  if (text && BLOCK_RE.test(text)) return 'block-signature';
  return null;
}

function loadProgress() {
  try { return fs.existsSync(PROG) ? JSON.parse(fs.readFileSync(PROG, 'utf8')) : {}; }
  catch (_) { return {}; }
}
function saveProgress(done) {
  try { fs.writeFileSync(PROG, JSON.stringify(done)); } catch (e) { process.stderr.write(`[progress] write failed: ${e.message}\n`); }
}

// ml for one "<number> <unit>" token. l/ltr/litre/kg -> *1000; ml/g -> as-is.
function unitMl(n, u) {
  if (u === 'ml' || u === 'g') return n;
  if (u === 'l' || u === 'ltr' || u === 'litre' || u === 'kg') return n * 1000;
  return null;
}
// TOTAL pack volume in ml. Combo-aware: a multiplicative pack like "2 x 1 L" is
// 2 * 1L = 2000 ml. The old regex matched only the first "1 L" and silently dropped
// the "2 x" multiplier, so 2L combos were recorded as 1000 ml (and, when the API
// per-litre was absent, the Rs/L fallback came out 2x too high).
function parseVolMl(pack) {
  if (!pack) return null;
  const s = pack.toLowerCase();
  const combo = s.match(/([\d.]+)\s*[x×*]\s*([\d.]+)\s*(ml|l|ltr|litre|kg|g)/);
  if (combo) {
    const each = unitMl(parseFloat(combo[2]), combo[3]);
    return each != null ? parseFloat(combo[1]) * each : null;
  }
  // Unit-FIRST combos ("1 L X 2") are the SAME pack in the other order (zepto fix
  // 2026-06-10 — stores render either); parse it too, before the single-token fallback.
  const comboU = s.match(/([\d.]+)\s*(ml|l|ltr|litre|kg|g)\s*[x×*]\s*([\d.]+)/);
  if (comboU) {
    const each = unitMl(parseFloat(comboU[1]), comboU[2]);
    return each != null ? each * parseFloat(comboU[3]) : null;
  }
  const m = s.match(/([\d.]+)\s*(ml|l|ltr|litre|kg|g)/);
  if (!m) return null;
  return unitMl(parseFloat(m[1]), m[2]);
}
function canonical(name, pack, brand) {
  const base = (name || '').toLowerCase()
    .replace(/\(.*?\)/g, '').replace(/[^a-z0-9 ]/g, '')
    .replace(/\s+/g, ' ').trim().replace(/\s/g, '-');
  const vol = parseVolMl(pack);
  const volTag = vol ? (vol >= 1000 ? (vol / 1000) + 'l' : vol + 'ml') : 'na';
  // brand is OPTIONAL: it is only ever passed in COMPETITOR_MODE. When omitted/falsy the
  // brandTag is '' and the returned canonical is byte-for-byte identical to the old 2-arg form.
  const brandTag = brand ? (String(brand).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') + '-') : '';
  return `${brandTag}${base}-${volTag}`.replace(/--+/g, '-');
}

// ======================= COMPETITOR_MODE helpers (env-gated) =======================
// Pure helpers + module-level constants used ONLY by the competitor branch. None of them
// run or mutate anything when COMPETITOR_MODE is unset (the consts collapse to null / {} / []
// and every call site is behind `if (COMPETITOR_MODE)`).
function escRe(s) { return String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }

// Brand whitelist regex, resolved from (in order): tools/competitor/competitor_brands.json
// (accepts a raw regex string, {regex|whitelist_regex:"..."}, an array of brands, or
// {brands:[{brand,aliases}],ours:[...]}), then env COMPETITOR_BRANDS (comma list), then a
// sane edible-oil default list. This repo ships `whitelist_regex`, so that branch wins.
function loadCompetitorRegex() {
  const def = ['jivo', 'sano', 'fortune', 'saffola', 'dhara', 'gemini', 'sundrop', 'figaro',
    'nature ?fresh', 'emami', 'patanjali', 'freedom', 'gold ?winner', 'sunpure', 'ricela',
    'borges', 'disano', 'del ?monte', 'oleev', 'leonardo', 'idhayam', 'gulab', 'natureland',
    'p ?mark', 'engine', 'bb ?royal', 'rafael ?salgado', 'tata'];
  try {
    const f = path.join(COMP_DIR, 'competitor_brands.json');
    if (fs.existsSync(f)) {
      const j = JSON.parse(fs.readFileSync(f, 'utf8'));
      if (typeof j === 'string' && j.trim()) return new RegExp(j, 'i');
      // Preferred: a ready-made regex string (this file ships `whitelist_regex`).
      const rgx = j && (j.regex || j.whitelist_regex);
      if (typeof rgx === 'string' && rgx.trim()) return new RegExp(rgx, 'i');
      // Else build one from a brand list — entries may be plain strings OR
      // {brand, aliases:[...]} objects; also fold in any `ours` (Jivo/Sano).
      const list = Array.isArray(j) ? j : (j && Array.isArray(j.brands) ? j.brands : null);
      if (list && list.length) {
        const terms = [];
        for (const b of list) {
          if (typeof b === 'string') terms.push(b);
          else if (b && typeof b === 'object') {
            if (b.brand) terms.push(b.brand);
            if (Array.isArray(b.aliases)) for (const a of b.aliases) if (a) terms.push(a);
          }
        }
        if (j && Array.isArray(j.ours)) for (const o of j.ours) if (o) terms.push(o);
        const uniq = Array.from(new Set(terms.filter(Boolean)));
        if (uniq.length) return new RegExp('(' + uniq.map(escRe).join('|') + ')', 'i');
      }
    }
  } catch (e) { process.stderr.write(`[comp] competitor_brands.json load failed (${e.message}); using fallback list\n`); }
  if (process.env.COMPETITOR_BRANDS) {
    const list = process.env.COMPETITOR_BRANDS.split(',').map((s) => s.trim()).filter(Boolean);
    if (list.length) return new RegExp('(' + list.map(escRe).join('|') + ')', 'i');
  }
  return new RegExp('(' + def.join('|') + ')', 'i');
}

// Category query terms, from tools/competitor/category_queries.json (array, {queries:[...]},
// or a {term: category} map -> its keys), then env COMPETITOR_QUERIES, then defaults.
function loadCategoryQueries() {
  const def = ['olive oil', 'mustard oil', 'sunflower oil', 'canola oil', 'rice bran oil',
    'groundnut oil', 'soyabean oil', 'blended oil'];
  try {
    const f = path.join(COMP_DIR, 'category_queries.json');
    if (fs.existsSync(f)) {
      const j = JSON.parse(fs.readFileSync(f, 'utf8'));
      if (Array.isArray(j)) return j.filter(Boolean);
      if (j && Array.isArray(j.queries)) return j.queries.filter(Boolean);
      if (j && typeof j === 'object') return Object.keys(j).filter((k) => k !== 'keep_jivo_query');
    }
  } catch (e) { process.stderr.write(`[comp] category_queries.json load failed (${e.message}); using fallback list\n`); }
  if (process.env.COMPETITOR_QUERIES) return process.env.COMPETITOR_QUERIES.split(',').map((s) => s.trim()).filter(Boolean);
  return def;
}

// Optional explicit {query: category} map (only when category_queries.json is such an object).
function loadCategoryMap() {
  try {
    const f = path.join(COMP_DIR, 'category_queries.json');
    if (fs.existsSync(f)) {
      const j = JSON.parse(fs.readFileSync(f, 'utf8'));
      if (j && !Array.isArray(j) && typeof j === 'object' && !Array.isArray(j.queries)) {
        const m = {};
        for (const k of Object.keys(j)) if (typeof j[k] === 'string') m[k.toLowerCase()] = j[k];
        return m;
      }
    }
  } catch (_) { /* fall through to empty map */ }
  return {};
}

// Brand label = the whitelist substring actually present in the text (productBrand or name).
function deriveBrand(text) {
  if (!COMPETITOR_RE) return '';
  const m = (text || '').match(COMPETITOR_RE);
  return m ? m[0].replace(/\s+/g, ' ').trim() : '';
}

// Category from the explicit map, else keyword-scan name then query term. Returns the
// short category slug used by maps_to_jivo.json buckets (e.g. olive, mustard, rice_bran).
function deriveCategory(term, name) {
  const t = (term || '').toLowerCase();
  const n = (name || '').toLowerCase();
  if (CATEGORY_MAP[t]) return CATEGORY_MAP[t];
  const cats = [
    [/mustard|kachi ghani|sarso/, 'mustard'],
    [/sunflower/, 'sunflower'],
    [/soya|soybean|soyabean/, 'soyabean'],
    [/groundnut|peanut/, 'groundnut'],
    [/rice ?bran/, 'rice_bran'],
    [/olive/, 'olive'],
    [/canola/, 'canola'],
    [/sesame|gingelly|til\b/, 'sesame'],
    [/coconut/, 'coconut'],
    [/ghee/, 'ghee'],
    [/blend/, 'blended'],
    [/vegetable/, 'vegetable'],
  ];
  for (const [re, c] of cats) { if (re.test(n) || re.test(t)) return c; }
  // fall back to the query term, normalised (" oil" stripped, spaces -> "_").
  const slug = t.replace(/\s*oil\s*$/, '').trim().replace(/\s+/g, '_');
  return (slug && slug !== 'jivo') ? slug : 'edible_oil';
}

// Light sub-grade extraction from the product name (best-effort; '' when none found).
function deriveSubGrade(name) {
  const n = (name || '').toLowerCase();
  const grades = [
    [/extra virgin/, 'extra_virgin'],
    [/extra light/, 'extra_light'],
    [/virgin/, 'virgin'],
    [/pomace/, 'pomace'],
    [/double refined/, 'double_refined'],
    [/kachi ghani|cold ?press|wood ?press|wooden ?press|ghani/, 'kachi_ghani'],
    [/filtered/, 'filtered'],
    [/refined/, 'refined'],
    [/light/, 'light'],
  ];
  for (const [re, g] of grades) if (re.test(n)) return g;
  return '';
}

// Pack unit family for the contract: 'g' when the pack is mass-only (g/kg), else 'ml'.
function packUnit(pack) {
  const s = (pack || '').toLowerCase();
  const hasLiquid = /\d[\d.]*\s*(?:ml|l|ltr|litre)\b/.test(s);
  const hasMass = /\d[\d.]*\s*(?:kg|g)\b/.test(s);
  return (hasMass && !hasLiquid) ? 'g' : 'ml';
}

// vol in ML for the competitor contract: grams -> volume via oil density (ghee 0.91,
// other oils 0.916); liquids pass straight through. parseVolMl already handles combos.
function competitorVolMl(pack, isGhee) {
  const raw = parseVolMl(pack);
  if (raw == null) return null;
  if (packUnit(pack) === 'g') return Math.round((raw / (isGhee ? 0.91 : 0.916)) * 100) / 100;
  return raw;
}

// Best-effort sponsored/ad detector over Flipkart's structured product node. Conservative:
// only explicit ad fields / a "sponsored" tag flip it to 1, so it never false-positives.
function detectAd(p, v) {
  try {
    if (p && (p.adInfo || p.adsInfo || p.adId || p.isAd || p.sponsored)) return true;
    if (v && (v.isAd || v.sponsored || v.adId)) return true;
    const tags = (v && (v.tags || v.productTags)) || [];
    const arr = Array.isArray(tags) ? tags : [];
    for (const tg of arr) {
      const s = typeof tg === 'string' ? tg : (tg && (tg.text || tg.value || tg.title || tg.type) || '');
      if (/sponsored/i.test(s)) return true;
    }
  } catch (_) { /* default: not an ad */ }
  return false;
}

// Built once at module load; only populated when COMPETITOR_MODE is on.
const COMPETITOR_RE = COMPETITOR_MODE ? loadCompetitorRegex() : null;
const CATEGORY_MAP = COMPETITOR_MODE ? loadCategoryMap() : {};
const COMPETITOR_TERMS = COMPETITOR_MODE ? Array.from(new Set(['jivo', ...loadCategoryQueries()])) : [];
// ===================== end COMPETITOR_MODE helpers =====================

// POST a Flipkart BFF call from inside the page (inherits the transplanted cookies + DC routing).
async function api(page, url, body) {
  return page.evaluate(async ({ url, body }) => {
    try {
      const r = await fetch(url, {
        method: 'POST', credentials: 'include',
        headers: { flipkart_secure: 'true', 'content-type': 'application/json',
          'accept-language': 'en-IN,en;q=0.9', 'x-user-agent': navigator.userAgent },
        body: JSON.stringify(body),
      });
      const t = await r.text(); let j = null; try { j = JSON.parse(t); } catch (_) {}
      // Return a short slice of the raw body too: when Akamai walls the IP it serves an
      // HTML block page instead of JSON, which respBlocked() scans for a block signature.
      return { status: r.status, json: j, text: j ? '' : t.slice(0, 4000) };
    } catch (e) { return { status: -1, error: String(e) }; }
  }, { url, body });
}

function parseProducts(searchJson, rec, term) {
  const rows = [];
  let rank = 0;   // competitor-only: running position across the ranked response (inert in jivo mode)
  const slots = ((searchJson && (searchJson.RESPONSE || searchJson).slots)) || [];
  for (const s of slots) {
    const ps = (((s.widget || {}).data || {}).products) || [];
    for (const p of ps) {
      rank++;
      const v = ((p.productInfo || {}).value) || {};
      const act = (p.productInfo || {}).action || {};
      const title = ((v.titles || {}).title) || '';
      if (COMPETITOR_MODE) {
        // competitor gate: keep any whitelisted brand (jivo/sano + rivals) by title OR productBrand
        if (!COMPETITOR_RE.test(title) && !COMPETITOR_RE.test(v.productBrand || '')) continue;
      } else if (!/jivo/i.test(title) && !/jivo/i.test(v.productBrand || '')) continue;
      const pack = ((v.titles || {}).subtitle) || '';
      const name = title.replace(/\(pack of \d+\)/i, '').replace(/\s+/g, ' ').trim();
      const pricing = v.pricing || {};
      const sale = (pricing.finalPrice || {}).value;
      const mrpEntry = (pricing.prices || []).find((x) => x.priceType === 'MRP');
      // No MRP from the API (e.g. some combo packs) -> leave it null. Do NOT fabricate
      // mrp = sale: that invents a phantom MRP and a fake 0% "discount" on a real SKU.
      const mrp = mrpEntry ? mrpEntry.value : null;
      if (COMPETITOR_MODE) {
        if ((!COMPETITOR_RE.test(name) && !COMPETITOR_RE.test(v.productBrand || '')) || !sale) continue;
      } else if (!/jivo/i.test(name) || !sale) continue;
      // Discount is undefined without an MRP basis -> null (not 0) when mrp is absent.
      const disc = (mrp == null) ? null
        : (typeof pricing.totalDiscount === 'number') ? pricing.totalDiscount
        : (mrp && sale && mrp >= sale ? Math.round(((mrp - sale) / mrp) * 1000) / 10 : null);
      const vol = parseVolMl(pack);
      const ppu = ((pricing.pricePerUnit || {}).pivotQualifier === 'L') ? (pricing.pricePerUnit || {}).pricePerUnit : null;
      const storeId = (((act.params || {}).shopId) || [])[0] || '';
      // ---- listing identity (ADDITIVE, fail-safe): pid + PDP url for the SKU map ----
      // productInfo.action carries the product navigation target. Evidence: action.params
      // values are arrays (shopId above); the PDP url form is /…/p/itm…?pid=<PID>&… and the
      // generic https://www.flipkart.com/product/p/itme?pid=<PID> resolves (both proven in
      // tools/pricematch/fragments/map-flipkart.json). Field names defensive: several
      // candidate paths, first hit wins; on ANY error the row is built exactly as before
      // (keys simply omitted).
      let fkPid = '';
      let listingUrl = '';
      try {
        // primitives only — a non-string/number candidate (object/bool/etc.) is junk, not a pid
        const first = (x) => {
          if (Array.isArray(x)) x = x.length ? x[0] : null;
          return (typeof x === 'string' || typeof x === 'number') ? String(x) : '';
        };
        // pid shape gate (e.g. GHEHHZBQJBNVZGGQ), applied PER candidate so a junk
        // candidate falls through to the next instead of killing the whole chain.
        // itm…/lst… are Flipkart PAGE/LISTING ids (16-char alnum — they'd pass the
        // shape gate) but are NOT product pids; never record one (W4 review ruling).
        const pidOk = (s) => (/^[A-Za-z0-9]{8,32}$/.test(s) && !/^(itm|lst)/i.test(s)) ? s : '';
        const ap = act.params || {};
        const aurl = typeof act.url === 'string' ? act.url : '';
        fkPid = pidOk(first(ap.pid)) || pidOk(first(ap.productId))
          || pidOk((aurl.match(/[?&]pid=([A-Za-z0-9]+)/) || [])[1] || '')
          || pidOk(first(v.id)) || pidOk(first(v.productId)) || '';
        if (aurl) listingUrl = /^https?:\/\//i.test(aurl) ? aurl : 'https://www.flipkart.com' + (aurl.startsWith('/') ? '' : '/') + aurl;
        else if (fkPid) listingUrl = 'https://www.flipkart.com/product/p/itme?pid=' + fkPid;
      } catch (_) { fkPid = ''; listingUrl = ''; }
      if (COMPETITOR_MODE) {
        // ---- COMPETITOR_MODE row (shared competitor contract) ----
        // brand = productBrand when present, else the whitelist substring found in the title.
        const brand = (v.productBrand && String(v.productBrand).trim()) ? String(v.productBrand).trim() : deriveBrand(title || name);
        const category = deriveCategory(term, name);
        const subGrade = deriveSubGrade(name);
        const isGhee = /ghee/i.test(name) || /ghee/i.test(category);
        const unitC = packUnit(pack);
        const volC = competitorVolMl(pack, isGhee);
        rows.push({
          platform: 'flipkart-minutes',
          city: rec.city, pincode: rec.pincode,
          store_id: storeId, store_name: storeId,
          brand, name, canonical: canonical(name, pack, brand),
          category, sub_grade: subGrade,
          pack: pack || '', vol_ml: volC, unit: unitC,
          per_litre: volC ? Math.round((sale / (volC / 1000)) * 100) / 100 : null,
          mrp, sale, discount_pct: disc,
          in_stock: ((v.availability || {}).displayState === 'IN_STOCK') ? 1 : 0,
          rank, is_ad: detectAd(p, v) ? 1 : 0,
          captured_at: new Date().toISOString(),
          ...((fkPid || listingUrl) ? { fk_pid: fkPid, listing_url: listingUrl } : {}),
        });
        continue;
      }
      rows.push({
        city: rec.city, pincode: rec.pincode, locality: rec.locality,
        store_id: storeId, store_name: storeId,
        sku_raw: name, canonical: canonical(name, pack), pack,
        vol_ml: vol, sale, mrp, discount_pct: disc,
        per_litre: ppu != null ? ppu : (vol ? Math.round((sale / (vol / 1000)) * 100) / 100 : null),
        eta_min: null, in_stock: ((v.availability || {}).displayState === 'IN_STOCK') ? 1 : 0,
        ...((fkPid || listingUrl) ? { fk_pid: fkPid, listing_url: listingUrl } : {}),
      });
    }
  }
  if (COMPETITOR_MODE) {
    // competitor dedup includes brand so a JIVO row and a rival row of the same name+pack
    // don't collapse into one (brand is already inside the canonical too).
    const ddc = new Map();
    for (const r of rows) { const k = `${r.store_id}|${(r.brand || '').toLowerCase()}|${r.canonical}`; if (!ddc.has(k)) ddc.set(k, r); }
    return [...ddc.values()];
  }
  const dd = new Map();
  for (const r of rows) { const k = `${r.store_id}|${r.canonical}`; if (!dd.has(k)) dd.set(k, r); }
  return [...dd.values()];
}

async function scrapePincode(page, rec) {
  // SIM hooks (tests only; never active in production runs):
  //   FKM_BLOCK_SIM=1 -> every pincode reports blocked (drives the backoff/partial test)
  //   FKM_SIM=1       -> return a synthetic serviceable row without a browser (resume test)
  if (process.env.FKM_BLOCK_SIM === '1') {
    await new Promise((r) => setTimeout(r, 10));
    return { ...rec, serviceable: false, store_id: '', store_name: '', rows: [], blocked: 'sim-block' };
  }
  if (process.env.FKM_SIM === '1') {
    await new Promise((r) => setTimeout(r, 10));
    const rows = [{
      city: rec.city, pincode: rec.pincode, locality: rec.locality,
      store_id: 'sim', store_name: 'sim-store', sku_raw: 'Jivo Sim Oil',
      canonical: 'jivo-sim-oil-1l', pack: '1 L', vol_ml: 1000, sale: 199, mrp: 250,
      discount_pct: 20, per_litre: 199, eta_min: null, in_stock: 1,
    }];
    return { ...rec, serviceable: true, store_id: 'sim', store_name: 'sim-store', rows, blocked: null };
  }
  const locBody = {
    geoLocation: { latitude: String(rec.lat), longitude: String(rec.lon) },
    addressInfo: { addressLine1: rec.locality || rec.city, city: rec.city, state: STATE_OF[rec.city] || '', pincode: String(rec.pincode) },
    redirectionUrl: '/flipkart-minutes-store?marketplace=HYPERLOCAL', marketplace: 'HYPERLOCAL',
  };
  if (COMPETITOR_MODE) {
    // Competitor sweep: set the pincode context once (location/update), then run one
    // page/fetch PER term — q=jivo PLUS each category query from category_queries.json —
    // harvesting every whitelisted brand from each ranked response. Same block/backoff
    // contract as the jivo path (a block returns blocked:<reason> for scrapeWithBackoff).
    // Writes NOTHING here; the main runner writes only under tools/competitor/.
    let serviceableC = false;
    let storeIdC = '';
    let compRows = [];
    for (let attempt = 1; attempt <= 2; attempt++) {
      const loc = await api(page, LOC_URL, locBody);
      const lb = respBlocked(loc);
      if (lb) { process.stderr.write(`[blocked] ${rec.city} ${rec.pincode} -> ${lb} on location/update\n`); return { ...rec, serviceable: false, store_id: '', store_name: '', rows: [], blocked: lb }; }
      serviceableC = loc.status === 200;
      let redirSeen = false;
      compRows = [];
      storeIdC = '';
      for (const term of COMPETITOR_TERMS) {
        const body = {
          pageUri: `/search?q=${encodeURIComponent(term)}&marketplace=HYPERLOCAL`,
          locationContext: { pincode: parseInt(rec.pincode, 10), changed: false },
          pageContext: { trackingContext: { context: { eVar51: 'direct_browse', eVar61: 'direct_browse' } }, fetchSeoData: true, networkSpeed: 9400 },
          requestContext: { type: 'BROWSE_PAGE' },
        };
        const srch = await api(page, SEARCH_URL, body);
        const sb = respBlocked(srch);
        if (sb) { process.stderr.write(`[blocked] ${rec.city} ${rec.pincode} -> ${sb} on page/fetch (q=${term})\n`); return { ...rec, serviceable: false, store_id: '', store_name: '', rows: [], blocked: sb }; }
        const redir = (((srch.json && (srch.json.RESPONSE || srch.json).pageMeta) || {}).redirectionObject || {}).statusCode;
        if (redir === 302) { redirSeen = true; continue; }
        const rws = parseProducts(srch.json, rec, term);
        for (const r of rws) compRows.push(r);
        if (!storeIdC && rws.length) storeIdC = rws[0].store_id || '';
      }
      if (compRows.length === 0 && redirSeen && attempt < 2) { await page.waitForTimeout(600); continue; }
      break;
    }
    // dedup across terms on (store_id, brand, canonical) — the same SKU can surface in
    // more than one category response (e.g. a blend listed under two terms).
    const ddc = new Map();
    for (const r of compRows) { const k = `${r.store_id}|${(r.brand || '').toLowerCase()}|${r.canonical}`; if (!ddc.has(k)) ddc.set(k, r); }
    return { ...rec, serviceable: serviceableC, store_id: storeIdC, store_name: storeIdC, rows: [...ddc.values()], blocked: null };
  }
  const searchBody = {
    pageUri: '/search?q=jivo&marketplace=HYPERLOCAL',
    locationContext: { pincode: parseInt(rec.pincode, 10), changed: false },
    pageContext: { trackingContext: { context: { eVar51: 'direct_browse', eVar61: 'direct_browse' } }, fetchSeoData: true, networkSpeed: 9400 },
    requestContext: { type: 'BROWSE_PAGE' },
  };
  let serviceable = false;
  for (let attempt = 1; attempt <= 2; attempt++) {
    const loc = await api(page, LOC_URL, locBody);
    // Block check on the location call: a walled IP fails here before any product fetch.
    let b = respBlocked(loc);
    if (b) { process.stderr.write(`[blocked] ${rec.city} ${rec.pincode} -> ${b} on location/update\n`); return { ...rec, serviceable: false, store_id: '', store_name: '', rows: [], blocked: b }; }
    serviceable = loc.status === 200;
    const srch = await api(page, SEARCH_URL, searchBody);
    b = respBlocked(srch);
    if (b) { process.stderr.write(`[blocked] ${rec.city} ${rec.pincode} -> ${b} on page/fetch\n`); return { ...rec, serviceable: false, store_id: '', store_name: '', rows: [], blocked: b }; }
    const redir = (((srch.json && (srch.json.RESPONSE || srch.json).pageMeta) || {}).redirectionObject || {}).statusCode;
    if (redir === 302) { if (attempt < 2) { await page.waitForTimeout(600); continue; } return { ...rec, serviceable: false, store_id: '', store_name: '', rows: [], blocked: null }; }
    const rows = parseProducts(srch.json, rec);
    const sid = (rows[0] || {}).store_id || '';
    return { ...rec, serviceable: true, store_id: sid, store_name: sid, rows, blocked: null };
  }
  return { ...rec, serviceable, store_id: '', store_name: '', rows: [], blocked: null };
}

// Scrape one pincode with block-aware exponential backoff. A blocked attempt backs off and
// retries up to MAX_BLOCK_RETRIES; if still blocked we record 0 rows and tag the result
// `partial_block` (the run is then marked partial). NEVER evades — it only waits and retries
// politely on the same context, then gives up honestly.
async function scrapeWithBackoff(page, rec) {
  for (let attempt = 0; ; attempt++) {
    const res = await scrapePincode(page, rec);
    if (!res.blocked) return res;
    if (attempt >= MAX_BLOCK_RETRIES) {
      process.stderr.write(`[blocked] ${rec.city} ${rec.pincode} still blocked after ${attempt} retr${attempt === 1 ? 'y' : 'ies'} (${res.blocked}); recording 0 rows, run is partial\n`);
      return { ...res, partial_block: true };
    }
    await backoff(attempt);
  }
}

async function newCtxPage(browser) {
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', storageState: STATE });
  await ctx.route('**/*', (route) => {
    const t = route.request().resourceType();
    if (['image', 'font', 'media', 'stylesheet'].includes(t)) return route.abort();
    return route.continue();
  });
  const page = await ctx.newPage();
  // Load the logged-in homepage once: establishes flipkart.com origin (for credentialed fetch)
  // and lets Flipkart refresh the short-lived `at` from the long-lived `rt` if needed.
  await page.goto('https://www.flipkart.com/', { waitUntil: 'domcontentloaded', timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(800);
  return { ctx, page };
}

// Exported for the offline volparse test (same pattern as zepto/amazon-fresh); the scrape
// only runs when invoked directly, so `require`-ing this file never launches a browser.
module.exports = { parseVolMl, unitMl, canonical };

if (require.main === module) (async () => {
  // SIM mode never launches a browser or touches the live session — it drives the
  // hermetic fault-injection tests purely through scrapePincode's SIM short-circuit.
  let browser = null;
  if (!SIM) {
    try { browser = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox'] }); }
    catch (_) { browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] }); }
  }
  const t0 = Date.now();

  // Health check: a known-good pincode must return Jivo, else the session is dead -> fall back.
  // (Skipped in SIM — there is no live session.)
  // (Skipped in COMPETITOR_MODE: the logged-in API is DC-bound, so the northern canary 201304
  //  false-fails for a HYD-region token; the browser fallback has no competitor logic anyway, so
  //  we run the API loop directly and capture whatever pincodes this DC serves.)
  if (!SIM && process.env.COMPETITOR_MODE !== '1') {
    const hc = await newCtxPage(browser);
    const probe = await scrapePincode(hc.page, { city: 'Noida', pincode: '201304', locality: 'Sector 106', lat: 28.5355, lon: 77.391 });
    await hc.ctx.close();
    if (probe.rows.length === 0) { await browser.close(); fallbackToBrowser('session health-check failed (pincode 201304 returned no Jivo — cookies likely expired)'); }
  }

  // Resume: reload any per-pincode results already captured for TODAY and skip them.
  // The progress file is keyed by pincode and rewritten after EACH pincode, so a kill
  // mid-run loses at most the in-flight pincode; a re-run resumes with no duplicate work.
  const done = loadProgress();
  const doneCount = Object.keys(done).length;
  if (doneCount) process.stderr.write(`[resume] ${doneCount} pincodes already done in ${PROG}; resuming\n`);
  let partial = false;

  // Partition pincodes round-robin across CONCURRENCY isolated contexts.
  const buckets = Array.from({ length: CONCURRENCY }, () => []);
  PINCODES.forEach((p, i) => buckets[i % CONCURRENCY].push(p));
  const perPin = [];
  await Promise.all(buckets.map(async (bucket) => {
    if (!bucket.length) return;
    // SIM has no browser/context; scrapePincode short-circuits before using `page`.
    let ctx = null;
    let page = null;
    if (!SIM) ({ ctx, page } = await newCtxPage(browser));
    for (const rec of bucket) {
      if (done[rec.pincode]) { perPin.push(done[rec.pincode]); continue; }   // checkpoint hit — skip
      let res;
      try {
        res = await scrapeWithBackoff(page, rec);
      } catch (e) {
        // A per-pincode failure can never abort the bucket or the run (partial tolerance).
        process.stderr.write(`[err] ${rec.city} ${rec.pincode}: ${e.message}\n`);
        res = { ...rec, serviceable: false, store_id: '', store_name: '', rows: [], blocked: null, error: String(e && e.message) };
      }
      if (res.blocked || res.partial_block) partial = true;   // any unresolved block => partial run
      done[rec.pincode] = res;
      saveProgress(done);                                     // checkpoint AFTER each pincode
      perPin.push(res);
    }
    if (ctx) await ctx.close();
  }));
  if (browser) await browser.close();

  perPin.sort((a, b) => String(a.pincode).localeCompare(String(b.pincode)));
  const allRows = perPin.flatMap((p) => p.rows);
  const summary = {
    pincodes_total: PINCODES.length,
    pincodes_serviceable: perPin.filter((p) => p.serviceable).length,
    pincodes_with_jivo: perPin.filter((p) => p.rows.length > 0).length,
    pincodes_blocked: perPin.filter((p) => p.blocked || p.partial_block).length,
    total_rows: allRows.length,
    unique_skus: new Set(allRows.map((r) => r.canonical)).size,
    wall_s: Math.round((Date.now() - t0) / 1000),
    partial,
    captured_at: new Date().toISOString(),
    mode: SIM ? 'sim' : 'api',
  };
  process.stderr.write('[SUMMARY] ' + JSON.stringify(summary) + '\n');
  if (COMPETITOR_MODE) {
    // Competitor mode writes ONLY under tools/competitor/data/ — NEVER the jivo result.json
    // (OUT), and never under data/ vault/ reviews/ baselines/. The filename uses the
    // "flipkart-minutes_competitor_" prefix (never "Jivo-", which the mailer auto-emails).
    summary.mode = 'competitor';
    const dataDir = path.join(COMP_DIR, 'data');
    try { fs.mkdirSync(dataDir, { recursive: true }); } catch (_) { /* already exists */ }
    const outJson = path.join(dataDir, `flipkart-minutes_competitor_${COMP_DATE}.json`);
    fs.writeFileSync(outJson, JSON.stringify({ summary, allRows }, null, 2));
    // Append to the shared history CSV (create header if missing).
    const csvPath = path.join(dataDir, 'competitor_history.csv');
    const header = 'run_id,date_ist,platform,brand,category,canonical,city,pincode,store_id,pack,vol_ml,per_litre,mrp,sale,discount_pct,in_stock,rank,is_ad\n';
    if (!fs.existsSync(csvPath)) fs.writeFileSync(csvPath, header);
    const esc = (val) => { const s = (val == null) ? '' : String(val); return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
    const runId = `flipkart-minutes-${COMP_DATE}-${Date.now()}`;
    const lines = allRows.map((r) => [runId, COMP_DATE, 'flipkart-minutes', r.brand, r.category, r.canonical, r.city, r.pincode, r.store_id, r.pack, r.vol_ml, r.per_litre, r.mrp, r.sale, r.discount_pct, r.in_stock, r.rank, r.is_ad].map(esc).join(','));
    if (lines.length) fs.appendFileSync(csvPath, lines.join('\n') + '\n');
    process.stderr.write(`[comp] wrote ${allRows.length} rows -> ${outJson} and appended history -> ${csvPath}\n`);
    console.log(JSON.stringify(summary));
    return;
  }
  fs.writeFileSync(OUT, JSON.stringify({ summary, perPin, allRows, partial }, null, 2));
  console.log(JSON.stringify(summary));
})().catch((e) => {
  // In SIM (tests) there is no browser fallback to take — surface the error and exit.
  if (SIM) { process.stderr.write('[fkm-sim] crashed: ' + (e && e.message) + '\n'); process.exit(1); }
  fallbackToBrowser('api scraper crashed: ' + e.message);
});
