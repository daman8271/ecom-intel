// RECON — find the no-login Amazon FRESH entry point.
// Tests search-index aliases + landing pages + inspects the top-nav flyout
// for the real "Amazon Fresh" href. Modest, spaced requests (2-4s).
const { chromium } = require('playwright');

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

async function passInterstitial(page) {
  await page.goto('https://www.amazon.in/', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await page.waitForTimeout(2000);
  try { await page.getByRole('button', { name: /continue shopping/i }).click({ timeout: 7000 }); } catch (e) {}
  await page.waitForTimeout(2500);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 } });
  await ctx.route('**/*', (route) => {
    const t = route.request().resourceType();
    if (['image', 'font', 'media'].includes(t)) return route.abort();
    return route.continue();
  });
  const page = await ctx.newPage();
  await passInterstitial(page);

  // 1) Inspect the homepage nav for any Fresh/Alm hrefs.
  const navLinks = await page.evaluate(() => {
    const out = [];
    document.querySelectorAll('a[href]').forEach((a) => {
      const h = a.getAttribute('href') || '';
      const txt = (a.innerText || a.textContent || '').replace(/\s+/g, ' ').trim();
      if (/fresh|amazonfresh|\/alm|almstore|freshstore|grocery|pantry/i.test(h + ' ' + txt)) {
        out.push({ txt: txt.slice(0, 40), href: h.slice(0, 160) });
      }
    });
    // dedupe
    const seen = new Set();
    return out.filter((o) => { const k = o.txt + o.href; if (seen.has(k)) return false; seen.add(k); return true; });
  });
  console.log('=== NAV LINKS matching fresh/alm/grocery ===');
  navLinks.forEach((l) => console.log(`  "${l.txt}" -> ${l.href}`));
  await sleep(2500);

  // 2) Probe candidate entry points.
  const probes = [
    'https://www.amazon.in/s?k=jivo&i=freshstore',
    'https://www.amazon.in/s?k=jivo&i=fresh',
    'https://www.amazon.in/s?k=jivo&i=amazonfresh',
    'https://www.amazon.in/s?k=jivo&i=grocery',
    'https://www.amazon.in/s?k=jivo&i=alm',
    'https://www.amazon.in/s?k=jivo&i=nowstore', // baseline control (known-good Now)
    'https://www.amazon.in/fresh',
    'https://www.amazon.in/alm',
    'https://www.amazon.in/amazonfresh',
  ];

  for (const u of probes) {
    try {
      const r = await page.goto(u, { waitUntil: 'domcontentloaded', timeout: 30000 });
      await page.waitForTimeout(1800);
      const d = await page.evaluate(() => {
        const T = (el) => (el ? (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim() : '');
        const cards = [...document.querySelectorAll('[data-component-type="s-search-result"][data-asin], [data-asin]:not([data-asin=""])')];
        const body = (document.body && document.body.innerText) || '';
        return {
          finalUrl: location.href,
          title: document.title,
          loginWall: /sign-?in|ap\/signin/i.test(location.href) || !!document.getElementById('ap_password'),
          captcha: /enter the characters you see below|type the characters|not a robot|automated access/i.test(body),
          continueShop: /continue shopping/i.test(body) && !document.querySelector('[data-component-type="s-search-result"]'),
          glow: T(document.getElementById('glow-ingress-line2')),
          cardCount: cards.length,
          // index dropdown current value tells us if alias was accepted/coerced
          searchIndexLabel: T(document.querySelector('#searchDropdownBox option[selected], #nav-search-label-id, #searchDropdownBox')),
          sampleAsins: cards.slice(0, 6).map((c) => ({ asin: c.getAttribute('data-asin'), title: T(c.querySelector('h2, .a-size-base-plus, .a-size-medium')).slice(0, 45) })),
          bodyHead: body.replace(/\s+/g, ' ').slice(0, 220),
        };
      });
      console.log(`\nPROBE ${u}`);
      console.log(`  http=${r ? r.status() : '?'} final=${d.finalUrl}`);
      console.log(`  title="${d.title}" cards=${d.cardCount} login=${d.loginWall} captcha=${d.captcha} continueShop=${d.continueShop}`);
      console.log(`  glow="${d.glow}" indexLabel="${d.searchIndexLabel}"`);
      if (d.cardCount) d.sampleAsins.forEach((s) => console.log(`     ${s.asin} "${s.title}"`));
      else console.log(`  bodyHead="${d.bodyHead}"`);
    } catch (e) {
      console.log(`\nPROBE ${u}\n  ERR ${e.message}`);
    }
    await sleep(3000);
  }

  await browser.close();
})();
