const { chromium } = require('playwright');

(async () => {
  console.log("Launching Playwright...");
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
  });
  const page = await context.newPage();
  
  try {
    console.log("Navigating to Zepto website...");
    const response = await page.goto('https://www.zeptonow.com/search?q=jivo', { waitUntil: 'domcontentloaded', timeout: 15000 });
    
    console.log(`HTTP Status: ${response ? response.status() : 'Unknown'}`);
    if (response && response.status() === 403) {
      console.log("BLOCKED BY 403 (CloudFront WAF)");
    }
    
    const title = await page.title();
    console.log("Page Title:", title);
    
    const pageText = await page.evaluate(() => document.body.innerText.substring(0, 500));
    console.log("Extracted text snippet:");
    console.log(pageText.replace(/\n+/g, ' '));
  } catch (error) {
    console.error("Navigation failed or timed out:", error.message);
  } finally {
    await browser.close();
  }
})();
