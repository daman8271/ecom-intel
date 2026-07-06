#!/usr/bin/env bash
# blinkit_live_watch.sh — temporary live observer for the 2026-07-07 Blinkit run.
#
# This does not scrape or deliver. It records Mac process status, expected output
# files, and the read-only Blinkit quality monitor during the live run window.
set -u

DIR=/opt/ecom-intel
cd "$DIR" || exit 0

TODAY="${BLINKIT_WATCH_DATE:-$(TZ=Asia/Kolkata date +%F)}"
END_HHMM="${BLINKIT_WATCH_END:-10:45}"
LOG_DIR="$DIR/logs"
LOG="$LOG_DIR/blinkit_live_watch-${TODAY}.log"
mkdir -p "$LOG_DIR"

log() {
  printf '[%s] blinkit_live_watch: %s\n' "$(TZ=Asia/Kolkata date '+%F %T %Z')" "$*" | tee -a "$LOG"
}

end_epoch() {
  TZ=Asia/Kolkata date -d "$TODAY $END_HHMM" +%s 2>/dev/null || date +%s
}

mac_status() {
  ssh -o BatchMode=yes -o ConnectTimeout=10 macpro \
    "ps -axo pid,command | grep -E 'run_blinkit_mac_to_vps.sh|platforms/blinkit/scrape.js' | grep -v grep || true; tail -5 /Users/danny./VPS-Migration/logs/blinkit-launchd.out 2>/dev/null || true; tail -5 /Users/danny./VPS-Migration/logs/blinkit-launchd.err 2>/dev/null || true" \
    2>&1 | sed 's/^/[mac] /' | tee -a "$LOG" >/dev/null
}

log "start; watching until ${TODAY} ${END_HHMM} IST"
while [ "$(date +%s)" -le "$(end_epoch)" ]; do
  REPORT="$DIR/output/Jivo-Blinkit-Live-Report-${TODAY}.xlsx"
  NOT_LISTED="$DIR/output/Jivo-Blinkit-Not-Listed-Pincodes-${TODAY}.xlsx"
  [ -f "$REPORT" ] && log "main report present: $(stat -c '%y %s' "$REPORT" 2>/dev/null)" || log "main report missing"
  [ -f "$NOT_LISTED" ] && log "not-listed report present: $(stat -c '%y %s' "$NOT_LISTED" 2>/dev/null)" || log "not-listed report missing"
  mac_status
  BLINKIT_MONITOR_DRYRUN=1 "$DIR/tools/cron/blinkit_quality_monitor.sh" watch >> "$LOG" 2>&1 || true
  sleep "${BLINKIT_WATCH_INTERVAL:-300}"
done
log "done"
