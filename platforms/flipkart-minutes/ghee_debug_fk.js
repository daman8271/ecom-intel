const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ 
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
    locale: 'en-IN' 
  });
  const page = await ctx.newPage();
  await page.goto('https://www.flipkart.com/search?q=ghee&marketplace=FLIPKART', { waitUntil: 'networkidle', timeout: 30000 });
  await page.waitForTimeout(2000);
  
  // Get all text content to see what's on the page
  const result = await page.evaluate(() => {
    // Try different selectors
    const data = {
      title: document.title,
      bodyLen: document.body.innerText.length,
      // count different elements
      divCount: document.querySelectorAll('div').length,
      // Sample product elements
      items: []
    };
    
    // Try various selectors
    const selectors = [
      '._1AtVbE', '._2kHMtA', '.CXW8mj', '._13oc-S', '[class*="product"]',
      '._4ddWXP', '._2B099V', '._3pLy-c', '.slAVV4'
    ];
    
    for (const sel of selectors) {
      const els = document.querySelectorAll(sel);
      if (els.length > 0) {
        data[sel] = els.length;
        // Try to get first item's text
        const first = els[0];
        const text = first.innerText ? first.innerText.substring(0, 200) : '';
        if (text.toLowerCase().includes('ghee')) {
          data[sel + '_sample'] = text;
        }
      }
    }
    
    // Try to find any elements with price ₹
    const priceEls = Array.from(document.querySelectorAll('*')).filter(el => 
      el.childElementCount === 0 && el.innerText && el.innerText.match(/^₹\s*\d/)
    );
    data.priceEls = priceEls.slice(0, 5).map(el => ({ tag: el.tagName, cls: el.className, text: el.innerText }));
    
    return data;
  });
  
  process.stderr.write(JSON.stringify(result, null, 2) + '\n');
  await browser.close();
})();
