#!/usr/bin/env bash
# Explicit 09:00 IST Blinkit delivery checkpoint.
# The send helpers are marker-safe and quality-gated, so this can run alongside
# the normal 15-minute retries without duplicate WhatsApp messages.
set -u

ROOT=/opt/ecom-intel
cd "$ROOT" || exit 1
mkdir -p logs

PASS="${1:-delivery-sweep-0900}"
DATE_IST="${BLINKIT_DELIVERY_SWEEP_DATE:-$(TZ=Asia/Kolkata date +%F)}"
LOG="logs/blinkit-whatsapp-delivery-sweep-${DATE_IST}.log"
MAIN="output/Jivo-Blinkit-Live-Report-${DATE_IST}.xlsx"
NOT_LISTED="output/Jivo-Blinkit-Not-Listed-Pincodes-${DATE_IST}.xlsx"
MAIN_SENT="logs/blinkit-main-wa-${DATE_IST}.sent"
NOT_LISTED_SENT="logs/blinkit-not-listed-wa-${DATE_IST}.sent"

log() {
  printf '[%s] blinkit_delivery_sweep(%s): %s\n' \
    "$(TZ=Asia/Kolkata date '+%F %T %Z')" "$PASS" "$*" | tee -a "$LOG"
}

log "start for $DATE_IST"

if [ -s "$MAIN" ] && [ -s "$NOT_LISTED" ]; then
  log "reports present; running quality gate"
  BLINKIT_MONITOR_DRYRUN=1 \
    BLINKIT_MONITOR_DATE="$DATE_IST" \
    BLINKIT_MONITOR_REPORT="$MAIN" \
    BLINKIT_MONITOR_NOT_LISTED_REPORT="$NOT_LISTED" \
    "$ROOT/tools/cron/blinkit_quality_monitor.sh" "$PASS" >>"$LOG" 2>&1 || true
else
  [ -s "$MAIN" ] || log "main workbook missing: $MAIN"
  [ -s "$NOT_LISTED" ] || log "not-listed workbook missing: $NOT_LISTED"
fi

rc=0
BLINKIT_MAIN_WA_DATE="$DATE_IST" "$ROOT/tools/whatsapp/send_blinkit_main_direct.sh" "$PASS" >>"$LOG" 2>&1 || rc=1
BLINKIT_NOT_LISTED_DATE="$DATE_IST" "$ROOT/tools/whatsapp/send_blinkit_not_listed_direct.sh" "$PASS" >>"$LOG" 2>&1 || rc=1

if [ -s "$MAIN_SENT" ] && [ -s "$NOT_LISTED_SENT" ]; then
  log "complete; both WhatsApp sent markers exist"
  BLINKIT_TOP8_DATE="$DATE_IST" \
    "$ROOT/tools/competitor/start_blinkit_top8_daily.sh" >>"$LOG" 2>&1 || true
  exit 0
fi

log "pending; main_sent=$([ -s "$MAIN_SENT" ] && echo yes || echo no) not_listed_sent=$([ -s "$NOT_LISTED_SENT" ] && echo yes || echo no)"
exit "$rc"
