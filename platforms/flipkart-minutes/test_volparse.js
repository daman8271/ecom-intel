// OFFLINE volparse test for flipkart-minutes — covers BOTH modes' parsers (API scrape.js
// and the scrape.browser.js fallback); no network, no scrape (both mains are require-guarded,
// and the missing-session fallbackToBrowser only fires on direct run).
// Ports the zepto 2026-06-10 combo fix: scrape.js already read multiplier-first ("2 x 1 L",
// live in result.json) but missed unit-first ("1 L X 2"); the browser parser had neither.
// Run: node platforms/flipkart-minutes/test_volparse.js
const api = require('./scrape.js');
const browser = require('./scrape.browser.js');

const CASES = [
  // multiplier-first combos ("M x N unit") — live FK-Minutes subtitle format
  ['2 x 1 L', 2000],
  ['2x1L', 2000],
  ['3 x 500 ml', 1500],
  ['2 * 1 l', 2000],            // FK's '*' separator variant (kept from the API parser)
  // unit-first combos ("N unit X M") — the order this port adds
  ['1 L X 2', 2000],
  ['750 ml x 2', 1500],
  // single quantities — live FK-Minutes pack strings (result.json 2026-06-10)
  ['1 L', 1000],
  ['1000 ml', 1000],
  ['5 L', 5000],
  // junk
  ['', null],
  [null, null],
];

let fail = 0;
for (const [mode, mod] of [['api', api], ['browser', browser]]) {
  for (const [input, want] of CASES) {
    const got = mod.parseVolMl(input);
    const ok = got === want;
    if (!ok) fail++;
    console.log(`${ok ? 'PASS' : 'FAIL'}  [${mode}] parseVolMl(${JSON.stringify(input)}) = ${got} (want ${want})`);
  }
}

// combos must canonicalize to their TOTAL volume tag (2l), not the per-bottle 1l
{
  const got = api.canonical('JIVO Extra Light Olive Oil Can', '1 L X 2');
  const ok = got === 'jivo-extra-light-olive-oil-can-2l';
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  canonical(olive can, '1 L X 2') = ${got} (want jivo-extra-light-olive-oil-can-2l)`);
}

if (fail) { console.error(`\n${fail} FAILED`); process.exit(1); }
console.log('\nALL PASS');
