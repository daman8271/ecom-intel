// 10-second WhatsApp watcher for ecom-intel.
//
// Watches the configured Ecom team group plus direct messages to this linked
// number. Replies only when a message is relevant:
//   - group message mentions this number / bot JID
//   - group message starts with /codex
//   - group message contains cron/scraper/self-heal/ecom-intel keywords
//   - any direct DM to the linked number
//
// Default mode is a small safe acknowledgement. Set WA_BOT_AGENT=codex to ask
// Codex CLI for a read-only answer.
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { openSocket, delay } = require('./_sock');

const ROOT = path.join(__dirname, '..', '..');
const TARGET_FILE = path.join(ROOT, 'secrets', 'whatsapp-target.json');
const STATE_FILE = process.env.WA_BOT_STATE || path.join(ROOT, 'secrets', 'whatsapp-bot-state.json');
const LOG_FILE = process.env.WA_BOT_LOG || path.join(ROOT, 'logs', 'whatsapp-watch.log');

const INTERVAL_MS = Number(process.env.WA_BOT_INTERVAL_MS || 10000);
const BOT_NUMBER = (process.env.WA_BOT_NUMBER || '918899011758').replace(/[^0-9]/g, '');
const BOT_JID = `${BOT_NUMBER}@s.whatsapp.net`;
const AGENT = (process.env.WA_BOT_AGENT || 'template').toLowerCase();
const SEND = process.env.WA_BOT_SEND !== '0';
const CODEX_TIMEOUT_MS = Number(process.env.WA_BOT_CODEX_TIMEOUT_MS || 90000);
const RESPOND_TO_FROM_ME = process.env.WA_BOT_RESPOND_TO_FROM_ME === '1';
// Self-chat / DM-only mode: ignore the group entirely and only answer chats whose
// number is in WA_BOT_DM_ALLOWLIST (defaults to the linked number's own self-chat).
const DISABLE_GROUP = process.env.WA_BOT_DISABLE_GROUP === '1';
const DM_ALLOWLIST = new Set(
  (process.env.WA_BOT_DM_ALLOWLIST || '')
    .split(',')
    .map((s) => s.replace(/[^0-9]/g, ''))
    .filter(Boolean)
);
const STARTED_AT_S = Math.floor(Date.now() / 1000);
const STARTUP_GRACE_S = Number(process.env.WA_BOT_STARTUP_GRACE_S || 20);

const KEYWORDS = [
  'cron', 'scraper', 'scrape', 'selfheal', 'self-heal', 'self healing',
  'ecom-intel', 'ecom intel', 'blinkit', '', 'zepto',
  'flipkart', 'amazon', 'fresh', 'report', 'excel', 'vault',
];

function mkdirFor(file) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
}

function log(line) {
  mkdirFor(LOG_FILE);
  fs.appendFileSync(LOG_FILE, `[${new Date().toISOString()}] ${line}\n`);
}

function loadJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (_) {
    return fallback;
  }
}

function saveJson(file, data) {
  mkdirFor(file);
  fs.writeFileSync(file, JSON.stringify(data, null, 2));
}

function bodyOf(m) {
  const msg = m.message || {};
  return msg.conversation ||
    msg.extendedTextMessage?.text ||
    msg.imageMessage?.caption ||
    msg.videoMessage?.caption ||
    (msg.reactionMessage ? `[reaction ${msg.reactionMessage.text}]` : '') ||
    '';
}

function mentionsOf(m) {
  const msg = m.message || {};
  const ctx =
    msg.extendedTextMessage?.contextInfo ||
    msg.imageMessage?.contextInfo ||
    msg.videoMessage?.contextInfo ||
    {};
  return ctx.mentionedJid || [];
}

function isGroup(jid) {
  return /@g\.us$/.test(jid || '');
}

function isDirect(jid) {
  return /@s\.whatsapp\.net$/.test(jid || '');
}

// Bare numeric id of a chat/user JID: "918899011758:15@s.whatsapp.net" -> "918899011758".
function chatNumber(jid) {
  return String(jid || '').split('@')[0].split(':')[0].replace(/[^0-9]/g, '');
}

function relevantMessage(m, targetJid) {
  if (!m.message) return { ok: false, why: 'empty-message' };

  const chat = m.key.remoteJid || '';
  const text = bodyOf(m).trim();
  if (!text) return { ok: false, why: 'empty-text' };

  const lower = text.toLowerCase();
  const mentions = mentionsOf(m).map((j) => String(j).split(':')[0]);
  const mentioned = mentions.includes(BOT_JID) ||
    lower.includes(`@${BOT_NUMBER}`) ||
    lower.includes(BOT_NUMBER);

  const botEcho = lower.startsWith('codex watcher saw this') ||
    lower.startsWith('codex here from the vps') ||
    lower.includes('i am online on the vps');

  // Self-chat / DM-only mode: never touch the group; only the allowlisted
  // number(s). The owner's own messages (fromMe) in the self-chat are the trigger;
  // the bot's own replies are filtered out by id-tracking + the botEcho guard.
  if (DISABLE_GROUP) {
    if (isGroup(chat)) return { ok: false, why: 'group-disabled' };
    if (DM_ALLOWLIST.size && !DM_ALLOWLIST.has(chatNumber(chat))) {
      return { ok: false, why: 'not-allowlisted' };
    }
    if (m.key.fromMe && botEcho) return { ok: false, why: 'skip-bot-echo' };
    return { ok: true, why: m.key.fromMe ? 'self-chat' : 'allowlisted-dm' };
  }

  if (m.key.fromMe) {
    if (!RESPOND_TO_FROM_ME || botEcho) return { ok: false, why: 'skip-own-or-bot-echo' };
    if (isDirect(chat)) return { ok: true, why: 'direct-message-from-owner' };
    if (chat === targetJid && (mentioned || lower.startsWith('/codex'))) {
      return { ok: true, why: 'owner-command' };
    }
    return { ok: false, why: 'skip-own-non-command' };
  }

  if (isDirect(chat)) return { ok: true, why: 'direct-message' };

  if (chat === targetJid) {
    if (mentioned) return { ok: true, why: 'mentioned-number' };
    if (lower.startsWith('/codex')) return { ok: true, why: 'slash-codex' };
    if (KEYWORDS.some((k) => lower.includes(k))) return { ok: true, why: 'ecom-keyword' };
  }

  return { ok: false, why: 'not-targeted' };
}

function trimState(state) {
  state.seen = (state.seen || []).slice(-800);
  state.replied = (state.replied || []).slice(-800);
}

function buildTemplateReply({ text, why }) {
  const clean = text.replace(/\s+/g, ' ').trim().slice(0, 240);
  return [
    `Codex watcher saw this (${why}).`,
    `Message: "${clean}"`,
    '',
    'I am online on the VPS. For repo/cron work, tag this number or start with /codex and I will inspect it in read-only mode when agent mode is enabled.',
  ].join('\n');
}

function askCodex({ chat, from, name, text, why }) {
  const outFile = path.join('/tmp', `wa-codex-${Date.now()}-${Math.random().toString(16).slice(2)}.txt`);
  const prompt = [
    'You are Codex running as a WhatsApp reply bot for the ecom-intel VPS.',
    'Answer the incoming WhatsApp message briefly and practically.',
    'Do not edit files. Do not run destructive commands. If repo state is needed, inspect read-only.',
    'If the request asks to change cron, scraper, WhatsApp automation, or self-heal behavior, explain the safe next step and say you can implement it when explicitly asked in the terminal.',
    'Keep the reply under 900 characters. No markdown tables.',
    '',
    `Trigger: ${why}`,
    `Chat: ${chat}`,
    `From: ${name || from}`,
    `Message: ${text}`,
  ].join('\n');

  const res = spawnSync('codex', [
    '--ask-for-approval', 'never',
    'exec',
    '-C', ROOT,
    '-s', 'read-only',
    '--ephemeral',
    '--color', 'never',
    '-o', outFile,
    prompt,
  ], {
    encoding: 'utf8',
    timeout: CODEX_TIMEOUT_MS,
    maxBuffer: 1024 * 1024,
  });

  if (res.error) {
    log(`codex error: ${res.error.message}`);
    return null;
  }
  if (res.status !== 0) {
    log(`codex exited ${res.status}: ${(res.stderr || '').slice(0, 500)}`);
    return null;
  }
  let answer = '';
  try {
    answer = fs.readFileSync(outFile, 'utf8');
    fs.unlinkSync(outFile);
  } catch (_) {
    answer = res.stdout || '';
  }
  return answer.trim().slice(0, 3500);
}

async function main() {
  const target = loadJson(TARGET_FILE, {});
  const targetJid = process.env.WA_BOT_GROUP_JID || target.jid;
  if (!targetJid && !DISABLE_GROUP) {
    console.error('No target group configured. Set secrets/whatsapp-target.json or WA_BOT_GROUP_JID.');
    process.exit(2);
  }

  const state = loadJson(STATE_FILE, { seen: [], replied: [] });
  state.seen = state.seen || [];
  state.replied = state.replied || [];
  const seen = new Set(state.seen);
  const replied = new Set(state.replied);

  log(`watch start target=${targetJid} bot=${BOT_JID} intervalMs=${INTERVAL_MS} agent=${AGENT} send=${SEND}`);

  while (true) {
    let sock;
    try {
      sock = await openSocket({
        attempts: 6,
        openTimeoutMs: 30000,
        onSock: (s) => {
          s.ev.on('messages.upsert', async ({ messages }) => {
            for (const m of messages || []) {
              const id = m.key?.id;
              if (!id || seen.has(id)) continue;
              seen.add(id);
              state.seen.push(id);

              const chat = m.key.remoteJid || '';
              const text = bodyOf(m).trim();
              const from = m.key.participant || m.key.remoteJid || '';
              const name = m.pushName || '';
              const msgTs = Number(m.messageTimestamp || 0);
              if (msgTs && msgTs < STARTED_AT_S - STARTUP_GRACE_S) {
                log(`message id=${id} chat=${chat} old=true ts=${msgTs} text=${text.slice(0, 120)}`);
                continue;
              }
              const rel = relevantMessage(m, targetJid);

              log(`message id=${id} chat=${chat} from=${name || from} relevant=${rel.ok} why=${rel.why} text=${text.slice(0, 160)}`);
              if (!rel.ok || replied.has(id)) continue;

              let reply = null;
              if (AGENT === 'codex') {
                reply = askCodex({ chat, from, name, text, why: rel.why });
              }
              if (!reply) reply = buildTemplateReply({ text, why: rel.why });

              if (SEND) {
                const sent = await sock.sendMessage(chat, { text: reply }, { quoted: m });
                // Track our own outgoing id so the echo of our reply (also fromMe in
                // the self-chat) is never treated as a new message -> no reply loop.
                const sentId = sent?.key?.id;
                if (sentId) {
                  if (!seen.has(sentId)) { seen.add(sentId); state.seen.push(sentId); }
                  replied.add(sentId); state.replied.push(sentId);
                }
                await delay(1200);
                log(`replied id=${id} chat=${chat} chars=${reply.length} sentId=${sentId || 'n/a'}`);
              } else {
                log(`dry-run reply id=${id} chat=${chat}: ${reply.replace(/\s+/g, ' ').slice(0, 500)}`);
              }

              replied.add(id);
              state.replied.push(id);
              trimState(state);
              saveJson(STATE_FILE, state);
            }
          });
        },
      });

      log('socket open');
      while (true) {
        trimState(state);
        saveJson(STATE_FILE, state);
        await delay(INTERVAL_MS);
      }
    } catch (e) {
      log(`socket loop error: ${e.message}`);
      try { sock?.end?.(undefined); } catch (_) {}
      await delay(INTERVAL_MS);
    }
  }
}

main().catch((e) => {
  console.error(e);
  log(`fatal: ${e.stack || e.message}`);
  process.exit(1);
});
