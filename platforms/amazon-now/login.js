// Interactive Amazon.in OTP login for the Now/Fresh dummy account.
// Drives the sign-in flow with a phone number, pauses when Amazon prompts
// for OTP, reads the OTP from /tmp/amazon_otp_input (written by Claude when
// the user shares it in chat), submits it, then dumps the storageState
// cookie jar to platforms/amazon-now/secrets/amazon-now.storageState.json.
//
// Status is written to /tmp/amazon_otp_state at each step so the parent
// process can watch progress without hammering the browser:
//   STARTING → HOMEPAGE → ENTERING_PHONE → SWITCHING_TO_OTP →
//   WAITING_FOR_OTP → SUBMITTING_OTP → DONE
// (or BLOCKED_CAPTCHA / NO_OTP_FIELD / ERROR:<msg> on failure)
//
//   PHONE=8899011758 node login.js
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const PHONE = process.env.PHONE || '8899011758';
const OUT_DIR = path.join(__dirname, 'secrets');
const STATE_FILE = '/tmp/amazon_otp_state';
const OTP_INPUT_FILE = '/tmp/amazon_otp_input';
const DEBUG_DIR = OUT_DIR;
const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

function writeState(s) {
  fs.writeFileSync(STATE_FILE, s + '\n');
  process.stderr.write(`[state] ${s}\n`);
}

function debugDump(page, label) {
  return Promise.all([
    page.content().then((html) => fs.writeFileSync(path.join(DEBUG_DIR, `dbg.${label}.html`), html)).catch(() => {}),
    page.screenshot({ path: path.join(DEBUG_DIR, `dbg.${label}.png`), fullPage: true }).catch(() => {}),
  ]);
}

async function waitForOtp(timeoutMs = 15 * 60 * 1000) {
  const start = Date.now();
  if (fs.existsSync(OTP_INPUT_FILE)) fs.unlinkSync(OTP_INPUT_FILE);
  while (Date.now() - start < timeoutMs) {
    if (fs.existsSync(OTP_INPUT_FILE)) {
      const raw = fs.readFileSync(OTP_INPUT_FILE, 'utf8').trim();
      // Allow OTPs of 4-8 digits, ignore stray punctuation/spaces
      const otp = raw.replace(/[^0-9]/g, '');
      fs.unlinkSync(OTP_INPUT_FILE);
      if (/^\d{4,8}$/.test(otp)) return otp;
      process.stderr.write(`[otp] invalid "${raw}" -> "${otp}", still waiting\n`);
    }
    await new Promise((r) => setTimeout(r, 1500));
  }
  throw new Error('OTP timeout (15 min)');
}

(async () => {
  if (!fs.existsSync(OUT_DIR)) fs.mkdirSync(OUT_DIR, { recursive: true });
  writeState('STARTING');

  const browser = await chromium.launch({
    headless: true,
    args: [
      '--disable-blink-features=AutomationControlled',
      '--no-sandbox',
    ],
  });
  const ctx = await browser.newContext({
    userAgent: UA,
    locale: 'en-IN',
    timezoneId: 'Asia/Kolkata',
    viewport: { width: 1366, height: 900 },
    extraHTTPHeaders: { 'Accept-Language': 'en-IN,en;q=0.9' },
  });
  // mild stealth
  await ctx.addInitScript(() => {
    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
    Object.defineProperty(navigator, 'languages', { get: () => ['en-IN', 'en'] });
    Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3, 4, 5] });
  });

  const page = await ctx.newPage();

  try {
    // 1) Go straight to the sign-in endpoint.
    writeState('HOMEPAGE');
    const signinUrl =
      'https://www.amazon.in/ap/signin?openid.return_to=' +
      encodeURIComponent('https://www.amazon.in/?ref_=nav_signin') +
      '&openid.identity=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select' +
      '&openid.assoc_handle=inflex' +
      '&openid.mode=checkid_setup' +
      '&openid.ns=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0' +
      '&openid.claimed_id=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select';
    await page.goto(signinUrl, { waitUntil: 'domcontentloaded', timeout: 45000 });
    await page.waitForTimeout(2500);

    // detect a captcha / robot wall before we type anything
    const blocked = await page.evaluate(() => /enter the characters you see below|robot|automated access/i.test(document.body.innerText || ''));
    if (blocked) {
      await debugDump(page, 'blocked');
      writeState('BLOCKED_CAPTCHA');
      throw new Error('captcha on signin page — likely datacenter-IP block; need residential proxy');
    }

    // 2) Enter phone number.
    writeState('ENTERING_PHONE');
    const phoneField = await page.waitForSelector('#ap_email_login, #ap_email, input[name="email"]', { timeout: 15000 });
    await phoneField.fill(PHONE);
    await page.waitForTimeout(900);
    const contBtn = await page.$('#continue, input#continue, #continue-announce');
    if (contBtn) {
      await contBtn.click().catch(() => {});
    } else {
      await page.keyboard.press('Enter');
    }
    await page.waitForLoadState('domcontentloaded', { timeout: 30000 }).catch(() => {});
    await page.waitForTimeout(3500);

    // 3) Identify which page we landed on (password vs OTP).
    let pageType = await page.evaluate(() => {
      const body = document.body.innerText || '';
      return {
        url: location.href,
        hasPassword: !!document.getElementById('ap_password'),
        hasOtpInput: !!(document.getElementById('auth-pv-enter-code') || document.querySelector('input[name="otpCode"], input[name="code"], input[autocomplete="one-time-code"]')),
        useOtpLink: !!document.querySelector('#auth-use-OTP-link, a[href*="OTPChallenge"], a[href*="useOtp"], a[id*="otp" i]'),
        bodyHead: body.slice(0, 600).replace(/\s+/g, ' '),
      };
    });
    process.stderr.write('[pageType] ' + JSON.stringify(pageType) + '\n');
    await debugDump(page, 'after-phone');

    // 4) If we got the password page, try clicking "Use OTP" to switch flows.
    if (pageType.hasPassword && !pageType.hasOtpInput) {
      writeState('SWITCHING_TO_OTP');
      const switched = await page.evaluate(() => {
        const candidates = [...document.querySelectorAll('a, button, span')].filter((el) => /one[- ]?time password|use otp|sign in with otp|otp/i.test((el.innerText || '').trim()));
        if (candidates[0]) { candidates[0].click(); return true; }
        return false;
      });
      if (switched) {
        await page.waitForLoadState('domcontentloaded', { timeout: 20000 }).catch(() => {});
        await page.waitForTimeout(2500);
      }
      pageType = await page.evaluate(() => ({
        url: location.href,
        hasPassword: !!document.getElementById('ap_password'),
        hasOtpInput: !!(document.getElementById('auth-pv-enter-code') || document.querySelector('input[name="otpCode"], input[name="code"], input[autocomplete="one-time-code"]')),
      }));
      process.stderr.write('[after switch] ' + JSON.stringify(pageType) + '\n');
    }

    // 5) Wait for the OTP input field to render.
    writeState('WAITING_FOR_OTP_FIELD');
    const otpSel = 'input[name="otpCode"], input[name="code"], #auth-pv-enter-code, input[autocomplete="one-time-code"]';
    const otpField = await page.waitForSelector(otpSel, { timeout: 20000 }).catch(() => null);
    if (!otpField) {
      await debugDump(page, 'no-otp');
      writeState('NO_OTP_FIELD');
      throw new Error('OTP input field never appeared — see secrets/dbg.no-otp.{html,png}');
    }

    // 6) Pause for the user's OTP via the watch file.
    writeState('WAITING_FOR_OTP');
    process.stderr.write(`[otp] OTP sent to ${PHONE}. Write 6-digit code to ${OTP_INPUT_FILE} (poll every 1.5s).\n`);
    const otp = await waitForOtp();
    writeState('SUBMITTING_OTP');
    await otpField.fill(otp);
    await page.waitForTimeout(700);
    const submitBtn = await page.$('#auth-signin-button, #signInSubmit, input[type="submit"]');
    if (submitBtn) await submitBtn.click().catch(() => {});
    else await page.keyboard.press('Enter');
    await page.waitForLoadState('domcontentloaded', { timeout: 30000 }).catch(() => {});
    await page.waitForTimeout(4500);

    // 7) Verify we ended up logged in (home page with greeting).
    const loggedIn = await page.evaluate(() => {
      const greeting = document.querySelector('#nav-link-accountList-nav-line-1, #nav-link-accountList .nav-line-1');
      return {
        url: location.href,
        greeting: greeting ? (greeting.innerText || '').trim() : '',
        signinPage: /ap\/signin|errors\/validateCaptcha/i.test(location.href),
        wrongOtp: /enter the correct (code|otp)/i.test(document.body.innerText || ''),
      };
    });
    process.stderr.write('[verify] ' + JSON.stringify(loggedIn) + '\n');
    await debugDump(page, 'after-otp');

    if (loggedIn.signinPage || loggedIn.wrongOtp) {
      writeState('OTP_WRONG_OR_REJECTED');
      throw new Error('still on signin / wrong OTP: ' + JSON.stringify(loggedIn));
    }

    // 8) Save the cookie jar.
    const out = path.join(OUT_DIR, 'amazon-now.storageState.json');
    await ctx.storageState({ path: out });
    fs.writeFileSync(path.join(OUT_DIR, 'login.meta.json'), JSON.stringify({
      phone: PHONE,
      capturedAt: new Date().toISOString(),
      url: loggedIn.url,
      greeting: loggedIn.greeting,
    }, null, 2));
    writeState('DONE');
    process.stderr.write('[done] storageState -> ' + out + '\n');
  } catch (e) {
    writeState('ERROR:' + e.message.slice(0, 140));
    process.stderr.write('[fatal] ' + e.stack + '\n');
    process.exitCode = 1;
  } finally {
    await browser.close().catch(() => {});
  }
})();
