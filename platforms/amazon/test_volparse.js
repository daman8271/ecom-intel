// OFFLINE test harness for the parseVolMl fix. No network, no scraper, no account.
// Compares OLD vs NEW parse + per_litre across every pack in result.json/products.json.
const fs = require('fs');
const path = require('path');

// ---- OLD (buggy) ----------------------------------------------------------
function parseVolMlOld(pack) {
  if (!pack) return null;
  const p = String(pack).toLowerCase();
  const mult = p.match(/([\d.]+)\s*x\s*([\d.]+)\s*(ml|mls|l|ltr|ltrs|litre|litres|kg|gms?|g)\b/);
  if (mult) {
    const count = parseFloat(mult[1]);
    let v = parseFloat(mult[2]);
    const u = mult[3];
    if (/^(l|ltr|ltrs|litre|litres|kg)$/.test(u)) v *= 1000;
    return count * v;
  }
  const m = p.match(/([\d.]+)\s*(ml|mls|l|ltr|ltrs|litre|litres|kg|gms?|g)\b/);
  if (!m) return null;
  let n = parseFloat(m[1]);
  const u = m[2];
  if (/^(l|ltr|ltrs|litre|litres|kg)$/.test(u)) n *= 1000;
  return n;
}

// ---- NEW (fixed) ----------------------------------------------------------
const { parseVolMl } = require('./volparse.js');

const PRICE_PER_L_MAX = 6000; // sanity-only, mirror the constant we add to scrape.js

const rows = JSON.parse(fs.readFileSync(path.join(__dirname, 'result.json'), 'utf8')).allRows;
// also fold in products.json packs (authoritative source of the combo strings)
const prods = JSON.parse(fs.readFileSync(path.join(__dirname, 'products.json'), 'utf8'));

const packs = new Map(); // pack -> {sample sku}
for (const r of rows) if (r.pack) packs.set(r.pack, r.sku_raw);
for (const p of prods) if (p.pack) packs.set(p.pack, p.name);

let changed = 0, newlyParsed = 0, lost = 0;
const report = [];
for (const [pack, sku] of packs) {
  const o = parseVolMlOld(pack);
  const n = parseVolMl(pack);
  if (o !== n) {
    changed++;
    if (o == null && n != null) newlyParsed++;
    if (o != null && n == null) lost++;
    report.push({ pack, old: o, neu: n, sku: (sku || '').slice(0, 40) });
  }
}
report.sort((a, b) => (a.old || 0) - (b.old || 0));
console.log(`distinct packs: ${packs.size} | changed: ${changed} | newly-parsed(old null->new val): ${newlyParsed} | lost(old val->new null): ${lost}\n`);
for (const r of report) {
  console.log(`  ${String(r.old).padStart(6)} -> ${String(r.neu).padStart(6)}   ${JSON.stringify(r.pack).padEnd(34)} ${r.sku}`);
}

// ---- per_litre impact on the actual oil rows ------------------------------
console.log('\n=== per_litre BEFORE -> AFTER (oils with a pack) ===');
let plChanged = 0, plClamped = 0;
const after = [];
for (const r of rows) {
  if (!r.is_oil) continue;
  const volOld = parseVolMlOld(r.pack);
  const volNew = parseVolMl(r.pack);
  const sale = r.sale;
  const plOld = (volOld && sale != null) ? Math.round(sale / (volOld / 1000) * 100) / 100 : null;
  let plNew = (volNew && sale != null) ? Math.round(sale / (volNew / 1000) * 100) / 100 : null;
  let clamped = false;
  if (plNew != null && (plNew <= 0 || plNew > PRICE_PER_L_MAX)) { plNew = null; clamped = true; plClamped++; }
  if (plOld !== plNew) plChanged++;
  if (plNew != null) after.push({ pl: plNew, pack: r.pack, sku: r.sku_raw.slice(0, 40) });
  if (plOld !== plNew && sale != null) {
    console.log(`  ${String(plOld).padStart(8)} -> ${String(plNew).padStart(8)}${clamped ? ' [CLAMPED]' : ''}  vol ${volOld}->${volNew}  sale ${sale}  ${JSON.stringify(r.pack)}`);
  }
}
console.log(`\nper_litre changed: ${plChanged} | clamped-to-null: ${plClamped}`);
after.sort((a, b) => b.pl - a.pl);
console.log('\n=== highest surviving per_litre AFTER fix (sanity: should all be plausible) ===');
for (const r of after.slice(0, 12)) console.log(`  ${String(r.pl).padStart(8)}  ${JSON.stringify(r.pack).padEnd(28)} ${r.sku}`);

// ---- fixed-point assertions (COMBO-ORDER FIX 2026-06-10) -------------------
// Combos appear in BOTH orders; unit-FIRST ("250 GMS X 2") used to fall through to the
// single match and record only the first token. Additive/mixed/null behavior must not move.
const CASES = [
  // unit-first combos — incl. the two live catalog packs this fix corrects
  ['1 L X 2', 2000], ['250 GMS X 2', 500], ['250 GMS X 3', 750],
  // multiplier-first combos (existing behavior, must not regress)
  ['2 x 1 L', 2000], ['2x1L', 2000], ['3 x 500 ml', 1500],
  // additive bundles (live packs — the 2026-06-05/06 fixes, must not regress)
  ['5LTR + 1LTR (BUNDLE)', 6000], ['5 + 1 LTR', 6000], ['1LTR + 200 GM (BUNDLE)', 1000],
  // singles + fail-safe nulls
  ['1 LTR', 1000], ['200 MLS', 200], ['5 + 1 EV', null], [null, null],
];
let fail = 0;
console.log('\n=== combo-order assertions ===');
for (const [input, want] of CASES) {
  const got = parseVolMl(input);
  const ok = got === want;
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  parseVolMl(${JSON.stringify(input)}) = ${got} (want ${want})`);
}
if (fail) { console.error(`\n${fail} FAILED`); process.exit(1); }
console.log('\nALL PASS');
