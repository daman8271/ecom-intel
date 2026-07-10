const { chromium } = require('playwright');
const fs = require('fs');

(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ 
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
    locale: 'en-IN' 
  });
  const page = await ctx.newPage();
  const apiResponses = [];
  
  // Intercept all JSON API responses
  page.on('response', async (resp) => {
    const url = resp.url();
    const ct = resp.headers()['content-type'] || '';
    if (ct.includes('json') && (url.includes('search') || url.includes('product') || url.includes('api'))) {
      try {
        const body = await resp.text();
        if (body.length > 100 && body.includes('ghee') || body.includes('"title"')) {
          apiResponses.push({ url: url.substring(0, 120), bodyLen: body.length, sample: body.substring(0, 300) });
        }
      } catch (_) {}
    }
  });
  
  await page.goto('https://www.flipkart.com/search?q=ghee&marketplace=FLIPKART', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(4000);
  
  // Scroll to trigger lazy loading
  await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight / 2));
  await page.waitForTimeout(2000);
  
  const bodyText = await page.evaluate(() => document.body.innerText);
  process.stderr.write(`Body len: ${bodyText.length}, API responses: ${apiResponses.length}\n`);
  apiResponses.forEach(r => process.stderr.write(`API: ${r.url}\n  sample: ${r.sample.substring(0, 200)}\n`));
  
  // Try to get product JSON from the page's script tags
  const scriptData = await page.evaluate(() => {
    const scripts = Array.from(document.querySelectorAll('script[type="application/ld+json"]'));
    return scripts.map(s => s.textContent);
  });
  process.stderr.write(`ld+json scripts: ${scriptData.length}\n`);
  scriptData.forEach(s => process.stderr.write(`${s.substring(0,300)}\n`));
  
  await browser.close();
})();
