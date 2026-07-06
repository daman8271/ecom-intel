#!/usr/bin/env bash
# blinkit_live_watch.sh — live observer for the daily authenticated Blinkit run.
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
  local progress_file="/Users/danny./VPS-Migration/imported/ecom-intel/platforms/blinkit/.progress.${TODAY}.json"
  ssh -o BatchMode=yes -o ConnectTimeout=10 macpro \
    "ps -axo pid,etime,command | grep -E 'run_blinkit_mac_to_vps.sh|platforms/blinkit/scrape.js' | grep -v grep || true
python3 - <<'PY' '$progress_file' 2>/dev/null || true
import json, os, sys
p = sys.argv[1]
if not os.path.exists(p):
    print(f'progress missing: {p}')
    raise SystemExit(0)
d = json.load(open(p, encoding='utf-8'))
items = list(d.items()) if isinstance(d, dict) else []
rows = [r for _, pin in items for r in (pin.get('rows') or []) if isinstance(pin, dict)]
stock_unverified = sum(
    1 for r in rows
    if r.get('stock_unverified')
    or str(r.get('listing_status') or '').strip().lower() == 'stock_unverified'
    or str(r.get('stock_source') or '').strip().lower().endswith('_unverified')
)
print('progress done={done} resolved={resolved} auth_ok={auth_ok} blocked={blocked} rows={rows} stock_unverified={stock_unverified} last={last}'.format(
    done=len(items),
    resolved=sum(1 for _, pin in items if isinstance(pin, dict) and pin.get('resolved')),
    auth_ok=sum(1 for _, pin in items if isinstance(pin, dict) and pin.get('auth_accepted')),
    blocked=sum(1 for _, pin in items if isinstance(pin, dict) and pin.get('blocked')),
    rows=len(rows),
    stock_unverified=stock_unverified,
    last=','.join([pin for pin, _ in items[-5:]]),
))
PY
latest=\$(ls -t /Users/danny./VPS-Migration/logs/blinkit/run-*.log 2>/dev/null | head -1)
[ -n \"\$latest\" ] && { echo \"latest_run_log=\$latest\"; tail -12 \"\$latest\"; }
tail -5 /Users/danny./VPS-Migration/logs/blinkit-launchd.out 2>/dev/null || true
tail -5 /Users/danny./VPS-Migration/logs/blinkit-launchd.err 2>/dev/null || true" \
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
