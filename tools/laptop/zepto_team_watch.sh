#!/usr/bin/env bash
# zepto_team_watch.sh — backstop for the Zepto device-team split. Called by
# zepto_macpro_guard.sh (watchdog 08:35 / late 09:10 passes) and by its own
# light cron (*/10 08-09).
#
# Exit code contract for the guard:
#   0 = an active team run exists and is being handled (working / merged /
#       rescued) — the guard should exit without legacy action this pass.
#   3 = no active team run (or the team run was abandoned and the pointer
#       cleared) — the guard proceeds with its legacy logic.
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
  laptop_file_fresh "$WIN_RUN_FS/run.stdout" 1200
}
rescue_local() {
  local idx="$1" marker="$RUN/.rescue-$1"
  [ -f "$marker" ] && return 1
  touch "$marker"
  LOG "RESCUE: scraping shard-$idx locally on the VPS"
  team_tg "🛠 Zepto team watch: shard-$idx of $RUN_ID has no result and its device is idle — rescuing that half on the VPS now."
  nohup bash -c "cd '$DIR' && env SHARD_ROLE='vps-rescue' CONCURRENCY='${ZEPTO_TEAM_RESCUE_CONCURRENCY:-3}' \
      timeout --foreground -k 60 7200s \
      tools/shards/run_platform_shard.sh zepto platforms/zepto/pincodes.daily.json 2 '$idx' '$RUN_ID' \
      >> logs/zepto_team.log 2>&1; \
    tools/laptop/zepto_team_merge.sh '$RUN_ID' >> logs/zepto_team.log 2>&1" \
    >/dev/null 2>&1 &
  return 0
}

if pgrep -f "run_platform_shard.sh zepto" >/dev/null 2>&1; then
  LOG "a local shard rescue is already running — waiting"
  exit 0
fi

handled=0
if [ ! -s "$R0" ]; then
  if mac_working; then
    LOG "Mac still scraping shard-0 — waiting"; handled=1
  elif rescue_local 0; then
    handled=1
  fi
fi
if [ ! -s "$R1" ]; then
  if laptop_working; then
    LOG "laptop still scraping shard-1 — waiting"; handled=1
  elif rescue_local 1; then
    handled=1
  fi
fi
[ -s "$R0" ] && [ -s "$R1" ] && handled=1

if [ "$handled" = 0 ]; then
  LOG "team run $RUN_ID is stuck with rescues already burned — clearing pointer, guard goes legacy"
  team_tg "⚠️ Zepto team run $RUN_ID abandoned (shards missing, rescues exhausted). Guard falls back to a full run."
  clear_active zepto "$RUN_ID"
  exit 3
fi
exit 0
