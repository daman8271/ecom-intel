const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

function istDateString(d = new Date()) {
  return new Date(d.getTime() + 5.5 * 3600 * 1000).toISOString().slice(0, 10);
}

// ---- COMPETITOR_MODE (env-gated, ADDITIVE — see task brief) ----------------------------
// Everything competitor-related activates ONLY when process.env.COMPETITOR_MODE === '1'.
// When it is unset, COMPETITOR_MODE is false, every const below collapses to a harmless
// default (null / {} / []), and NONE of the competitor branches execute — so the scraper's
// queries, jivo-only filter and output paths stay byte-for-byte unchanged. Competitor data
// is written ONLY under tools/competitor/ (never under data/ vault/ reviews/ baselines/).
const COMPETITOR_MODE = process.env.COMPETITOR_MODE === '1';
const COMP_DIR = path.join(__dirname, '..', '..', 'tools', 'competitor');
const COMP_DATE = process.env.COMPETITOR_DATE || istDateString();

const PFILE = process.env.PINCODES_FILE || (__dirname + '/pincodes.json');
const PINCODES = JSON.parse(fs.readFileSync(PFILE, 'utf8'));
const BLINKIT_AUTH = (() => {
  let fileAuth = {};
  if (process.env.BLINKIT_AUTH_STATE_FILE) {
    try { fileAuth = JSON.parse(fs.readFileSync(process.env.BLINKIT_AUTH_STATE_FILE, 'utf8')); }
    catch (e) { process.stderr.write(`[auth] failed to read BLINKIT_AUTH_STATE_FILE: ${e.message}\n`); }
  }
  const rawToken = process.env.BLINKIT_ACCESS_TOKEN || process.env.BLINKIT_AUTH_ACCESS_TOKEN || fileAuth.accessToken || '';
  if (!rawToken) return null;
  let accessToken = rawToken;
  try { accessToken = decodeURIComponent(rawToken); } catch (_) { /* keep raw */ }
  const deviceId = process.env.BLINKIT_DEVICE_ID || process.env.BLINKIT_AUTH_DEVICE_ID || fileAuth.deviceId || '';
  return { accessToken, deviceId };
})();
const BLINKIT_REQUIRE_AUTH = process.env.BLINKIT_REQUIRE_AUTH !== '0';
// NOTE: keep this LOW (2). Blinkit rate-limits dark-store geocode/resolution per
// IP; at concurrency >=3 from the datacenter IP many pincodes never re-resolve
// off the Gurgaon default and get (correctly) dropped as unresolved — tanking
// genuine coverage. Concurrency 2 keeps resolution ~complete. See blinkit.fix.md.
const CONCURRENCY = parseInt(process.env.CONCURRENCY || '2', 10);
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
// Blinkit stock is address/dark-store sensitive even when the header shows the same
// pincode. Treat a first-pass OOS card as provisional and probe nearby coordinates
// before publishing a hard "No".
const BLINKIT_OOS_PROBE = process.env.BLINKIT_OOS_PROBE !== '0';
const OOS_PROBE_OFFSETS = [
  { label: 'west', dlat: 0, dlon: -0.012 },
  { label: 'east', dlat: 0, dlon: 0.012 },
  { label: 'north', dlat: 0.012, dlon: 0 },
  { label: 'south', dlat: -0.012, dlon: 0 },
  { label: 'northwest', dlat: 0.012, dlon: -0.012 },
  { label: 'northeast', dlat: 0.012, dlon: 0.012 },
  { label: 'southwest', dlat: -0.012, dlon: -0.012 },
  { label: 'southeast', dlat: -0.012, dlon: 0.012 },
];
const BLINKIT_PDP_OOS_PROBE = process.env.BLINKIT_PDP_OOS_PROBE !== '0';
// Keep PDP price verification targeted: the user's screenshot failures were
// specific pincode/SKU rows where search showed a stale/base price but PDP showed
// a lower effective price. Probing every listed row would add thousands of PDP
// visits and miss the 10:00 delivery window.
const BLINKIT_PDP_PRICE_PROBE = process.env.BLINKIT_PDP_PRICE_PROBE !== '0';
const DEFAULT_PDP_PRICE_CANARIES = '110094:407561,110012:407851,110012:406593';
const PDP_PRICE_CANARIES = new Set(
  (process.env.BLINKIT_PDP_PRICE_CANARIES || DEFAULT_PDP_PRICE_CANARIES)
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
);
const PDP_PRICE_PROBE_MODE = (process.env.BLINKIT_PDP_PRICE_PROBE_MODE || 'expanded').trim().toLowerCase();
const PDP_PRICE_PROBE_MIN_SALE = parseInt(process.env.BLINKIT_PDP_PRICE_PROBE_MIN_SALE || '1100', 10);
const PDP_PRICE_PROBE_MIN_VOL_ML = parseInt(process.env.BLINKIT_PDP_PRICE_PROBE_MIN_VOL_ML || '5000', 10);

// ---- Hardening (Wave-1 coverage pilot, 2026-06-29) -------------------------------
// At 1,885 pincodes a run is long, so it MUST survive interruption and rate-limiting
// without losing work or throwing. Three additions, all opt-in / fail-safe:
//   (1) checkpoint/resume — per-pincode result cached in .progress.<date>.json; a
//       re-run the same day skips finished pincodes and resumes where it stopped.
//   (2) block-detection + exponential backoff — a 403/429/503 or an Akamai/"access
//       denied"/captcha body is treated as a block: back off (capped) and retry a
//       few times, then record 0 rows and flag the run partial (NEVER evade — owner rule).
//   (3) partial tolerance — one pincode can never kill the run; result.json always
//       gets written with a top-level `partial` flag so the batch wrapper sees it.
// SIM hooks (BLINKIT_SIM / BLINKIT_BLOCK_SIM) drive the hermetic fault-injection
// tests in test_hardening.md without launching a browser or hitting Blinkit live.
const PROG = process.env.BLINKIT_PROGRESS_FILE || (COMPETITOR_MODE
  ? `${COMP_DIR}/data/.progress.competitor.${path.basename(__dirname)}.${COMP_DATE}.json`
  : `${__dirname}/.progress.${istDateString()}.json`);
const MAX_BLOCK_RETRIES = parseInt(process.env.BLINKIT_BLOCK_RETRIES || '4', 10);
// Body signatures of a block page. Deliberately specific (NOT bare "403"/"429",
// which could appear in legitimate page text) — HTTP status carries those.
const BLOCK_RE = /access denied|akamai|reference #\s*\d|too many requests|rate[\s-]?limit|are you a human|captcha|forbidden/i;

async function backoff(attempt) {
  const ms = Math.min(60000, 2000 * Math.pow(2, attempt)) + Math.floor(Math.random() * 1000);
  process.stderr.write(`[backoff] attempt ${attempt} -> sleeping ${Math.round(ms)}ms\n`);
  await new Promise((r) => setTimeout(r, ms));
}

// Classify a navigation response / page as blocked. Returns a short reason string or null.
async function pageBlocked(resp, page) {
  try {
    if (resp && typeof resp.status === 'function') {
      const s = resp.status();
      if (s === 403 || s === 429 || s === 503) return `http ${s}`;
    }
    const body = (await page.content()).slice(0, 5000);
    if (BLOCK_RE.test(body)) return 'block-signature';
  } catch (_) { /* content() can race a navigation; treat as not-blocked */ }
  return null;
}

function loadProgress() {
  try { return fs.existsSync(PROG) ? JSON.parse(fs.readFileSync(PROG, 'utf8')) : {}; }
  catch (_) { return {}; }
}
function saveProgress(done) {
  try { fs.writeFileSync(PROG, JSON.stringify(done)); } catch (e) { process.stderr.write(`[progress] write failed: ${e.message}\n`); }
}

function parseVolMl(pack) {
  if (!pack) return null;
  const s = pack.toLowerCase();
  const toMl = (n, u) => {
    if (u === 'ml' || u === 'g') return n;
    if (u === 'l' || u === 'ltr' || u === 'litre' || u === 'kg') return n * 1000;
    return null;
  };
  // Combo packs come in BOTH orders ("1 l x 2" and "2 x 1 l" are the same 2L pack —
  // same fix as zepto 2026-06-10). They must run BEFORE the single-quantity match,
  // which would otherwise read only the first token and halve the recorded volume
  // (doubling Rs/L). Unit-first "N unit X M":
  let m = s.match(/([\d.]+)\s*(ml|l|ltr|litre|kg|g)\b\s*[x×]\s*([\d.]+)/);
  if (m) { const base = toMl(parseFloat(m[1]), m[2]); return base != null ? base * parseFloat(m[3]) : null; }
  // Multiplier-first "M x N unit" ("2 x 1 l", "2x1l", "3 x 500 ml"):
  m = s.match(/([\d.]+)\s*[x×]\s*([\d.]+)\s*(ml|l|ltr|litre|kg|g)\b/);
  if (m) { const base = toMl(parseFloat(m[2]), m[3]); return base != null ? parseFloat(m[1]) * base : null; }
  // Single quantity (original first-token behavior, unchanged).
  m = s.match(/([\d.]+)\s*(ml|l|ltr|litre|kg|g)/);
  if (!m) return null;
  return toMl(parseFloat(m[1]), m[2]);
}

function parseRs(value) {
  const n = parseInt(String(value || '').replace(/,/g, ''), 10);
  return Number.isFinite(n) ? n : null;
}

function rupeePrices(text) {
  return [...String(text || '').matchAll(/₹\s*([\d,]+)/g)]
    .map((m) => parseRs(m[1]))
    .filter((n) => n != null);
}

function buyAtPrice(text) {
  const body = String(text || '').replace(/\s+/g, ' ').trim();
  const patterns = [
    /\bbuy\s+at\s*₹\s*([\d,]+)/ig,
    /\bbuy\s+for\s*₹\s*([\d,]+)/ig,
    /\beffective(?:\s+price)?\s*₹\s*([\d,]+)/ig,
    /\bget\s+it\s+at\s*₹\s*([\d,]+)/ig,
  ];
  const vals = [];
  for (const re of patterns) {
    let m;
    while ((m = re.exec(body))) {
      const n = parseRs(m[1]);
      if (n != null) vals.push(n);
    }
  }
  return vals.length ? Math.min(...vals) : null;
}

function priceInfo(text, volMl, disc = null) {
  const body = String(text || '');
  const prices = rupeePrices(body);
  const mrpMatch = body.match(/MRP\s*₹\s*([\d,]+)/i);
  const baseSale = prices.length ? prices[0] : null;
  const mrp = mrpMatch ? parseRs(mrpMatch[1]) : (prices.length > 1 ? prices[1] : baseSale);
  const offerSale = buyAtPrice(body);
  const sale = (offerSale != null && (baseSale == null || offerSale <= baseSale)) ? offerSale : baseSale;
  return {
    sale,
    mrp,
    base_sale: baseSale,
    offer_sale: (offerSale != null && baseSale != null && offerSale < baseSale) ? offerSale : null,
    discount_pct: (mrp && sale && mrp >= sale) ? Math.round(((mrp - sale) / mrp) * 1000) / 10 : (disc ? parseFloat(disc) : null),
    per_litre: volMl && sale ? Math.round((sale / (volMl / 1000)) * 100) / 100 : null,
  };
}

function priceSource(source, info) {
  return info && info.offer_sale ? `${source}_offer` : source;
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

function canonical(name, pack, brand) {
  const base = (name || '').toLowerCase()
    .replace(/\(.*?\)/g, '')
    .replace(/[^a-z0-9 ]/g, '')
    .replace(/\s+/g, ' ').trim()
    .replace(/\s/g, '-');
  const vol = parseVolMl(pack);
  const volTag = vol ? (vol >= 1000 ? (vol / 1000) + 'l' : vol + 'ml') : 'na';
  // brand is OPTIONAL: it is only ever passed in COMPETITOR_MODE. When omitted/falsy
  // brandTag is '' and the returned canonical is byte-for-byte identical to before.
  const brandTag = brand ? (String(brand).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') + '-') : '';
  return `${brandTag}${base}-${volTag}`.replace(/--+/g, '-');
}

function locationLabel(rec) {
  if (rec.landmark) return rec.landmark;
  if (rec.city === 'Delhi') return `New Delhi, Delhi ${rec.pincode}, India`;
  return `${rec.locality || rec.city}, ${rec.city} ${rec.pincode}, India`;
}

function locationLocality(rec) {
  if (rec.city === 'Delhi') return 'New Delhi';
  return rec.locality || rec.city;
}

function locationCookieSpecs(rec) {
  const locality = locationLocality(rec);
  const landmark = locationLabel(rec);
  return [
    { name: 'gr_1_lat', value: String(rec.lat), domain: 'blinkit.com', path: '/' },
    { name: 'gr_1_lon', value: String(rec.lon), domain: 'blinkit.com', path: '/' },
    { name: 'gr_1_locality', value: encodeURIComponent(locality), domain: 'blinkit.com', path: '/' },
    { name: 'gr_1_landmark', value: encodeURIComponent(landmark), domain: 'blinkit.com', path: '/' },
  ];
}

function probeRecords(rec) {
  return OOS_PROBE_OFFSETS.map((o) => ({
    ...rec,
    lat: Math.round((Number(rec.lat) + o.dlat) * 1e7) / 1e7,
    lon: Math.round((Number(rec.lon) + o.dlon) * 1e7) / 1e7,
    probe_label: o.label,
  }));
}

function shouldPdpPriceProbe(rec, row) {
  if (!BLINKIT_PDP_PRICE_PROBE) return false;
  if (!row || !row.in_stock || !row.listing_url || !row.prid) return false;
  const pin = String(rec && rec.pincode || row.pincode || '').trim();
  const prid = String(row.prid || '').trim();
  if (PDP_PRICE_CANARIES.has(`${pin}:${prid}`) || PDP_PRICE_CANARIES.has(`*:${prid}`)) return true;
  if (PDP_PRICE_PROBE_MODE === 'canary') return false;
  if (PDP_PRICE_PROBE_MODE === 'all') return true;

  const source = String(row.price_source || row.stock_source || '').trim().toLowerCase();
  const hasOfferEvidence = row.offer_sale != null || source.includes('offer') || source.includes('pdp');
  if (hasOfferEvidence) return false;

  const sale = Number(row.sale || 0);
  const vol = Number(row.vol_ml || parseVolMl(row.pack) || 0);
  const plainSearch = source === '' || source === 'search_card' || source === 'search_probe';
  const highValue = (
    (Number.isFinite(sale) && sale >= PDP_PRICE_PROBE_MIN_SALE) &&
    (Number.isFinite(vol) && vol >= PDP_PRICE_PROBE_MIN_VOL_ML)
  );
  return plainSearch && highValue;
}

function markUnverifiedOosRows(rows) {
  return rows.map((row) => {
    if (!row || row.in_stock !== 0) return row;
    const stockSource = String(row.stock_source || '').trim().toLowerCase();
    const verified = row.pdp_checked || stockSource === 'pdp' || stockSource === 'pdp_probe';
    if (verified) return row;
    return {
      ...row,
      in_stock: null,
      listing_status: 'stock_unverified',
      stock_source: stockSource ? `${stockSource}_unverified` : 'search_card_oos_unverified',
      stock_unverified: 1,
    };
  });
}

function parseJivoCards(cards, rec, store) {
  const out = [];
  for (const card of cards) {
    const c = (card && typeof card === 'object') ? (card.text || '') : (card || '');
    // pattern: [disc% OFF] [eta MINS] NAME PACK ₹SALE ₹MRP ADD/OutofStock
    const inStock = !/out of stock/i.test(c);
    const eta = (c.match(/(\d+)\s*MINS?/i) || [])[1];
    const disc = (c.match(/(\d+)%\s*OFF/i) || [])[1];
    // name: between the MINS/OFF prefix and the first ₹ / pack
    let name = c.replace(/^\d+%\s*OFF\s*/i, '').replace(/^.*?\d+\s*MINS?\s*/i, '');
    name = name.replace(/Out of Stock/i, '').trim();
    const packM = name.match(/(\d[\d.]*\s*(?:ml|l|ltr|litre|kg|g))/i);
    const pack = packM ? packM[1] : '';
    name = name.replace(/₹.*$/, '').replace(/ADD\s*$/i, '');
    if (pack) name = name.split(pack)[0];
    name = name.trim();
    const volMl = parseVolMl(pack);
    const price = priceInfo(c, volMl, disc);
    if (!/jivo/i.test(name) || !price.sale) continue;
    // listing identity (additive, fail-safe): prid + constructed PDP url. Prefer the
    // real anchor slug; else slugify the parsed name (Blinkit routes PDPs on prid —
    // the slug segment is cosmetic). On any error the row is built exactly as before.
    let identity = {};
    try {
      const prid = (card && typeof card === 'object' && card.prid) ? String(card.prid) : '';
      if (prid) {
        const slug = (card.slug || name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '')) || 'p';
        identity = { prid, listing_url: `https://blinkit.com/prn/${slug}/prid/${prid}` };
      }
    } catch (_) { identity = {}; }
    out.push({
      city: rec.city, pincode: rec.pincode, locality: rec.locality,
      store_id: store.id || '', store_name: store.name || '',
      sku_raw: name, canonical: canonical(name, pack), pack: pack || '',
      vol_ml: volMl, sale: price.sale, mrp: price.mrp,
      base_sale: price.base_sale, offer_sale: price.offer_sale,
      discount_pct: price.discount_pct,
      per_litre: price.per_litre,
      eta_min: eta ? parseInt(eta, 10) : null,
      in_stock: inStock ? 1 : 0,
      listing_status: inStock ? 'listed_in_stock' : 'listed_out_of_stock',
      stock_source: 'search_card',
      price_source: priceSource(inStock ? 'search_card' : 'search_card_oos', price),
      ...identity,
    });
  }
  return out;
}

function pdpPackVariants(row) {
  const variants = new Set();
  if (row.pack) variants.add(String(row.pack).replace(/\s+/g, ' ').trim());
  const vol = Number(row.vol_ml || parseVolMl(row.pack));
  if (vol) {
    if (vol >= 1000) {
      const litres = vol / 1000;
      const s = Number.isInteger(litres) ? String(litres) : String(litres).replace(/\.0+$/, '');
      variants.add(`${s} l`);
      variants.add(`${s} ltr`);
      variants.add(`${s} litre`);
      variants.add(`${s} liter`);
    } else {
      variants.add(`${vol} ml`);
    }
  }
  return [...variants].filter(Boolean);
}

function cleanProductName(name) {
  let out = String(name || '').replace(/\s+/g, ' ').trim();
  while (out.endsWith('(')) out = out.slice(0, -1).trim();
  return out;
}

function parsePdpProductText(text, row) {
  const body = String(text || '').replace(/\s+/g, ' ').trim();
  const lower = body.toLowerCase();
  const name = cleanProductName(row.sku_raw);
  if (!name) return null;
  const candidates = [];
  const packVariants = pdpPackVariants(row).map((pack) => String(pack).toLowerCase());
  for (const pack of pdpPackVariants(row)) {
    const needle = `${name} ${pack}`.toLowerCase();
    let idx = lower.indexOf(needle);
    while (idx >= 0) {
      candidates.push(idx);
      idx = lower.indexOf(needle, idx + 1);
    }
  }
  let nameIdx = lower.indexOf(name.toLowerCase());
  while (nameIdx >= 0) {
    const nearby = lower.slice(nameIdx, nameIdx + 220);
    if (packVariants.some((pack) => nearby.includes(pack) || nearby.includes(`(${pack})`))) {
      candidates.push(nameIdx);
    }
    nameIdx = lower.indexOf(name.toLowerCase(), nameIdx + 1);
  }
  if (!candidates.length) return null;
  let segment = '';
  for (const idx of candidates) {
    const snip = body.slice(idx, idx + 650);
    const head = snip.split(/Why shop from blinkit\?/i)[0];
    if (/out of stock|add to cart|\bADD\b|₹/.test(head)) {
      segment = head;
      break;
    }
  }
  if (!segment) segment = body.slice(candidates[0], candidates[0] + 450).split(/Why shop from blinkit\?/i)[0];
  const out = /out of stock/i.test(segment);
  const hasAdd = /add to cart|\bADD\b/i.test(segment);
  const price = priceInfo(segment, row.vol_ml);
  return {
    in_stock: hasAdd && !out ? 1 : 0,
    sale: price.sale,
    mrp: price.mrp,
    base_sale: price.base_sale,
    offer_sale: price.offer_sale,
    discount_pct: price.discount_pct,
    per_litre: price.per_litre,
    snippet: segment.slice(0, 240),
  };
}

async function extractJivoCards(page) {
  return page.evaluate(() => {
    const out = [];
    const seen = new Set();
    const isVisibleCard = (el) => {
      const r = el.getBoundingClientRect();
      if (r.width < 100 || r.width > 420) return false;
      if (r.height < 180 || r.height > 620) return false;
      if (r.bottom < 0 || r.top > window.innerHeight * 3) return false;
      let cur = el;
      while (cur && cur !== document.documentElement) {
        const st = window.getComputedStyle(cur);
        if (st.display === 'none' || st.visibility === 'hidden' || Number(st.opacity || 1) === 0) return false;
        if (cur.getAttribute && cur.getAttribute('aria-hidden') === 'true') return false;
        cur = cur.parentElement;
      }
      return true;
    };
    document.querySelectorAll('div').forEach((el) => {
      const t = el.innerText || '';
      if (!/jivo/i.test(t) || !/₹/.test(t)) return;
      if (!isVisibleCard(el)) return;
      const key = t.slice(0, 90);
      if (seen.has(key)) return;
      seen.add(key);
      // ---- listing identity (ADDITIVE, fail-safe): numeric prid + PDP slug ----
      // Blinkit PDP urls are /prn/<slug>/prid/<prid> (owner-blessed form, see
      // tools/pricematch/fragments/map-qcom.json). Defensive: try a PDP anchor inside
      // or wrapping the card first; else a numeric id/data attribute on the card or a
      // close ancestor/descendant (SPA cards without hrefs). On ANY error the card is
      // recorded exactly as before (prid/slug just stay empty).
      let prid = '';
      let slug = '';
      try {
        const a = el.querySelector('a[href*="/prid/"]') || (el.closest ? el.closest('a[href*="/prid/"]') : null);
        const href = (a && a.getAttribute('href')) || '';
        const m = href.match(/\/prn\/([^/?#]+)\/prid\/(\d+)/);
        if (m) { slug = m[1]; prid = m[2]; }
        if (!prid) {
          const cand = [el, el.parentElement, el.closest ? el.closest('[id]') : null, el.querySelector('[id]')].filter(Boolean);
          for (const c2 of cand) {
            const idv = (c2.getAttribute && (c2.getAttribute('data-pid') || c2.getAttribute('data-product-id') || c2.getAttribute('id'))) || '';
            if (/^\d{4,8}$/.test(idv)) { prid = idv; break; }
          }
        }
      } catch (_) { prid = ''; slug = ''; }
      out.push({ text: t.replace(/\s+/g, ' ').trim(), prid, slug });
    });
    return out;
  });
}

// ======================= COMPETITOR_MODE helpers (env-gated) =======================
// All of the following are pure helpers + module-level constants used ONLY by the
// competitor branch. None run / mutate anything when COMPETITOR_MODE is unset.
function escRe(s) { return String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }

// Brand whitelist regex, resolved from (in order): tools/competitor/competitor_brands.json
// (accepts a raw regex string, {regex:"..."}, an array of brands, or {brands:[...]}),
// then env COMPETITOR_BRANDS (comma list), then a sane edible-oil default list.
function loadCompetitorRegex() {
  const def = ['jivo', 'fortune', 'saffola', 'dhara', 'gemini', 'sundrop', 'figaro', 'nature fresh',
    'emami healthy', 'patanjali', 'dalda', 'freedom', 'sweekar', 'postman', 'gold ?drop', 'gold ?winner',
    'ricela', 'borges', 'disano', 'del monte', 'oleev', 'kohinoor', 'mahakosh', 'engine', 'p mark',
    'gagan', 'scoop', 'rasoi', 'ktc', 'aashirvaad', 'tata'];
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
  const def = ['mustard oil', 'sunflower oil', 'refined oil', 'soyabean oil', 'groundnut oil',
    'rice bran oil', 'olive oil', 'ghee', 'vegetable oil'];
  try {
    const f = path.join(COMP_DIR, 'category_queries.json');
    if (fs.existsSync(f)) {
      const j = JSON.parse(fs.readFileSync(f, 'utf8'));
      if (Array.isArray(j)) return j.filter(Boolean);
      if (j && Array.isArray(j.queries)) return j.queries.filter(Boolean);
      if (j && typeof j === 'object') return Object.keys(j).filter(Boolean);
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

// Brand label = the whitelist substring actually present in the product name.
function deriveBrand(name) {
  if (!COMPETITOR_RE) return '';
  const m = (name || '').match(COMPETITOR_RE);
  return m ? m[0].replace(/\s+/g, ' ').trim() : '';
}

// Category from the explicit map, else keyword-scan name then query term.
function deriveCategory(term, name) {
  const t = (term || '').toLowerCase();
  const n = (name || '').toLowerCase();
  if (CATEGORY_MAP[t]) return CATEGORY_MAP[t];
  const cats = [
    [/mustard|kachi ghani|sarso/, 'mustard oil'],
    [/sunflower/, 'sunflower oil'],
    [/soya|soybean|soyabean/, 'soyabean oil'],
    [/groundnut|peanut/, 'groundnut oil'],
    [/rice ?bran/, 'rice bran oil'],
    [/olive/, 'olive oil'],
    [/canola/, 'canola oil'],
    [/sesame|gingelly|til\b/, 'sesame oil'],
    [/coconut/, 'coconut oil'],
    [/ghee/, 'ghee'],
    [/double refined|refined/, 'refined oil'],
    [/blend/, 'blended oil'],
    [/vegetable/, 'vegetable oil'],
  ];
  for (const [re, c] of cats) { if (re.test(n) || re.test(t)) return c; }
  return (t && t !== 'jivo') ? t : 'edible oil';
}

// Light sub-grade extraction from the product name (best-effort; '' when none found).
function deriveSubGrade(name) {
  const n = (name || '').toLowerCase();
  const grades = [
    [/extra virgin/, 'extra virgin'],
    [/virgin/, 'virgin'],
    [/double refined/, 'double refined'],
    [/kachi ghani|cold ?press|wood ?press|wooden ?press|ghani/, 'cold pressed'],
    [/filtered/, 'filtered'],
    [/refined/, 'refined'],
    [/pomace/, 'pomace'],
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

// Built once at module load; only populated when COMPETITOR_MODE is on.
const COMPETITOR_RE = COMPETITOR_MODE ? loadCompetitorRegex() : null;
const CATEGORY_MAP = COMPETITOR_MODE ? loadCategoryMap() : {};
const COMPETITOR_TERMS = COMPETITOR_MODE ? Array.from(new Set(['jivo', ...loadCategoryQueries()])) : [];
// ===================== end COMPETITOR_MODE helpers =====================

async function scrapeOne(browser, rec) {
  const t0 = Date.now();
  // SIM hooks (tests only; never active in production runs):
  //   BLINKIT_BLOCK_SIM=1 -> every pincode reports blocked (drives the backoff/partial test)
  //   BLINKIT_SIM=1       -> return a synthetic resolved row without a browser (resume test)
  if (process.env.BLINKIT_BLOCK_SIM === '1') {
    await new Promise((r) => setTimeout(r, 10));
    return { ...rec, store_id: '', store_name: '', resolved: false, blocked: 'sim-block', rows: [] };
  }
  if (process.env.BLINKIT_SIM === '1') {
    await new Promise((r) => setTimeout(r, 10));
    const rows = [{
      city: rec.city, pincode: rec.pincode, locality: rec.locality,
      store_id: 'sim', store_name: 'sim-store', sku_raw: 'Jivo Sim Oil',
      canonical: 'jivo-sim-oil-1l', pack: '1 l', vol_ml: 1000, sale: 199, mrp: 250,
      discount_pct: 20, per_litre: 199, eta_min: 10, in_stock: 1,
    }];
    return { ...rec, store_id: 'sim', store_name: 'sim-store', resolved: true, blocked: null, auth_accepted: BLINKIT_AUTH ? 1 : 0, rows };
  }
  const ctx = await browser.newContext({
    userAgent: UA,
    locale: 'en-IN',
    timezoneId: 'Asia/Kolkata',
    viewport: { width: 1280, height: 900 },
  });
  if (BLINKIT_AUTH) {
    await ctx.addInitScript((auth) => {
      try {
        localStorage.setItem('auth', JSON.stringify({ accessToken: auth.accessToken, phoneNumber: null }));
        if (auth.deviceId) localStorage.setItem('deviceId', auth.deviceId);
      } catch (_) { /* best-effort session hydration */ }
    }, BLINKIT_AUTH);
    const cookies = [{
      name: 'gr_1_accessToken',
      value: encodeURIComponent(BLINKIT_AUTH.accessToken),
      domain: 'blinkit.com',
      path: '/',
    }];
    if (BLINKIT_AUTH.deviceId) cookies.push({
      name: 'gr_1_deviceId',
      value: BLINKIT_AUTH.deviceId,
      domain: 'blinkit.com',
      path: '/',
    });
    await ctx.addCookies(cookies);
  }
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
  let blocked = null;
  let authAccepted = false;
  const injectLocation = async (r) => {
    try { await ctx.addCookies(locationCookieSpecs(r)); } catch (_) { /* cookie location is best-effort */ }
    return page.evaluate((rr) => {
    localStorage.setItem('location', JSON.stringify({
      coords: {
        isDefault: false,
        lat: rr.lat,
        lon: rr.lon,
        locality: rr.locationLocality,
        id: 1,
        isTopCity: true,
        cityName: rr.city,
        landmark: rr.locationLabel,
        addressId: null,
      }
    }));
    }, { ...r, locationLocality: locationLocality(r), locationLabel: locationLabel(r) });
  };
  const readState = async () => {
    const loc = JSON.parse((await page.evaluate(() => localStorage.getItem('location'))) || '{}');
    const m = JSON.parse((await page.evaluate(() => localStorage.getItem('merchant'))) || '{}');
    return { loc, m };
  };
  const waitForAuthAccepted = async () => {
    if (!BLINKIT_AUTH) return false;
    for (let poll = 0; poll < 8; poll++) {
      const ok = await page.evaluate(() => {
        const authKey = localStorage.getItem('authKey') || localStorage.getItem('authKeyITS');
        let user = null;
        try { user = JSON.parse(localStorage.getItem('user') || '{}'); } catch (_) { user = null; }
        const profile = user && typeof user === 'object' ? user.profile : null;
        return Boolean(authKey || (profile && Object.keys(profile).length));
      }).catch(() => false);
      if (ok) return true;
      await page.waitForTimeout(500);
    }
    return false;
  };
  const resolveLocationFor = async (r, polls = 4) => {
    let probeLoc = {};
    let probeStore = {};
    await injectLocation(r);
    await page.goto('https://blinkit.com/', { waitUntil: 'domcontentloaded', timeout: 30000 });
    for (let poll = 0; poll < polls; poll++) {
      await page.waitForTimeout(900);
      ({ loc: probeLoc, m: probeStore } = await readState());
      if (storeResolved(probeLoc, probeStore, r)) return { resolved: true, loc: probeLoc, store: probeStore };
    }
    return { resolved: false, loc: probeLoc, store: probeStore };
  };
  const verifyPdpRow = async (r, row, label) => {
    if (!row.listing_url) return null;
    const resolvedPdpLoc = await resolveLocationFor(r, 4);
    if (!resolvedPdpLoc.resolved) return null;
    await injectLocation(r);
    await page.goto(row.listing_url, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(3500);
    const { loc: pdpLoc, m: pdpStore } = await readState();
    if (!storeResolved(pdpLoc, pdpStore, r)) return null;
    const text = await page.evaluate(() => document.body.innerText || '');
    const parsed = parsePdpProductText(text, row);
    if (!parsed) return null;
    return {
      ...parsed,
      store: pdpStore,
      probe_label: label,
      probe_lat: r.lat,
      probe_lon: r.lon,
    };
  };
  try {
    const firstResp = await page.goto('https://blinkit.com/', { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(2000);
    // Block check on the landing page: if Blinkit is rate-limiting/Akamai-walling this
    // IP, bail early with a blocked signal so the caller can back off (never evade).
    blocked = await pageBlocked(firstResp, page);
    if (blocked) {
      process.stderr.write(`[blocked] ${rec.city} ${rec.pincode} -> ${blocked} on landing\n`);
      await ctx.close();
      return { ...rec, store_id: '', store_name: '', resolved: false, blocked, rows: [] };
    }
    authAccepted = await waitForAuthAccepted();
    if (BLINKIT_REQUIRE_AUTH && !authAccepted) {
      process.stderr.write(`[auth] ${rec.city} ${rec.pincode} -> Blinkit did not accept hydrated auth session\n`);
      await ctx.close();
      return { ...rec, store_id: '', store_name: '', resolved: false, blocked: 'auth-not-accepted', auth_accepted: 0, rows: [] };
    }
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
      return { ...rec, store_id: '', store_name: '', resolved: false, auth_accepted: authAccepted ? 1 : 0, rows: [] };
    }
    // ===== COMPETITOR_MODE branch (env-gated, ADDITIVE; the original jivo path below is
    // left fully intact and runs verbatim whenever COMPETITOR_MODE is unset). Loops over
    // [jivo + category queries], reusing the SAME injectLocation -> goto -> readState ->
    // harvest block per term, keeps a card when it matches the brand whitelist (not just
    // /jivo/) AND has a ₹ price, derives brand+category+sub_grade, and emits the shared
    // competitor row contract. Writes NOTHING here — the main runner writes only under
    // tools/competitor/. Returns the same result shape as the jivo path. =====
    if (COMPETITOR_MODE) {
      for (const term of COMPETITOR_TERMS) {
        await injectLocation(rec);
        await page.goto(`https://blinkit.com/s/?q=${encodeURIComponent(term)}`, { waitUntil: 'domcontentloaded', timeout: 30000 });
        await page.waitForTimeout(4500);
        ({ loc: activeLoc, m: store } = await readState());
        if (!storeResolved(activeLoc, store, rec)) {
          process.stderr.write(`[unresolved] ${rec.city} ${rec.pincode} -> store reverted on search "${term}" (active store=${store.name || 'n/a'} id=${store.id || ''}); skipping term\n`);
          continue;
        }
        const cards = await page.evaluate((reSrc) => {
          const RE = new RegExp(reSrc, 'i');
          const out = [];
          const seen = new Set();
          document.querySelectorAll('div').forEach((el) => {
            const t = el.innerText || '';
            // competitor gate (DOM harvest): whitelist regex instead of /jivo/, keep the ₹ gate
            if (!RE.test(t) || !/₹/.test(t)) return;
            const r = el.getBoundingClientRect();
            if (r.width < 100 || r.width > 420) return;
            if (r.height < 180 || r.height > 620) return;
            const key = t.slice(0, 90);
            if (seen.has(key)) return;
            seen.add(key);
            let prid = '';
            let slug = '';
            try {
              const a = el.querySelector('a[href*="/prid/"]') || (el.closest ? el.closest('a[href*="/prid/"]') : null);
              const href = (a && a.getAttribute('href')) || '';
              const m = href.match(/\/prn\/([^/?#]+)\/prid\/(\d+)/);
              if (m) { slug = m[1]; prid = m[2]; }
              if (!prid) {
                const cand = [el, el.parentElement, el.closest ? el.closest('[id]') : null, el.querySelector('[id]')].filter(Boolean);
                for (const c2 of cand) {
                  const idv = (c2.getAttribute && (c2.getAttribute('data-pid') || c2.getAttribute('data-product-id') || c2.getAttribute('id'))) || '';
                  if (/^\d{4,8}$/.test(idv)) { prid = idv; break; }
                }
              }
            } catch (_) { prid = ''; slug = ''; }
            out.push({ text: t.replace(/\s+/g, ' ').trim(), prid, slug, rank: out.length + 1 });
          });
          return out;
        }, COMPETITOR_RE.source);
        for (const card of cards) {
          const c = (card && typeof card === 'object') ? (card.text || '') : (card || '');
          const inStock = !/out of stock/i.test(c);
          const eta = (c.match(/(\d+)\s*MINS?/i) || [])[1];
          const disc = (c.match(/(\d+)%\s*OFF/i) || [])[1];
          const prices = [...c.matchAll(/₹\s*([\d,]+)/g)].map((m) => parseInt(m[1].replace(/,/g, ''), 10));
          const sale = prices.length ? prices[0] : null;
          const mrp = prices.length > 1 ? prices[1] : sale;
          let name = c.replace(/^\d+%\s*OFF\s*/i, '').replace(/^.*?\d+\s*MINS?\s*/i, '');
          name = name.replace(/Out of Stock/i, '').trim();
          const packM = name.match(/(\d[\d.]*\s*(?:ml|l|ltr|litre|kg|g))/i);
          const pack = packM ? packM[1] : '';
          name = name.replace(/₹.*$/, '').replace(/ADD\s*$/i, '');
          if (pack) name = name.split(pack)[0];
          name = name.trim();
          // competitor gate (row build): keep when the NAME matches the whitelist + has a price
          if (!COMPETITOR_RE.test(name) || !sale) continue;
          const brand = deriveBrand(name);
          const category = deriveCategory(term, name);
          const subGrade = deriveSubGrade(name);
          const isGhee = /ghee/i.test(name) || /ghee/i.test(category);
          const unit = packUnit(pack);
          const volMl = competitorVolMl(pack, isGhee);
          // ad/sponsored detector: standalone "Ad"/"sponsored" only (won't match the "ADD" button)
          const isAd = (/\bsponsored\b/i.test(c) || /(^|[^a-z])ad([^a-z]|$)/i.test(c)) ? 1 : 0;
          let identity = {};
          try {
            const prid = (card && typeof card === 'object' && card.prid) ? String(card.prid) : '';
            if (prid) {
              const slug = (card.slug || name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '')) || 'p';
              identity = { prid, listing_url: `https://blinkit.com/prn/${slug}/prid/${prid}` };
            }
          } catch (_) { identity = {}; }
          rows.push({
            platform: 'blinkit',
            city: rec.city, pincode: rec.pincode,
            store_id: store.id || '', store_name: store.name || '',
            brand, name, canonical: canonical(name, pack, brand),
            category, sub_grade: subGrade,
            pack: pack || '', vol_ml: volMl, unit,
            per_litre: volMl ? Math.round((sale / (volMl / 1000)) * 100) / 100 : null,
            mrp, sale,
            discount_pct: (mrp && sale && mrp >= sale) ? Math.round(((mrp - sale) / mrp) * 1000) / 10 : (disc ? parseFloat(disc) : null),
            in_stock: inStock ? 1 : 0,
            rank: (card && typeof card === 'object' && card.rank) ? card.rank : null,
            is_ad: isAd,
            captured_at: new Date().toISOString(),
            ...identity,
          });
        }
      }
      // dedup on (store_id, brand, canonical): brand in the key (and inside canonical) keeps
      // a competitor and a JIVO SKU of the same name+pack from collapsing into one row.
      const ddc = new Map();
      for (const r of rows) {
        const k = `${r.store_id}|${(r.brand || '').toLowerCase()}|${r.canonical}`;
        if (!ddc.has(k)) ddc.set(k, r);
      }
      rows = [...ddc.values()];
      process.stderr.write(`[ok:comp] ${rec.city} ${rec.pincode} -> ${rows.length} competitor SKUs across ${COMPETITOR_TERMS.length} queries (${((Date.now() - t0) / 1000).toFixed(1)}s) store=${store.name || 'n/a'}\n`);
      return { ...rec, store_id: store.id || '', store_name: store.name || '', resolved, blocked, auth_accepted: authAccepted ? 1 : 0, rows };
    }
    // Resolved on home — now run the Jivo search, then RE-VERIFY the active
    // store didn't revert during the search navigation before trusting cards.
    await injectLocation(rec);
    await page.goto('https://blinkit.com/s/?q=jivo', { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(4500);
    ({ loc: activeLoc, m: store } = await readState());
    if (!storeResolved(activeLoc, store, rec)) {
      process.stderr.write(`[unresolved] ${rec.city} ${rec.pincode} -> store reverted on search (active store=${store.name || 'n/a'} id=${store.id || ''}); recording 0 rows\n`);
      return { ...rec, store_id: '', store_name: '', resolved: false, auth_accepted: authAccepted ? 1 : 0, rows: [] };
    }
    const cards = await extractJivoCards(page);
    rows.push(...parseJivoCards(cards, rec, store));
    const primaryStore = { ...store };

    if (BLINKIT_OOS_PROBE && rows.some((r) => !r.in_stock)) {
      for (const probeRec of probeRecords(rec)) {
        if (!rows.some((r) => !r.in_stock)) break;
        let probeResolved = false;
        let probeLoc = {};
        let probeStore = {};
        await injectLocation(probeRec);
        await page.goto('https://blinkit.com/', { waitUntil: 'domcontentloaded', timeout: 30000 });
        for (let poll = 0; poll < 4 && !probeResolved; poll++) {
          await page.waitForTimeout(900);
          ({ loc: probeLoc, m: probeStore } = await readState());
          probeResolved = storeResolved(probeLoc, probeStore, probeRec);
        }
        if (!probeResolved) continue;
        await injectLocation(probeRec);
        await page.goto('https://blinkit.com/s/?q=jivo', { waitUntil: 'domcontentloaded', timeout: 30000 });
        await page.waitForTimeout(3500);
        ({ loc: probeLoc, m: probeStore } = await readState());
        if (!storeResolved(probeLoc, probeStore, probeRec)) continue;

        const probeRows = parseJivoCards(await extractJivoCards(page), rec, probeStore);
        let flips = 0;
        for (const candidate of probeRows) {
          if (!candidate.in_stock) continue;
          const idx = rows.findIndex((r) => {
            if (r.in_stock) return false;
            if (r.prid && candidate.prid) return String(r.prid) === String(candidate.prid);
            return r.canonical === candidate.canonical;
          });
          if (idx < 0) continue;
          const prev = rows[idx];
          rows[idx] = {
            ...prev,
            store_id: candidate.store_id,
            store_name: candidate.store_name,
            sale: candidate.sale,
            mrp: candidate.mrp,
            base_sale: candidate.base_sale,
            offer_sale: candidate.offer_sale,
            discount_pct: candidate.discount_pct,
            per_litre: candidate.per_litre,
            eta_min: candidate.eta_min,
            in_stock: 1,
            listing_status: 'listed_in_stock',
            stock_source: 'search_probe',
            price_source: priceSource('search_probe', candidate),
            search_in_stock: prev.in_stock,
            search_sale: prev.sale,
            search_mrp: prev.mrp,
            stock_probe: 'nearby_same_pincode',
            stock_probe_label: probeRec.probe_label,
            stock_probe_lat: probeRec.lat,
            stock_probe_lon: probeRec.lon,
            primary_store_id: prev.store_id,
            primary_store_name: prev.store_name,
            primary_eta_min: prev.eta_min,
          };
          flips++;
        }
        if (flips) {
          process.stderr.write(`[oos-probe] ${rec.city} ${rec.pincode} ${probeRec.probe_label} -> flipped ${flips} OOS row(s) via store=${probeStore.name || 'n/a'} id=${probeStore.id || ''}\n`);
        }
      }
    }
    if (BLINKIT_PDP_OOS_PROBE && rows.some((r) => !r.in_stock)) {
      for (let idx = 0; idx < rows.length; idx++) {
        if (rows[idx].in_stock) continue;
        const prev = rows[idx];
        let checked = false;
        let checkedPdp = null;
        const pdpRecs = [{ ...rec, probe_label: 'primary' }, ...probeRecords(rec)];
        for (const pdpRec of pdpRecs) {
          const pdp = await verifyPdpRow(pdpRec, prev, pdpRec.probe_label || 'primary');
          if (!pdp) continue;
          checked = true;
          checkedPdp = pdp;
          if (!pdp.in_stock) continue;
          rows[idx] = {
            ...prev,
            store_id: pdp.store.id || prev.store_id,
            store_name: pdp.store.name || prev.store_name,
            sale: pdp.sale ?? prev.sale,
            mrp: pdp.mrp ?? prev.mrp,
            base_sale: pdp.base_sale ?? prev.base_sale,
            offer_sale: pdp.offer_sale ?? prev.offer_sale,
            discount_pct: pdp.discount_pct ?? prev.discount_pct,
            per_litre: pdp.per_litre ?? prev.per_litre,
            in_stock: 1,
            listing_status: 'listed_in_stock',
            stock_source: 'pdp_probe',
            price_source: priceSource('pdp', pdp),
            search_in_stock: prev.in_stock,
            search_sale: prev.sale,
            search_mrp: prev.mrp,
            pdp_sale: pdp.sale,
            pdp_mrp: pdp.mrp,
            pdp_snippet: pdp.snippet,
            stock_probe: 'nearby_same_pincode_pdp',
            stock_probe_label: pdp.probe_label,
            stock_probe_lat: pdp.probe_lat,
            stock_probe_lon: pdp.probe_lon,
            primary_store_id: prev.primary_store_id || prev.store_id,
            primary_store_name: prev.primary_store_name || prev.store_name,
            primary_eta_min: prev.primary_eta_min || prev.eta_min,
          };
          process.stderr.write(`[pdp-probe] ${rec.city} ${rec.pincode} ${pdp.probe_label} -> flipped ${prev.sku_raw} via store=${pdp.store.name || 'n/a'} id=${pdp.store.id || ''} sale=${pdp.sale || 'n/a'}\n`);
          break;
        }
        if (!rows[idx].in_stock && checked) {
          rows[idx] = {
            ...rows[idx],
            sale: checkedPdp && checkedPdp.sale != null ? checkedPdp.sale : rows[idx].sale,
            mrp: checkedPdp && checkedPdp.mrp != null ? checkedPdp.mrp : rows[idx].mrp,
            base_sale: checkedPdp && checkedPdp.base_sale != null ? checkedPdp.base_sale : rows[idx].base_sale,
            offer_sale: checkedPdp && checkedPdp.offer_sale != null ? checkedPdp.offer_sale : rows[idx].offer_sale,
            discount_pct: checkedPdp && checkedPdp.discount_pct != null ? checkedPdp.discount_pct : rows[idx].discount_pct,
            per_litre: checkedPdp && checkedPdp.per_litre != null ? checkedPdp.per_litre : rows[idx].per_litre,
            listing_status: 'listed_out_of_stock',
            stock_source: rows[idx].stock_source === 'search_card' ? 'pdp' : rows[idx].stock_source,
            price_source: checkedPdp && checkedPdp.sale != null ? priceSource('pdp', checkedPdp) : rows[idx].price_source,
            pdp_checked: 1,
            pdp_in_stock: 0,
            pdp_sale: checkedPdp ? checkedPdp.sale : rows[idx].pdp_sale,
            pdp_mrp: checkedPdp ? checkedPdp.mrp : rows[idx].pdp_mrp,
            pdp_snippet: checkedPdp ? checkedPdp.snippet : rows[idx].pdp_snippet,
          };
        }
      }
    }
    if (BLINKIT_PDP_PRICE_PROBE) {
      for (let idx = 0; idx < rows.length; idx++) {
        if (!shouldPdpPriceProbe(rec, rows[idx])) continue;
        const prev = rows[idx];
        const pdp = await verifyPdpRow({ ...rec, probe_label: 'price-canary' }, prev, 'price-canary');
        if (!pdp) continue;
        const changed = (
          (pdp.sale != null && pdp.sale !== prev.sale) ||
          (pdp.mrp != null && pdp.mrp !== prev.mrp) ||
          (pdp.offer_sale != null && pdp.offer_sale !== prev.offer_sale)
        );
        rows[idx] = {
          ...prev,
          store_id: pdp.store.id || prev.store_id,
          store_name: pdp.store.name || prev.store_name,
          sale: pdp.sale ?? prev.sale,
          mrp: pdp.mrp ?? prev.mrp,
          base_sale: pdp.base_sale ?? prev.base_sale,
          offer_sale: pdp.offer_sale ?? prev.offer_sale,
          discount_pct: pdp.discount_pct ?? prev.discount_pct,
          per_litre: pdp.per_litre ?? prev.per_litre,
          in_stock: pdp.in_stock ? 1 : 0,
          listing_status: pdp.in_stock ? 'listed_in_stock' : 'listed_out_of_stock',
          stock_source: pdp.in_stock ? prev.stock_source : 'pdp_price_probe',
          price_source: priceSource('pdp_price_probe', pdp),
          pdp_checked: 1,
          pdp_in_stock: pdp.in_stock ? 1 : 0,
          pdp_sale: pdp.sale,
          pdp_mrp: pdp.mrp,
          pdp_snippet: pdp.snippet,
          pdp_price_checked: 1,
          pdp_price_changed: changed ? 1 : 0,
          price_probe: 'pdp_canary',
          search_sale: prev.search_sale ?? prev.sale,
          search_mrp: prev.search_mrp ?? prev.mrp,
        };
        if (changed) {
          process.stderr.write(`[pdp-price] ${rec.city} ${rec.pincode} -> updated ${prev.sku_raw} sale=${prev.sale || 'n/a'}=>${pdp.sale || 'n/a'} via PDP\n`);
        }
      }
    }
    rows = markUnverifiedOosRows(rows);
    if (BLINKIT_OOS_PROBE || BLINKIT_PDP_OOS_PROBE) {
      store = primaryStore;
    }
    // dedup on (store_id, canonical)
    const dd = new Map();
    for (const r of rows) {
      const k = `${r.store_id}|${r.canonical}`;
      if (!dd.has(k)) dd.set(k, r);
    }
    rows = [...dd.values()];
  } catch (e) {
    // A navigation error whose message carries a block signature is treated as a block
    // (so the caller backs off); any other error is just a per-pincode failure (0 rows).
    if (BLOCK_RE.test(String(e && e.message))) blocked = 'block-error';
    process.stderr.write(`[err] ${rec.city} ${rec.pincode}: ${e.message}${blocked ? ' (block)' : ''}\n`);
  } finally {
    try { await ctx.close(); } catch (_) { /* context may already be closed */ }
  }
  process.stderr.write(`[ok] ${rec.city} ${rec.pincode} -> ${rows.length} jivo SKUs (${((Date.now() - t0) / 1000).toFixed(1)}s) store=${store.name || 'n/a'}\n`);
  return { ...rec, store_id: store.id || '', store_name: store.name || '', resolved, blocked, auth_accepted: authAccepted ? 1 : 0, rows };
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

// Exported for the offline volparse test (same pattern as zepto/amazon-fresh); the scrape
// only runs when invoked directly, so `require`-ing this file never launches a browser.
module.exports = { parseVolMl, canonical, priceInfo, buyAtPrice, parsePdpProductText, shouldPdpPriceProbe, istDateString };

// Scrape one pincode with block-aware exponential backoff. A blocked attempt backs
// off and retries up to MAX_BLOCK_RETRIES; if still blocked we record 0 rows and tag
// the result `partial_block` (the run is then marked partial). NEVER evades — it only
// waits and retries politely, then gives up honestly.
async function scrapeWithBackoff(browser, rec) {
  for (let attempt = 0; ; attempt++) {
    const res = await scrapeOne(browser, rec);
    if (!res.blocked) return res;
    if (attempt >= MAX_BLOCK_RETRIES) {
      process.stderr.write(`[blocked] ${rec.city} ${rec.pincode} still blocked after ${attempt} retr${attempt === 1 ? 'y' : 'ies'} (${res.blocked}); recording 0 rows, run is partial\n`);
      return { ...res, partial_block: true };
    }
    await backoff(attempt);
  }
}

if (require.main === module) (async () => {
  if (BLINKIT_REQUIRE_AUTH && !BLINKIT_AUTH) {
    process.stderr.write('[auth] BLINKIT_REQUIRE_AUTH=1 but no Blinkit access token was provided\n');
    process.exit(3);
  }
  const browser = process.env.BLINKIT_SIM === '1' ? null : await chromium.launch({ headless: true });
  const t0 = Date.now();
  // Resume: reload any per-pincode results already captured for TODAY and skip them.
  const done = loadProgress();
  const doneCount = Object.keys(done).length;
  if (doneCount) process.stderr.write(`[resume] ${doneCount} pincodes already done in ${PROG}; resuming\n`);
  let partial = false;
  const perPin = await pool(PINCODES, CONCURRENCY, async (rec) => {
    if (done[rec.pincode]) return done[rec.pincode];          // checkpoint hit — skip
    const res = await scrapeWithBackoff(browser, rec);
    if (res.blocked || res.partial_block) partial = true;     // any unresolved block => partial run
    done[rec.pincode] = res;
    saveProgress(done);                                       // checkpoint AFTER each pincode
    return res;
  });
  if (browser) await browser.close();
  const allRows = perPin.flatMap((p) => p.rows);
  const authAcceptedPincodes = perPin.filter((p) => p.auth_accepted).length;
  const authVerified = BLINKIT_AUTH && (!BLINKIT_REQUIRE_AUTH || authAcceptedPincodes === perPin.length);
  const summary = {
    pincodes_total: PINCODES.length,
    pincodes_resolved: perPin.filter((p) => p.resolved).length,
    pincodes_unresolved: perPin.filter((p) => !p.resolved).length,
    pincodes_with_jivo: perPin.filter((p) => p.rows.length > 0).length,
    pincodes_blocked: perPin.filter((p) => p.blocked || p.partial_block).length,
    total_rows: allRows.length,
    unique_skus: new Set(allRows.map((r) => r.canonical)).size,
    wall_s: Math.round((Date.now() - t0) / 1000),
    partial,
    auth_session: BLINKIT_AUTH ? 1 : 0,
    auth_required: BLINKIT_REQUIRE_AUTH ? 1 : 0,
    auth_verified: authVerified ? 1 : 0,
    auth_verified_pincodes: authAcceptedPincodes,
    oos_probe_enabled: BLINKIT_OOS_PROBE ? 1 : 0,
    oos_probe_flips: allRows.filter((r) => r.stock_probe === 'nearby_same_pincode').length,
    pdp_oos_probe_enabled: BLINKIT_PDP_OOS_PROBE ? 1 : 0,
    pdp_oos_probe_flips: allRows.filter((r) => r.stock_probe === 'nearby_same_pincode_pdp').length,
    pdp_price_probe_enabled: BLINKIT_PDP_PRICE_PROBE ? 1 : 0,
    pdp_price_probe_checked: allRows.filter((r) => r.pdp_price_checked).length,
    pdp_price_probe_updates: allRows.filter((r) => r.pdp_price_changed).length,
    unverified_oos: allRows.filter((r) => !r.in_stock && !r.pdp_checked && r.stock_source !== 'pdp').length,
    captured_at: new Date().toISOString(),
  };
  process.stderr.write('[SUMMARY] ' + JSON.stringify(summary) + '\n');
  if (COMPETITOR_MODE) {
    // Competitor mode writes ONLY under tools/competitor/ — NEVER the jivo result.json /
    // data/blinkit paths, and never under data/ vault/ reviews/ baselines/. Output filename
    // uses the "blinkit_competitor_" prefix (never "Jivo-", which the mailer auto-emails).
    summary.mode = 'competitor';
    const dataDir = path.join(COMP_DIR, 'data');
    try { fs.mkdirSync(dataDir, { recursive: true }); } catch (_) { /* already exists */ }
    const outJson = path.join(dataDir, `blinkit_competitor_${COMP_DATE}.json`);
    fs.writeFileSync(outJson, JSON.stringify({ summary, allRows }, null, 2));
    // Append to the shared history CSV (create header if missing).
    const csvPath = path.join(dataDir, 'competitor_history.csv');
    const header = 'run_id,date_ist,platform,brand,category,canonical,city,pincode,store_id,pack,vol_ml,per_litre,mrp,sale,discount_pct,in_stock,rank,is_ad\n';
    if (!fs.existsSync(csvPath)) fs.writeFileSync(csvPath, header);
    const esc = (v) => { const s = (v == null) ? '' : String(v); return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
    const runId = `blinkit-${COMP_DATE}-${Date.now()}`;
    const lines = allRows.map((r) => [runId, COMP_DATE, 'blinkit', r.brand, r.category, r.canonical, r.city, r.pincode, r.store_id, r.pack, r.vol_ml, r.per_litre, r.mrp, r.sale, r.discount_pct, r.in_stock, r.rank, r.is_ad].map(esc).join(','));
    if (lines.length) fs.appendFileSync(csvPath, lines.join('\n') + '\n');
    process.stderr.write(`[comp] wrote ${allRows.length} rows -> ${outJson} and appended history -> ${csvPath}\n`);
    console.log(JSON.stringify(summary));
    return;
  }
  fs.writeFileSync(process.env.OUT_FILE || (__dirname + '/result.json'), JSON.stringify({ summary, perPin, allRows, partial }, null, 2));
  console.log(JSON.stringify(summary));
})();
