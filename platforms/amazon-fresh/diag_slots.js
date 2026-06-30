// DIAGNOSTIC (read-only on data; live-fetch only): for a few pincodes, dump for EVERY
// Jivo i=freshstore card the slot text as seen by BOTH the live scraper's selector and the
// old probe's selector, plus every delivery-ish element on the card — then apply the EXACT
// isFreshSlot() gate to each. Settles "is the gate over-dropping genuine Fresh, or was the
// probe just reading the wrong element?". MUST run under the .amazon-account.lock.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const STATE = path.join(__dirname, 'secrets', 'amazon-fresh.storageState.json');
const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const PINS = ['560034', '560001', '110021'];

// EXACT copy of scrape.js gate.
function isFreshSlot(slot) {
  const s = (slot || '').toLowerCase();
  if (!s) return false;
  if (/\bin\s+\d+\s*min/.test(s)) return true;
  if (/\d{1,2}\s*(?:am|pm)\s*[-–]\s*\d{1,2}\s*(?:am|pm)/.test(s)) return true;
  return false;
}
async function passInterstitial(page) {
  const hit = await page.evaluate(() => /continue shopping/i.test(document.body.innerText || '') && !document.querySelector('#nav-link-accountList')).catch(() => false);
  if (!hit) return;
  try { await page.getByRole('button', { name: /continue shopping/i }).click({ timeout: 6000 }); } catch (_) {}
  await sleep(1500);
}
async function setLocation(page, pin) {
  await page.goto('https://www.amazon.in/?ref_=nav_signin', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await sleep(1200); await passInterstitial(page);
  try {
    await page.click('#nav-global-location-popover-link, #glow-ingress-block', { timeout: 8000 }); await sleep(1400);
    await page.fill('#GLUXZipUpdateInput', pin, { timeout: 8000 }); await sleep(400);
    try { await page.click('#GLUXZipUpdate input[type="submit"], #GLUXZipUpdate-announce', { timeout: 5000 }); } catch (_) {}
    await sleep(1800);
    try { await page.click('button[name="glowDoneButton"], .a-popover-footer #GLUXConfirmClose', { timeout: 4000 }); } catch (_) {}
    await sleep(1200);
  } catch (e) {}
  return page.evaluate(() => { const g = document.getElementById('glow-ingress-line2'); return g ? (g.innerText || '').replace(/\s+/g, ' ').trim() : ''; });
}
(async () => {
  const browser = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new'] }).catch(() => chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }));
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
  const page = await ctx.newPage();
  const out = { ts: new Date().toISOString(), pins: [] };
  for (const pin of PINS) {
    const loc = await setLocation(page, pin);
    const data = await page.evaluate(async () => {
      const T = (el) => el ? (el.textContent || '').replace(/\s+/g, ' ').trim() : '';
      const res = await fetch('/s?k=jivo&i=freshstore', { headers: { accept: 'text/html' } });
      const html = await res.text();
      const doc = new DOMParser().parseFromString(html, 'text/html');
      const cards = [...doc.querySelectorAll('[data-component-type="s-search-result"][data-asin]')]
        .filter((c) => /jivo/i.test(c.textContent || '') && (c.getAttribute('data-asin') || '').length > 3);
      return cards.map((c) => ({
        asin: c.getAttribute('data-asin'),
        price: T(c.querySelector('.a-price[data-a-color="base"] .a-offscreen, .a-price .a-offscreen')),
        liveSlot: T(c.querySelector('[class*="delivery" i], .udm-primary-delivery-message')).slice(0, 90),
        probeSlot: T(c.querySelector('[data-cy="delivery-recipe"]')).slice(0, 90),
        allDelivery: [...c.querySelectorAll('[class*="delivery" i]')].map((e) => T(e).slice(0, 70)).filter(Boolean).slice(0, 6),
      }));
    });
    const enriched = data.map((d) => ({ ...d, liveFresh: isFreshSlot(d.liveSlot), probeFresh: isFreshSlot(d.probeSlot) }));
    const liveKept = enriched.filter((d) => d.liveFresh).length;
    const probeKept = enriched.filter((d) => d.probeFresh).length;
    out.pins.push({ pin, loc, jivo: enriched.length, liveKept, probeKept, cards: enriched });
    process.stderr.write(`[${pin}] loc="${loc}" jivo=${enriched.length} liveKept=${liveKept} probeKept=${probeKept}\n`);
    await sleep(1000);
  }
  await browser.close().catch(() => {});
  fs.writeFileSync(path.join(__dirname, 'secrets', 'diag_slots.json'), JSON.stringify(out, null, 2));
  process.stderr.write('[done] -> secrets/diag_slots.json\n');
})();
