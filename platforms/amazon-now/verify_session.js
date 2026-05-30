// Load the transplanted storageState and check, FROM THE VPS IP, whether the session is
// truly logged in and whether the address book is reachable (the surface we need for the
// per-pincode Now scrape). This is the make-or-break test of the cookie-transplant plan.
//
//   node verify_session.js
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const STATE = path.join(__dirname, 'secrets', 'amazon-now.storageState.json');
const OUT = path.join(__dirname, 'secrets');
const UA = process.env.UA ||
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function passInterstitial(page) {
  const hit = await page.evaluate(() => /continue shopping/i.test(document.body.innerText || '') && !document.querySelector('#nav-link-accountList')).catch(() => false);
  if (!hit) return;
  try { await page.getByRole('button', { name: /continue shopping/i }).click({ timeout: 6000 }); } catch (_) {}
  await page.waitForLoadState('domcontentloaded', { timeout: 20000 }).catch(() => {});
  await sleep(2000);
}

(async () => {
  if (!fs.existsSync(STATE)) { console.error('no storageState at ' + STATE); process.exit(1); }
  let browser;
  try { browser = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new', '--disable-blink-features=AutomationControlled'] }); }
  catch (_) { browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }); }

  const ctx = await browser.newContext({
    userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata',
    viewport: { width: 1366, height: 900 }, storageState: STATE,
    extraHTTPHeaders: { 'Accept-Language': 'en-IN,en;q=0.9' },
  });
  await ctx.addInitScript(() => { Object.defineProperty(navigator, 'webdriver', { get: () => undefined }); });
  const page = await ctx.newPage();

  const result = { homepage: {}, addresses: {} };
  try {
    // 1) Homepage: is the account greeting personalised (= logged in)?
    await page.goto('https://www.amazon.in/?ref_=nav_signin', { waitUntil: 'domcontentloaded', timeout: 45000 });
    await sleep(2500);
    await passInterstitial(page);
    result.homepage = await page.evaluate(() => {
      const g = document.querySelector('#nav-link-accountList-nav-line-1, #nav-link-accountList .nav-line-1');
      const txt = g ? (g.innerText || '').trim() : '';
      return {
        url: location.href,
        greeting: txt,
        loggedIn: /hello,?\s+(?!sign)/i.test(txt) && !/sign in/i.test(txt),
        captcha: /enter the characters|automated access|puzzle to protect/i.test(document.body.innerText || ''),
      };
    });
    await page.screenshot({ path: path.join(OUT, 'verify_home.png'), fullPage: false }).catch(() => {});

    // 2) Address book: the surface we drive to switch delivery pincodes.
    await page.goto('https://www.amazon.in/a/addresses', { waitUntil: 'domcontentloaded', timeout: 45000 });
    await sleep(2500);
    await passInterstitial(page);
    result.addresses = await page.evaluate(() => {
      const body = document.body.innerText || '';
      return {
        url: location.href,
        signinWall: /ap\/signin/i.test(location.href) || !!document.getElementById('ap_password'),
        hasAddressUI: /add address|your addresses|default address|add a new address/i.test(body),
        captcha: /enter the characters|automated access|puzzle to protect/i.test(body),
        addressCount: document.querySelectorAll('[class*="address" i] [class*="tile" i], .a-box-group .a-box').length,
      };
    });
    await page.screenshot({ path: path.join(OUT, 'verify_addresses.png'), fullPage: false }).catch(() => {});

    console.log(JSON.stringify(result, null, 2));
    const ok = result.homepage.loggedIn && !result.addresses.signinWall;
    console.log('\n=== VERDICT: ' + (ok ? 'SESSION WORKS FROM VPS ✓' : 'session NOT usable from VPS ✗') + ' ===');
    if (result.homepage.greeting) console.log('greeting: ' + result.homepage.greeting);
  } catch (e) {
    console.error('verify error: ' + e.message);
    process.exitCode = 1;
  } finally {
    await browser.close().catch(() => {});
  }
})();
