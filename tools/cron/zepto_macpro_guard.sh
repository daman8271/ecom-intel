#!/usr/bin/env bash
# Zepto Mac Pro primary guard.
#
# Zepto is Mac Pro + Windows only. Datacenter fallbacks are deliberately
# prohibited: they are both slow under 429 pressure and hide device failures.
set -uo pipefail

DIR=/opt/ecom-intel
cd "$DIR" || exit 0
mkdir -p logs

PASS="${1:-launch}"
TODAY="$(date +%F)"
TODAY_COMPACT="$(date +%Y%m%d)"
NOW="$(date +%s)"
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

offbox_failure(){
  local reason="$1"
  LOG "OFFBOX-ONLY: $reason; VPS/KVM fallback is disabled"
  tg "⚠️ Zepto Mac/Windows workflow needs attention: $reason. VPS/KVM fallback is disabled by policy."
  return 1
}

if [ -f "$REPORT" ]; then
  LOG "today's report present — OK"
  exit 0
fi

case "$PASS" in
  launch)
    if mac_running; then
      if mac_stale_previous_run; then
        offbox_failure "stale previous-day Mac Pro Zepto run is still active"
        exit 0
      fi
      LOG "Mac Pro Zepto already running"
      exit 0
    fi
    # Device-team split (laptop worker #4): try laptop shard-1 + Mac shard-0
    # first; if Windows cannot participate, the Mac-only production runner is
    # still allowed. No datacenter fallback is available.
    if [ "${ZEPTO_TEAM_DISABLE:-0}" != "1" ] && tools/laptop/zepto_team_launch.sh >> logs/zepto_team.log 2>&1; then
      LOG "device-team split engaged — laptop shard-1 + Mac shard-0 (logs/zepto_team.log)"
      exit 0
    fi
    if trigger_mac; then
      LOG "Mac Pro Zepto trigger sent"
    else
      offbox_failure "Mac Pro trigger failed at $(date +%H:%M) IST"
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
        offbox_failure "stale previous-day Mac Pro Zepto run is still active"
        exit 0
      fi
      LOG "Mac Pro Zepto still running — waiting"
      exit 0
    fi
    if mac_reachable; then
      if trigger_mac; then LOG "Mac Pro Zepto watchdog trigger sent"; exit 0; fi
    fi
    offbox_failure "no report and Mac Pro is not running"
    ;;
  *)
    LOG "unknown pass '$PASS'"
    exit 2
    ;;
esac
