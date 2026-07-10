const { chromium } = require('playwright');
const fs = require('fs');
const OUT = '/root/ghee-research/raw/flipkart/result_ghee.json';

function inferBrand(name) {
  const n = name.toLowerCase();
  const brands = ['amul','aashirvaad','patanjali','gowardhan','mother dairy','nandini','ananda',
    'organic india','anveshan','akshayakalpa','grb','himalayan natives','barosi','two brothers',
    'kapiva','druk','country delight','milky mist','dinshaw','kwality','heritage','verka',
    'saajfarms','rosier','harvest heaven','nutralite','dabur','gavyratan'];
  for (const b of brands) { if (n.includes(b)) return b.charAt(0).toUpperCase()+b.slice(1); }
  return name.split(' ').slice(0,2).join(' ');
}
function inferPack(name) {
  const m = name.match(/(\d+(?:\.\d+)?)\s*(kg|g|gm|gram|litre|liter|l\b|ml)/i);
  return m ? m[0].trim() : null;
}
function isA2(name) { return /\ba2\b|a2\s*cow|bilona/i.test(name); }

(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const allSkus = [];
  
  for (let pg = 1; pg <= 4; pg++) {
    const ctx = await browser.newContext({ 
      userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
      locale: 'en-IN'
    });
    const page = await ctx.newPage();
    const url = pg === 1 
      ? 'https://www.flipkart.com/search?q=ghee&marketplace=FLIPKART'
      : `https://www.flipkart.com/search?q=ghee&marketplace=FLIPKART&page=${pg}`;
    process.stderr.write(`[fk] Page ${pg}: ${url}\n`);
    
    try {
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
      await page.waitForTimeout(4000);
      await page.evaluate(() => window.scrollTo(0, 800));
      await page.waitForTimeout(2000);
      
      const items = await page.evaluate(() => {
        const scripts = Array.from(document.querySelectorAll('script[type="application/ld+json"]'));
        const allItems = [];
        for (const s of scripts) {
          try {
            const j = JSON.parse(s.textContent);
            if (j && j.itemListElement) allItems.push(...j.itemListElement);
            else if (j && Array.isArray(j)) j.forEach(x => x && x.itemListElement && allItems.push(...x.itemListElement));
          } catch (_) {}
        }
        return allItems;
      });
      
      process.stderr.write(`[fk] Page ${pg}: ${items.length} ld+json items\n`);
      
      for (const item of items) {
        const name = item.name || '';
        if (!name.toLowerCase().includes('ghee')) continue;
        const pid = (item.url || '').match(/\/p\/([A-Z0-9]+)/) || ['','?'];
        const pack = inferPack(name);
        allSkus.push({
          pid: pid[1],
          name, brand: inferBrand(name), pack,
          price_inr: null, mrp_inr: null, per_kg_inr: null,
          in_stock: true, a2: isA2(name), source_page: pg, url: item.url
        });
      }
      if (items.length === 0) break;
    } catch (e) {
      process.stderr.write(`[fk] Page ${pg} error: ${e.message}\n`);
      break;
    } finally {
      await ctx.close();
    }
  }
  
  await browser.close();
  fs.writeFileSync(OUT, JSON.stringify({ platform:'flipkart', query:'ghee', total_skus: allSkus.length, skus: allSkus }, null, 2));
  process.stdout.write(JSON.stringify({ total_skus: allSkus.length }) + '\n');
  process.stderr.write(`[fk] Done: ${allSkus.length} ghee items\n`);
})();
