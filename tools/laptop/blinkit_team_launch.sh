#!/usr/bin/env bash
# blinkit_team_launch.sh — Blinkit device-team split: the Windows laptop
# (worker #4) takes HALF the daily pincode universe, the Mac Pro the other half.
# Owner ruling 2026-07-12: laptop is a first-class daily worker, not a fallback.
#
# Cron 06:15 IST (before the Mac's 06:30 launchd run). Flow:
#   1. Preconditions — no report yet, no active team run, Mac NOT flagged
#      offline, BOTH Mac and laptop reachable. Any miss -> exit silently and
#      today runs exactly like before (full universe on the Mac / existing
#      guards). Fail-safe: no pointer file, no behavior change.
#   2. Deterministic 2-way split (tools/shards/split_pincodes.py, index % 2)
#      into shards/runs/<RUN_ID>/blinkit/shard-{0,1}-of-2/.
#   3. Sync reviewed scrape.js + auth state + shard-1 config to the laptop and
#      run a 1-pin live auth/store preflight there (same gates as the Mac
#      wrapper). Preflight failure -> abort split, Mac runs the full list.
#   4. Publish shards/runs/ACTIVE-blinkit-team; the 06:30 Mac wrapper sees it
#      and scrapes shard-0 instead of the full list.
#   5. WMI-launch the laptop shard detached. Its .cmd dead-drops result.json to
#      shards/runs/<RUN_ID>/blinkit/shard-1-of-2/ and triggers
#      blinkit_team_merge.sh; blinkit_team_watch.sh (cron */10) is the backstop
#      collector/rescuer. Merge rebuilds the FULL 1791-pin set, so every
#      ingest.sh gate runs unchanged.
set -uo pipefail
DIR=/opt/ecom-intel
cd "$DIR" || exit 0
. tools/laptop/lib.sh
LOG(){ echo "[$(date '+%F %T')] blinkit_team_launch: $*"; }

TODAY="$(date +%F)"
REPORT="output/Jivo-Blinkit-Live-Report-${TODAY}.xlsx"
SOURCE="${BLINKIT_TEAM_SOURCE:-platforms/blinkit/pincodes.daily.json}"
AUTH_LAPTOP="secrets/blinkit-auth-state-laptop.json"
CONCURRENCY="${BLINKIT_TEAM_LAPTOP_CONCURRENCY:-3}"   # 2->3 (2026-07-13): keep merge comfortably ahead of the 11:00 deadline

[ -f "$REPORT" ] && { LOG "today's report already present — nothing to do"; exit 0; }
if [ -f logs/.mac-offline ]; then
  LOG "Mac flagged offline — VPS+KVM fallback owns today; not splitting"
  exit 0
fi
if id="$(read_active blinkit)"; then
  LOG "team run already active: $id"
  exit 0
fi

exec 9>"logs/.blinkit-team-launch.lock"
flock -n 9 || { LOG "another launch holds the lock"; exit 0; }

if ! timeout 30 ssh -o BatchMode=yes -o ConnectTimeout=10 macpro "exit 0" >/dev/null 2>&1; then
  LOG "Mac Pro unreachable — not splitting (guards own Mac-down recovery)"
  exit 0
fi
if ! laptop_up; then
  LOG "laptop unreachable — Mac runs the full universe today"
  team_tg "ℹ️ Blinkit 06:15: laptop unreachable — no split today, Mac takes the full ${TODAY} universe."
  exit 0
fi
[ -s "$AUTH_LAPTOP" ] || { LOG "missing $AUTH_LAPTOP — cannot run laptop shard"; exit 0; }
[ -s "$SOURCE" ] || { LOG "missing source config $SOURCE"; exit 1; }

RUN_ID="$(date +%Y%m%d-%H%M%S)-blinkit-team"
RUN="shards/runs/$RUN_ID/blinkit"
LOG "planning $RUN_ID from $SOURCE"

for i in 0 1; do
  d="$RUN/shard-$i-of-2"
  mkdir -p "$d"
  role=macpro; [ "$i" = 1 ] && role=laptop
  python3 tools/shards/split_pincodes.py blinkit "$SOURCE" "$d" \
    --total 2 --index "$i" --run-id "$RUN_ID" --role "$role" > "$d/split.log" || {
      LOG "split failed for shard $i"; rm -rf "shards/runs/$RUN_ID"; exit 1; }
done
SHARD1_CFG="$RUN/shard-1-of-2/pincodes.1-of-2.json"
PIN_COUNT1="$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$SHARD1_CFG")"

# --- sync the laptop (pull-at-start parity with the Mac wrapper) ---
WIN_RUN_FS="$WIN_RUNS_FS/$RUN_ID"
WIN_RUN_BS="$WIN_RUNS_BS\\$RUN_ID"
if ! laptop_mkdir "$WIN_RUN_FS"; then LOG "laptop mkdir failed"; rm -rf "shards/runs/$RUN_ID"; exit 1; fi
sync_fail=0
laptop_push platforms/blinkit/scrape.js "$WIN_ECOM_FS/platforms/blinkit/scrape.js" || sync_fail=1
laptop_push "$AUTH_LAPTOP" "$WIN_BASE_FS/secrets/blinkit-auth-state.json" || sync_fail=1
laptop_push "$SHARD1_CFG" "$WIN_RUN_FS/pincodes.json" || sync_fail=1
if [ "$sync_fail" = 1 ]; then
  LOG "laptop sync failed — Mac runs the full universe today"
  team_tg "⚠️ Blinkit 06:15: laptop sync failed — no split today, Mac takes the full list."
  rm -rf "shards/runs/$RUN_ID"
  exit 1
fi

# --- 1-pin live auth/store preflight on the laptop (same gates as the Mac) ---
if [ "${BLINKIT_TEAM_SKIP_PREFLIGHT:-0}" != "1" ]; then
  python3 - "$SHARD1_CFG" "$RUN/preflight-pincodes.json" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1], encoding="utf-8"))
preferred = next((r for r in rows if str(r.get("pincode")) == "110094"), rows[0])
json.dump([preferred], open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
PY
  laptop_push "$RUN/preflight-pincodes.json" "$WIN_RUN_FS/preflight-pincodes.json" || sync_fail=1
  cat > "$RUN/preflight.cmd" <<EOF
@echo off
cd /d "$WIN_ECOM_BS\\platforms\\blinkit"
set "BLINKIT_AUTH_STATE_FILE=$WIN_BASE_BS\\secrets\\blinkit-auth-state.json"
set "BLINKIT_REQUIRE_AUTH=1"
set "BLINKIT_OOS_PROBE=0"
set "BLINKIT_PDP_OOS_PROBE=0"
set "BLINKIT_PDP_PRICE_PROBE=0"
set "CONCURRENCY=1"
set "BLINKIT_CHROMIUM_EXECUTABLE=$WIN_CHROMIUM"
set "PINCODES_FILE=$WIN_RUN_BS\\preflight-pincodes.json"
set "OUT_FILE=$WIN_RUN_BS\\preflight.json"
set "BLINKIT_PROGRESS_FILE=$WIN_RUN_BS\\preflight.progress.json"
node scrape.js 1>"$WIN_RUN_BS\\preflight.stdout" 2>"$WIN_RUN_BS\\preflight.log"
exit /b %ERRORLEVEL%
EOF
  sed -i 's/$/\r/' "$RUN/preflight.cmd"
  laptop_push "$RUN/preflight.cmd" "$WIN_RUN_FS/preflight.cmd" || sync_fail=1
  [ "$sync_fail" = 1 ] && { LOG "preflight push failed"; rm -rf "shards/runs/$RUN_ID"; exit 1; }
  LOG "running 1-pin live auth/store preflight on the laptop"
  timeout 300 ssh -o BatchMode=yes -o ConnectTimeout=15 "$LAPTOP_HOST" \
    "cmd /c \"$WIN_RUN_BS\\preflight.cmd\"" >/dev/null 2>&1
  laptop_pull "$WIN_RUN_FS/preflight.json" "$RUN/preflight.json" || true
  if ! python3 - "$RUN/preflight.json" >> "$RUN/preflight.verdict" 2>&1 <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8")); s = d.get("summary") or {}
per = d.get("perPin") or []
ok = (s.get("auth_session") == 1 and s.get("auth_required") == 1
      and s.get("auth_verified") == 1 and s.get("auth_verified_pincodes") == 1
      and s.get("pincodes_total") == 1 and s.get("pincodes_resolved") == 1
      and len(per) == 1 and per[0].get("auth_accepted") == 1
      and not per[0].get("blocked"))
print({"auth_preflight_ok": ok, "summary": s})
if not ok:
    raise SystemExit("laptop Blinkit live auth/store preflight failed")
PY
  then
    LOG "laptop preflight FAILED — no split today, Mac takes the full list (see $RUN/preflight.verdict)"
    team_tg "⚠️ Blinkit 06:15: laptop 1-pin auth preflight FAILED — no split today; Mac runs the full ${TODAY} universe. Check the laptop Blinkit session."
    rm -f "$RUN/preflight-pincodes.json"
    exit 1
  fi
  LOG "laptop preflight PASS"
fi

# --- full shard runner (.cmd) — dead-drops back and triggers the merge ---
cat > "$RUN/laptop.run.cmd" <<EOF
@echo off
cd /d "$WIN_ECOM_BS\\platforms\\blinkit"
set "BLINKIT_AUTH_STATE_FILE=$WIN_BASE_BS\\secrets\\blinkit-auth-state.json"
set "BLINKIT_REQUIRE_AUTH=1"
set "BLINKIT_OOS_PROBE=1"
set "BLINKIT_PDP_OOS_PROBE=1"
set "BLINKIT_PDP_PRICE_PROBE=1"
set "CONCURRENCY=$CONCURRENCY"
set "BLINKIT_CHROMIUM_EXECUTABLE=$WIN_CHROMIUM"
set "PINCODES_FILE=$WIN_RUN_BS\\pincodes.json"
set "OUT_FILE=$WIN_RUN_BS\\result.json"
set "BLINKIT_PROGRESS_FILE=$WIN_RUN_BS\\run.progress.json"
node scrape.js 1>"$WIN_RUN_BS\\run.stdout" 2>"$WIN_RUN_BS\\run.log"
set "RC=%ERRORLEVEL%"
>"$WIN_RUN_BS\\run.rc" echo %RC%
>"$WIN_RUN_BS\\run.done" echo %DATE% %TIME%
scp -q -o BatchMode=yes -o ConnectTimeout=20 "$WIN_RUN_BS\\run.rc" "$WIN_RUN_BS\\run.done" vps-bridge:/opt/ecom-intel/$RUN/shard-1-of-2/
if exist "$WIN_RUN_BS\\result.json" scp -q -o BatchMode=yes -o ConnectTimeout=20 "$WIN_RUN_BS\\result.json" vps-bridge:/opt/ecom-intel/$RUN/shard-1-of-2/result.json
scp -q -o BatchMode=yes -o ConnectTimeout=20 "$WIN_RUN_BS\\run.log" vps-bridge:/opt/ecom-intel/$RUN/shard-1-of-2/laptop.run.log
ssh -o BatchMode=yes -o ConnectTimeout=20 vps-bridge "cd /opt/ecom-intel && nohup tools/laptop/blinkit_team_merge.sh '$RUN_ID' >> logs/blinkit_team.log 2>&1 </dev/null &"
exit /b %RC%
EOF
sed -i 's/$/\r/' "$RUN/laptop.run.cmd"
laptop_push "$RUN/laptop.run.cmd" "$WIN_RUN_FS/laptop.run.cmd" || {
  LOG "runner push failed"; exit 1; }

printf '%s\n' "$RUN_ID" > "$(team_ptr_path blinkit)"
if ! laptop_spawn_cmd "$WIN_RUN_BS\\laptop.run.cmd"; then
  LOG "laptop spawn FAILED — clearing pointer; Mac runs the full list"
  clear_active blinkit "$RUN_ID"
  team_tg "⚠️ Blinkit 06:15: laptop shard spawn failed — no split today; Mac runs the full list."
  exit 1
fi
PIN_COUNT0="$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$RUN/shard-0-of-2/pincodes.0-of-2.json")"
LOG "team run $RUN_ID LIVE — laptop scraping shard-1 ($PIN_COUNT1 pins); Mac will take shard-0 ($PIN_COUNT0 pins) at 06:30"
team_tg "🚀 Blinkit device-team ${TODAY}: laptop started shard-1 (${PIN_COUNT1} pins), Mac takes shard-0 (${PIN_COUNT0} pins) at 06:30. Merge → normal full-universe gates."
exit 0
