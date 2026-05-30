// Capture the exact network request the GLOW widget fires to SET the delivery pincode,
// so we can replay it directly (one request, ~0.5s) instead of the slow click-through.
const { chromium } = require('playwright');
const path = require('path');
const STATE = path.join(__dirname, 'secrets/amazon-now.storageState.json');
const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  let b; try { b = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new'] }); } catch (_) { b = await chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }); }
  const ctx = await b.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
  const page = await ctx.newPage();
  const hits = [];
  page.on('request', (req) => {
    const u = req.url();
    if (/address-change|portal-migration|glow|changeLocation|GLUXChangePostalCode|gp\/delivery|/.test(u) && /address|glow|location|postal|delivery/i.test(u)) {
      hits.push({ method: req.method(), url: u.slice(0, 160), post: (req.postData() || '').slice(0, 300), csrf: req.headers()['anti-csrftoken-a2z'] || '' });
    }
  });
  await page.goto('https://www.amazon.in/?ref_=nav_signin', { waitUntil: 'domcontentloaded', timeout: 45000 }); await sleep(1500);
  await page.click('#nav-global-location-popover-link', { timeout: 8000 }); await sleep(1500);
  await page.fill('#GLUXZipUpdateInput', '400017', { timeout: 8000 }); await sleep(400);
  try { await page.click('#GLUXZipUpdate input[type="submit"], #GLUXZipUpdate-announce', { timeout: 5000 }); } catch (_) {}
  await sleep(2500);
  try { await page.click('button[name="glowDoneButton"], .a-popover-footer #GLUXConfirmClose', { timeout: 4000 }); } catch (_) {}
  await sleep(1500);
  console.log('=== location-set network calls ===');
  for (const h of hits) console.log(`${h.method} ${h.url}\n   post: ${h.post}\n   csrf: ${h.csrf}`);
  // also grab the CSRF token the page exposes for glow
  const tok = await page.evaluate(() => {
    const m = (window.ue && window.ue_csm) ? 'ue' : '';
    const meta = document.querySelector('input[name="anti-csrftoken-a2z"]');
    return { metaToken: meta ? meta.value : '', hasGlowCsrf: !!(window.csmCsrfToken) };
  }).catch(() => ({}));
  console.log('page token hint:', JSON.stringify(tok));
  await b.close();
})();
