// One-time pairing: links this VPS as a WhatsApp linked-device of the given number.
// Usage:  node link.js 918899011758     (full international format, digits only, no +)
// Prints an 8-digit PAIRING CODE. On that phone:
//   WhatsApp > Settings > Linked Devices > Link a Device > "Link with phone number instead"
//   -> enter the code. Auth keys persist to secrets/whatsapp-auth/ (never need the phone again).
// Uses openSocket() so it reconnects through the post-pair "restart required" (515) that
// Baileys ALWAYS emits after a fresh link — that reconnect is what actually finalises it.
const { openSocket, delay } = require('./_sock');

(async () => {
  const phone = (process.argv[2] || '').replace(/[^0-9]/g, '');
  if (!phone || phone.length < 10) {
    console.error('Usage: node link.js <number, intl digits only e.g. 918899011758>');
    process.exit(2);
  }

  let asked = false;
  // attach to every (re)connect; only the first, unregistered socket requests a code
  function onSock(sock) {
    if (sock.authState.creds.registered) return;
    const ask = async (trigger) => {
      if (asked) return;
      asked = true;
      try {
        const code = await sock.requestPairingCode(phone);
        const pretty = code.match(/.{1,4}/g)?.join('-') || code;
        console.log('\n========================================');
        console.log('  PAIRING CODE:  ' + pretty);
        console.log('  Number: +' + phone);
        console.log('  WhatsApp > Linked Devices > Link a Device');
        console.log('  > "Link with phone number instead" > enter code');
        console.log('========================================\n');
        console.log('Waiting for you to enter it... [via ' + trigger + ']');
      } catch (e) {
        console.error('requestPairingCode failed:', e.message);
      }
    };
    setTimeout(() => ask('timer'), 3500);
    sock.ev.on('connection.update', (u) => { if (u.qr) ask('qr'); });
  }

  try {
    // long per-attempt window: attempt 1 waits for you to type the code, then the
    // 515 close triggers attempt 2 which opens for real.
    await openSocket({ onSock, attempts: 6, openTimeoutMs: 190000 });
    // CRITICAL: let the post-open creds.update flush fully to disk before exiting.
    // A premature exit/kill here truncates creds.json to 0 bytes and kills the session.
    await delay(5000);
    console.log('\n✅ LINKED successfully. Session saved — phone not needed again.');
    process.exit(0);
  } catch (e) {
    console.error('\n❌ Link failed:', e.message);
    process.exit(1);
  }
})();
