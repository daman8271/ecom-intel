// ---------------------------------------------------------------------------
// tools/proxy.js — central proxy resolver for all Playwright scrapers.
//
// Returns a Playwright-compatible proxy object, or null when no proxy is
// configured (so scrapers run DIRECT, unchanged, with zero proxy code paths).
//
//   const getProxy = require('../../tools/proxy');
//   const proxy = getProxy();                       // null when unset
//   const browser = await chromium.launch({
//     headless: true,
//     ...(proxy ? { proxy } : {}),                  // spread => no-op when null
//   });
//
// Config source (first match wins, per key):
//   1. process.env  (if run.sh / cron exported the vars)
//   2. secrets.env at the repo root, parsed here directly.
//      NOTE: run.sh launches `node scrape.js` BEFORE it sources secrets.env
//      (and only inside a subshell), so the node process does NOT inherit
//      PROXY_* from the shell. This module therefore reads secrets.env itself
//      so the proxy works without touching run.sh.
//
// Recognised keys (set these in secrets.env):
//   PROXY_URL       full endpoint, e.g.  http://geo.iproyal.com:12321
//                   (creds may be embedded: http://user:pass@host:port — they
//                    are split out automatically into username/password)
//   PROXY_USERNAME  optional, if not embedded in PROXY_URL
//   PROXY_PASSWORD  optional, if not embedded in PROXY_URL
//
// If PROXY_URL is empty/absent -> returns null -> DIRECT connection.
// ---------------------------------------------------------------------------

const fs = require('fs');
const path = require('path');

// Repo root is one level up from tools/.
const REPO_ROOT = path.resolve(__dirname, '..');
const SECRETS_PATH = path.join(REPO_ROOT, 'secrets.env');

// Minimal KEY=value parser for the same shell-sourceable format secrets.env
// already uses (no `export`, no quotes required). Tolerates quotes, comments,
// and blank lines. Does NOT override anything already present in process.env.
function loadSecretsFile() {
  const out = {};
  let raw;
  try {
    raw = fs.readFileSync(SECRETS_PATH, 'utf8');
  } catch (e) {
    return out; // no secrets.env -> nothing to add
  }
  for (const line of raw.split('\n')) {
    const s = line.trim();
    if (!s || s.startsWith('#')) continue;
    const eq = s.indexOf('=');
    if (eq < 0) continue;
    let key = s.slice(0, eq).trim();
    if (key.startsWith('export ')) key = key.slice('export '.length).trim();
    let val = s.slice(eq + 1).trim();
    // strip a single matching pair of surrounding quotes
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1);
    }
    out[key] = val;
  }
  return out;
}

// Read a key from process.env first, then from secrets.env. Empty string
// counts as "unset" so a blank placeholder in secrets.env means DIRECT.
function readKey(key, fileVars) {
  const fromEnv = process.env[key];
  if (fromEnv !== undefined && fromEnv !== '') return fromEnv;
  const fromFile = fileVars[key];
  if (fromFile !== undefined && fromFile !== '') return fromFile;
  return undefined;
}

/**
 * Resolve proxy config for Playwright.
 * @returns {{server:string, username?:string, password?:string}|null}
 */
function getProxy() {
  const fileVars = loadSecretsFile();

  const url = readKey('PROXY_URL', fileVars);
  if (!url) return null; // no proxy configured -> DIRECT

  let username = readKey('PROXY_USERNAME', fileVars);
  let password = readKey('PROXY_PASSWORD', fileVars);

  // Normalise to a scheme://host:port URL. Playwright needs an explicit scheme;
  // a bare "host:port" mis-parses (the host becomes the scheme), so prepend
  // http:// when no recognised proxy scheme is present.
  const hasScheme = /^(https?|socks[45]?):\/\//i.test(url);
  let server = hasScheme ? url : 'http://' + url;

  // Allow creds embedded in the URL: scheme://user:pass@host:port. Split them
  // into the separate username/password fields Playwright expects.
  try {
    const u = new URL(server);
    if (u.username) {
      username = username || decodeURIComponent(u.username);
      if (u.password) password = password || decodeURIComponent(u.password);
      u.username = '';
      u.password = '';
      server = u.toString().replace(/\/$/, '');
    }
  } catch (e) {
    // Leave server as-is; Playwright will surface a clear error if malformed.
  }

  const proxy = { server };
  if (username) proxy.username = username;
  if (password) proxy.password = password;
  return proxy;
}

// Tiny human-readable describer for logs (never prints the password).
function describeProxy(proxy) {
  if (!proxy) return 'DIRECT (no proxy)';
  const user = proxy.username ? proxy.username.split('_')[0] : '(none)';
  return `PROXY ${proxy.server} user=${user}***`;
}

module.exports = getProxy;
module.exports.getProxy = getProxy;
module.exports.describeProxy = describeProxy;
