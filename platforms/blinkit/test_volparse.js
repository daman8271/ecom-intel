// OFFLINE volparse test for blinkit — no network, no scrape (scrape.js main is require-guarded).
// Ports the zepto 2026-06-10 combo fix: combo packs render in BOTH orders ("1 L X 2" at some
// stores, "2 x 1 L" at others); the parser must read both, before the single-quantity fallback.
// Run: node platforms/blinkit/test_volparse.js
const { parseVolMl, canonical, priceInfo, buyAtPrice, parsePdpProductText, shouldPdpPriceProbe, istDateString } = require('./scrape.js');

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
  const got = istDateString(new Date('2026-07-06T22:15:00.000Z'));
  const ok = got === '2026-07-07';
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  istDateString(early IST run) = ${got} (want 2026-07-07)`);
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

{
  const got = shouldPdpPriceProbe(
    { pincode: '110094' },
    { in_stock: 1, prid: '407561', listing_url: 'https://blinkit.com/prn/jivo-pomace-olive-oil/prid/407561' }
  );
  const ok = got === true;
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  shouldPdpPriceProbe(canary) = ${got} (want true)`);
}

{
  const got = shouldPdpPriceProbe(
    { pincode: '110094' },
    { in_stock: 1, prid: '528706', listing_url: 'https://blinkit.com/prn/jivo-pomace-olive-oil/prid/528706' }
  );
  const ok = got === false;
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  shouldPdpPriceProbe(non-canary low-info) = ${got} (want false)`);
}

{
  const got = shouldPdpPriceProbe(
    { pincode: '110094' },
    {
      in_stock: 1,
      prid: '528706',
      listing_url: 'https://blinkit.com/prn/jivo-extra-light-olive-oil/prid/528706',
      sale: 1499,
      vol_ml: 5000,
      price_source: 'search_card',
    }
  );
  const ok = got === true;
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  shouldPdpPriceProbe(high-value search row) = ${got} (want true)`);
}

{
  const got = shouldPdpPriceProbe(
    { pincode: '110094' },
    {
      in_stock: 1,
      prid: '528706',
      listing_url: 'https://blinkit.com/prn/jivo-extra-light-olive-oil/prid/528706',
      sale: 1499,
      vol_ml: 5000,
      offer_sale: 1399,
      price_source: 'search_card_offer',
    }
  );
  const ok = got === false;
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  shouldPdpPriceProbe(offer-evidence row) = ${got} (want false)`);
}

{
  const row = { sku_raw: 'Jivo Pomace Olive Oil', pack: '5 l', vol_ml: 5000 };
  const got = parsePdpProductText('Home / Oil / Jivo Pomace Olive Oil Jivo Pomace Olive Oil 5 ltr ₹1,875 MRP ₹4,999 Buy at ₹1,687 Apply Code: TEST Add to cart Why shop from blinkit?', row);
  const ok = got && got.in_stock === 1 && got.sale === 1687 && got.base_sale === 1875 && got.offer_sale === 1687 && got.mrp === 4999;
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  parsePdpProductText(Buy at) = ${JSON.stringify(got)} (want sale=1687 base=1875 offer=1687 mrp=4999)`);
}

{
  const row = { sku_raw: 'Jivo Cold Pressed Canola Oil', pack: '5 l', vol_ml: 5000 };
  const got = parsePdpProductText('Home / Oil / Jivo Cold Pressed Canola Oil (5 l) Jivo Cold Pressed Canola Oil (5 l) 5 ltr ₹1,193 MRP ₹1,650 27% OFF Add to cart Why shop from blinkit?', row);
  const ok = got && got.in_stock === 1 && got.sale === 1193 && got.mrp === 1650;
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  parsePdpProductText(parenthesized pack) = ${JSON.stringify(got)} (want sale=1193 mrp=1650)`);
}

if (fail) { console.error(`\n${fail} FAILED`); process.exit(1); }
console.log('\nALL PASS');
