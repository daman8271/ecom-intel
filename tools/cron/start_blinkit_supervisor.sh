#!/usr/bin/env bash
set -euo pipefail
cd /opt/ecom-intel
TODAY="$(TZ=Asia/Kolkata date +%Y%m%d)"
SESSION="blinkit-supervisor-${TODAY}"
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "[start_blinkit_supervisor] already running: $SESSION"
  exit 0
fi
tmux new-session -d -s "$SESSION" './tools/cron/blinkit_today_supervisor.sh'
echo "[start_blinkit_supervisor] started: $SESSION"
