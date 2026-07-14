#!/usr/bin/env bash
# Event-style starter: launch from quality-approved Blinkit data readiness.
set -u

ROOT=/opt/ecom-intel
cd "$ROOT" || exit 1
DATE_IST="${BLINKIT_TOP8_DATE:-$(TZ=Asia/Kolkata date +%F)}"
SESSION="blinkit-top8-${DATE_IST//-/}"
MAIN_REPORT="$ROOT/output/Jivo-Blinkit-Live-Report-${DATE_IST}.xlsx"
TOP8_SENT="$ROOT/logs/blinkit-top8-wa-${DATE_IST}.sent"

[ -s "$TOP8_SENT" ] && { echo "[blinkit_top8_start] already delivered"; exit 0; }
[ -s "$MAIN_REPORT" ] || { echo "[blinkit_top8_start] waiting for accepted Blinkit workbook"; exit 0; }
if ! BLINKIT_MONITOR_DATE="$DATE_IST" \
     BLINKIT_MONITOR_REPORT="$MAIN_REPORT" \
     BLINKIT_MONITOR_DRYRUN=1 \
     BLINKIT_MONITOR_EXIT_CODE=1 \
     "$ROOT/tools/cron/blinkit_quality_monitor.sh" pre-competitor >/dev/null; then
  echo "[blinkit_top8_start] Blinkit workbook is present but quality approval failed"
  exit 0
fi
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "[blinkit_top8_start] already running: $SESSION"
  exit 0
fi

tmux new-session -d -s "$SESSION" \
  "cd '$ROOT' && exec ./tools/competitor/blinkit_top8_daily.sh >> 'logs/blinkit-top8-${DATE_IST}.tmux.log' 2>&1"
echo "[blinkit_top8_start] started: $SESSION"
