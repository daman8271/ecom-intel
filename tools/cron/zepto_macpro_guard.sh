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
TODAY_COMPACT="$(date +%Y%m%d)"
NOW="$(date +%s)"
BATCH_TS="$(date -d "$TODAY 10:00" +%s)"
REPORT="output/Jivo-Zepto-Live-Report-${TODAY}.xlsx"
WRAPPER="/Users/danny./VPS-Migration/scripts/run_zepto_mac_to_vps.sh"
MAC_STALE_RUNNING_S="${ZEPTO_MAC_STALE_RUNNING_S:-18000}"
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

mac_stale_previous_run(){
  ssh -o BatchMode=yes -o ConnectTimeout=15 macpro \
    "TODAY_COMPACT='$TODAY_COMPACT' STALE_S='$MAC_STALE_RUNNING_S' python3 - <<'PY'
import os
import subprocess
import sys
import time

cmds = subprocess.check_output(
    \"ps -eo command | grep -E 'run_zepto_mac_to_vps.sh|platforms/zepto|OUT_FILE=.*zepto-' | grep -v grep || true\",
    shell=True,
    text=True,
)
if not cmds.strip():
    sys.exit(1)
if f\"zepto-{os.environ['TODAY_COMPACT']}\" in cmds:
    sys.exit(1)
lock = '/tmp/com.danny.zepto-mac-to-vps.lock'
if not os.path.exists(lock):
    sys.exit(1)
age = int(time.time() - os.path.getmtime(lock))
sys.exit(0 if age >= int(os.environ['STALE_S']) else 1)
PY" >/dev/null 2>&1
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
    if mac_running; then
      if mac_stale_previous_run; then
        LOG "stale previous-day Mac Pro Zepto run still active; using VPS fallback instead of waiting"
        tg "⚠️ Zepto guard: previous-day Mac Pro Zepto is still active at $(date +%H:%M) IST; using VPS fallback for today's report. KVM1 remains disabled."
        local_vps_rescue
        exit 0
      fi
      LOG "Mac Pro Zepto already running"
      exit 0
    fi
    # Device-team split (laptop worker #4): try laptop shard-1 + Mac shard-0
    # first; any failure inside the launcher returns nonzero and we fall back
    # to the legacy full-universe Mac trigger below.
    if [ "${ZEPTO_TEAM_DISABLE:-0}" != "1" ] && tools/laptop/zepto_team_launch.sh >> logs/zepto_team.log 2>&1; then
      LOG "device-team split engaged — laptop shard-1 + Mac shard-0 (logs/zepto_team.log)"
      exit 0
    fi
    if trigger_mac; then
      LOG "Mac Pro Zepto trigger sent"
    else
      LOG "Mac Pro trigger failed; starting VPS fallback"
      tg "⚠️ Zepto guard: Mac Pro trigger failed at $(date +%H:%M) IST; using VPS fallback. KVM1 will not run Zepto."
      local_vps_rescue
    fi
    ;;
  watchdog|late)
    # Device-team split: while a team run is active, the team watch owns
    # pull/merge/rescue for this pass (exit 0). Exit 3 = no/abandoned team run
    # -> fall through to the legacy checks below.
    if tools/laptop/zepto_team_watch.sh >> logs/zepto_team.log 2>&1; then
      LOG "device-team run active — team watch handled this pass"
      exit 0
    fi
    if mac_running; then
      if mac_stale_previous_run; then
        LOG "stale previous-day Mac Pro Zepto run still active; using VPS fallback instead of waiting"
        tg "⚠️ Zepto guard: previous-day Mac Pro Zepto is still active at $(date +%H:%M) IST; using VPS fallback for today's report. KVM1 remains disabled."
        local_vps_rescue
        exit 0
      fi
      LOG "Mac Pro Zepto still running — waiting"
      exit 0
    fi
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
