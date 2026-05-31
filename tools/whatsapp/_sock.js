// Shared Baileys socket factory for the ecom-intel WhatsApp notifier.
// Short-lived by design: every command connects, does its job, and exits.
// No persistent daemon (attended-use pattern, same boundary as the Telegram helper).
const path = require('path');
const baileys = require('@whiskeysockets/baileys');
const makeWASocket = baileys.makeWASocket || baileys.default;
const { useMultiFileAuthState, fetchLatestBaileysVersion, Browsers, DisconnectReason } = baileys;

const AUTH_DIR = path.join(__dirname, '..', '..', 'secrets', 'whatsapp-auth');
const delay = (ms) => new Promise((r) => setTimeout(r, ms));

// Build a socket from the saved auth state. Returns { sock, saveCreds, state }.
async function makeSock({ logger } = {}) {
  const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR);
  const { version } = await fetchLatestBaileysVersion();
  const sock = makeWASocket({
    version,
    auth: state,
    browser: Browsers.ubuntu('Chrome'),
    printQRInTerminal: false,
    syncFullHistory: false,
    markOnlineOnConnect: false,
    logger: logger || require('pino')({ level: 'silent' }),
  });
  sock.ev.on('creds.update', saveCreds);
  return { sock, saveCreds, state };
}

// Open a ready socket, transparently reconnecting through the post-pair "restart
// required" (515) close that Baileys ALWAYS emits right after a fresh link, plus
// any transient close. Resolves with an OPEN socket. Throws on logged-out.
// onSock(sock) is called on every (re)connect so callers can (re)attach listeners.
async function openSocket({ onSock, attempts = 6, openTimeoutMs = 30000 } = {}) {
  let lastCode;
  for (let i = 0; i < attempts; i++) {
    const { sock } = await makeSock();
    if (onSock) onSock(sock);
    const res = await new Promise((resolve) => {
      const to = setTimeout(() => resolve({ ok: false, code: 'timeout' }), openTimeoutMs);
      sock.ev.on('connection.update', (u) => {
        if (u.connection === 'open') { clearTimeout(to); resolve({ ok: true, sock }); }
        if (u.connection === 'close') {
          clearTimeout(to);
          resolve({ ok: false, code: u.lastDisconnect?.error?.output?.statusCode });
        }
      });
    });
    if (res.ok) return res.sock;
    lastCode = res.code;
    if (res.code === DisconnectReason.loggedOut) throw new Error('LOGGED_OUT — session dead, re-run link.js');
    try { sock.end?.(undefined); } catch (_) {}
    await delay(900); // restartRequired / transient -> rebuild and retry
  }
  throw new Error('could not open socket (last close code ' + lastCode + ')');
}

module.exports = { makeSock, openSocket, AUTH_DIR, delay, DisconnectReason };
