// Convert a Cookie-Editor export (flipkart.com, captured on the user's CLEAN machine while
// logged in) into a Playwright storageState the VPS can load. The pure-API path is blocked
// for GUESTS because Flipkart's JS mints a `T` device-fingerprint cookie that's cross-checked
// against the `at` auth JWT. A logged-in session exported from a real browser carries a VALID
// `T` + matching `at` — the one thing we can't forge — so we transplant it (same trick as
// Amazon Now).
//
//   node import_cookies.js <cookie-editor-export.json>
//   # writes secrets/flipkart-minutes.storageState.json
//
// Cookie-Editor JSON is an array of { name, value, domain, path, secure, httpOnly,
// sameSite, expirationDate(seconds), session }. Playwright wants
// { cookies:[{name,value,domain,path,expires,httpOnly,secure,sameSite}], origins:[] }.
const fs = require('fs');
const path = require('path');

const IN = process.argv[2];
if (!IN) { console.error('usage: node import_cookies.js <cookie-editor-export.json>'); process.exit(1); }
const OUTDIR = path.join(__dirname, 'secrets');
const OUT = path.join(OUTDIR, 'flipkart-minutes.storageState.json');

// Auth-critical Flipkart cookies. `at` = the auth JWT (logged-in), `T` = device fingerprint
// the server binds the session to. Without both, the transplant won't unlock the pure-API flow.
const CRITICAL = ['at', 'T'];
const NICE = ['SN', 'K-ACTION', 'ud', 'S', 'vd', 'Network-Type', 'Tj'];

function mapSameSite(s) {
  if (!s) return 'Lax';
  const t = String(s).toLowerCase();
  if (t === 'no_restriction' || t === 'none') return 'None';
  if (t === 'strict') return 'Strict';
  return 'Lax';
}

const raw = JSON.parse(fs.readFileSync(IN, 'utf8'));
const arr = Array.isArray(raw) ? raw : (raw.cookies || []);
if (!arr.length) { console.error('no cookies found in export'); process.exit(1); }

const cookies = arr.map((c) => {
  const out = {
    name: c.name,
    value: c.value,
    domain: c.domain || '.flipkart.com',
    path: c.path || '/',
    httpOnly: !!c.httpOnly,
    secure: c.secure !== false,
    sameSite: mapSameSite(c.sameSite),
  };
  if (c.session) out.expires = -1;
  else if (c.expirationDate) out.expires = Math.round(c.expirationDate);
  else out.expires = -1;
  return out;
}).filter((c) => c.name && c.value);

fs.mkdirSync(OUTDIR, { recursive: true });
fs.writeFileSync(OUT, JSON.stringify({ cookies, origins: [] }, null, 2));
try { fs.chmodSync(OUT, 0o600); } catch (_) {}

const names = new Set(cookies.map((c) => c.name));
const haveCrit = CRITICAL.filter((n) => names.has(n));
const missCrit = CRITICAL.filter((n) => !names.has(n));
console.log(`wrote ${cookies.length} cookies -> ${OUT}`);
console.log(`critical present: ${haveCrit.join(', ') || '(none!)'}`);
if (missCrit.length) console.error(`*** MISSING critical cookie(s): ${missCrit.join(', ')} — session likely NOT logged in; re-export while logged into flipkart.com ***`);
console.log(`also present: ${NICE.filter((n) => names.has(n)).join(', ') || '(none)'}`);

// Decode the DC hint from the `at` JWT (z field => which N.rome.api subdomain to call).
const at = cookies.find((c) => c.name === 'at');
if (at) {
  try {
    const payload = JSON.parse(Buffer.from(at.value.split('.')[1], 'base64').toString('utf8'));
    console.log(`at JWT: z(DC)=${payload.z}  dId=${payload.dId ? 'present' : 'absent'}  exp=${payload.exp ? new Date(payload.exp * 1000).toISOString() : '?'}`);
  } catch (_) { console.log('at JWT: could not decode payload (ok, probe will brute-force the DC)'); }
}
