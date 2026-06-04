// OFFLINE test for the 2026-06-04 audit fixes (BUG-1 combo per-litre, BUG-2 canonical).
// Replays the captured result.json titles through the NEW helpers — NO scraper, NO browser,
// NO network, NO location change. Proves: (1) the 3 combo SKUs now compute the correct total
// volume/Rs-L, (2) the working "1+1 Litres" combo is unchanged, (3) NO other SKU's volume
// changes (regression), (4) canonical splits/merges are resolved.
//   node test_combo_fix.js
const fs = require('fs');
const path = require('path');
const { parseVolMl, comboVolMl, packFromTitle, normalizeCanonicals, canonical } = require('./scrape.js');

const d = JSON.parse(fs.readFileSync(path.join(__dirname, 'result.json'), 'utf8'));
const rows = d.allRows;

// Mirror toRow()'s volume chain: comboVolMl(name) || comboVolMl(fullTitle) || parseVolMl(pack).
// result.json stores only `name` (=sku_raw, the pre-"|" slice) and the already-derived `pack`
// (which in toRow comes from packFromTitle(name)||packFromTitle(fullTitle)). For combos the volume
// lives in `name`, so comboVolMl(sku_raw) reproduces the combo branch; for everything else the
// stored `pack` reproduces toRow's single-pack fallback faithfully (incl. |-suffixed fullTitle packs).
const newVol = (r) => comboVolMl(r.sku_raw) || parseVolMl(r.pack);

let fail = 0;
const ok = (c, msg) => { if (!c) { fail++; console.log('  ✗ FAIL: ' + msg); } else console.log('  ✓ ' + msg); };

// --- One representative captured row per ASIN ---
const byAsin = {};
for (const r of rows) if (!byAsin[r.asin]) byAsin[r.asin] = r;

console.log('=== A. The 3 combo SKUs (BUG-1) now compute the correct TOTAL volume ===');
const expect = {
  B0BKQ6PBQP: { ml: 10000, why: '5L + 5L' },
  B0BGPGRP4Z: { ml: 6000,  why: '5L + 1L' },
  B0FR5BLRH6: { ml: 6000,  why: '5L + 1L combo pack' },
};
for (const [asin, e] of Object.entries(expect)) {
  const r = byAsin[asin]; const v = newVol(r);
  const oldPL = r.per_litre; const newPL = r.sale ? Math.round((r.sale / (v / 1000)) * 100) / 100 : null;
  console.log(`  ${asin}  ${JSON.stringify(r.sku_raw)}`);
  console.log(`      OLD vol=${r.vol_ml} Rs/L=${oldPL}  ->  NEW vol=${v} Rs/L=${newPL}  (expect ${e.ml}ml, ${e.why})`);
  ok(v === e.ml, `${asin} volume = ${e.ml}ml`);
}

console.log('\n=== B. The already-working combo must NOT regress ===');
{
  const r = byAsin['B0152TWWSQ']; const v = newVol(r); // "1+1 Litres"
  console.log(`  B0152TWWSQ ${JSON.stringify(r.sku_raw)} -> NEW vol=${v}`);
  ok(v === 2000, '"1+1 Litres" still = 2000ml (captured was ' + r.vol_ml + ')');
}

console.log('\n=== C. REGRESSION: every OTHER SKU volume unchanged vs captured ===');
let changed = 0;
for (const [asin, r] of Object.entries(byAsin)) {
  const v = newVol(r);
  const isCombo = expect[asin];
  if (v !== r.vol_ml) {
    changed++;
    const expected = isCombo ? '(combo — intended)' : '*** UNEXPECTED ***';
    console.log(`  ${asin}: ${r.vol_ml} -> ${v}  ${expected}  ${JSON.stringify(r.sku_raw).slice(0,70)}`);
    if (!isCombo) fail++;
  }
}
ok(changed === 3, `exactly 3 SKUs changed volume (all combos); ${changed} changed`);

console.log('\n=== D. Canonical normalization (BUG-2) ===');
// Build a copy of rows with the ORIGINAL canonical, run normalizeCanonicals, inspect.
const clone = rows.map((r) => ({ ...r }));
normalizeCanonicals(clone);
const canonByAsin = {};
for (const r of clone) (canonByAsin[r.asin] || (canonByAsin[r.asin] = new Set())).add(r.canonical);
// D1: B07X53ZL6J (cookin/cooking title variant) collapses to ONE canonical
ok(canonByAsin['B07X53ZL6J'].size === 1,
  `B07X53ZL6J (Cooking/Cookin variant) -> 1 canonical [${[...canonByAsin['B07X53ZL6J']]}]`);
// D2: distinct same-title ASINs stay distinct
const cA = [...canonByAsin['B09NYCSQLF']][0];
const cB = [...canonByAsin['B0GZZS8J7Q']][0];
ok(cA !== cB, `distinct mustard ASINs kept separate: B09NYCSQLF=${cA}  B0GZZS8J7Q=${cB}`);
// D3: every ASIN now maps to exactly ONE canonical (no more title-variant splits)
const splits = Object.entries(canonByAsin).filter(([, s]) => s.size > 1);
ok(splits.length === 0, `no ASIN maps to >1 canonical (was 1 split); ${splits.length} splits`);
// D4: every canonical maps to exactly ONE asin (no more over-merge)
const canonAsin = {};
for (const r of clone) (canonAsin[r.canonical] || (canonAsin[r.canonical] = new Set())).add(r.asin);
const merges = Object.entries(canonAsin).filter(([, s]) => s.size > 1);
ok(merges.length === 0, `no canonical maps to >1 ASIN (was 1 over-merge); ${merges.length} merges`);

const oldUniq = new Set(rows.map((r) => r.canonical)).size;
const newUniq = new Set(clone.map((r) => r.canonical)).size;
console.log(`  unique_skus: ${oldUniq} (old, title-canonical) -> ${newUniq} (new, ASIN-stable)  [distinct ASINs = ${Object.keys(byAsin).length}]`);
ok(newUniq === Object.keys(byAsin).length, `unique_skus now == distinct ASIN count (${Object.keys(byAsin).length})`);

console.log('\n=== E. Synthetic edge cases for the additive branch ===');
ok(comboVolMl('Jivo Oil 500 ml + 1 L combo') === 1500, 'mixed units "500 ml + 1 L" sum to 1500ml (per-unit convert before sum)');
ok(comboVolMl('Jivo Mustard 5 Litre with Sunflower 5 Litre') === 10000, '"5 Litre with 5 Litre" = 10000ml');
ok(comboVolMl('Jivo Oil 1 Liter & 1 Liter') === 2000, 'American "1 Liter & 1 Liter" = 2000ml');
ok(comboVolMl('Jivo Pomace Olive Oil 1 Litre') === null, 'single-pack (no combo indicator, 1 token) -> null (falls back to parseVolMl)');
ok(comboVolMl('Jivo Blend of Rice Bran & Sunflower Oil') === null, '"&" with ZERO volume tokens -> null (no false combo)');
ok(comboVolMl('Jivo Canola 1+1 Litres') === 2000, 'shared-trailing-unit "1+1 Litres" still = 2000ml (existing branch)');

console.log('\n' + (fail === 0 ? '✅ ALL TESTS PASSED' : `❌ ${fail} CHECK(S) FAILED`));
process.exit(fail === 0 ? 0 : 1);
