#!/usr/bin/env bash
# Event-style starter: launch the top-8 run only after both Blinkit reports sent.
set -u

ROOT=/opt/ecom-intel
cd "$ROOT" || exit 1
DATE_IST="${BLINKIT_TOP8_DATE:-$(TZ=Asia/Kolkata date +%F)}"
SESSION="blinkit-top8-${DATE_IST//-/}"
MAIN_SENT="$ROOT/logs/blinkit-main-wa-${DATE_IST}.sent"
NOT_LISTED_SENT="$ROOT/logs/blinkit-not-listed-wa-${DATE_IST}.sent"
TOP8_SENT="$ROOT/logs/blinkit-top8-wa-${DATE_IST}.sent"

[ -s "$TOP8_SENT" ] && { echo "[blinkit_top8_start] already delivered"; exit 0; }
if [ ! -s "$MAIN_SENT" ] || [ ! -s "$NOT_LISTED_SENT" ]; then
  echo "[blinkit_top8_start] waiting for Blinkit main + not-listed delivery"
  exit 0
fi
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "[blinkit_top8_start] already running: $SESSION"
  exit 0
fi

tmux new-session -d -s "$SESSION" \
  "cd '$ROOT' && exec ./tools/competitor/blinkit_top8_daily.sh >> 'logs/blinkit-top8-${DATE_IST}.tmux.log' 2>&1"
echo "[blinkit_top8_start] started: $SESSION"
