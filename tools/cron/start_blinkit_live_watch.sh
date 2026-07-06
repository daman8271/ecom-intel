#!/usr/bin/env bash
# Start the Blinkit live watcher once per IST day. Idempotent wrapper for cron.
set -euo pipefail

ROOT=/opt/ecom-intel
TODAY="$(TZ=Asia/Kolkata date +%Y%m%d)"
SESSION="blinkit-live-watch-${TODAY}"

cd "$ROOT"
mkdir -p logs

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "[start_blinkit_live_watch] already running: $SESSION"
  exit 0
fi

tmux new-session -d -s "$SESSION" './tools/cron/blinkit_live_watch.sh'
echo "[start_blinkit_live_watch] started: $SESSION"
