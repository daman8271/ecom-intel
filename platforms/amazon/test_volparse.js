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
