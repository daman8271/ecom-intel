// OFFLINE volparse test for blinkit — no network, no scrape (scrape.js main is require-guarded).
// Ports the zepto 2026-06-10 combo fix: combo packs render in BOTH orders ("1 L X 2" at some
// stores, "2 x 1 L" at others); the parser must read both, before the single-quantity fallback.
// Run: node platforms/blinkit/test_volparse.js
const { parseVolMl, canonical, priceInfo, buyAtPrice } = require('./scrape.js');

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

{
  const txt = 'Jivo Pomace Olive Oil 5 l ₹1,876 MRP ₹4,999 62% OFF Buy at ₹1,688 Apply Code: AXISNEO ADD';
  const p = priceInfo(txt, 5000);
  const ok = p.sale === 1688 && p.base_sale === 1876 && p.offer_sale === 1688 &&
    p.mrp === 4999 && p.per_litre === 337.6;
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  priceInfo(Buy at) = ${JSON.stringify(p)} (want sale=1688 base=1876 offer=1688 mrp=4999)`);
}

{
  const got = buyAtPrice('Buy at ₹1,687 Apply Code: TEST');
  const ok = got === 1687;
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  buyAtPrice(...) = ${got} (want 1687)`);
}

{
  const got = buyAtPrice('Buy for ₹1,687 after wallet offer');
  const ok = got === 1687;
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  buyAtPrice(buy for) = ${got} (want 1687)`);
}

{
  const got = buyAtPrice('Effective price ₹1,687 with bank offer');
  const ok = got === 1687;
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  buyAtPrice(effective price) = ${got} (want 1687)`);
}

{
  const got = buyAtPrice('Get it at ₹1,687 after coupon');
  const ok = got === 1687;
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  buyAtPrice(get it at) = ${got} (want 1687)`);
}

if (fail) { console.error(`\n${fail} FAILED`); process.exit(1); }
console.log('\nALL PASS');
