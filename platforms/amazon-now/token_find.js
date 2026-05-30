const { chromium } = require('playwright');
const path = require('path');
const STATE = path.join(__dirname, 'secrets/amazon-now.storageState.json');
const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  let b; try { b = await chromium.launch({ headless: true, channel: 'chrome', args: ['--no-sandbox', '--headless=new'] }); } catch (_) { b = await chromium.launch({ headless: true, args: ['--no-sandbox', '--headless=new'] }); }
  const ctx = await b.newContext({ userAgent: UA, locale: 'en-IN', timezoneId: 'Asia/Kolkata', viewport: { width: 1366, height: 900 }, storageState: STATE });
  const page = await ctx.newPage();
  await page.goto('https://www.amazon.in/?ref_=nav_signin', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await sleep(1500);

  const out = await page.evaluate(async () => {
    const res = { homepage: [], addrSel: [], addrSelToken: '' };
    const html = document.documentElement.outerHTML;
    const patterns = [
      /CSRF_TOKEN['"]?\s*[:=]\s*['"]([^'"]{16,})['"]/g,
      /anti-csrftoken-a2z['"]?\s*[:=]\s*['"]([^'"]{16,})['"]/g,
      /"csrfToken"\s*:\s*"([^"]{16,})"/g,
      /name="anti-csrftoken-a2z"\s+value="([^"]+)"/g,
    ];
    for (const p of patterns) { let m; while ((m = p.exec(html))) res.homepage.push(m[1].slice(0, 30)); }
    // try the address-selections fragment and look for a token in ITS body
    try {
      const r = await fetch('/portal-migration/hz/glow/get-rendered-address-selections?deviceType=desktop&pageType=Gateway&storeContext=NoStoreName&actionSource=desktop');
      const t = await r.text();
      res.addrSelStatus = r.status; res.addrSelLen = t.length;
      for (const p of [/CSRF_TOKEN['"]?\s*[:=]\s*['"]([^'"]{16,})['"]/g, /anti-csrftoken-a2z["']?\s*[:=]\s*["']([^"']{16,})["']/g, /name="anti-csrftoken-a2z"\s+value="([^"]+)"/g]) { let m; while ((m = p.exec(t))) res.addrSel.push(m[1].slice(0, 30)); }
      // raw snippet around any 'csrf' mention
      const i = t.toLowerCase().indexOf('csrf');
      res.addrSelSnippet = i >= 0 ? t.slice(i - 20, i + 90).replace(/\s+/g, ' ') : '(no csrf substring)';
    } catch (e) { res.addrSelErr = e.message; }
    return res;
  });
  console.log(JSON.stringify(out, null, 1));
  await b.close();
})();
