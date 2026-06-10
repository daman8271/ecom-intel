// OFFLINE volparse test for zepto — no network, no scrape (scrape.js main is require-guarded).
// Covers the 2026-06-10 per_litre_sanity hold: Zepto renders the same combo variant as
// "1 L X 2" at some stores and "2 x 1 L" at others; the parser must read BOTH orders.
// Run: node platforms/zepto/test_volparse.js
const { parseVolMl, volFromVariant, canonical } = require('./scrape.js');

const CASES = [
  // multiplier-FIRST combos ("M x N unit") — the live bug behind the held 06-10 sheets
  ['2 x 1 L', 2000],
  ['2x1L', 2000],
  ['2 × 1 L', 2000],
  ['3 x 500 ml', 1500],
  // unit-first combos (existing behavior, must not regress)
  ['1 L X 2', 2000],
  ['2 L X 2', 4000],
  ['750 ml x 2', 1500],
  // additive packs
  ['1+1 litres', 2000],
  // single quantities incl. Zepto's truncated-'ml' quirk
  ['1 pc (5 L)', 5000],
  ['1 Pack(200 m)', 200],
  ['200 ml', 200],
  ['5 l', 5000],
  // junk
  ['', null],
  [null, null],
];

let fail = 0;
for (const [input, want] of CASES) {
  const got = parseVolMl(input);
  const ok = got === want;
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  parseVolMl(${JSON.stringify(input)}) = ${got} (want ${want})`);
}

// structured fields stay authoritative over any display string
{
  const got = volFromVariant({ packsize: 2, unitOfMeasure: 'LITER' }, '2 x 1 L');
  const ok = got === 2000;
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  volFromVariant(packsize=2/LITER) = ${got} (want 2000)`);
}

// the fix must merge the phantom combo-1l canonical back into combo-2l
{
  const got = canonical('Jivo Extra Light Olive Oil Combo', parseVolMl('2 x 1 L'));
  const ok = got === 'jivo-extra-light-olive-oil-combo-2l';
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  canonical(combo, '2 x 1 L') = ${got} (want jivo-extra-light-olive-oil-combo-2l)`);
}

if (fail) { console.error(`\n${fail} FAILED`); process.exit(1); }
console.log('\nALL PASS');
