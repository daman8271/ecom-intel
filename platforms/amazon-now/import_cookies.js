// Convert a Cookie-Editor export (amazon.in, captured on a CLEAN IP) into a Playwright
// storageState the VPS scraper can load. The VPS can't log in (AWS WAF rejects correct
// captcha solves from the datacenter IP), so we transplant an authenticated session made
// on the user's own browser.
//
//   node import_cookies.js <cookie-editor-export.json>
//   # writes secrets/amazon-now.storageState.json
//
// Cookie-Editor JSON is an array of { name, value, domain, path, secure, httpOnly,
// sameSite, expirationDate(seconds), session }. Playwright wants
// { cookies:[{name,value,domain,path,expires,httpOnly,secure,sameSite}], origins:[] }.
const fs = require('fs');
const path = require('path');

const IN = process.argv[2];
if (!IN) { console.error('usage: node import_cookies.js <cookie-editor-export.json>'); process.exit(1); }
const OUT = path.join(__dirname, 'secrets', 'amazon-now.storageState.json');

// The auth-critical cookies we MUST see, or the session isn't really logged in.
const CRITICAL = ['session-token', 'ubid-acbin', 'at-acbin', 'sess-at-acbin', 'x-acbin', 'session-id'];

function mapSameSite(s) {
  if (!s) return 'Lax';
  const t = String(s).toLowerCase();
  if (t === 'no_restriction' || t === 'none') return 'None';
  if (t === 'lax' || t === 'unspecified') return 'Lax';
  if (t === 'strict') return 'Strict';
  return 'Lax';
}

const raw = JSON.parse(fs.readFileSync(IN, 'utf8'));
const arr = Array.isArray(raw) ? raw : (raw.cookies || []);
if (!arr.length) { console.error('no cookies found in export'); process.exit(1); }

const cookies = arr.map((c) => {
  let domain = c.domain || '.amazon.in';
  // Playwright is happy with leading-dot domains; keep as-is.
  const out = {
    name: c.name,
    value: c.value,
    domain,
    path: c.path || '/',
    httpOnly: !!c.httpOnly,
    secure: !!c.secure,
    sameSite: mapSameSite(c.sameSite),
  };
  // expires: seconds since epoch; -1 for session cookies (Playwright convention).
  if (c.session || c.expirationDate == null) out.expires = -1;
  else out.expires = Math.round(c.expirationDate);
  return out;
}).filter((c) => c.name && c.value != null);

const state = { cookies, origins: [] };
if (!fs.existsSync(path.dirname(OUT))) fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, JSON.stringify(state, null, 2));

const names = new Set(cookies.map((c) => c.name));
const haveCritical = CRITICAL.filter((n) => names.has(n));
const missing = CRITICAL.filter((n) => !names.has(n));
console.log(`wrote ${cookies.length} cookies -> ${OUT}`);
console.log(`amazon.in domains: ${[...new Set(cookies.map((c) => c.domain))].join(', ')}`);
console.log(`critical present: ${haveCritical.join(', ') || '(none!)'}`);
if (missing.length) console.log(`critical MISSING: ${missing.join(', ')}  <-- session-token + at-acbin are the must-haves`);
