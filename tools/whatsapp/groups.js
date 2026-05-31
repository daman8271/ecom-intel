// Lists every group + DM this linked number can post to, with their JIDs.
// Usage: node groups.js
// Pick the target group's JID and save it:  echo '{"jid":"...@g.us","name":"..."}' > secrets/whatsapp-target.json
const fs = require('fs');
const path = require('path');
const { openSocket, delay } = require('./_sock');

(async () => {
  let sock;
  try {
    sock = await openSocket();
  } catch (e) {
    console.error('Connect failed:', e.message);
    process.exit(e.message.includes('LOGGED_OUT') ? 3 : 1);
  }
  await delay(1500);
  const groups = await sock.groupFetchAllParticipating();
  const list = Object.values(groups).map((g) => ({
    jid: g.id,
    name: g.subject,
    size: (g.participants || []).length,
  }));
  console.log('\n=== GROUPS this number is in (' + list.length + ') ===');
  for (const g of list) console.log(`  ${g.name}  [${g.size} members]\n     JID: ${g.jid}`);
  console.log('\nTo set a target group:');
  console.log(`  echo '{"jid":"<JID>","name":"<name>"}' > ` + path.join(__dirname, '..', '..', 'secrets', 'whatsapp-target.json'));
  await delay(500);
  process.exit(0);
})();
