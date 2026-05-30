// Amazon.in Now/Fresh login v2 — fingerprint-hardened, warm-up + AAMation captcha handoff.
//
// Strategy (see PLAN.md): make the AWS WAF "AAMation" captcha RARE via real-Chrome
// new-headless rendering, a coherent Linux fingerprint, and a warm-up browse that banks
// an aws-waf-token; SOLVE it the few times it still fires via a vision handoff to the
// main orchestration loop over watch files; then reuse the existing OTP watch-file flow.
//
// Phone-OTP flow status -> /tmp/amazon_otp_state (read OTP from /tmp/amazon_otp_input):
//   STARTING -> WARMUP -> HOMEPAGE -> ENTERING_PHONE ->
//   [BLOCKED_CAPTCHA_SOLVING -> CAPTCHA_PASSED] -> SWITCHING_TO_OTP ->
//   WAITING_FOR_OTP_FIELD -> WAITING_FOR_OTP -> SUBMITTING_OTP -> DONE
//   (or BLOCKED_CAPTCHA / NO_OTP_FIELD / ERROR:<msg> on failure)
//
// AAMation captcha status -> /tmp/aamation_state (read tile indices from /tmp/aamation_click):
//   CAPTCHA_DETECTED -> AWAIT_VISION:<round> -> CLICKING:<round> -> CONFIRMED:<round> ->
//   (CAPTCHA_SOLVED | CAPTCHA_BAILED:<reason> | CAPTCHA_DOM_UNEXPECTED)
//
// Usage:
//   PHONE=8899011758 node login_v2.js                 # phone-OTP primary flow
//   node login_v2.js --warmup                          # guest gardener: bake + save guest.storageState.json
//   MODE=password EMAIL=x@y.com PASSWORD=... node login_v2.js   # fallback 1: email+password (no phone)
//   HEADED=1 xvfb-run -a --server-args='-screen 0 1366x900x24' node login_v2.js  # strongest fingerprint
//
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const PHONE = process.env.PHONE || '8899011758';
const MODE = (process.env.MODE || 'phone').toLowerCase(); // 'phone' | 'password'
const EMAIL = process.env.EMAIL || '';
const PASSWORD = process.env.PASSWORD || '';
const HEADED = process.env.HEADED === '1' || process.argv.includes('--headed');
const WARMUP_ONLY = process.argv.includes('--warmup');

const OUT_DIR = path.join(__dirname, 'secrets');
const DEBUG_DIR = OUT_DIR;
const STATE_FILE = '/tmp/amazon_otp_state';
const OTP_INPUT_FILE = '/tmp/amazon_otp_input';
const GUEST_STATE = path.join(OUT_DIR, 'guest.storageState.json');
const SESSION_OUT = path.join(OUT_DIR, 'amazon-now.storageState.json');

// A current Linux Chrome UA matching this box (kills the Mac-UA-on-Linux tell from login.js).
// If you install google-chrome-stable, the launched binary's real version still wins for TLS/GPU;
// keep this major version close to the installed Chrome.
// Match the installed google-chrome-stable major version (148) so the JS-visible UA
// agrees with the real browser's TLS + sec-ch-ua client hints (a mismatch is a WAF tell).
const UA = process.env.UA ||
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';

// AAMation captcha watch-file protocol (parallel to the OTP watcher).
const CAP_STATE = '/tmp/aamation_state';
const CAP_CLICK = '/tmp/aamation_click';
const CAP_RESULT = '/tmp/aamation_result';
const CAP_VERIFY = '/tmp/aamation_verify';   // pre-Confirm gate: vision loop writes "<round>|GO" or "<round>|BAIL"
const VERIFY_PAUSE = process.env.VERIFY_PAUSE === '1'; // diagnostic: pause for visual check before Confirm
const capPng = (r) => `/tmp/aamation_round_${r}.png`;
const capGrid = (r) => `/tmp/aamation_grid_${r}.png`;
const capMeta = (r) => `/tmp/aamation_meta_${r}.json`;
const capPre = (r) => `/tmp/aamation_preconfirm_${r}.png`;
const MAX_ROUNDS = 6;                  // Required is 3 grids; allow spare re-serves (pre-OTP, no rate cost).
const VISION_TIMEOUT_MS = 5 * 60 * 1000;

// ---------------------------------------------------------------------------
// Small helpers (match login.js ergonomics)
// ---------------------------------------------------------------------------
function writeState(s) {
  fs.writeFileSync(STATE_FILE, s + '\n');
  process.stderr.write(`[state] ${s}\n`);
}
function writeCap(s) {
  fs.writeFileSync(CAP_STATE, s + '\n');
  process.stderr.write(`[cap] ${s}\n`);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const jitter = (a, b) => a + Math.floor(Math.random() * (b - a));

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
      const otp = raw.replace(/[^0-9]/g, '');
      fs.unlinkSync(OTP_INPUT_FILE);
      if (/^\d{4,8}$/.test(otp)) return otp;
      process.stderr.write(`[otp] invalid "${raw}" -> "${otp}", still waiting\n`);
    }
    await sleep(1500);
  }
  throw new Error('OTP timeout (15 min)');
}

// Human-ish typing into a filled-blank field (per-keystroke delay beats fill()).
async function humanType(page, selector, text) {
  const el = await page.waitForSelector(selector, { timeout: 15000 });
  await el.click({ delay: jitter(40, 120) }).catch(() => {});
  await el.fill('');
  for (const ch of text) {
    await page.keyboard.type(ch, { delay: jitter(70, 180) });
  }
  return el;
}

// Move the mouse along a short human-ish path before a click, then click an element.
async function humanClick(page, el) {
  try {
    const box = await el.boundingBox();
    if (box) {
      const tx = box.x + box.width / 2 + jitter(-6, 6);
      const ty = box.y + box.height / 2 + jitter(-4, 4);
      const steps = 3 + Math.floor(Math.random() * 4);
      await page.mouse.move(tx - jitter(40, 120), ty - jitter(30, 80));
      await page.mouse.move(tx, ty, { steps });
      await sleep(jitter(80, 240));
    }
  } catch (_) { /* best-effort */ }
  await el.click({ delay: jitter(40, 120) }).catch(() => {});
}

// ---------------------------------------------------------------------------
// AAMation captcha helpers (verified selectors from dbg.after-phone.html)
//   #captcha-container canvas              -> the painted 3x3 grid (324x324 intrinsic)
//   #captcha-container canvas button (x9)  -> transparent overlays, DOM order = tile 0..8 (row-major)
//   #captcha-container em                  -> the target word ("the scissors")
//   "Solved: N Required: M"                -> counter (counts GRIDS solved, not tiles)
//   #amzn-btn-verify-internal              -> Confirm (fires the WAF grading XHR)
//   #amzn-btn-refresh-internal             -> new puzzle
// ---------------------------------------------------------------------------
async function isAamationCaptcha(page) {
  return page.evaluate(() => /\/ap\/cvf/i.test(location.href) && !!document.querySelector('#captcha-container canvas'));
}

async function readCaptchaInfo(page) {
  return page.evaluate(() => {
    const form = document.querySelector('#captcha-container form');
    const txt = form ? form.innerText : '';
    const cm = txt.match(/Solved:\s*(\d+)\s*Required:\s*(\d+)/i);
    const em = document.querySelector('#captcha-container em');
    const canvas = document.querySelector('#captcha-container canvas');
    const r = canvas ? canvas.getBoundingClientRect() : null;
    return {
      solved: cm ? +cm[1] : null,
      required: cm ? +cm[2] : null,
      word: em ? (em.innerText || '').trim() : '',
      geom: r ? { left: r.left, top: r.top, width: r.width, height: r.height, dpr: window.devicePixelRatio || 1 } : null,
      nButtons: document.querySelectorAll('#captcha-container canvas button').length,
    };
  });
}

// Wait for the vision loop to write /tmp/aamation_click for THIS round.
// Returns {kind:'INDICES', idx:[...], word} | {kind:'NONE'|'REFRESH'|'BAIL'} | {kind:'TIMEOUT'}.
async function waitForCaptchaClick(round) {
  const start = Date.now();
  if (fs.existsSync(CAP_CLICK)) fs.unlinkSync(CAP_CLICK); // drop any stale answer
  while (Date.now() - start < VISION_TIMEOUT_MS) {
    if (fs.existsSync(CAP_CLICK)) {
      const raw = fs.readFileSync(CAP_CLICK, 'utf8').trim();
      fs.unlinkSync(CAP_CLICK);
      const parts = raw.split('|'); // round|word|csv
      if (parts.length >= 3 && (+parts[0]) === round) {
        const payload = parts.slice(2).join('|').trim();
        if (/^(NONE|REFRESH|BAIL)$/i.test(payload)) return { kind: payload.toUpperCase() };
        const idx = [...new Set(
          payload.split(',').map((s) => +s.trim()).filter((n) => Number.isInteger(n) && n >= 0 && n <= 8),
        )].sort((a, b) => a - b);
        if (idx.length) return { kind: 'INDICES', idx, word: parts[1] };
      }
      process.stderr.write(`[cap] stale/invalid click "${raw}" (round ${round})\n`);
    }
    await sleep(1000);
  }
  return { kind: 'TIMEOUT' };
}

// Screenshot the modal + grid, compute tile centers, write meta, then signal AWAIT_VISION (last).
async function emitRound(page, round, info) {
  const modal = await page.$('#captcha-container .amzn-captcha-modal');
  if (modal) {
    await modal.scrollIntoViewIfNeeded().catch(() => {});
    await sleep(600); // let the canvas repaint settle before the screenshot
    await modal.screenshot({ path: capPng(round) }).catch(() => {});
  }
  if (info.geom) {
    const g = info.geom;
    const cw = g.width / 3;
    const ch = g.height / 3;
    // Tight grid-only crop in CSS px (Playwright handles DPR internally).
    await page.screenshot({ path: capGrid(round), clip: { x: g.left, y: g.top, width: g.width, height: g.height } }).catch(() => {});
    const tileCenters = [...Array(9)].map((_, i) => {
      const c = i % 3;
      const rr = (i / 3) | 0;
      return [g.left + cw * (c + 0.5), g.top + ch * (rr + 0.5)];
    });
    fs.writeFileSync(capMeta(round), JSON.stringify({
      round,
      targetWordGuess: info.word,
      required: info.required,
      solvedSoFar: info.solved,
      gridFile: capGrid(round),
      modalFile: capPng(round),
      tileCenters,
    }, null, 2));
  }
  writeCap(`AWAIT_VISION:${round}`); // written LAST so the loop only acts once everything is flushed
}

const TILE_SEL = '#captcha-container canvas button';

// Screenshot just tile i's cell of the canvas. Playwright screenshots are immune to canvas
// cross-origin taint (canvas.toDataURL() would throw SecurityError). Localizing to the cell
// lets us verify the SELECTION marker painted on the RIGHT tile, not just any focus-ring
// change elsewhere on the grid.
async function tileCellShot(page, i) {
  const info = await readCaptchaInfo(page);
  if (!info.geom) return null;
  const g = info.geom, cw = g.width / 3, ch = g.height / 3;
  const c = i % 3, rr = (i / 3) | 0;
  try {
    return await page.screenshot({ clip: { x: g.left + c * cw, y: g.top + rr * ch, width: cw, height: ch }, timeout: 4000 });
  } catch (_) { return null; }
}

// Toggle-select tile i. EMPIRICAL FINDINGS that shaped this:
//   - The 9 grid buttons are canvas-FALLBACK nodes (0x0, not rendered) -> elementHandle mouse
//     click times out, and a raw canvas-pixel mouse click does NOT register with the widget.
//   - A synthetic DOM .click() only FOCUSED the tile (drew the focus ring -> a full-canvas diff
//     falsely read as "registered") but never SELECTED it -> every Confirm submitted empty.
// The widget toggles selection on a TRUSTED keyboard activation of the focused <button>. So we
// DOM-focus button i, then press Space/Enter via real (trusted) keyboard input, and verify by
// diffing ONLY tile i's cell so we know the selection actually painted on the right tile.
async function selectTile(page, i) {
  const focusIt = () => page.evaluate(([s, idx]) => { const b = document.querySelectorAll(s)[idx]; if (b) { b.focus(); return document.activeElement === b; } return false; }, [TILE_SEL, i]);
  await focusIt();
  await sleep(180);
  const before = await tileCellShot(page, i); // taken AFTER focus -> isolates SELECTION from the focus ring
  const methods = [
    { name: 'space', run: async () => { await page.keyboard.press('Space'); } },
    { name: 'enter', run: async () => { await page.keyboard.press('Enter'); } },
    { name: 'dom-click', run: async () => { await page.evaluate(([s, idx]) => { const b = document.querySelectorAll(s)[idx]; if (b) b.click(); }, [TILE_SEL, i]); } },
  ];
  for (const m of methods) {
    await m.run();
    await sleep(jitter(300, 520));
    const after = await tileCellShot(page, i);
    if (before && after && !before.equals(after)) {
      process.stderr.write(`[cap] tile ${i} selected via ${m.name}\n`);
      return true;
    }
    await focusIt(); // re-assert focus on tile i before trying the next method
  }
  process.stderr.write(`[cap] tile ${i} did NOT register (cell unchanged via space/enter/click)\n`);
  return false;
}

// Diagnostic gate: wait for the vision loop to approve the selection before Confirm.
async function waitForVerify(round) {
  const start = Date.now();
  if (fs.existsSync(CAP_VERIFY)) fs.unlinkSync(CAP_VERIFY);
  while (Date.now() - start < VISION_TIMEOUT_MS) {
    if (fs.existsSync(CAP_VERIFY)) {
      const raw = fs.readFileSync(CAP_VERIFY, 'utf8').trim();
      fs.unlinkSync(CAP_VERIFY);
      const p = raw.split('|');
      if ((+p[0]) === round) return /BAIL/i.test(p[1] || '') ? 'BAIL' : 'GO';
    }
    await sleep(1000);
  }
  return 'TIMEOUT';
}

// Select the chosen tiles (self-verifying), then press Confirm.
async function answerRound(page, ans, round) {
  writeCap(`CLICKING:${round}`);
  const buttons = await page.$$(TILE_SEL);
  if (buttons.length !== 9) { writeCap('CAPTCHA_DOM_UNEXPECTED'); throw new Error('grid buttons != 9'); }

  // NONE (no matching tile) / REFRESH (unreadable): re-roll instead of confirming.
  if (ans.kind === 'REFRESH' || ans.kind === 'NONE') {
    const rb = await page.$('#amzn-btn-refresh-internal');
    if (rb) await humanClick(page, rb);
    await sleep(jitter(700, 1100));
    return { refreshed: true };
  }

  let registered = 0;
  for (const i of ans.idx) {
    if (await selectTile(page, i)) registered++;
    await sleep(jitter(150, 350)); // small human-ish gap between taps
  }
  process.stderr.write(`[cap] round ${round}: ${registered}/${ans.idx.length} tiles registered\n`);
  // Record how many landed so the vision loop can see if clicks are still failing.
  fs.writeFileSync(CAP_RESULT, `REGISTERED:${registered}/${ans.idx.length}\n`);

  // Diagnostic: screenshot the modal AFTER selecting (so we can SEE whether tiles show
  // selection markers) and optionally pause for visual approval before spending Confirm.
  if (VERIFY_PAUSE) {
    const m = await page.$('#captcha-container .amzn-captcha-modal');
    if (m) { await sleep(400); await m.screenshot({ path: capPre(round) }).catch(() => {}); }
    writeCap(`AWAIT_VERIFY:${round}`);
    const v = await waitForVerify(round);
    if (v !== 'GO') { writeCap(`CAPTCHA_BAILED:verify_${v.toLowerCase()}`); throw new Error('verify gate: ' + v); }
  }

  const confirm = await page.$('#amzn-btn-verify-internal');
  if (!confirm) { writeCap('CAPTCHA_DOM_UNEXPECTED'); throw new Error('no confirm btn'); }
  writeCap(`CONFIRMED:${round}`);
  await humanClick(page, confirm); // Confirm is a normally-rendered button — one real click
  await sleep(1800); // allow counter increment + new puzzle render, OR navigation off /ap/cvf
  return { refreshed: false };
}

// The full multi-round captcha loop. Returns when solved; throws on bail (caller exits non-zero).
async function solveAamation(page) {
  writeCap('CAPTCHA_DETECTED');
  writeState('BLOCKED_CAPTCHA_SOLVING');
  let round = 0;
  let sameWord = null;
  let sameCount = 0;

  while (true) {
    round++;
    if (round > MAX_ROUNDS) { writeCap('CAPTCHA_BAILED:max_rounds'); throw new Error('captcha rounds exhausted'); }

    // (a) grid gone? then we're already through.
    if (!(await page.$('#captcha-container canvas'))) { writeCap('CAPTCHA_SOLVED'); break; }

    // (b) read counter + target word + geom; sanity-check the DOM.
    const info = await readCaptchaInfo(page);
    if (info.nButtons !== 9 || !info.geom) { writeCap('CAPTCHA_DOM_UNEXPECTED'); throw new Error('captcha DOM changed'); }

    // (c) guard against an unsolvable object being re-served forever.
    if (info.word && info.word === sameWord) {
      if (++sameCount > 2) { writeCap('CAPTCHA_BAILED:unsolvable'); throw new Error('same grid re-served'); }
    } else {
      sameWord = info.word;
      sameCount = 0;
    }

    await debugDump(page, `cap-round-${round}`);

    // (d) write artifacts + signal vision, then wait for the loop's answer.
    await emitRound(page, round, info);
    const ans = await waitForCaptchaClick(round);
    if (ans.kind === 'TIMEOUT') { writeCap('CAPTCHA_BAILED:vision_timeout'); throw new Error('vision timeout'); }
    if (ans.kind === 'BAIL') { writeCap('CAPTCHA_BAILED:loop_requested'); throw new Error('loop bailed'); }

    // (e) click + confirm (or refresh on NONE/REFRESH).
    const res = await answerRound(page, ans, round);
    if (res.refreshed) {
      fs.writeFileSync(CAP_RESULT, 'NEW_ROUND:refresh\n');
      continue; // a brand-new puzzle is up; solve it next round
    }

    // (f) post-Confirm assessment.
    const done = await page.evaluate(() => !document.querySelector('#captcha-container canvas') || !/\/ap\/cvf/i.test(location.href));
    const otpVisible = await page.$('input[name="otpCode"], input[name="code"], #auth-pv-enter-code, input[autocomplete="one-time-code"], #ap_password');
    const post = await readCaptchaInfo(page);
    fs.writeFileSync(CAP_RESULT, (done || otpVisible) ? 'SOLVED\n' : `NEW_ROUND:${post.solved}/${post.required}\n`);
    if (done || otpVisible) { writeCap('CAPTCHA_SOLVED'); writeState('CAPTCHA_PASSED'); break; }
    // else: a fresh grid (next required object, or a re-serve after a wrong answer) -> next round.
  }
}

// ---------------------------------------------------------------------------
// Browser launch — real-Chrome new-headless when available; coherent fingerprint.
// ---------------------------------------------------------------------------
function launchArgs() {
  const args = [
    '--disable-blink-features=AutomationControlled',
    '--no-sandbox',
    '--disable-dev-shm-usage',
  ];
  // Old Playwright headless => flat/identical canvas (instant WAF flag). Use the new engine.
  if (!HEADED) args.push('--headless=new');
  return args;
}

async function launchBrowser() {
  const base = { headless: HEADED ? false : true, args: launchArgs() };
  // Prefer the real Chrome binary (real TLS + GPU-backed canvas). Fall back to bundled chromium.
  try {
    const b = await chromium.launch({ ...base, channel: 'chrome' });
    process.stderr.write('[launch] channel=chrome (real Chrome)\n');
    return b;
  } catch (e) {
    process.stderr.write('[launch] chrome channel unavailable, falling back to bundled chromium with ANGLE\n');
    return chromium.launch({
      ...base,
      args: [...base.args, '--use-gl=angle', '--use-angle=swiftshader-webgl'],
    });
  }
}

// Stealth: patch only the boolean automation tells. Do NOT randomize canvas (negative signal).
// Drop the detectable plugins=[1..5] array hack from login.js; keep a coherent Linux platform.
async function applyStealth(ctx) {
  await ctx.addInitScript(() => {
    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
    Object.defineProperty(navigator, 'languages', { get: () => ['en-IN', 'en'] });
    Object.defineProperty(navigator, 'platform', { get: () => 'Linux x86_64' });
    // window.chrome runtime object (absent in headless => a tell).
    if (!window.chrome) {
      window.chrome = { runtime: {} };
    }
    // permissions.query consistency for notifications.
    try {
      const orig = window.navigator.permissions && window.navigator.permissions.query;
      if (orig) {
        window.navigator.permissions.query = (p) =>
          (p && p.name === 'notifications')
            ? Promise.resolve({ state: Notification.permission })
            : orig(p);
      }
    } catch (_) { /* ignore */ }
  });
}

async function newWarmContext(browser) {
  const opts = {
    userAgent: UA,
    locale: 'en-IN',
    timezoneId: 'Asia/Kolkata',
    viewport: { width: 1366, height: 900 },
    deviceScaleFactor: 2, // sharper 324px grid -> 648px capture for the vision read (DPR-safe)
    extraHTTPHeaders: { 'Accept-Language': 'en-IN,en;q=0.9' },
  };
  // Reuse an aged guest storageState if the gardener has run.
  if (fs.existsSync(GUEST_STATE)) {
    opts.storageState = GUEST_STATE;
    process.stderr.write(`[warmup] reusing aged guest storageState ${GUEST_STATE}\n`);
  }
  const ctx = await browser.newContext(opts);
  await applyStealth(ctx);
  return ctx;
}

// The datacenter IP sometimes gets the "Continue shopping" interstitial (dog page)
// instead of the real homepage. Click through it so we bank real session cookies.
async function passInterstitial(page) {
  for (let i = 0; i < 2; i++) {
    const hit = await page.evaluate(() => /continue shopping/i.test(document.body.innerText || '') && !document.querySelector('#nav-link-accountList')).catch(() => false);
    if (!hit) return;
    const btn = await page.$('button:has-text("Continue shopping"), input[type="submit"][value*="Continue" i], a:has-text("Continue shopping")');
    if (btn) { await humanClick(page, btn); }
    else { try { await page.getByRole('button', { name: /continue shopping/i }).click({ timeout: 5000 }); } catch (_) {} }
    await page.waitForLoadState('domcontentloaded', { timeout: 20000 }).catch(() => {});
    await sleep(jitter(1500, 2600));
  }
}

// Browse amazon.in as a guest to bank session cookies + aws-waf-token before signin.
async function warmUp(page) {
  writeState('WARMUP');
  await page.goto('https://www.amazon.in/', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await page.waitForTimeout(2000);
  await passInterstitial(page);
  await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
  await sleep(jitter(900, 2200));
  // Human-paced scrolls.
  for (let i = 0; i < 3; i++) {
    await page.mouse.wheel(0, jitter(400, 900));
    await sleep(jitter(500, 1400));
  }
  // Best-effort: hover the nav account area to look organic.
  const acct = await page.$('#nav-link-accountList');
  if (acct) {
    try {
      const box = await acct.boundingBox();
      if (box) await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2, { steps: 5 });
    } catch (_) { /* ignore */ }
  }
  await sleep(jitter(600, 1500));
}

// Reach signin organically by clicking the nav link (real Referer + carried aws-waf-token).
async function gotoSigninOrganic(page) {
  const acct = await page.$('#nav-link-accountList, a[data-nav-role="signin"], #nav-link-accountList-nav-line-1');
  if (acct) {
    await humanClick(page, acct);
    await page.waitForLoadState('domcontentloaded', { timeout: 30000 }).catch(() => {});
    await sleep(jitter(1500, 2800));
  }
  // If the click didn't land us on signin, fall back to the canonical signin URL.
  const onSignin = await page.evaluate(() => /\/ap\/signin/i.test(location.href) || !!document.querySelector('#ap_email, #ap_email_login'));
  if (!onSignin) {
    const signinUrl =
      'https://www.amazon.in/ap/signin?openid.return_to=' +
      encodeURIComponent('https://www.amazon.in/?ref_=nav_signin') +
      '&openid.identity=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select' +
      '&openid.assoc_handle=inflex' +
      '&openid.mode=checkid_setup' +
      '&openid.ns=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0' +
      '&openid.claimed_id=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select';
    await page.goto(signinUrl, { waitUntil: 'domcontentloaded', timeout: 45000 });
    await sleep(jitter(1800, 2800));
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
(async () => {
  if (!fs.existsSync(OUT_DIR)) fs.mkdirSync(OUT_DIR, { recursive: true });
  writeState('STARTING');

  const browser = await launchBrowser();
  const ctx = await newWarmContext(browser);
  const page = await ctx.newPage();

  try {
    // --- Gardener mode: just warm up and persist an aged guest storageState, no signin. ---
    if (WARMUP_ONLY) {
      await warmUp(page);
      await ctx.storageState({ path: GUEST_STATE });
      process.stderr.write(`[warmup] saved aged guest storageState -> ${GUEST_STATE}\n`);
      writeState('WARMUP_SAVED');
      return;
    }

    // 1) Warm up the session (banks aws-waf-token) and reach signin organically.
    await warmUp(page);
    writeState('HOMEPAGE');
    await gotoSigninOrganic(page);

    // Detect a hard robot wall before we type anything.
    const blocked = await page.evaluate(() => /enter the characters you see below|automated access/i.test(document.body.innerText || ''));
    if (blocked) {
      await debugDump(page, 'blocked');
      writeState('BLOCKED_CAPTCHA');
      throw new Error('text/robot captcha on signin page — datacenter-IP block');
    }

    // 2) Enter the identifier. ONE submit per process invocation (account-safety rule).
    writeState('ENTERING_PHONE');
    const identifier = (MODE === 'password' && EMAIL) ? EMAIL : PHONE;
    await humanType(page, '#ap_email_login, #ap_email, input[name="email"]', identifier);
    await sleep(jitter(600, 1100));
    const contBtn = await page.$('#continue, input#continue, #continue-announce');
    if (contBtn) await humanClick(page, contBtn);
    else await page.keyboard.press('Enter');
    await page.waitForLoadState('domcontentloaded', { timeout: 30000 }).catch(() => {});
    await sleep(jitter(3000, 4200));

    await debugDump(page, 'after-phone');

    // 3) If the AAMation captcha gated the OTP send, run the vision-handoff loop.
    if (await isAamationCaptcha(page)) {
      await solveAamation(page); // throws (and we exit non-zero) on any bail
    }

    // 4) Fallback path: email+password (no SMS-OTP gate). Used when MODE=password.
    if (MODE === 'password' && PASSWORD) {
      const pw = await page.$('#ap_password');
      if (pw) {
        writeState('ENTERING_PASSWORD');
        await humanType(page, '#ap_password', PASSWORD);
        await sleep(jitter(500, 900));
        const signBtn = await page.$('#signInSubmit, #auth-signin-button, input[type="submit"]');
        if (signBtn) await humanClick(page, signBtn);
        else await page.keyboard.press('Enter');
        await page.waitForLoadState('domcontentloaded', { timeout: 30000 }).catch(() => {});
        await sleep(jitter(3500, 4800));
        // A password sign-in can still be challenged by a 2-step code -> fall through to OTP handling.
        if (await isAamationCaptcha(page)) await solveAamation(page);
      }
    }

    // 5) Identify which page we landed on (password vs OTP).
    let pageType = await page.evaluate(() => {
      const body = document.body.innerText || '';
      return {
        url: location.href,
        hasPassword: !!document.getElementById('ap_password'),
        hasOtpInput: !!(document.getElementById('auth-pv-enter-code') || document.querySelector('input[name="otpCode"], input[name="code"], input[autocomplete="one-time-code"]')),
        useOtpLink: !!document.querySelector('#auth-use-OTP-link, a[href*="OTPChallenge"], a[href*="useOtp"], a[id*="otp" i]'),
        loggedIn: !!document.querySelector('#nav-link-accountList-nav-line-1'),
        bodyHead: body.slice(0, 600).replace(/\s+/g, ' '),
      };
    });
    process.stderr.write('[pageType] ' + JSON.stringify(pageType) + '\n');

    // 6) If password path already logged us in, skip straight to saving state.
    if (!pageType.loggedIn) {
      // 6a) Password page but we want OTP: click "Use OTP" to switch flows.
      if (pageType.hasPassword && !pageType.hasOtpInput && MODE !== 'password') {
        writeState('SWITCHING_TO_OTP');
        const switched = await page.evaluate(() => {
          const candidates = [...document.querySelectorAll('a, button, span')].filter((el) => /one[- ]?time password|use otp|sign in with otp|otp/i.test((el.innerText || '').trim()));
          if (candidates[0]) { candidates[0].click(); return true; }
          return false;
        });
        if (switched) {
          await page.waitForLoadState('domcontentloaded', { timeout: 20000 }).catch(() => {});
          await sleep(jitter(2000, 3000));
        }
        // The OTP switch can also re-trigger the captcha.
        if (await isAamationCaptcha(page)) await solveAamation(page);
      }

      // 6b) Wait for the OTP input field (skip when MODE=password without an OTP step).
      const otpSel = 'input[name="otpCode"], input[name="code"], #auth-pv-enter-code, input[autocomplete="one-time-code"]';
      const otpField = await page.waitForSelector(otpSel, { timeout: 20000 }).catch(() => null);

      if (otpField) {
        writeState('WAITING_FOR_OTP_FIELD');
        // 6c) Pause for the user's OTP via the watch file.
        writeState('WAITING_FOR_OTP');
        process.stderr.write(`[otp] OTP sent to ${PHONE}. Write the code to ${OTP_INPUT_FILE} (poll every 1.5s).\n`);
        const otp = await waitForOtp();
        writeState('SUBMITTING_OTP');
        await otpField.fill(otp);
        await sleep(jitter(500, 900));
        const submitBtn = await page.$('#auth-signin-button, #signInSubmit, input[type="submit"]');
        if (submitBtn) await humanClick(page, submitBtn);
        else await page.keyboard.press('Enter');
        await page.waitForLoadState('domcontentloaded', { timeout: 30000 }).catch(() => {});
        await sleep(jitter(4000, 5200));
      } else if (MODE !== 'password') {
        await debugDump(page, 'no-otp');
        writeState('NO_OTP_FIELD');
        throw new Error('OTP input field never appeared — see secrets/dbg.no-otp.{html,png}');
      }
    }

    // 7) Verify we ended up logged in.
    const loggedIn = await page.evaluate(() => {
      const greeting = document.querySelector('#nav-link-accountList-nav-line-1, #nav-link-accountList .nav-line-1');
      return {
        url: location.href,
        greeting: greeting ? (greeting.innerText || '').trim() : '',
        signinPage: /ap\/signin|errors\/validateCaptcha|ap\/cvf/i.test(location.href),
        wrongOtp: /enter the correct (code|otp)/i.test(document.body.innerText || ''),
      };
    });
    process.stderr.write('[verify] ' + JSON.stringify(loggedIn) + '\n');
    await debugDump(page, 'after-otp');

    if (loggedIn.signinPage || loggedIn.wrongOtp) {
      writeState('OTP_WRONG_OR_REJECTED');
      throw new Error('still on signin / wrong code: ' + JSON.stringify(loggedIn));
    }

    // 8) Save the cookie jar (and refresh the aged guest state for next time).
    await ctx.storageState({ path: SESSION_OUT });
    fs.writeFileSync(path.join(OUT_DIR, 'login.meta.json'), JSON.stringify({
      phone: PHONE,
      mode: MODE,
      capturedAt: new Date().toISOString(),
      url: loggedIn.url,
      greeting: loggedIn.greeting,
    }, null, 2));
    writeState('DONE');
    process.stderr.write('[done] storageState -> ' + SESSION_OUT + '\n');
  } catch (e) {
    writeState('ERROR:' + e.message.slice(0, 140));
    process.stderr.write('[fatal] ' + e.stack + '\n');
    process.exitCode = 1;
  } finally {
    // Clean captcha watch-files so a later run starts fresh.
    for (const f of [CAP_STATE, CAP_CLICK, CAP_RESULT]) { try { fs.unlinkSync(f); } catch (_) {} }
    for (let r = 1; r <= MAX_ROUNDS; r++) {
      for (const f of [capPng(r), capGrid(r), capMeta(r)]) { try { fs.unlinkSync(f); } catch (_) {} }
    }
    await browser.close().catch(() => {});
  }
})();
