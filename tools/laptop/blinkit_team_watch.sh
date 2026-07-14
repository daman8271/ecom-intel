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
#   5. Recovery: retry a missing shard only on its assigned Mac/Windows device.
#      Datacenter scraping is prohibited for Blinkit production.
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
    "pgrep -f 'run_blinkit_mac_to_vps.sh|platforms/blinkit/scrape.js|OUT_FILE=.*blinkit-' >/dev/null" >/dev/null 2>&1
}
laptop_working() {
  laptop_file_fresh "$WIN_RUN_FS/run.progress.json" 1500 && return 0
  laptop_file_fresh "$WIN_RUN_FS/run.stdout" 1500
}
retry_due() {
  local marker="$1" interval="${2:-600}"
  [ ! -e "$marker" ] && return 0
  [ $(( $(date +%s) - $(stat -c %Y "$marker" 2>/dev/null || echo 0) )) -ge "$interval" ]
}

if [ ! -s "$R0" ]; then
  if mac_working; then
    LOG "Mac still scraping shard-0 — waiting"
  elif retry_due "$RUN/.mac-retrigger"; then
    touch "$RUN/.mac-retrigger"
    LOG "shard-0 missing and Mac idle — re-triggering the Mac wrapper"
    [ -f "$RUN/.mac-alerted" ] || {
      touch "$RUN/.mac-alerted"
      team_tg "⚠️ Blinkit team watch: Mac shard-0 of $RUN_ID is missing/idle; retrying on Mac. VPS fallback is disabled."
    }
    timeout 30 ssh -o BatchMode=yes -o ConnectTimeout=15 macpro \
      "nohup $WRAPPER >/tmp/blinkit-team-retrigger.log 2>&1 & disown" >/dev/null 2>&1 \
      || true
  else
    LOG "Mac retry is inside the cooldown window"
  fi
fi

if [ ! -s "$R1" ]; then
  if laptop_working; then
    LOG "laptop still scraping shard-1 — waiting"
  elif retry_due "$RUN/.laptop-retrigger"; then
    touch "$RUN/.laptop-retrigger"
    LOG "laptop shard-1 missing/stale — retrying resumable Windows runner"
    [ -f "$RUN/.laptop-alerted" ] || {
      touch "$RUN/.laptop-alerted"
      team_tg "⚠️ Blinkit team watch: Windows shard-1 of $RUN_ID is missing/stale; retrying on Windows. VPS fallback is disabled."
    }
    laptop_spawn_cmd "$WIN_RUNS_BS\\$RUN_ID\\laptop.run.cmd" || true
  fi
fi
exit 0
