#!/usr/bin/env bash
# Zepto Mac Pro primary guard.
#
# Owner decision 2026-07-09: do not run Zepto on KVM1. KVM1 showed repeat
# recoverable HTTP 429s while Mac Pro and the main VPS completed the same smoke
# set cleanly. This guard starts the Mac Pro feeder and uses only the VPS as the
# emergency fallback.
set -uo pipefail

DIR=/opt/ecom-intel
cd "$DIR" || exit 0
mkdir -p logs

PASS="${1:-launch}"
TODAY="$(date +%F)"
NOW="$(date +%s)"
BATCH_TS="$(date -d "$TODAY 10:00" +%s)"
REPORT="output/Jivo-Zepto-Live-Report-${TODAY}.xlsx"
WRAPPER="/Users/danny./VPS-Migration/scripts/run_zepto_mac_to_vps.sh"
LOG(){ echo "[$(date '+%F %T')] zepto_macpro_guard($PASS): $*"; }

tg(){ ( set +e
  [ -f "$DIR/secrets.env" ] && . "$DIR/secrets.env"
  CH="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "$CH" ] || exit 0
  curl -s --max-time 30 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CH}" \
    --data-urlencode "text=$1" >/dev/null ) || true; }

pending_sweep_id(){
  local l s
  for l in output/.batch/launched-"$TODAY"-*; do
    [ -e "$l" ] || continue
    s="${l##*/launched-}"
    [ -e "output/.batch/sent-$s" ] && continue
    printf '%s\n' "$s"
    return 0
  done
}

mac_reachable(){ ssh -o BatchMode=yes -o ConnectTimeout=15 macpro "true" >/dev/null 2>&1; }
mac_running(){
  ssh -o BatchMode=yes -o ConnectTimeout=15 macpro \
    "pgrep -f 'run_zepto_mac_to_vps.sh|platforms/zepto/scrape.js' >/dev/null" >/dev/null 2>&1
}

trigger_mac(){
  ssh -o BatchMode=yes -o ConnectTimeout=15 macpro \
    "nohup '$WRAPPER' >/tmp/zepto-guard-rerun.log 2>&1 & disown" >/dev/null 2>&1
}

local_vps_rescue(){
  local sid est rc v verdict
  est=2700
  if [ $((NOW + est)) -gt $((BATCH_TS - 300)) ]; then
    LOG "too late for VPS rescue before the 10:00 batch"
    tg "⚠️ Zepto guard: too late to re-run Zepto before the 10:00 batch; post-batch selfheal/next guard must deliver it late."
    return 0
  fi
  exec 7>"logs/.sweep-chain.lock"
  if ! flock -w 900 7; then
    LOG "sweep-chain lock busy; cannot run VPS Zepto rescue now"
    tg "⏳ Zepto guard: VPS chain still busy, so Zepto rescue was not started concurrently. KVM1 will not be used."
    return 0
  fi
  sid="$(pending_sweep_id || true)"
  LOG "VPS rescue start sid=${sid:-none}"
  tg "🛠 Zepto guard: Mac Pro unavailable/missed; running Zepto on the VPS as fallback. KVM1 is disabled for Zepto."
  rc=0
  DEFER_DELIVERY="${sid:+1}" SWEEP_ID="$sid" COVERAGE_DAILY=1 \
    timeout 6300 ./run.sh zepto >> logs/zepto-vps-rescue.log 2>&1 || rc=$?
  v="$(ls -t reviews/zepto-"$TODAY"-*.json 2>/dev/null | grep -Ev -- '-(unhold|doctor|probe|w2probe)\.json$' | head -1)"
  verdict="none"; [ -n "$v" ] && verdict="$(python3 -c 'import json,sys;print((json.load(open(sys.argv[1])).get("verdict") or "?").upper())' "$v" 2>/dev/null || echo '?')"
  LOG "VPS rescue done rc=$rc verdict=$verdict"
  [ "$verdict" = "OK" ] && tg "✅ Zepto VPS fallback verdict OK; KVM1 was not used." || tg "⚠️ Zepto VPS fallback verdict $verdict rc=$rc; held by normal gates."
}

if [ -f "$REPORT" ]; then
  LOG "today's report present — OK"
  exit 0
fi

case "$PASS" in
  launch)
    if mac_running; then LOG "Mac Pro Zepto already running"; exit 0; fi
    if trigger_mac; then
      LOG "Mac Pro Zepto trigger sent"
    else
      LOG "Mac Pro trigger failed; starting VPS fallback"
      tg "⚠️ Zepto guard: Mac Pro trigger failed at $(date +%H:%M) IST; using VPS fallback. KVM1 will not run Zepto."
      local_vps_rescue
    fi
    ;;
  watchdog|late)
    if mac_running; then LOG "Mac Pro Zepto still running — waiting"; exit 0; fi
    if mac_reachable && [ "$NOW" -lt "$(date -d "$TODAY 09:00" +%s)" ]; then
      if trigger_mac; then LOG "Mac Pro Zepto watchdog trigger sent"; exit 0; fi
    fi
    LOG "no report and Mac Pro not running; using VPS fallback"
    local_vps_rescue
    ;;
  *)
    LOG "unknown pass '$PASS'"
    exit 2
    ;;
esac
