#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const inputPath = process.argv[2] || '-';
const outputPath = process.argv[3] || path.join(__dirname, '..', '..', 'secrets', 'blinkit-auth-state.json');

function readInput() {
  if (inputPath === '-') return fs.readFileSync(0, 'utf8');
  return fs.readFileSync(inputPath, 'utf8');
}

function cookieValue(cookies, name) {
  const row = cookies.find((c) => c && c.name === name && String(c.value || '').trim());
  return row ? String(row.value).trim() : '';
}

function sameSite(value) {
  const v = String(value || '').trim().toLowerCase();
  if (v === 'lax') return 'Lax';
  if (v === 'strict') return 'Strict';
  if (v === 'none' || v === 'no_restriction') return 'None';
  return undefined;
}

function normalizeCookie(c) {
  const out = {
    name: String(c.name),
    value: String(c.value),
    domain: c.domain || (String(c.name).startsWith('_') ? '.blinkit.com' : 'blinkit.com'),
    path: c.path || '/',
  };
  if (typeof c.expirationDate === 'number' && Number.isFinite(c.expirationDate)) out.expires = Math.floor(c.expirationDate);
  if (c.httpOnly != null) out.httpOnly = Boolean(c.httpOnly);
  if (c.secure != null) out.secure = Boolean(c.secure);
  const ss = sameSite(c.sameSite);
  if (ss) out.sameSite = ss;
  return out;
}

let cookies;
try {
  cookies = JSON.parse(readInput());
} catch (err) {
  console.error(`[blinkit-import-cookies] invalid JSON: ${err.message}`);
  process.exit(2);
}
if (!Array.isArray(cookies)) {
  console.error('[blinkit-import-cookies] expected a Cookie-Editor JSON array');
  process.exit(2);
}

const accessToken = cookieValue(cookies, 'gr_1_accessToken');
const deviceId = cookieValue(cookies, 'gr_1_deviceId');
if (!accessToken || !deviceId) {
  console.error('[blinkit-import-cookies] missing gr_1_accessToken or gr_1_deviceId');
  process.exit(3);
}

const keepNames = new Set(['gr_1_accessToken', 'gr_1_deviceId', '__cf_bm', '_cfuvid']);
const sessionCookies = cookies
  .filter((c) => c && keepNames.has(c.name) && String(c.value || '').trim())
  .map(normalizeCookie);

const out = {
  accessToken,
  deviceId,
  cookies: sessionCookies,
  updatedAt: new Date().toISOString(),
  source: 'cookie-export',
};

fs.mkdirSync(path.dirname(outputPath), { recursive: true, mode: 0o700 });
if (fs.existsSync(outputPath)) {
  const backup = `${outputPath}.bak-${new Date().toISOString().replace(/[-:.TZ]/g, '').slice(0, 14)}`;
  fs.copyFileSync(outputPath, backup);
  fs.chmodSync(backup, 0o600);
}
fs.writeFileSync(outputPath, `${JSON.stringify(out, null, 2)}\n`, { mode: 0o600 });
fs.chmodSync(outputPath, 0o600);
console.log(JSON.stringify({
  ok: true,
  output: outputPath,
  hasAccessToken: true,
  hasDeviceId: true,
  cookies: sessionCookies.map((c) => c.name),
}, null, 2));
