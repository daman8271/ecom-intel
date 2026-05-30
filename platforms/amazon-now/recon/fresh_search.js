// RECON #2 — the /fresh landing 200s and lands on /alm/storefront?almBrandId=ctnow.
// Now characterize the Fresh SEARCH surface. Try:
//   - the search box on the /fresh storefront (submit "jivo")
//   - direct /s?k=jivo with almBrandId / fresh ref params
//   - the i=nowstore alias (known-good baseline) once 503s clear
// Long warm-up + big gaps to dodge the soft-block we hit earlier.
const { chromium } = require('playwright');

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function passInterstitial(page) {
  await page.goto('https://www.amazon.in/', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await page.waitForTimeout(2000);
  try { await page.getByRole('button', { name: /continue shopping/i }).click({ timeout: 7000 }); } catch (e) {}
  await page.waitForTimeout(2500);
}

async function describe(page, label) {
  const d = await page.evaluate(() => {
    const T = (el) => (el ? (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim() : '');
    const cards = [...document.querySelectorAll('[data-component-type="s-search-result"][data-asin], [data-asin]:not([data-asin=""])')];
    const body = (document.body && document.body.innerText) || '';
    return {
      finalUrl: location.href,
      title: document.title,
      http503: /503 - Service Unavailable|rush hour and traffic/i.test(body),
      captcha: /enter the characters you see below|type the characters|not a robot/i.test(body),
      glow: T(document.getElementById('glow-ingress-line2')) || T(document.getElementById('nav-global-location-popover-link')),
      indexLabel: T(document.querySelector('#nav-search-label-id')),
      cardCount: cards.length,
      cards: cards.slice(0, 10).map((c) => ({
        asin: c.getAttribute('data-asin'),
        title: T(c.querySelector('h2, .a-size-base-plus, .a-size-medium')).slice(0, 50),
        price: T(c.querySelector('.a-price .a-offscreen')),
        promise: T(c.querySelector('[class*="delivery" i]')).slice(0, 50),
      })),
    };
  });
  console.log(`\n[${label}] http503=${d.http503} captcha=${d.captcha} cards=${d.cardCount}`);
  console.log(`  final=${d.finalUrl}`);
  console.log(`  title="${d.title}" glow="${d.glow}" indexLabel="${d.indexLabel}"`);
  d.cards.forEach((c) => console.log(`    ${c.asin} ₹${c.price || '-'} "${c.title}" [${c.promise}]`));
  return d;
}

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

  // A) Load the Fresh storefront landing.
  try {
    await page.goto('https://www.amazon.in/fresh', { waitUntil: 'domcontentloaded', timeout: 35000 });
    await page.waitForTimeout(2500);
    await describe(page, 'A: /fresh landing');
    // dump the search form action + any storefront search links
    const forms = await page.evaluate(() => {
      const out = { searchAlias: null, formAction: null, freshLinks: [] };
      const sel = document.querySelector('#searchDropdownBox, select[name="url"]');
      if (sel) out.searchAlias = sel.value;
      const f = document.querySelector('form[role="search"], #nav-search-bar-form');
      if (f) out.formAction = f.getAttribute('action');
      document.querySelectorAll('a[href*="almBrandId"], a[href*="freshstore"], a[href*="/s?"]').forEach((a) => {
        out.freshLinks.push((a.getAttribute('href') || '').slice(0, 140));
      });
      out.freshLinks = [...new Set(out.freshLinks)].slice(0, 12);
      return out;
    });
    console.log('  searchAlias=' + forms.searchAlias + ' formAction=' + forms.formAction);
    forms.freshLinks.forEach((l) => console.log('   link: ' + l));
  } catch (e) { console.log('A ERR ' + e.message); }
  await sleep(3500);

  // B) Type jivo into the storefront search box and submit (most authentic).
  try {
    const box = await page.$('#twotabsearchtextbox, input[name="k"]');
    if (box) {
      await box.fill('jivo');
      await page.keyboard.press('Enter');
      await page.waitForLoadState('domcontentloaded', { timeout: 30000 });
      await page.waitForTimeout(2500);
      await describe(page, 'B: storefront search "jivo"');
    } else { console.log('B: no search box found'); }
  } catch (e) { console.log('B ERR ' + e.message); }
  await sleep(3500);

  // C) Direct URL variants carrying the ctnow / fresh context.
  const probes = [
    'https://www.amazon.in/s?k=jivo&i=nowstore',
    'https://www.amazon.in/s?k=jivo&almBrandId=ctnow',
    'https://www.amazon.in/s?k=jivo&i=nowstore&almBrandId=ctnow',
  ];
  for (const u of probes) {
    try {
      await page.goto(u, { waitUntil: 'domcontentloaded', timeout: 30000 });
      await page.waitForTimeout(2200);
      await describe(page, 'C: ' + u);
    } catch (e) { console.log('C ERR ' + u + ' ' + e.message); }
    await sleep(3500);
  }

  await browser.close();
})();
