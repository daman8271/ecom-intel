#!/usr/bin/env bash
# zepto_team_launch.sh — Zepto device-team split: Windows laptop (worker #4)
# scrapes HALF the daily pincode universe, the Mac Pro the other half.
# Called by zepto_macpro_guard.sh (launch pass, 07:25 IST).
#
# Exit code contract for the guard:
#   0 = team split engaged (laptop shard-1 spawned; Mac shard-0 is triggered or
#       left queued for the device-only watcher).
#   1 = split not possible — guard proceeds with the legacy full-universe path.
#
# Zepto shards run only on the Mac Pro and Windows laptop. The VPS is not a
# production scraper or merge fallback.
# Results reassemble via merge_platform_shards.py (union must equal the full
# source list) and ingest through the untouched run.sh SCRAPE_RESULT_DROP path,
# so every review/selfheal baseline gate sees full-universe counts.
set -uo pipefail
DIR=/opt/ecom-intel
cd "$DIR" || exit 1
. tools/laptop/lib.sh
LOG(){ echo "[$(date '+%F %T')] zepto_team_launch: $*"; }

TODAY="$(date +%F)"
REPORT="output/Jivo-Zepto-Live-Report-${TODAY}.xlsx"
SOURCE="${ZEPTO_TEAM_SOURCE:-platforms/zepto/pincodes.daily.json}"
WRAPPER="/Users/danny./VPS-Migration/scripts/run_zepto_mac_to_vps.sh"
MAC_PROJECT="/Users/danny./VPS-Migration/imported/ecom-intel/platforms/zepto"
CONCURRENCY="${ZEPTO_TEAM_LAPTOP_CONCURRENCY:-3}"

[ -f "$REPORT" ] && { LOG "today's report already present"; exit 1; }
if id="$(read_active zepto)"; then
  LOG "team run already active: $id"
  exit 0
fi
exec 9>"logs/.zepto-team-launch.lock"
flock -n 9 || { LOG "another launch holds the lock"; exit 1; }
laptop_up || { LOG "laptop unreachable — legacy full run"; exit 1; }
[ -s "$SOURCE" ] || { LOG "missing source config $SOURCE"; exit 1; }

RUN_ID="$(date +%Y%m%d-%H%M%S)-zepto-team"
RUN="shards/runs/$RUN_ID/zepto"
LOG "planning $RUN_ID from $SOURCE"

for i in 0 1; do
  d="$RUN/shard-$i-of-2"
  mkdir -p "$d"
  role=macpro; [ "$i" = 1 ] && role=laptop
  python3 tools/shards/split_pincodes.py zepto "$SOURCE" "$d" \
    --total 2 --index "$i" --run-id "$RUN_ID" --role "$role" > "$d/split.log" || {
      LOG "split failed for shard $i"; rm -rf "shards/runs/$RUN_ID"; exit 1; }
done
SHARD0_CFG="$RUN/shard-0-of-2/pincodes.0-of-2.json"
SHARD1_CFG="$RUN/shard-1-of-2/pincodes.1-of-2.json"
PINS0="$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$SHARD0_CFG")"
PINS1="$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$SHARD1_CFG")"

# --- laptop shard-1 ---
WIN_RUN_FS="$WIN_RUNS_FS/$RUN_ID"
WIN_RUN_BS="$WIN_RUNS_BS\\$RUN_ID"
if ! laptop_mkdir "$WIN_RUN_FS"; then LOG "laptop mkdir failed"; rm -rf "shards/runs/$RUN_ID"; exit 1; fi
sync_fail=0
laptop_push platforms/zepto/scrape.js "$WIN_ECOM_FS/platforms/zepto/scrape.js" || sync_fail=1
laptop_push "$SHARD1_CFG" "$WIN_RUN_FS/pincodes.json" || sync_fail=1
if [ "$sync_fail" = 1 ]; then
  LOG "laptop sync failed — legacy full run"
  rm -rf "shards/runs/$RUN_ID"
  exit 1
fi
cat > "$RUN/laptop.run.cmd" <<EOF
@echo off
cd /d "$WIN_ECOM_BS\\platforms\\zepto"
set "CONCURRENCY=$CONCURRENCY"
set "ZEPTO_SEED_VARIANTS=1"
set "PINCODES_FILE=$WIN_RUN_BS\\pincodes.json"
set "OUT_FILE=$WIN_RUN_BS\\result.json"
node scrape.js 1>"$WIN_RUN_BS\\run.stdout" 2>"$WIN_RUN_BS\\run.log"
set "RC=%ERRORLEVEL%"
>"$WIN_RUN_BS\\run.rc" echo %RC%
>"$WIN_RUN_BS\\run.done" echo %DATE% %TIME%
scp -q -o BatchMode=yes -o ConnectTimeout=20 "$WIN_RUN_BS\\run.rc" "$WIN_RUN_BS\\run.done" vps-bridge:/opt/ecom-intel/$RUN/shard-1-of-2/
if exist "$WIN_RUN_BS\\result.json" scp -q -o BatchMode=yes -o ConnectTimeout=20 "$WIN_RUN_BS\\result.json" vps-bridge:/opt/ecom-intel/$RUN/shard-1-of-2/result.json
scp -q -o BatchMode=yes -o ConnectTimeout=20 "$WIN_RUN_BS\\run.log" vps-bridge:/opt/ecom-intel/$RUN/shard-1-of-2/laptop.run.log
ssh -o BatchMode=yes -o ConnectTimeout=20 vps-bridge "cd /opt/ecom-intel && nohup tools/laptop/zepto_team_merge.sh '$RUN_ID' >> logs/zepto_team.log 2>&1 </dev/null &"
exit /b %RC%
EOF
sed -i 's/$/\r/' "$RUN/laptop.run.cmd"
laptop_push "$RUN/laptop.run.cmd" "$WIN_RUN_FS/laptop.run.cmd" || {
  LOG "runner push failed — legacy full run"; rm -rf "shards/runs/$RUN_ID"; exit 1; }

printf '%s\n' "$RUN_ID" > "$(team_ptr_path zepto)"
if ! laptop_spawn_cmd "$WIN_RUN_BS\\laptop.run.cmd"; then
  LOG "laptop spawn FAILED — clearing pointer; legacy full run"
  clear_active zepto "$RUN_ID"
  exit 1
fi
LOG "laptop scraping shard-1 ($PINS1 pins)"

# --- Mac shard-0 (env PINCODES_FILE — zero Mac-side script changes) ---
MAC_CFG="$MAC_PROJECT/mac-runs/team-${RUN_ID}-pincodes.json"
mac_ok=1
timeout 30 ssh -o BatchMode=yes -o ConnectTimeout=15 macpro "mkdir -p '$MAC_PROJECT/mac-runs'" >/dev/null 2>&1 || mac_ok=0
if [ "$mac_ok" = 1 ]; then
  rsync -az -e "ssh -o BatchMode=yes -o ConnectTimeout=15" "$SHARD0_CFG" "macpro:$MAC_CFG" >/dev/null 2>&1 || mac_ok=0
fi
if [ "$mac_ok" = 1 ]; then
  timeout 30 ssh -o BatchMode=yes -o ConnectTimeout=15 macpro \
    "nohup env PINCODES_FILE='$MAC_CFG' '$WRAPPER' >/tmp/zepto-team-shard0.log 2>&1 & disown" >/dev/null 2>&1 || mac_ok=0
fi
if [ "$mac_ok" = 1 ]; then
  LOG "Mac triggered on shard-0 ($PINS0 pins)"
  team_tg "🚀 Zepto device-team ${TODAY}: laptop shard-1 (${PINS1} pins) + Mac shard-0 (${PINS0} pins) launched. Merge → normal gates."
else
  touch "$RUN/.mac-launch-pending"
  LOG "Mac trigger failed — shard-0 queued for Mac-only watcher retry"
  team_tg "⚠️ Zepto device-team ${TODAY}: laptop shard-1 (${PINS1} pins) launched, but Mac shard-0 (${PINS0} pins) is queued for retry. VPS/KVM fallback is disabled."
fi
exit 0
