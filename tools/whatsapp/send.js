// Send a WhatsApp message (short-lived connect -> send -> exit). No daemon.
// Usage:
//   node send.js "text here"                  -> sends to the target in secrets/whatsapp-target.json
//   node send.js "<jid>" "text here"          -> sends to an explicit JID (group ...@g.us or DM ...@s.whatsapp.net)
//   echo "text" | node send.js                -> reads body from stdin (good for long reports)
const fs = require('fs');
const path = require('path');
const { openSocket, delay } = require('./_sock');

const TARGET_FILE = path.join(__dirname, '..', '..', 'secrets', 'whatsapp-target.json');

function resolveArgs() {
  const a = process.argv.slice(2);
  let jid, text;
  if (a.length >= 2 && /@(g\.us|s\.whatsapp\.net)$/.test(a[0])) { jid = a[0]; text = a.slice(1).join(' '); }
  else if (a.length >= 1) { text = a.join(' '); }
  if (!text && !process.stdin.isTTY) text = fs.readFileSync(0, 'utf8');
  if (!jid) {
    if (!fs.existsSync(TARGET_FILE)) { console.error('No target set. Run groups.js then save secrets/whatsapp-target.json, or pass a JID.'); process.exit(2); }
    jid = JSON.parse(fs.readFileSync(TARGET_FILE, 'utf8')).jid;
  }
  if (!text || !text.trim()) { console.error('Empty message.'); process.exit(2); }
  return { jid, text: text.replace(/\s+$/, '') };
}

(async () => {
  const { jid, text } = resolveArgs();
  let sock;
  try { sock = await openSocket(); }
  catch (e) { console.error('Connect failed:', e.message); process.exit(e.message.includes('LOGGED_OUT') ? 3 : 1); }
  await delay(800);
  await sock.sendMessage(jid, { text });
  await delay(2500); // let the send round-trip to the server before we tear down
  console.log('SENT ->', jid, '(' + text.length + ' chars)');
  process.exit(0);
})();
