// Convert a Cookie-Editor export of a LOGGED-IN bigbasket.com session into
// Playwright cookies the scraper can inject, so the scrape runs as a real
// bbStar member and captures MEMBER prices (what a logged-in customer pays),
// not the logged-out public prices.
//
// Mirrors platforms/amazon-now/import_cookies.js (the cookie-transplant pattern).
// Used two ways:
//   1. As a MODULE  — scrape.js requires it and calls loadBBCookies(path) to get
//      a Playwright cookie array to ctx.addCookies(...) right after newContext.
//   2. As a CLI     — `node import_cookies.js [cookie-editor-export.json]`
//      validates the export, reports which auth-critical cookies are present,
//      and writes secrets/bb.storageState.json (handy for manual checks).
//
// Cookie-Editor JSON is an array of { name, value, domain, path, secure, httpOnly,
// sameSite, expirationDate(seconds), session }. Playwright wants
// { name, value, domain, path, expires, httpOnly, secure, sameSite }.
//
// SECURITY: bb_cookies.json holds LIVE auth tokens. It is gitignored and must NEVER
// be committed/printed. This file logs only cookie NAMES + presence, never values.
const fs = require('fs');
const path = require('path');

const DEFAULT_COOKIE_PATH = path.join(__dirname, 'secrets', 'bb_cookies.json');
const STORAGE_STATE_OUT = path.join(__dirname, 'secrets', 'bb.storageState.json');

// The auth cookies that prove a genuine logged-in member session. BBAUTHTOKEN is
// the must-have bearer; sessionid + _bb_cid (customer id) + customer_hash identify
// the member. If BBAUTHTOKEN is absent the export is not a logged-in session.
const CRITICAL = ['BBAUTHTOKEN', 'sessionid', '_bb_cid', 'customer_hash'];

function mapSameSite(s) {
  if (!s) return 'Lax';
  const t = String(s).toLowerCase();
  if (t === 'no_restriction' || t === 'none') return 'None';
  if (t === 'lax' || t === 'unspecified') return 'Lax';
  if (t === 'strict') return 'Strict';
  return 'Lax';
}

// Convert a parsed Cookie-Editor array (or {cookies:[...]}) into Playwright cookies.
// Drops entries with no name or empty value (Cookie-Editor exports a few empty
// placeholder cookies like _bb_addressinfo="" that Playwright rejects).
function toPlaywrightCookies(raw) {
  const arr = Array.isArray(raw) ? raw : (raw && raw.cookies) || [];
  return arr
    .map((c) => {
      const out = {
        name: c.name,
        value: c.value,
        domain: c.domain || '.bigbasket.com',
        path: c.path || '/',
        httpOnly: !!c.httpOnly,
        secure: !!c.secure,
        sameSite: mapSameSite(c.sameSite),
      };
      // 'None' requires secure per the cookie spec; Playwright enforces it.
      if (out.sameSite === 'None') out.secure = true;
      // expires: seconds since epoch; -1 for session cookies (Playwright convention).
      if (c.session || c.expirationDate == null) out.expires = -1;
      else out.expires = Math.round(c.expirationDate);
      return out;
    })
    .filter((c) => c.name && c.value != null && c.value !== '');
}

// Read + convert the secrets cookie file. Returns { cookies, names, haveCritical,
// missing, loggedIn }. loggedIn is true only when BBAUTHTOKEN is present (the
// bearer that makes member pricing appear). Throws only if the file is unreadable.
function loadBBCookies(cookiePath = DEFAULT_COOKIE_PATH) {
  const raw = JSON.parse(fs.readFileSync(cookiePath, 'utf8'));
  const cookies = toPlaywrightCookies(raw);
  const names = new Set(cookies.map((c) => c.name));
  const haveCritical = CRITICAL.filter((n) => names.has(n));
  const missing = CRITICAL.filter((n) => !names.has(n));
  return { cookies, names, haveCritical, missing, loggedIn: names.has('BBAUTHTOKEN') };
}

module.exports = { toPlaywrightCookies, loadBBCookies, CRITICAL, DEFAULT_COOKIE_PATH };

// ---- CLI ----
if (require.main === module) {
  const IN = process.argv[2] || DEFAULT_COOKIE_PATH;
  let info;
  try {
    info = loadBBCookies(IN);
  } catch (e) {
    console.error(`could not read cookie export ${IN}: ${e.message}`);
    process.exit(1);
  }
  if (!info.cookies.length) {
    console.error('no usable cookies found in export');
    process.exit(1);
  }
  const state = { cookies: info.cookies, origins: [] };
  if (!fs.existsSync(path.dirname(STORAGE_STATE_OUT))) {
    fs.mkdirSync(path.dirname(STORAGE_STATE_OUT), { recursive: true });
  }
  fs.writeFileSync(STORAGE_STATE_OUT, JSON.stringify(state, null, 2));
  console.log(`read ${info.cookies.length} usable cookies from ${IN}`);
  console.log(`wrote storageState -> ${STORAGE_STATE_OUT}`);
  console.log(`domains: ${[...new Set(info.cookies.map((c) => c.domain))].join(', ')}`);
  console.log(`critical present: ${info.haveCritical.join(', ') || '(none!)'}`);
  if (info.missing.length) {
    console.log(`critical MISSING: ${info.missing.join(', ')}  <-- BBAUTHTOKEN is the must-have`);
  }
  console.log(info.loggedIn ? 'looks LOGGED IN (BBAUTHTOKEN present)' : 'NOT logged in — re-export from a logged-in browser');
}
