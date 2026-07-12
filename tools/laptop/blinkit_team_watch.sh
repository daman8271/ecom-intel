#!/usr/bin/env bash
# blinkit_team_watch.sh — cron */10 06-09 IST backstop for the Blinkit
# device-team split (Mac shard-0 + Windows laptop shard-1).
#
# Duties, in order:
#   1. No active team run today -> exit (read_active clears stale pointers).
#   2. Report already built -> clear pointer, exit.
#   3. Pull laptop artifacts that the laptop's own scp push may have missed
#      (tunnel blip): result.json / run.rc / run.done / run.log.
#   4. Both shard results present -> run blinkit_team_merge.sh (idempotent).
#   5. Rescue: a shard is missing, its device is NOT working on it, and the run
#      is >15 min old ->
#        shard-0 (Mac): re-trigger the Mac wrapper once (it re-enters team mode
#          and re-scrapes shard-0); if still nothing 40 min later, scrape the
#          shard locally on the VPS (authenticated, same env as the proven
#          VPS+KVM fallback).
#        shard-1 (laptop): scrape the shard locally on the VPS.
#      Each rescue fires once (marker files) and chains straight into merge.
set -uo pipefail
DIR=/opt/ecom-intel
cd "$DIR" || exit 0
. tools/laptop/lib.sh
LOG(){ echo "[$(date '+%F %T')] blinkit_team_watch: $*"; }

RUN_ID="$(read_active blinkit)" || exit 0
RUN="shards/runs/$RUN_ID/blinkit"
TODAY="$(date +%F)"
REPORT="output/Jivo-Blinkit-Live-Report-${TODAY}.xlsx"
WRAPPER="/Users/danny./VPS-Migration/scripts/run_blinkit_mac_to_vps.sh"
WIN_RUN_FS="$WIN_RUNS_FS/$RUN_ID"

if [ -f "$REPORT" ] || [ -f "$RUN/.ingested" ]; then
  clear_active blinkit "$RUN_ID"
  exit 0
fi

exec 9>"logs/.blinkit-team-watch.lock"
flock -n 9 || exit 0

R0="$RUN/shard-0-of-2/result.json"
R1="$RUN/shard-1-of-2/result.json"

# 3. backstop-pull laptop artifacts
if [ ! -s "$R1" ] && laptop_up; then
  for f in result.json run.rc run.done run.log; do
    laptop_pull "$WIN_RUN_FS/$f" "$RUN/shard-1-of-2/$f" || true
  done
  [ -s "$R1" ] && LOG "pulled laptop shard-1 result via backstop scp"
fi

# 4. merge when complete
if [ -s "$R0" ] && [ -s "$R1" ]; then
  LOG "both shards present — merging"
  tools/laptop/blinkit_team_merge.sh "$RUN_ID" >> logs/blinkit_team.log 2>&1
  exit 0
fi

# 5. rescue logic
PTR="$(team_ptr_path blinkit)"
AGE=$(( $(date +%s) - $(stat -c %Y "$PTR" 2>/dev/null || date +%s) ))
[ "$AGE" -lt 900 ] && { LOG "run is ${AGE}s old — devices still warming up"; exit 0; }

mac_working() {
  timeout 30 ssh -o BatchMode=yes -o ConnectTimeout=15 macpro \
    "pgrep -f run_blinkit_mac_to_vps.sh >/dev/null" >/dev/null 2>&1
}
laptop_working() {
  laptop_file_fresh "$WIN_RUN_FS/run.progress.json" 1500 && return 0
  laptop_file_fresh "$WIN_RUN_FS/run.stdout" 1500
}
rescue_local() {
  local idx="$1" marker="$RUN/.rescue-$1"
  [ -f "$marker" ] && return 0
  touch "$marker"
  LOG "RESCUE: scraping shard-$idx locally on the VPS (authenticated)"
  team_tg "🛠 Blinkit team watch: shard-$idx of $RUN_ID has no result and its device is idle — rescuing that half on the VPS now."
  nohup bash -c "cd '$DIR' && env \
      BLINKIT_AUTH_STATE_FILE='$DIR/secrets/blinkit-auth-state.json' \
      BLINKIT_REQUIRE_AUTH=1 BLINKIT_OOS_PROBE=1 BLINKIT_PDP_OOS_PROBE=1 \
      BLINKIT_PDP_PRICE_PROBE=1 CONCURRENCY='${BLINKIT_TEAM_RESCUE_CONCURRENCY:-2}' \
      SHARD_ROLE='vps-rescue' \
      timeout --foreground -k 60 9000s \
      tools/shards/run_platform_shard.sh blinkit platforms/blinkit/pincodes.daily.json 2 '$idx' '$RUN_ID' \
      >> logs/blinkit_team.log 2>&1; \
    tools/laptop/blinkit_team_merge.sh '$RUN_ID' >> logs/blinkit_team.log 2>&1" \
    >/dev/null 2>&1 &
}

if pgrep -f "run_platform_shard.sh blinkit" >/dev/null 2>&1; then
  LOG "a local shard rescue is already running — waiting"
  exit 0
fi

if [ ! -s "$R0" ]; then
  if mac_working; then
    LOG "Mac still scraping shard-0 — waiting"
  elif [ ! -f "$RUN/.mac-retrigger" ]; then
    touch "$RUN/.mac-retrigger"
    LOG "shard-0 missing and Mac idle — re-triggering the Mac wrapper (team mode re-entry)"
    team_tg "🛠 Blinkit team watch: Mac shard-0 of $RUN_ID missing with Mac idle — re-triggered the Mac wrapper."
    timeout 30 ssh -o BatchMode=yes -o ConnectTimeout=15 macpro \
      "nohup $WRAPPER >/tmp/blinkit-team-retrigger.log 2>&1 & disown" >/dev/null 2>&1 \
      || rescue_local 0
  elif [ $(( $(date +%s) - $(stat -c %Y "$RUN/.mac-retrigger") )) -gt 2400 ]; then
    rescue_local 0
  else
    LOG "Mac re-trigger sent recently — giving it time"
  fi
fi

if [ ! -s "$R1" ]; then
  if laptop_working; then
    LOG "laptop still scraping shard-1 — waiting"
  else
    rescue_local 1
  fi
fi
exit 0
