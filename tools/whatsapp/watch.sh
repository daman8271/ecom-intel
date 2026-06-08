#!/usr/bin/env bash
# Run the WhatsApp watcher continuously. Intended for tmux/systemd, not cron.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$DIR"
mkdir -p logs secrets

# --- INBOUND DISABLED 2026-06-01 (owner request): the bot is OUTBOUND-ONLY now. ---
# The auto-reply listener (watch.js) is off; the number only PUSHES cron reports to
# the group via post_reports.js. To deliberately bring inbound back, run with
# WA_BOT_ENABLE=1 (and review the reply-scope rules in watch.js first).
if [ "${WA_BOT_ENABLE:-0}" != "1" ]; then
  echo "[wa] inbound watcher is DISABLED (outbound-only mode). Set WA_BOT_ENABLE=1 to re-enable." >&2
  exit 0
fi

# Defaults: private self-chat assistant answered by Claude (read-only), group off.
: "${WA_BOT_INTERVAL_MS:=10000}"
: "${WA_BOT_NUMBER:=918899011758}"
: "${WA_BOT_AGENT:=claude}"
: "${WA_BOT_SEND:=1}"
: "${WA_BOT_RESPOND_TO_FROM_ME:=1}"
: "${WA_BOT_DISABLE_GROUP:=1}"
: "${WA_BOT_DM_ALLOWLIST:=918899011758,185414426054881}"
export WA_BOT_INTERVAL_MS WA_BOT_NUMBER WA_BOT_AGENT WA_BOT_SEND WA_BOT_RESPOND_TO_FROM_ME WA_BOT_DISABLE_GROUP WA_BOT_DM_ALLOWLIST

exec node tools/whatsapp/watch.js
