#!/usr/bin/env bash
# Long-running Blinkit watchdog session. Started idempotently by cron in tmux.
set -u

ROOT=/opt/ecom-intel
cd "$ROOT" || exit 1

DATE_IST="${BLINKIT_AGENT_DATE:-$(TZ=Asia/Kolkata date +%F)}"
END_HHMM="${BLINKIT_AGENT_END:-16:05}"
INTERVAL="${BLINKIT_AGENT_INTERVAL:-300}"
LOG="logs/blinkit-agent/watch-${DATE_IST}.log"
mkdir -p logs/blinkit-agent

log() {
  printf '[%s] blinkit_agent_watch: %s\n' "$(TZ=Asia/Kolkata date '+%F %T %Z')" "$*" | tee -a "$LOG"
}

end_epoch() {
  TZ=Asia/Kolkata date -d "$DATE_IST $END_HHMM" +%s 2>/dev/null || date +%s
}

complete() {
  [ -s "logs/blinkit-main-wa-${DATE_IST}.sent" ] && [ -s "logs/blinkit-not-listed-wa-${DATE_IST}.sent" ]
}

log "start; watching until ${DATE_IST} ${END_HHMM} IST"
"$ROOT/tools/cron/blinkit_agent_hook.sh" start >>"$LOG" 2>&1 || true

while [ "$(date +%s)" -le "$(end_epoch)" ]; do
  "$ROOT/tools/cron/blinkit_agent_hook.sh" poll >>"$LOG" 2>&1 || true
  if complete; then
    log "delivery complete; exiting"
    exit 0
  fi
  sleep "$INTERVAL"
done

"$ROOT/tools/cron/blinkit_agent_hook.sh" final >>"$LOG" 2>&1 || true
if complete; then
  log "delivery complete at final check"
  exit 0
fi
log "end window reached without both delivery markers"
exit 1
