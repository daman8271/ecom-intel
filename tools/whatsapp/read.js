// Read recent/buffered WhatsApp messages (short-lived). No daemon.
// WhatsApp buffers messages for a linked device while it's offline and delivers them
// on the next connect, so this catches what was said since the last read.
// Every captured message is appended to secrets/whatsapp-inbox.jsonl (durable log).
// Usage: node read.js [seconds]     (default window 9s)
const fs = require('fs');
const path = require('path');
const { openSocket, delay } = require('./_sock');

const INBOX = path.join(__dirname, '..', '..', 'secrets', 'whatsapp-inbox.jsonl');
const WINDOW = (parseInt(process.argv[2], 10) || 9) * 1000;

function bodyOf(m) {
  const msg = m.message || {};
  return msg.conversation || msg.extendedTextMessage?.text ||
    msg.imageMessage?.caption || msg.videoMessage?.caption ||
    (msg.reactionMessage ? '[reaction ' + msg.reactionMessage.text + ']' : '') ||
    (Object.keys(msg)[0] ? '[' + Object.keys(msg)[0] + ']' : '');
}

(async () => {
  const seen = [];
  const onMessages = ({ messages }) => {
    for (const m of messages) {
      if (!m.message) continue;
      const rec = {
        chat: m.key.remoteJid,
        from: m.key.fromMe ? 'me' : (m.key.participant || m.key.remoteJid),
        name: m.pushName || '',
        ts: m.messageTimestamp ? Number(m.messageTimestamp) : null,
        text: bodyOf(m),
        fromMe: !!m.key.fromMe,
      };
      seen.push(rec);
      try { fs.appendFileSync(INBOX, JSON.stringify(rec) + '\n'); } catch (_) {}
    }
  };
  try { await openSocket({ onSock: (s) => s.ev.on('messages.upsert', onMessages) }); }
  catch (e) { console.error('Connect failed:', e.message); process.exit(e.message.includes('LOGGED_OUT') ? 3 : 1); }

  await delay(WINDOW);
  if (!seen.length) { console.log('(no new messages in the last ' + (WINDOW / 1000) + 's)'); }
  else {
    console.log('=== ' + seen.length + ' message(s) ===');
    for (const r of seen) {
      const when = r.ts ? new Date(r.ts * 1000).toISOString().slice(11, 19) : '--:--:--';
      const who = r.fromMe ? 'ME' : (r.name || r.from.split('@')[0]);
      console.log(`[${when}] ${who}: ${r.text}`);
    }
  }
  process.exit(0);
})();
