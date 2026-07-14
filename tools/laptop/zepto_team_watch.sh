#!/usr/bin/env bash
# zepto_team_watch.sh — backstop for the Zepto device-team split. Called by
# zepto_macpro_guard.sh (watchdog 08:35 / late 09:10 passes) and by its own
# light cron (*/10 08-09).
#
# Exit code contract for the guard:
#   0 = an active team run exists and is being handled on Mac/Windows.
#   3 = no active team run; the guard may start a new Mac/Windows run.
set -uo pipefail
DIR=/opt/ecom-intel
cd "$DIR" || exit 3
. tools/laptop/lib.sh
LOG(){ echo "[$(date '+%F %T')] zepto_team_watch: $*"; }

RUN_ID="$(read_active zepto)" || exit 3
RUN="shards/runs/$RUN_ID/zepto"
TODAY="$(date +%F)"
REPORT="output/Jivo-Zepto-Live-Report-${TODAY}.xlsx"
WRAPPER="/Users/danny./VPS-Migration/scripts/run_zepto_mac_to_vps.sh"
MAC_PROJECT="/Users/danny./VPS-Migration/imported/ecom-intel/platforms/zepto"
WIN_RUN_FS="$WIN_RUNS_FS/$RUN_ID"

if [ -f "$REPORT" ] || [ -f "$RUN/.ingested" ]; then
  clear_active zepto "$RUN_ID"
  exit 0
fi

exec 9>"logs/.zepto-team-watch.lock"
flock -n 9 || exit 0

R0="$RUN/shard-0-of-2/result.json"
R1="$RUN/shard-1-of-2/result.json"

# backstop-pull laptop artifacts the laptop's own push may have missed
if [ ! -s "$R1" ] && laptop_up; then
  for f in result.json run.rc run.done run.log; do
    laptop_pull "$WIN_RUN_FS/$f" "$RUN/shard-1-of-2/$f" || true
  done
  [ -s "$R1" ] && LOG "pulled laptop shard-1 result via backstop scp"
fi

if [ -s "$R0" ] && [ -s "$R1" ]; then
  LOG "both shards present — merging"
  tools/laptop/zepto_team_merge.sh "$RUN_ID" >> logs/zepto_team.log 2>&1
  exit 0
fi

PTR="$(team_ptr_path zepto)"
AGE=$(( $(date +%s) - $(stat -c %Y "$PTR" 2>/dev/null || date +%s) ))
[ "$AGE" -lt 900 ] && { LOG "run is ${AGE}s old — devices still warming up"; exit 0; }

mac_working() {
  timeout 30 ssh -o BatchMode=yes -o ConnectTimeout=15 macpro \
    "pgrep -f 'run_zepto_mac_to_vps.sh|platforms/zepto/scrape.js' >/dev/null" >/dev/null 2>&1
}
laptop_working() {
  [ -s "$RUN/shard-1-of-2/run.done" ] && return 1
  laptop_file_fresh "$WIN_ECOM_FS/platforms/zepto/.progress.${TODAY}.json" 1200
}
retry_due() {
  local marker="$1" interval="${2:-600}"
  [ ! -e "$marker" ] && return 0
  [ $(( $(date +%s) - $(stat -c %Y "$marker" 2>/dev/null || echo 0) )) -ge "$interval" ]
}
retry_mac() {
  local marker="$RUN/.mac-retry" cfg="$MAC_PROJECT/mac-runs/team-${RUN_ID}-pincodes.json"
  retry_due "$marker" || return 0
  touch "$marker"
  LOG "Mac shard-0 missing and idle — retrying Mac wrapper"
  timeout 30 ssh -o BatchMode=yes -o ConnectTimeout=15 macpro \
    "nohup env PINCODES_FILE='$cfg' '$WRAPPER' >/tmp/zepto-team-shard0-retry.log 2>&1 & disown" >/dev/null 2>&1 || true
}
retry_laptop() {
  local marker="$RUN/.laptop-retry"
  retry_due "$marker" || return 0
  touch "$marker"
  LOG "laptop shard-1 missing and stale — retrying resumable Windows runner"
  laptop_spawn_cmd "$WIN_RUNS_BS\\$RUN_ID\\laptop.run.cmd" || true
}

handled=0
if [ ! -s "$R0" ]; then
  if mac_working; then
    LOG "Mac still scraping shard-0 — waiting"; handled=1
  else
    retry_mac; handled=1
    if [ ! -f "$RUN/.mac-alerted" ]; then
      touch "$RUN/.mac-alerted"
      team_tg "⚠️ Zepto team watch: Mac shard-0 is missing and idle; retrying on Mac. VPS/KVM fallback remains disabled."
    fi
  fi
fi
if [ ! -s "$R1" ]; then
  if laptop_working; then
    LOG "laptop still scraping shard-1 — waiting"; handled=1
  else
    retry_laptop; handled=1
    if [ ! -f "$RUN/.laptop-alerted" ]; then
      touch "$RUN/.laptop-alerted"
      team_tg "⚠️ Zepto team watch: Windows shard-1 is missing/stale; retrying on Windows. VPS/KVM fallback remains disabled."
    fi
  fi
fi
[ -s "$R0" ] && [ -s "$R1" ] && handled=1

if [ "$handled" = 0 ]; then
  LOG "team run $RUN_ID is stuck on Mac/Windows; keeping pointer for resumable retries"
fi
exit 0
