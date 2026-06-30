// VERIFY whether Gemini's Fresh slot-gate HELPED (dropped real marketplace bleed) or
// HARMED (dropped genuine Amazon Fresh items). For a few pincodes, fetch the i=freshstore
// search, list EVERY Jivo card with its delivery slot, the Now-style blue badge (if any),
// and Gemini's isFreshSlot verdict — then show what the DROPPED cards actually say.
// Also side-by-side with almBrandId=amazonfresh to see if a cleaner Fresh surface exists.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const STATE = path.join(__dirname, 'secrets', 'amazon-fresh.storageState.json');
const OUT = path.join(__dirname, 'secrets');
const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const PINS = [
  { city: 'Bengaluru', pincode: '560034' },
  { city: 'Delhi', pincode: '110021' },
  { city: 'Mumbai', pincode: '400001' },
  { city: 'Olpad', pincode: '394540' },
];
const SURFACES = { freshstore: 'i=freshstore', amazonfresh: 'almBrandId=amazonfresh' };

// EXACT copy of Gemini's gate (amazon-fresh/scrape.js) so we test the real logic.
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
async function fetchSurface(page, qstr) {
  return page.evaluate(async ({ qstr }) => {
    const res = await fetch('/s?k=jivo&' + qstr, { headers: { accept: 'text/html' } });
    const html = await res.text();
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const clean = (el) => { if (!el) return ''; const c = el.cloneNode(true); c.querySelectorAll('style,script').forEach((s) => s.remove()); return (c.textContent || '').replace(/\s+/g, ' ').trim(); };
    const cards = [...doc.querySelectorAll('[data-component-type="s-search-result"][data-asin]')].filter((c) => /jivo/i.test(c.textContent || ''));
    return {
      amazonNow: /amazon\s*now/i.test(html), amazonFresh: /amazon\s*fresh/i.test(html),
      rows: cards.map((c) => ({
        asin: c.getAttribute('data-asin'),
        price: clean(c.querySelector('.a-price .a-offscreen')),
        slot: clean(c.querySelector('[data-cy="delivery-recipe"]')).slice(0, 70),
        dex: clean(c.querySelector('.dex-text-slanted-blue-highlight')),
      })),
    };
  }, { qstr });
}

(async () => {
  const browser = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new'] }).catch(() => chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }));
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
  const page = await ctx.newPage();
  const out = { ts: new Date().toISOString(), pins: [] };
  for (const p of PINS) {
    const loc = await setLocation(page, p.pincode);
    const rec = { ...p, loc, surfaces: {} };
    for (const [tag, q] of Object.entries(SURFACES)) {
      try {
        const r = await fetchSurface(page, q);
        const kept = r.rows.filter((x) => isFreshSlot(x.slot));
        const dropped = r.rows.filter((x) => !isFreshSlot(x.slot));
        rec.surfaces[tag] = { jivo: r.rows.length, kept: kept.length, dropped: dropped.length, amazonNow: r.amazonNow, amazonFresh: r.amazonFresh,
          droppedSamples: dropped.slice(0, 6).map((x) => `${x.asin} ₹${x.price} slot="${x.slot}" dex="${x.dex}"`),
          keptSamples: kept.slice(0, 4).map((x) => `${x.asin} ₹${x.price} slot="${x.slot}" dex="${x.dex}"`) };
        process.stderr.write(`[${p.city} ${p.pincode}] ${tag}: jivo=${r.rows.length} kept=${kept.length} dropped=${dropped.length} now=${r.amazonNow} fresh=${r.amazonFresh}\n`);
      } catch (e) { rec.surfaces[tag] = { err: e.message }; }
      await sleep(1000);
    }
    out.pins.push(rec);
  }
  await browser.close().catch(() => {});
  fs.writeFileSync(path.join(OUT, 'probe_fresh_verify.json'), JSON.stringify(out, null, 2));
  process.stderr.write('[done] -> secrets/probe_fresh_verify.json\n');
})();
