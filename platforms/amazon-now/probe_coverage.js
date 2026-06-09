// COVERAGE-MISS probe (amzcover W1, 2026-06-09) — READ-ONLY, writes ONLY to OUT_FILE (/tmp).
// Question: for the 12 suspect Jivo ASINs absent@110095, is it a REAL per-store not-Now-stock,
// or a CAPTURE-MISS (the broad k=jivo search drops a card a DIRECT ASIN check would surface)?
//
// For each probe pincode it does, with the location set the SAME way scrape.ctnow.js does:
//   (a) the normal broad search  /s?k=jivo&almBrandId=ctnow  across MAXPAGES (the production path),
//       collecting EVERY jivo card raw (no canonical-dedup) + its instant-Now status, so we see if a
//       suspect appears in the broad search at all.
//   (b) a DIRECT per-ASIN check  /s?k=<asin>&almBrandId=ctnow  for each suspect — does THAT surface
//       the card, and with a genuine instant-minute Now badge?
//   (c) PDP corroboration  /dp/<asin>  with the ctnow location set — the buy-box delivery promise.
// Apples-to-apples with the scraper's own genuine-Now rule: a card is Now-serviceable ⇔ it shows an
// instant-minute tier ("in N minutes" -> '10 min'). Scheduled tiers (tomorrow/today/overnight) are
// Fresh, NOT Now. 110095 is the ref; 400601 is a control where 7 suspects ARE present (method check).
//
//   flock /opt/ecom-intel/.amazon-now.lock node probe_coverage.js
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const STATE = path.join(__dirname, 'secrets', 'amazon-now.storageState.json');
const OUT = process.env.OUT_FILE || '/tmp/amznow-coverage-probe.json';
const PINS = (process.env.PINS || '110095,400601').split(',').map((s) => s.trim()).filter(Boolean);
const MAXPAGES = parseInt(process.env.MAXPAGES || '3', 10);
const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// 12 suspects: ASIN -> label (from sku_map.json platforms['amazon-now'].id)
const SUSPECTS = {
  B077ZN4G28: 'CANOLA 5L', B0BZ8K3DQP: 'COCONUT 1L', B093BMGPQC: 'EXTRA VIRGIN 1L',
  B0C9Q1S6QG: 'GOLD 5L', B0CKFFW9B6: 'GROUNDNUT 1L', B09NYCSQLF: 'MUSTARD 1L',
  B091XPD9J3: 'MUSTARD 5L', B0DBHQ2QWW: 'RICE BRAN 1L', B0B6HNNL5B: 'SOYABEAN 1L',
  B0B4SJTNF2: 'SUNFLOWER 1L', B0DM2G4YCC: 'WG MANGO JUICE 500ML', B0FF9P7XVX: 'YELLOW MUSTARD 1L',
};

// instant-minute discriminator — IDENTICAL to scrape.ctnow.js nowTier()=='10 min'
function isInstant(badge, deliv) {
  const s = ((badge || '') + ' ' + (deliv || '')).toLowerCase();
  return /\bin\s+\d+\s*min/.test(s);
}
function tier(badge, deliv) {
  const s = ((badge || '') + ' ' + (deliv || '')).toLowerCase();
  if (/\bin\s+\d+\s*min/.test(s)) return '10 min';
  if (/\bovernight\b/.test(s)) return 'overnight';
  if (/\btoday\b/.test(s)) return 'today';
  if (/\btomorrow\b/.test(s)) return 'tomorrow';
  return (badge || '').trim().toLowerCase() || '';
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
  } catch (e) { process.stderr.write('[loc] ui err ' + e.message + '\n'); }
  return page.evaluate(() => { const g = document.getElementById('glow-ingress-line2'); return g ? (g.innerText || '').replace(/\s+/g, ' ').trim() : ''; });
}

// One ctnow search (query = 'jivo' for broad, or an ASIN for direct). Returns ALL cards raw.
async function ctnowSearch(page, query, pageNo) {
  return page.evaluate(async ({ query, pageNo }) => {
    const url = '/s?k=' + encodeURIComponent(query) + '&almBrandId=ctnow' + (pageNo > 1 ? '&page=' + pageNo : '');
    const r = await fetch(url, { headers: { accept: 'text/html' } });
    const html = await r.text();
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const T = (el) => el ? (el.textContent || '').replace(/\s+/g, ' ').trim() : '';
    const cards = [...doc.querySelectorAll('[data-component-type="s-search-result"][data-asin]')].filter((c) => (c.getAttribute('data-asin') || '').length > 3);
    const rows = cards.map((c) => {
      const badgeEl = c.querySelector('.dex-text-slanted-blue-highlight');
      return {
        asin: c.getAttribute('data-asin'),
        title: T(c.querySelector('h2 a span, [data-cy="title-recipe"]')).slice(0, 80),
        badge: T(badgeEl),
        nowBadge: !!(badgeEl && T(badgeEl)),
        deliv: T(c.querySelector('[data-cy="delivery-recipe"]')).slice(0, 100),
        oos: /currently unavailable|out of stock|sold out/i.test(T(c)),
        isJivo: /jivo/i.test(T(c)),
      };
    });
    return {
      amazonNowPage: /amazon\s*now/i.test(html),
      hasNext: !!doc.querySelector('a.s-pagination-next:not(.s-pagination-disabled)'),
      totalCards: cards.length, rows,
    };
  }, { query, pageNo });
}

// PDP corroboration with ctnow location already set.
async function pdpCheck(page, asin) {
  try {
    await page.goto('https://www.amazon.in/dp/' + asin + '?almBrandId=ctnow', { waitUntil: 'domcontentloaded', timeout: 40000 });
    await sleep(900); await passInterstitial(page);
    return await page.evaluate(() => {
      const T = (sel) => { const el = document.querySelector(sel); return el ? (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim() : ''; };
      const avail = T('#availability, #availability span');
      const deliv = T('#mir-layout-DELIVERY_BLOCK, #deliveryBlockMessage, #delivery-block-feature, [data-csa-c-content-id="DEXUnifiedCXPDM"]').slice(0, 200);
      const buybox = T('#buybox, #desktop_buybox').slice(0, 120);
      const body = (document.body.innerText || '');
      const minHit = (body.match(/\b(?:in|within|get it in)\s+\d+\s*(?:min|minute|mins|minutes)\b/i) || [])[0] || '';
      const nowOnPage = /amazon\s*now/i.test(body);
      const unavailable = /currently unavailable|out of stock|we don't know when|cannot be (shipped|delivered)/i.test(avail + ' ' + body.slice(0, 4000));
      return { avail: avail.slice(0, 120), deliv, buybox, minHit, nowOnPage, unavailable };
    });
  } catch (e) { return { err: e.message }; }
}

(async () => {
  if (!fs.existsSync(STATE)) { console.error('FATAL no session ' + STATE); process.exit(2); }
  let browser;
  try { browser = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new', '--disable-blink-features=AutomationControlled'] }); }
  catch (_) { browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }); }
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
  await ctx.addInitScript(() => { Object.defineProperty(navigator, 'webdriver', { get: () => undefined }); });
  const page = await ctx.newPage();

  // session sanity
  await page.goto('https://www.amazon.in/?ref_=nav_signin', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await sleep(1200); await passInterstitial(page);
  const greet = await page.evaluate(() => { const g = document.querySelector('#nav-link-accountList-nav-line-1, #nav-link-accountList .nav-line-1'); return g ? (g.innerText || '').trim() : ''; });
  process.stderr.write('[session] greeting="' + greet + '"\n');

  const out = { ts: new Date().toISOString(), greeting: greet, suspects: SUSPECTS, results: [] };
  for (const pin of PINS) {
    const loc = await setLocation(page, pin);
    process.stderr.write(`\n[${pin}] location="${loc}"\n`);

    // (a) broad k=jivo search across pages — raw, no dedup
    const broad = [];
    let nowPage = false;
    for (let pg = 1; pg <= MAXPAGES; pg++) {
      const res = await ctnowSearch(page, 'jivo', pg);
      if (pg === 1) nowPage = res.amazonNowPage;
      for (const c of res.rows) if (c.isJivo) broad.push({ ...c, page: pg, tier: tier(c.badge, c.deliv), instant: isInstant(c.badge, c.deliv) });
      if (!res.hasNext) break;
      await sleep(300 + Math.random() * 300);
    }
    const broadByAsin = {};
    for (const c of broad) if (!broadByAsin[c.asin]) broadByAsin[c.asin] = c;
    process.stderr.write(`[${pin}] broad jivo cards=${broad.length} (instant=${broad.filter((c) => c.instant).length}) nowPage=${nowPage}\n`);

    // (b)+(c) per-suspect direct ASIN search + PDP
    const perSuspect = {};
    for (const [asin, label] of Object.entries(SUSPECTS)) {
      const inBroad = broadByAsin[asin] || null;
      // direct ASIN search on ctnow
      const ds = await ctnowSearch(page, asin, 1);
      const dcard = ds.rows.find((c) => c.asin === asin) || null;
      const direct = dcard ? { found: true, title: dcard.title, badge: dcard.badge, deliv: dcard.deliv, oos: dcard.oos, tier: tier(dcard.badge, dcard.deliv), instant: isInstant(dcard.badge, dcard.deliv), nowPage: ds.amazonNowPage, totalCards: ds.totalCards } : { found: false, nowPage: ds.amazonNowPage, totalCards: ds.totalCards };
      await sleep(250 + Math.random() * 250);
      const pdp = await pdpCheck(page, asin);
      await sleep(250 + Math.random() * 250);

      // classify: Now-serviceable here ⇔ an instant-minute tier shows via broad OR direct search
      const instantSomewhere = !!(inBroad && inBroad.instant) || !!direct.instant;
      perSuspect[asin] = {
        label,
        in_broad_search: inBroad ? { tier: inBroad.tier, instant: inBroad.instant, badge: inBroad.badge, deliv: inBroad.deliv, page: inBroad.page, oos: inBroad.oos } : null,
        direct_asin_search: direct,
        pdp,
        now_serviceable: instantSomewhere,
      };
      process.stderr.write(`  [${label}] ${asin}: broad=${inBroad ? inBroad.tier : 'ABSENT'} direct=${direct.found ? direct.tier : 'NOT-FOUND'} pdpMin="${pdp.minHit || ''}" pdpUnavail=${pdp.unavailable} -> now_serviceable=${instantSomewhere}\n`);
    }

    out.results.push({ pin, location: loc, amazon_now_page: nowPage, broad_jivo_total: broad.length, broad_jivo_instant: broad.filter((c) => c.instant).length, broad_asins: Object.keys(broadByAsin), suspects: perSuspect });
  }
  await browser.close().catch(() => {});
  fs.writeFileSync(OUT, JSON.stringify(out, null, 2));
  process.stderr.write('\n[done] -> ' + OUT + '\n');
})();
