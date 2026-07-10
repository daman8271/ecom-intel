// Quick Flipkart ghee keyword search capture
const { chromium } = require('playwright');
const fs = require('fs');

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const OUT = '/root/ghee-research/raw/flipkart/result_ghee.json';
const MAX_PAGES = 3;

function parsePrice(s) {
  if (!s) return null;
  const m = s.replace(/,/g,'').match(/[\d.]+/);
  return m ? parseFloat(m[0]) : null;
}

function inferBrand(name) {
  const n = name.toLowerCase();
  const brands = [
    'amul','aashirvaad','patanjali','gowardhan','mother dairy','nandini','ananda','heritage',
    'verka','param','organic india','anveshan','akshayakalpa','sid\'s farm','barosi','grb',
    'himalayan natives','jivika','two brothers','organic tattva','kapiva','vedaka','dinshaw',
    'milky mist','natureland','pride of cows','country delight','druk','kwality'
  ];
  for (const b of brands) { if (n.includes(b)) return b.charAt(0).toUpperCase()+b.slice(1); }
  return name.split(' ').slice(0,2).join(' ');
}

function inferPackSize(name) {
  const m = name.match(/(\d+(?:\.\d+)?)\s*(kg|g|gm|gram|litre|liter|l\b|ml)/i);
  return m ? m[0].trim() : null;
}

function isA2(name) { return /\ba2\b|a2\s*cow|a2\s*milk|bilona/i.test(name); }

function toPerKg(price, name, pack) {
  const s = (pack || name || '').toLowerCase();
  const m1 = s.match(/(\d+(?:\.\d+)?)\s*kg/i);
  if (m1) return price / parseFloat(m1[1]);
  const m2 = s.match(/(\d+(?:\.\d+)?)\s*(?:g|gm|gram)/i);
  if (m2) return price / (parseFloat(m2[1]) / 1000);
  const m3 = s.match(/(\d+(?:\.\d+)?)\s*(?:litre|liter|l\b)/i);
  if (m3) return price / parseFloat(m3[1]);
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
      const url = pg === 1
        ? 'https://www.flipkart.com/search?q=ghee&otracker=search&otracker1=search&marketplace=FLIPKART&as-show=on&as=off'
        : `https://www.flipkart.com/search?q=ghee&otracker=search&marketplace=FLIPKART&page=${pg}`;
      process.stderr.write(`[flipkart] Fetching page ${pg}: ${url}\n`);
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
      await page.waitForTimeout(2500);

      // Dismiss login popup if present
      try {
        const closeBtn = await page.$('button._2KpZ6l._2doB4z');
        if (closeBtn) await closeBtn.click();
      } catch (_) {}

      const items = await page.evaluate(() => {
        const results = [];
        // Flipkart search result cards
        const cards = document.querySelectorAll('._1AtVbE, [data-id], ._13oc-S');
        const seen = new Set();
        cards.forEach(card => {
          const nameEl = card.querySelector('._4rR01T, .s1Q9rs, ._2WkVRV, a[href*="/p/"]');
          const name = nameEl ? (nameEl.textContent || nameEl.getAttribute('title') || '').trim() : '';
          if (!name || !/ghee/i.test(name)) return;
          const href = card.querySelector('a[href*="/p/"]');
          const url = href ? href.getAttribute('href') : '';
          const pid = url ? (url.match(/\/p\/([A-Z0-9]+)/) || [])[1] : null;
          if (!pid || seen.has(pid)) return;
          seen.add(pid);
          const priceEl = card.querySelector('._30jeq3, ._1_WHN1');
          const mrpEl = card.querySelector('._3I9_wc, ._3tbZJD');
          const stockEl = card.querySelector('._3Yf_7X, .TAJNBR'); // OOS indicators
          results.push({
            pid, name, url,
            price_text: priceEl ? priceEl.textContent.trim() : null,
            mrp_text: mrpEl ? mrpEl.textContent.trim() : null,
            in_stock: !stockEl
          });
        });
        return results;
      });

      process.stderr.write(`[flipkart] Page ${pg}: ${items.length} ghee items\n`);
      for (const item of items) {
        if (skus.find(s => s.pid === item.pid)) continue;
        const price = parsePrice(item.price_text);
        const mrp = parsePrice(item.mrp_text);
        const pack = inferPackSize(item.name);
        const per_kg = price ? toPerKg(price, item.name, pack) : null;
        skus.push({
          pid: item.pid,
          name: item.name,
          brand: inferBrand(item.name),
          pack,
          price_inr: price,
          mrp_inr: mrp,
          per_kg_inr: per_kg ? Math.round(per_kg) : null,
          in_stock: item.in_stock,
          a2: isA2(item.name),
          source_page: pg
        });
      }
      if (items.length === 0) { process.stderr.write('[flipkart] Empty page, stopping\n'); break; }
    }
  } catch (e) {
    process.stderr.write(`[flipkart] Error: ${e.message}\n`);
  }
  await browser.close();
  fs.writeFileSync(OUT, JSON.stringify({ platform:'flipkart', query:'ghee', total_skus: skus.length, skus }, null, 2));
  process.stderr.write(`[flipkart] Done. ${skus.length} unique ghee SKUs\n`);
  process.stdout.write(JSON.stringify({total_skus: skus.length, captured_at: new Date().toISOString()}) + '\n');
})();
