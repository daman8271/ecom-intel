const { chromium } = require('playwright');
const fs = require('fs');

(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36', locale: 'en-IN' });
  const page = await ctx.newPage();
  await page.goto('https://www.amazon.in/s?k=ghee', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(2000);
  const title = await page.title();
  const text = (await page.evaluate(() => document.body.innerText)).slice(0, 500);
  const asinCount = await page.evaluate(() => document.querySelectorAll('[data-asin]:not([data-asin=""])').length);
  process.stderr.write(`Title: ${title}\nASINs: ${asinCount}\nText: ${text}\n`);
  await browser.close();
})();
