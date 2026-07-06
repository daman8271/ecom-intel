// Post the daily ecom reports to WhatsApp over ONE connection:
//   1) a single consolidated summary message
//   2) each platform's Excel report as a document attachment
// connect -> send all -> exit. No daemon. Outbound-only; never listens/replies.
//
// Usage:
//   node post_reports.js <manifest.json>             -> target group in secrets/whatsapp-target.json
//   node post_reports.js <manifest.json> --jid <JID> -> explicit JID (e.g. self-chat dry run)
//
// manifest.json shape: {"summary": "...", "files": [{"path","caption"}, ...]}
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { openSocket, delay } = require('./_sock');

const TARGET_FILE = path.join(__dirname, '..', '..', 'secrets', 'whatsapp-target.json');
const XLSX_MIME = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const GAP_MS = Number(process.env.WA_POST_GAP_MS || 1800); // gentle gap between messages

const args = process.argv.slice(2);
let manifestPath, jidOverride;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--jid') jidOverride = args[++i];
  else if (!manifestPath) manifestPath = args[i];
}
if (!manifestPath || !fs.existsSync(manifestPath)) {
  console.error('manifest not found:', manifestPath);
  process.exit(2);
}
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
let jid = jidOverride;
if (!jid) {
  if (!fs.existsSync(TARGET_FILE)) { console.error('no target set (secrets/whatsapp-target.json)'); process.exit(2); }
  jid = JSON.parse(fs.readFileSync(TARGET_FILE, 'utf8')).jid;
}

function runBlinkitGate(filePath, passName) {
  const base = path.basename(filePath);
  const m = base.match(/(\d{4}-\d{2}-\d{2})/);
  const env = {
    ...process.env,
    BLINKIT_MONITOR_DRYRUN: '1',
    BLINKIT_MONITOR_EXIT_CODE: '1',
    BLINKIT_MONITOR_DATE: m ? m[1] : '',
  };
  if (/Jivo-Blinkit-Live-Report-\d{4}-\d{2}-\d{2}\.xlsx$/.test(base)) {
    env.BLINKIT_MONITOR_REPORT = filePath;
  }
  if (/Jivo-Blinkit-Not-Listed-Pincodes-\d{4}-\d{2}-\d{2}\.xlsx$/.test(base)) {
    env.BLINKIT_MONITOR_REPORT = path.join(path.dirname(filePath), `Jivo-Blinkit-Live-Report-${m ? m[1] : ''}.xlsx`);
    env.BLINKIT_MONITOR_NOT_LISTED_REPORT = filePath;
  }
  const gate = spawnSync(path.join(__dirname, '..', 'cron', 'blinkit_quality_monitor.sh'), [passName], {
    env,
    stdio: 'inherit',
  });
  return gate.status === 0;
}

(async () => {
  let sock;
  try { sock = await openSocket(); }
  catch (e) { console.error('Connect failed:', e.message); process.exit(e.message.includes('LOGGED_OUT') ? 3 : 1); }
  await delay(1000);

  // 1) consolidated summary
  await sock.sendMessage(jid, { text: manifest.summary });
  console.log('SENT summary (' + manifest.summary.length + ' chars) ->', jid);
  await delay(GAP_MS);

  // 2) each report as a document
  let n = 0;
  const files = manifest.files || [];
  for (const f of files) {
    if (!fs.existsSync(f.path)) { console.error('skip missing:', f.path); continue; }
    if (/Jivo-Blinkit-Live-Report-\d{4}-\d{2}-\d{2}\.xlsx$/.test(path.basename(f.path))) {
      if (!runBlinkitGate(f.path, 'pre-whatsapp-post-reports')) {
        console.error('skip Blinkit report; quality gate failed:', f.path);
        continue;
      }
    }
    if (/Jivo-Blinkit-Not-Listed-Pincodes-\d{4}-\d{2}-\d{2}\.xlsx$/.test(path.basename(f.path))) {
      const allowed = process.env.BLINKIT_NOT_LISTED_WA_CHAT || '917703818227@s.whatsapp.net';
      if (jid !== allowed) {
        console.error('skip Blinkit not-listed workbook; direct recipient required:', allowed);
        continue;
      }
      if (!runBlinkitGate(f.path, 'pre-whatsapp-post-reports-not-listed')) {
        console.error('skip Blinkit not-listed workbook; quality gate failed:', f.path);
        continue;
      }
    }
    await sock.sendMessage(jid, {
      document: fs.readFileSync(f.path),
      fileName: path.basename(f.path),
      mimetype: XLSX_MIME,
      caption: f.caption || undefined,
    });
    n++;
    console.log('SENT doc ' + n + '/' + files.length + ' ->', path.basename(f.path));
    await delay(GAP_MS);
  }

  await delay(2500); // let the last send round-trip before teardown
  console.log('DONE: summary +', n, 'reports ->', jid);
  process.exit(0);
})();
