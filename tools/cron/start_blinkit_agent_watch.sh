#!/usr/bin/env bash
# Start the Blinkit production agent/watchdog once per IST day.
set -euo pipefail

ROOT=/opt/ecom-intel
TODAY="$(TZ=Asia/Kolkata date +%Y%m%d)"
SESSION="blinkit-agent-watch-${TODAY}"

cd "$ROOT"
mkdir -p logs/blinkit-agent

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "[start_blinkit_agent_watch] already running: $SESSION"
  exit 0
fi

tmux new-session -d -s "$SESSION" './tools/cron/blinkit_agent_watch.sh'
echo "[start_blinkit_agent_watch] started: $SESSION"
