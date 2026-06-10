// OFFLINE volparse test for amazon-now — covers BOTH surfaces' parsers (legacy scrape.js
// and the real-Now scrape.ctnow.js); no network, no scrape (both mains are require-guarded).
// Ports the zepto 2026-06-10 combo fix: combo packs render in BOTH orders ("1 L X 2" /
// "2 x 1 L"); the parser must read both, before the single-quantity fallback.
// Run: node platforms/amazon-now/test_volparse.js
const legacy = require('./scrape.js');
const ctnow = require('./scrape.ctnow.js');

const CASES = [
  // multiplier-FIRST combos ("M x N unit")
  ['2 x 1 L', 2000],
  ['2x1L', 2000],
  ['3 x 500 ml', 1500],
  // unit-first combos ("N unit X M")
  ['1 L X 2', 2000],
  ['750 ml x 2', 1500],
  // single quantities — live Amazon Now pack strings (result.json 2026-06-10)
  ['1 l', 1000],
  ['2 l', 2000],
  ['5 l', 5000],
  ['500 ml', 500],
  // junk
  ['', null],
  [null, null],
];

let fail = 0;
for (const [surface, mod] of [['scrape.js', legacy], ['scrape.ctnow.js', ctnow]]) {
  for (const [input, want] of CASES) {
    const got = mod.parseVolMl(input);
    const ok = got === want;
    if (!ok) fail++;
    console.log(`${ok ? 'PASS' : 'FAIL'}  [${surface}] parseVolMl(${JSON.stringify(input)}) = ${got} (want ${want})`);
  }
}

// packFromTitle regression: still extracts the FIRST single token from plain titles
{
  const got = ctnow.packFromTitle('Jivo Extra Light Olive Oil 1 Litre');
  const ok = got === '1 l';
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  packFromTitle('… 1 Litre') = ${JSON.stringify(got)} (want "1 l")`);
}

// combos must canonicalize to their TOTAL volume tag (2l), not the per-bottle 1l
{
  const got = ctnow.canonical('Jivo Extra Light Olive Oil', '2 x 1 l');
  const ok = got === 'jivo-extra-light-olive-oil-2l';
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  canonical(olive, '2 x 1 l') = ${got} (want jivo-extra-light-olive-oil-2l)`);
}

if (fail) { console.error(`\n${fail} FAILED`); process.exit(1); }
console.log('\nALL PASS');
