// RECON #2 — reverse the GLOW location-set mechanism.
// Loads homepage (interstitial pass), then drives the GLOW "deliver to" widget
// to enter a pincode, capturing the exact HTTP request(s) fired to set location
// (portal-migration / address-change / glow) and the cookies they set.
//
//   cd /opt/ecom-intel/platforms/amazon-now && node recon/glow.js 110001
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const OUT = __dirname;

async function passInterstitial(page) {
  await page.goto('https://www.amazon.in/', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await page.waitForTimeout(2000);
  try { await page.getByRole('button', { name: /continue shopping/i }).click({ timeout: 7000 }); } catch (e) {}
  await page.waitForTimeout(2500);
}

(async () => {
  const pin = process.argv[2] || '110001';
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 } });
  await ctx.route('**/*', (route) => {
    const t = route.request().resourceType();
    if (['image', 'font', 'media'].includes(t)) return route.abort();
    return route.continue();
  });
  const page = await ctx.newPage();
  const glowReqs = [];
  page.on('request', (req) => {
    const u = req.url();
    if (/glow|address-change|portal-migration|changeLocation|GLUXChangePostalCodeAction|gp\/delivery|csm.*location/i.test(u)) {
      glowReqs.push({ url: u, method: req.method(), post: req.postData() || '', headers: req.headers() });
    }
  });
  page.on('response', async (resp) => {
    const u = resp.url();
    if (/glow|address-change|portal-migration|changeLocation|GLUXChangePostalCodeAction|gp\/delivery/i.test(u)) {
      const sc = resp.headers()['set-cookie'] || '';
      let body = '';
      try { body = (await resp.text()).slice(0, 1200); } catch (e) {}
      const i = glowReqs.findIndex((r) => r.url === u && r.respStatus === undefined);
      const rec = glowReqs.find((r) => r.url === u && !r.respStatus) || {};
      rec.respStatus = resp.status();
      rec.setCookie = sc;
      rec.respBody = body.replace(/\s+/g, ' ');
    }
  });

  await passInterstitial(page);

  const before = await ctx.cookies();
  const glowBefore = await page.evaluate(() => {
    const el = document.getElementById('glow-ingress-line2');
    return el ? el.innerText.replace(/\s+/g, ' ').trim() : '';
  });
  console.error('GLOW before:', JSON.stringify(glowBefore));

  // open the location popover
  try {
    await page.click('#nav-global-location-popover-link', { timeout: 8000 });
    await page.waitForTimeout(2000);
    // pincode input id in the GLOW popover
    const input = await page.$('#GLUXZipUpdateInput, input[autocomplete="postal-code"], #GLUXZipUpdate input');
    if (input) {
      await input.fill(pin);
      await page.waitForTimeout(500);
      // apply button
      const applied = await page.click('#GLUXZipUpdate input[aria-labelledby="GLUXZipUpdate-announce"], #GLUXZipUpdate-announce, span#GLUXZipUpdate input', { timeout: 5000 }).then(() => true).catch(() => false);
      if (!applied) {
        await page.keyboard.press('Enter').catch(() => {});
      }
      await page.waitForTimeout(3000);
      // a "Done" / continue button sometimes appears
      try { await page.click('button[name="glowDoneButton"], .a-popover-footer input[type="submit"], #GLUXConfirmClose', { timeout: 4000 }); } catch (e) {}
      await page.waitForTimeout(2500);
    } else {
      console.error('NO pincode input found in popover');
    }
  } catch (e) {
    console.error('popover/interaction err:', e.message);
  }

  await page.reload({ waitUntil: 'domcontentloaded' }).catch(() => {});
  await page.waitForTimeout(2000);
  const glowAfter = await page.evaluate(() => {
    const el = document.getElementById('glow-ingress-line2');
    return el ? el.innerText.replace(/\s+/g, ' ').trim() : '';
  });
  console.error('GLOW after:', JSON.stringify(glowAfter));

  const after = await ctx.cookies();
  const diff = after.filter((c) => {
    const b = before.find((x) => x.name === c.name);
    return !b || b.value !== c.value;
  }).map((c) => ({ name: c.name, value: c.value.slice(0, 60), domain: c.domain }));

  fs.writeFileSync(path.join(OUT, `glow.reqs.${pin}.json`), JSON.stringify(glowReqs, null, 2));
  fs.writeFileSync(path.join(OUT, `glow.cookies.${pin}.json`), JSON.stringify(after, null, 2));
  console.error('GLOW requests captured:', glowReqs.length);
  glowReqs.forEach((r) => console.error('  ', r.method, r.respStatus || '?', r.url.slice(0, 110), '| post:', (r.post || '').slice(0, 120)));
  console.error('COOKIE DIFF after location change:', JSON.stringify(diff));

  await browser.close();
})();
