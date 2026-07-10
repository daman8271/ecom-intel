// Quick Amazon.in ghee keyword search capture
// Uses same Playwright patterns as platforms/amazon/scrape.js
const { chromium } = require('playwright');
const fs = require('fs');

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const OUT = '/root/ghee-research/raw/amazon/result_ghee.json';
const MAX_PAGES = 3;

async function passInterstitial(page) {
  try {
    const hit = await page.evaluate(() => /continue shopping/i.test(document.body.innerText || '')).catch(() => false);
    if (hit) {
      const btn = await page.$('input[value*="Continue"], a:has-text("Continue shopping")');
      if (btn) { await btn.click(); await page.waitForTimeout(2000); }
    }
  } catch (_) {}
}

function parsePrice(s) {
  if (!s) return null;
  const m = s.replace(/,/g,'').match(/[\d.]+/);
  return m ? parseFloat(m[0]) : null;
}

function inferBrand(name) {
  const n = name.toLowerCase();
  const brands = [
    'amul','aashirvaad','patanjali','gowardhan','mother dairy','nestle','nandini',
    'ananda','heritage','verka','vita','saras','kwality','dinshaw','milkfed',
    'param','organic india','anveshan','akshayakalpa','sid\'s farm','barosi',
    'druk','ghee pure','grb','himalayan natives','jivika','two brothers',
    'organic tattva','kapiva','vedaka','aarong','brar','country delight',
    'dairy best','farm origins','kamadhenu','milky mist','natureland',
    'para','pride of cows','sarda','shubhkart','tulsi','van vida'
  ];
  for (const b of brands) { if (n.includes(b)) return b.charAt(0).toUpperCase()+b.slice(1); }
  // First 2 words as fallback
  return name.split(' ').slice(0,2).join(' ');
}

function inferPackSize(name) {
  const m = name.match(/(\d+(?:\.\d+)?)\s*(kg|g|gm|gram|litre|liter|l|ml|pack of \d+)/i);
  if (!m) return null;
  return m[0].trim();
}

function isA2(name) {
  return /\ba2\b|a2\s*cow|a2\s*milk|bilona/i.test(name);
}

function toPerKg(price, name, pack) {
  // Try to parse pack size
  const s = (pack || name || '').toLowerCase();
  let ml = null;
  const m1 = s.match(/(\d+(?:\.\d+)?)\s*kg/i);
  if (m1) return price / parseFloat(m1[1]);
  const m2 = s.match(/(\d+(?:\.\d+)?)\s*(?:g|gm|gram)/i);
  if (m2) return price / (parseFloat(m2[1]) / 1000);
  const m3 = s.match(/(\d+(?:\.\d+)?)\s*(?:litre|liter|l\b)/i);
  if (m3) return price / parseFloat(m3[1]); // ghee density ~0.91 kg/L, use 1:1 approx for per_kg
  const m4 = s.match(/(\d+(?:\.\d+)?)\s*ml/i);
  if (m4) return price / (parseFloat(m4[1]) / 1000);
  return null;
}

(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', viewport: {width:1280,height:900} });
  const page = await ctx.newPage();
  const skus = [];

  try {
    for (let pg = 1; pg <= MAX_PAGES; pg++) {
      const url = `https://www.amazon.in/s?k=ghee&page=${pg}`;
      process.stderr.write(`[amazon] Fetching page ${pg}: ${url}\n`);
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
      await passInterstitial(page);
      await page.waitForTimeout(2000);

      const items = await page.evaluate(() => {
        const results = [];
        const cards = document.querySelectorAll('[data-asin]:not([data-asin=""])');
        cards.forEach(card => {
          const asin = card.getAttribute('data-asin');
          if (!asin || !/^B[0-9A-Z]{9}/.test(asin)) return;
          const nameEl = card.querySelector('h2 a span, .a-size-medium.a-color-base.a-text-normal');
          const name = nameEl ? nameEl.textContent.trim() : '';
          if (!name || !/ghee/i.test(name)) return;
          const priceEl = card.querySelector('.a-price .a-offscreen, .a-price-whole');
          const mrpEl = card.querySelector('.a-price.a-text-price .a-offscreen');
          const stockEl = card.querySelector('[aria-label*="out of stock"]');
          const linkEl = card.querySelector('h2 a');
          results.push({
            asin, name,
            price_text: priceEl ? priceEl.textContent.trim() : null,
            mrp_text: mrpEl ? mrpEl.textContent.trim() : null,
            in_stock: !stockEl,
            href: linkEl ? linkEl.getAttribute('href') : null
          });
        });
        return results;
      });

      process.stderr.write(`[amazon] Page ${pg}: ${items.length} ghee items\n`);
      for (const item of items) {
        if (skus.find(s => s.asin === item.asin)) continue; // dedup
        const price = parsePrice(item.price_text);
        const mrp = parsePrice(item.mrp_text);
        const pack = inferPackSize(item.name);
        const per_kg = price ? toPerKg(price, item.name, pack) : null;
        skus.push({
          asin: item.asin,
          name: item.name,
          brand: inferBrand(item.name),
          pack: pack,
          price_inr: price,
          mrp_inr: mrp,
          per_kg_inr: per_kg ? Math.round(per_kg) : null,
          in_stock: item.in_stock,
          a2: isA2(item.name),
          source_page: pg
        });
      }
      if (items.length === 0) { process.stderr.write('[amazon] Empty page, stopping\n'); break; }
    }
  } catch (e) {
    process.stderr.write(`[amazon] Error: ${e.message}\n`);
  }
  await browser.close();
  fs.writeFileSync(OUT, JSON.stringify({ platform:'amazon', query:'ghee', total_skus: skus.length, skus }, null, 2));
  process.stderr.write(`[amazon] Done. ${skus.length} unique ghee SKUs\n`);
  const j = JSON.stringify({total_skus: skus.length, captured_at: new Date().toISOString()});
  process.stdout.write(j + '\n');
})();
