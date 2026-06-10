// OFFLINE volparse test for amazon-fresh — no network, no scrape (scrape.js main is
// require-guarded; helpers were already exported). Ports the zepto 2026-06-10 combo fix
// into parseVolMl: combo PACK strings render in BOTH orders ("1 L X 2" / "2 x 1 L") —
// comboVolMl() already read both from raw titles, but pack strings land in parseVolMl,
// whose single-quantity match read just "1 l" and halved the volume.
// Run: node platforms/amazon-fresh/test_volparse.js
const { parseVolMl, comboVolMl, canonical } = require('./scrape.js');

const CASES = [
  // multiplier-FIRST combos ("M x N unit")
  ['2 x 1 L', 2000],
  ['2x1L', 2000],
  ['3 x 500 ml', 1500],
  // unit-first combos ("N unit X M"), incl. fresh's '*' separator convention
  ['1 L X 2', 2000],
  ['1 l * 2', 2000],
  // single quantities — live Amazon Fresh pack strings (result.json 2026-06-10)
  ['1 l', 1000],
  ['2 l', 2000],
  ['5 l', 5000],
  ['500 ml', 500],
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

// comboVolMl regressions: the TITLE path (both orders + additive) must not move
for (const [title, want] of [
  ['Jivo Canola Cold Pressed Edible Oil 1+1 Litres', 2000],          // live title
  ['Jivo Rice Bran Oil 5 Litre + 1 Litre Combo Pack', 6000],         // live title
  ['Jivo Extra Light Olive Oil 1 l x 2', 2000],
  ['Jivo Extra Light Olive Oil 2 x 1 l', 2000],
]) {
  const got = comboVolMl(title);
  const ok = got === want;
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  comboVolMl(${JSON.stringify(title)}) = ${got} (want ${want})`);
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
