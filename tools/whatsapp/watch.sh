#!/usr/bin/env bash
# Run the WhatsApp watcher continuously. Intended for tmux/systemd, not cron.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$DIR"
mkdir -p logs secrets

: "${WA_BOT_INTERVAL_MS:=10000}"
: "${WA_BOT_NUMBER:=918899011758}"
: "${WA_BOT_AGENT:=codex}"
: "${WA_BOT_SEND:=1}"
: "${WA_BOT_RESPOND_TO_FROM_ME:=1}"
export WA_BOT_INTERVAL_MS WA_BOT_NUMBER WA_BOT_AGENT WA_BOT_SEND WA_BOT_RESPOND_TO_FROM_ME

exec node tools/whatsapp/watch.js
