// RECON: find the REAL Amazon Now (quick-commerce) surface + its product/search API.
// The i=nowstore search proved to be legacy marketplace (no minute ETAs). Amazon Now
// (2025 India quick-commerce, ~10-30 min) is believed to live on the logged-in
// alm/ctnow storefront (the alm backend Amazon Fresh uses). This probe:
//   1. sets a metro delivery location via GLOW,
//   2. scans the homepage for a "Now"/quick-commerce entry point,
//   3. loads candidate Now URLs, capturing ALL network JSON (esp. anything with 'jivo',
//      a price, or a minute/hour ETA) + page signals + screenshots.
// Sequential, single account. Output: secrets/recon_now_real.json (+ jivo bodies, shots).
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const STATE = path.join(__dirname, 'secrets', 'amazon-now.storageState.json');
const OUT = path.join(__dirname, 'secrets');
const PIN = process.env.PIN || '560034'; // Bengaluru (Koramangala) — Amazon Now launch city
const UA = process.env.UA ||
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const CANDIDATES = [
  'https://www.amazon.in/fmc/storefront?almBrandId=ctnow',
  'https://www.amazon.in/alm/storefront?almBrandId=ctnow',
  'https://www.amazon.in/now',
  'https://www.amazon.in/amazonnow',
  'https://www.amazon.in/s?k=jivo&almBrandId=ctnow',
];

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
  } catch (e) { process.stderr.write('[loc] ui err ' + e.message + '\n'); }
  return page.evaluate(() => { const g = document.getElementById('glow-ingress-line2'); return g ? (g.innerText || '').replace(/\s+/g, ' ').trim() : ''; });
}

(async () => {
  if (!fs.existsSync(STATE)) { console.error('no session'); process.exit(2); }
  let browser;
  try { browser = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new', '--disable-blink-features=AutomationControlled'] }); }
  catch (_) { browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }); }
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
  await ctx.addInitScript(() => { Object.defineProperty(navigator, 'webdriver', { get: () => undefined }); });
  const page = await ctx.newPage();

  const net = [];           // interesting network responses (metadata)
  const jivoBodies = [];    // full bodies that mention jivo
  page.on('response', async (resp) => {
    try {
      const url = resp.url();
      const ct = (resp.headers()['content-type'] || '');
      const isJson = /json|javascript|text\/plain/.test(ct);
      const interestingUrl = /search|storefront|almapi|alm\/|fmc|/.test(url) && /amazon\.in/.test(url);
      if (!isJson && !interestingUrl) return;
      let body = '';
      try { body = await resp.text(); } catch (_) { return; }
      if (!body || body.length < 40) return;
      const hasJivo = /jivo/i.test(body);
      const hasEta = /\b(in|within)\s+\d+\s*(min|minute|hour|hr)|\b\d+\s*(min|mins|minutes)\b|get it in/i.test(body);
      const hasPrice = /"price"|priceAmount|a-price|₹|\bINR\b/i.test(body);
      if (hasJivo || (isJson && (hasEta || hasPrice) && /search|storefront|alm|product|widget|now/i.test(url))) {
        net.push({ url: url.slice(0, 180), status: resp.status(), ct: ct.slice(0, 40), bytes: body.length, hasJivo, hasEta, hasPrice });
        if (hasJivo && jivoBodies.length < 12) jivoBodies.push({ url, body: body.slice(0, 20000) });
      }
    } catch (_) {}
  });

  const out = { ts: new Date().toISOString(), pin: PIN, location: '', homepage_entrypoints: [], pages: [] };
  out.location = await setLocation(page, PIN);
  process.stderr.write(`[loc] resolved: "${out.location}"\n`);

  // scan homepage for a Now / quick-commerce entry point
  try {
    out.homepage_entrypoints = await page.evaluate(() => {
      const links = [...document.querySelectorAll('a[href]')];
      return links
        .filter((a) => /now|minute|quick|alm|ctnow|fmc|fresh/i.test((a.href + ' ' + (a.innerText || ''))))
        .slice(0, 40)
        .map((a) => ({ text: (a.innerText || '').replace(/\s+/g, ' ').trim().slice(0, 40), href: a.href.slice(0, 140) }));
    });
  } catch (_) {}

  for (const url of CANDIDATES) {
    const rec = { url, finalUrl: '', title: '', signals: {}, err: '' };
    try {
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 40000 });
      await sleep(3500); await passInterstitial(page);
      await page.evaluate(() => window.scrollBy(0, 1500)).catch(() => {});
      await sleep(2500);
      const info = await page.evaluate(() => {
        const body = document.body.innerText || '';
        return {
          finalUrl: location.href,
          title: (document.title || '').slice(0, 80),
          mentions_amazon_now: /amazon\s*now/i.test(body),
          mentions_minutes: /\b\d+\s*(min|mins|minutes)\b|in \d+ ?h|get it in/i.test(body),
          mentions_jivo: /jivo/i.test(body),
          not_found: /page not found|sorry.*looking for|dogs of amazon/i.test(body),
          bodyHead: body.replace(/\s+/g, ' ').slice(0, 220),
        };
      });
      rec.finalUrl = info.finalUrl; rec.title = info.title; rec.signals = info;
      const shot = path.join(OUT, 'recon_' + url.replace(/[^a-z0-9]+/gi, '_').slice(0, 40) + '.png');
      await page.screenshot({ path: shot }).catch(() => {});
      rec.shot = path.basename(shot);
    } catch (e) { rec.err = e.message; }
    process.stderr.write(`[page] ${url} -> ${rec.finalUrl || rec.err} | now=${rec.signals.mentions_amazon_now} mins=${rec.signals.mentions_minutes} jivo=${rec.signals.mentions_jivo} 404=${rec.signals.not_found}\n`);
    out.pages.push(rec);
    await sleep(1000);
  }

  out.network = net;
  await browser.close().catch(() => {});
  fs.writeFileSync(path.join(OUT, 'recon_now_real.json'), JSON.stringify(out, null, 2));
  if (jivoBodies.length) fs.writeFileSync(path.join(OUT, 'recon_now_jivo_bodies.json'), JSON.stringify(jivoBodies, null, 2));
  process.stderr.write(`[done] ${net.length} interesting responses, ${jivoBodies.length} jivo bodies -> secrets/recon_now_real.json\n`);
})();
