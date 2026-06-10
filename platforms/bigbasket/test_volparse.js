// OFFLINE volparse test for bigbasket — no network, no scrape (scrape.js main and the
// watchdog are require-guarded). Ports the zepto 2026-06-10 combo fix: combo packs render
// in BOTH orders ("1 L X 2" / "2 x 1 L"); the parser must read both, before the
// single-quantity fallback.
// Run: node platforms/bigbasket/test_volparse.js
const { parseVolMl, canonical, volMl } = require('./scrape.js');

const CASES = [
  // multiplier-FIRST combos ("M x N unit")
  ['2 x 1 L', 2000],
  ['2x1L', 2000],
  ['3 x 500 ml', 1500],
  // unit-first combos ("N unit X M")
  ['1 L X 2', 2000],
  ['750 ml x 2', 1500],
  // single quantities — live BigBasket pack strings (result.json 2026-06-10)
  ['1 L', 1000],
  ['2 L', 2000],
  ['200 ml', 200],
  ['750 ml', 750],
  ['5 L', 5000],
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

// volMl: pack string wins; structured magnitude stays the fallback when pack carries no volume
{
  const a = volMl({ magnitude: '1000' }, '2 x 1 L');
  const b = volMl({ magnitude: '5000', unit: 'ml' }, '');
  const ok = a === 2000 && b === 5000;
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  volMl(pack '2 x 1 L') = ${a} (want 2000); volMl(magnitude 5000ml) = ${b} (want 5000)`);
}

// combos must canonicalize to their TOTAL volume tag (2l), not the per-bottle 1l
{
  const got = canonical('Extra Light Olive Oil', '2 x 1 L');
  const ok = got === 'extra-light-olive-oil-2l';
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  canonical(olive, '2 x 1 L') = ${got} (want extra-light-olive-oil-2l)`);
}

if (fail) { console.error(`\n${fail} FAILED`); process.exit(1); }
console.log('\nALL PASS');
