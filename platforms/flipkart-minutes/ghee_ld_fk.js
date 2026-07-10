const { chromium } = require('playwright');
const fs = require('fs');
const OUT = '/root/ghee-research/raw/flipkart/result_ghee.json';

function inferBrand(name) {
  const n = name.toLowerCase();
  const brands = ['amul','aashirvaad','patanjali','gowardhan','mother dairy','nandini','ananda',
    'organic india','anveshan','akshayakalpa','grb','himalayan natives','barosi','two brothers',
    'kapiva','druk','country delight','milky mist','dinshaw','kwality','heritage','verka'];
  for (const b of brands) { if (n.includes(b)) return b.charAt(0).toUpperCase()+b.slice(1); }
  return name.split(' ').slice(0,2).join(' ');
}
function inferPackSize(name) {
  const m = name.match(/(\d+(?:\.\d+)?)\s*(kg|g|gm|gram|litre|liter|l\b|ml)/i);
  return m ? m[0].trim() : null;
}
function isA2(name) { return /\ba2\b|a2\s*cow|bilona/i.test(name); }
function parsePrice(s) {
  if (!s) return null;
  const m = s.replace(/,/g,'').match(/[\d.]+/);
  return m ? parseFloat(m[0]) : null;
}
function toPerKg(price, name, pack) {
  const s = (pack || name || '').toLowerCase();
  const m1 = s.match(/(\d+(?:\.\d+)?)\s*kg/i);
  if (m1) return Math.round(price / parseFloat(m1[1]));
  const m2 = s.match(/(\d+(?:\.\d+)?)\s*(?:g|gm|gram)/i);
  if (m2) return Math.round(price / (parseFloat(m2[1]) / 1000));
  const m3 = s.match(/(\d+(?:\.\d+)?)\s*(?:litre|liter|l\b)/i);
  if (m3) return Math.round(price / parseFloat(m3[1]));
  return null;
}

(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const skus = [];
  
  for (let pg = 1; pg <= 4; pg++) {
    const ctx = await browser.newContext({ 
      userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
      locale: 'en-IN'
    });
    const page = await ctx.newPage();
    const url = `https://www.flipkart.com/search?q=ghee&marketplace=FLIPKART&page=${pg}`;
    process.stderr.write(`[flipkart] Page ${pg}: ${url}\n`);
    try {
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
      await page.waitForTimeout(3000);
      
      const items = await page.evaluate(() => {
        const scripts = Array.from(document.querySelectorAll('script[type="application/ld+json"]'));
        const allItems = [];
        for (const s of scripts) {
          try {
            const j = JSON.parse(s.textContent);
            if (j && j.itemListElement) {
              allItems.push(...j.itemListElement);
            }
          } catch (_) {}
        }
        return allItems;
      });
      
      process.stderr.write(`[flipkart] Page ${pg}: ${items.length} ld+json items\n`);
      
      for (const item of items) {
        const name = item.name || '';
        if (!name.toLowerCase().includes('ghee')) continue;
        const pack = inferPackSize(name);
        // Prices not in ld+json, so null for now
        skus.push({
          pid: item.url ? (item.url.match(/\/p\/([A-Z0-9]+)/) || ['','?'])[1] : '?',
          name,
          brand: inferBrand(name),
          pack,
          price_inr: null,
          mrp_inr: null,
          per_kg_inr: null,
          in_stock: true,
          a2: isA2(name),
          source_page: pg,
          url: item.url
        });
      }
      
      if (items.length === 0) { process.stderr.write('[flipkart] Empty page\n'); break; }
    } catch (e) {
      process.stderr.write(`[flipkart] Page ${pg} error: ${e.message}\n`);
    } finally {
      await ctx.close();
    }
  }
  
  await browser.close();
  fs.writeFileSync(OUT, JSON.stringify({ platform:'flipkart', query:'ghee', total_skus: skus.length, skus }, null, 2));
  process.stderr.write(`[flipkart] Done. ${skus.length} unique ghee SKUs (no prices - ld+json only)\n`);
  process.stdout.write(JSON.stringify({total_skus: skus.length}) + '\n');
})();
