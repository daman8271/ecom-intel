// OFFLINE volparse test for blinkit — no network, no scrape (scrape.js main is require-guarded).
// Ports the zepto 2026-06-10 combo fix: combo packs render in BOTH orders ("1 L X 2" at some
// stores, "2 x 1 L" at others); the parser must read both, before the single-quantity fallback.
// Run: node platforms/blinkit/test_volparse.js
const { parseVolMl, canonical } = require('./scrape.js');

const CASES = [
  // multiplier-FIRST combos ("M x N unit")
  ['2 x 1 L', 2000],
  ['2x1L', 2000],
  ['3 x 500 ml', 1500],
  // unit-first combos ("N unit X M")
  ['1 L X 2', 2000],
  ['750 ml x 2', 1500],
  // single quantities — blinkit's live card packs (result.json 2026-06-10)
  ['1 l', 1000],
  ['2 l', 2000],
  ['5 l', 5000],
  ['500 ml', 500],
  ['1 kg', 1000],
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

// combos must canonicalize to their TOTAL volume tag (2l), not the per-bottle 1l
{
  const got = canonical('Jivo Extra Light Olive Oil', '2 x 1 l');
  const ok = got === 'jivo-extra-light-olive-oil-2l';
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  canonical(olive, '2 x 1 l') = ${got} (want jivo-extra-light-olive-oil-2l)`);
}

if (fail) { console.error(`\n${fail} FAILED`); process.exit(1); }
console.log('\nALL PASS');
