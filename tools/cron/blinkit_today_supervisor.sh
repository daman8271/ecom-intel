#!/usr/bin/env bash
# One-day active supervisor for Blinkit. It does not scrape directly; it triggers
# blinkit_batch_guard.sh when the run is missing and no residential worker is
# active. The guard retries only the Mac/Windows production workflow.
set -u

DIR=/opt/ecom-intel
cd "$DIR" || exit 1

TODAY="${BLINKIT_SUPERVISOR_DATE:-$(TZ=Asia/Kolkata date +%F)}"
START_HHMM="${BLINKIT_SUPERVISOR_START:-07:20}"
END_HHMM="${BLINKIT_SUPERVISOR_END:-11:15}"
INTERVAL="${BLINKIT_SUPERVISOR_INTERVAL:-300}"
LOG="$DIR/logs/blinkit-supervisor-${TODAY}.log"
mkdir -p "$DIR/logs"

log() {
  printf '[%s] blinkit_supervisor: %s\n' "$(TZ=Asia/Kolkata date '+%F %T %Z')" "$*" | tee -a "$LOG"
}

epoch_for() {
  TZ=Asia/Kolkata date -d "$TODAY $1" +%s 2>/dev/null || date +%s
}

hhmm_now() {
  TZ=Asia/Kolkata date +%H%M
}

main_report="$DIR/output/Jivo-Blinkit-Live-Report-${TODAY}.xlsx"
not_listed_report="$DIR/output/Jivo-Blinkit-Not-Listed-Pincodes-${TODAY}.xlsx"
main_sent="$DIR/logs/blinkit-main-wa-${TODAY}.sent"
not_listed_sent="$DIR/logs/blinkit-not-listed-wa-${TODAY}.sent"

device_worker_active() {
  ssh -o BatchMode=yes -o ConnectTimeout=8 macpro \
    "pgrep -f 'run_blinkit_mac_to_vps.sh|platforms/blinkit/scrape.js' >/dev/null" \
    >/dev/null 2>&1 && return 0
  local team_id
  team_id="$(head -1 "$DIR/shards/runs/ACTIVE-blinkit-team" 2>/dev/null || true)"
  [ -n "$team_id" ] || return 1
  timeout 20 ssh -o BatchMode=yes -o ConnectTimeout=8 laptop \
    "Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -match '$team_id' } | Select-Object -First 1" \
    2>/dev/null | grep -q "$team_id"
}

reports_present() {
  [ -s "$main_report" ] && [ -s "$not_listed_report" ]
}

delivery_complete() {
  [ -s "$main_sent" ] && [ -s "$not_listed_sent" ]
}

log "start; active window ${TODAY} ${START_HHMM}-${END_HHMM} IST"
while [ "$(date +%s)" -le "$(epoch_for "$END_HHMM")" ]; do
  if reports_present; then
    log "reports present; running quality and WhatsApp retry helpers"
    BLINKIT_MONITOR_DRYRUN=1 "$DIR/tools/cron/blinkit_quality_monitor.sh" supervisor >>"$LOG" 2>&1 || true
    "$DIR/tools/whatsapp/send_blinkit_main_direct.sh" supervisor >>"$LOG" 2>&1 || true
    "$DIR/tools/whatsapp/send_blinkit_not_listed_direct.sh" supervisor >>"$LOG" 2>&1 || true
    if delivery_complete; then
      log "delivery markers present; supervisor complete"
      exit 0
    fi
  else
    log "reports missing"
    if [ "$((10#$(hhmm_now)))" -ge "$((10#${START_HHMM/:/}))" ]; then
      if device_worker_active; then
        log "Blinkit worker active; not triggering another guard pass"
      else
        log "no active worker after start window; triggering guard"
        "$DIR/tools/cron/blinkit_batch_guard.sh" supervisor >>"$LOG" 2>&1 || true
      fi
    else
      log "before start window; waiting"
    fi
  fi
  sleep "$INTERVAL"
done

log "end window reached"
if reports_present; then
  exit 0
fi
exit 1
