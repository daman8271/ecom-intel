// Can parallel workers have INDEPENDENT locations if each gets its own session-id?
// Each context loads the auth (at-acbin/session-token) but CLEARS session-id so Amazon
// issues a fresh session per context. If location then tracks per-session, parallel is safe.
const { chromium } = require('playwright');
const path = require('path');
const STATE = path.join(__dirname, 'secrets/amazon-now.storageState.json');
const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function setpin(page, pin) {
  await page.goto('https://www.amazon.in/?ref_=nav_signin', { waitUntil: 'domcontentloaded', timeout: 45000 }); await sleep(1200);
  try {
    await page.click('#nav-global-location-popover-link', { timeout: 8000 }); await sleep(1400);
    await page.fill('#GLUXZipUpdateInput', pin, { timeout: 8000 }); await sleep(400);
    try { await page.click('#GLUXZipUpdate input[type="submit"], #GLUXZipUpdate-announce', { timeout: 5000 }); } catch (_) {}
    await sleep(1600);
    try { await page.click('button[name="glowDoneButton"], .a-popover-footer #GLUXConfirmClose', { timeout: 4000 }); } catch (_) {}
    await sleep(1000);
  } catch (e) {}
  return page.evaluate(() => {
    const g = document.getElementById('glow-ingress-line2');
    const acc = document.querySelector('#nav-link-accountList-nav-line-1');
    return { glow: g ? g.innerText.replace(/\s+/g, ' ').trim() : '', acct: acc ? acc.innerText.trim() : '' };
  });
}

async function probe(browser, pin, label) {
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
  // fresh session-id per context (keep auth cookies)
  try { await ctx.clearCookies({ name: 'session-id' }); await ctx.clearCookies({ name: 'session-id-time' }); await ctx.clearCookies({ name: 'ubid-acbin' }); } catch (_) {}
  const page = await ctx.newPage();
  const s = await setpin(page, pin);
  await page.goto('https://www.amazon.in/s?k=jivo&i=nowstore', { waitUntil: 'domcontentloaded', timeout: 40000 }); await sleep(2500);
  const d = await page.evaluate(() => {
    const T = (el) => el ? (el.innerText || '').replace(/\s+/g, ' ').trim() : '';
    const cards = [...document.querySelectorAll('[data-component-type="s-search-result"][data-asin]')];
    const jivo = cards.filter((c) => /\bjivo\b/i.test(T(c)));
    return { total: cards.length, jivo: jivo.length, slot: T(jivo[0] && jivo[0].querySelector('[class*="delivery" i]')).slice(0, 36) };
  });
  await ctx.close();
  console.log(`[${label}] set=${pin} glow="${s.glow}" acct="${s.acct}" cards=${d.total} jivo=${d.jivo} slot="${d.slot}"`);
  return { pin, glow: s.glow, ...d };
}

(async () => {
  let b; try { b = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new'] }); } catch (_) { b = await chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }); }
  const res = await Promise.all([probe(b, '400017', 'MUM'), probe(b, '700001', 'KOL'), probe(b, '174001', 'RURAL')]);
  const ok = res.every((r) => r.glow.includes(r.pin));
  console.log('INDEPENDENT:', ok ? 'YES (parallel safe with fresh session-id)' : 'NO (still collides — location is account-global)');
  await b.close();
})();
