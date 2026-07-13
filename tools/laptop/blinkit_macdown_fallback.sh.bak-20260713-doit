#!/usr/bin/env bash
# blinkit_macdown_fallback.sh <pass> — goal #81 step 7 (2026-07-13): when the
# Mac Pro is DOWN, prefer the RESIDENTIAL Windows laptop (worker #4) over the
# datacenter KVM1 path for Blinkit. The laptop scrapes shard-1 (WMI-detached,
# same runner pattern as blinkit_team_launch.sh), the VPS scrapes shard-0
# locally (same authenticated env as blinkit_team_watch.sh's proven rescue),
# and blinkit_team_merge.sh reassembles the FULL universe through the normal
# fail-closed ingest gates. Publishing the ACTIVE-blinkit-team pointer means
# the existing team watch (cron */10 06-11) babysits pull/merge/rescue and the
# batch guard's standby logic applies unchanged.
#
# Mac-down concurrency note: the Mac is offline, so the shared Blinkit session
# is NOT in concurrent use by it; laptop+VPS same-token concurrency is the same
# profile as the proven VPS+KVM fallback and the team-watch rescue.
#
# Exit codes: 0 = fallback ENGAGED (or already handled elsewhere) — caller must
# NOT start another fallback; nonzero = could not engage — caller should fall
# through to tools/cron/blinkit_vps_kvm_fallback.sh. Fail-safe by construction:
# any pre-spawn failure cleans up, clears the pointer, and returns nonzero.
#
# Smoke mode: BLINKIT_MACDOWN_PREFLIGHT_ONLY=1 runs split+sync+1-pin live
# laptop preflight, then stops — no pointer, no shard spawns, no ingest.
set -uo pipefail
DIR=/opt/ecom-intel
cd "$DIR" || exit 2
. tools/laptop/lib.sh
PASS="${1:-early}"
LOG(){ echo "[$(date '+%F %T')] blinkit_macdown_fallback($PASS): $*"; }

TODAY="$(date +%F)"
REPORT="output/Jivo-Blinkit-Live-Report-${TODAY}.xlsx"
SOURCE="${BLINKIT_TEAM_SOURCE:-platforms/blinkit/pincodes.daily.json}"
AUTH_LAPTOP="secrets/blinkit-auth-state-laptop.json"
AUTH_VPS="secrets/blinkit-auth-state.json"
CONCURRENCY="${BLINKIT_TEAM_LAPTOP_CONCURRENCY:-2}"
SMOKE="${BLINKIT_MACDOWN_PREFLIGHT_ONLY:-0}"

# Already handled elsewhere -> report "engaged" so the caller does not stack a
# second fallback on top. (Smoke mode skips these — it never writes state, so
# it is safe to exercise even on a day whose report already landed.)
if [ "$SMOKE" != "1" ]; then
  [ -f "$REPORT" ] && { LOG "today's report already present — nothing to do"; exit 0; }
  if id="$(read_active blinkit)"; then
    LOG "a team/fallback run is already active: $id — not stacking another"
    exit 0
  fi
fi

# Cannot engage -> nonzero so the caller uses the VPS+KVM1 path.
[ -s "$AUTH_LAPTOP" ] || { LOG "missing $AUTH_LAPTOP — cannot engage"; exit 2; }
[ -s "$AUTH_VPS" ]    || { LOG "missing $AUTH_VPS — cannot engage"; exit 2; }
[ -s "$SOURCE" ]      || { LOG "missing source config $SOURCE"; exit 2; }
if ! laptop_up; then
  LOG "laptop unreachable — cannot engage"
  exit 2
fi

exec 9>"logs/.blinkit-macdown-fallback.lock"
flock -n 9 || { LOG "another mac-down fallback holds the lock"; exit 0; }

RUN_ID="$(date +%Y%m%d-%H%M%S)-blinkit-macdown"
[ "$SMOKE" = "1" ] && RUN_ID="${RUN_ID}-smoke"
RUN="shards/runs/$RUN_ID/blinkit"
LOG "planning $RUN_ID from $SOURCE (laptop shard-1 + VPS shard-0)"

cleanup_fail(){
  clear_active blinkit "$RUN_ID"
  rm -rf "shards/runs/$RUN_ID"
}

# Pre-split ONLY shard-1 (the laptop's half). Shard-0 is split by
# run_platform_shard.sh itself with the same deterministic index%2 tool, so the
# two halves are complementary by construction.
D1="$RUN/shard-1-of-2"
mkdir -p "$D1"
if ! python3 tools/shards/split_pincodes.py blinkit "$SOURCE" "$D1" \
    --total 2 --index 1 --run-id "$RUN_ID" --role laptop > "$D1/split.log"; then
  LOG "shard-1 split failed"; cleanup_fail; exit 2
fi
SHARD1_CFG="$D1/pincodes.1-of-2.json"
PIN_COUNT1="$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$SHARD1_CFG")"

# --- sync the laptop (pull-at-start parity with blinkit_team_launch.sh) ---
WIN_RUN_FS="$WIN_RUNS_FS/$RUN_ID"
WIN_RUN_BS="$WIN_RUNS_BS\\$RUN_ID"
if ! laptop_mkdir "$WIN_RUN_FS"; then LOG "laptop mkdir failed"; cleanup_fail; exit 2; fi
sync_fail=0
laptop_push platforms/blinkit/scrape.js "$WIN_ECOM_FS/platforms/blinkit/scrape.js" || sync_fail=1
laptop_push "$AUTH_LAPTOP" "$WIN_BASE_FS/secrets/blinkit-auth-state.json" || sync_fail=1
laptop_push "$SHARD1_CFG" "$WIN_RUN_FS/pincodes.json" || sync_fail=1
if [ "$sync_fail" = 1 ]; then
  LOG "laptop sync failed — cannot engage"
  cleanup_fail
  exit 2
fi

# --- 1-pin live auth/store preflight on the laptop (same gates as team launch) ---
python3 - "$SHARD1_CFG" "$RUN/preflight-pincodes.json" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1], encoding="utf-8"))
preferred = next((r for r in rows if str(r.get("pincode")) == "110094"), rows[0])
json.dump([preferred], open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
PY
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
if ! laptop_push "$RUN/preflight-pincodes.json" "$WIN_RUN_FS/preflight-pincodes.json" \
   || ! laptop_push "$RUN/preflight.cmd" "$WIN_RUN_FS/preflight.cmd"; then
  LOG "preflight push failed"; cleanup_fail; exit 2
fi
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
  LOG "laptop preflight FAILED — cannot engage (see $RUN/preflight.verdict)"
  team_tg "⚠️ Blinkit mac-down fallback: laptop 1-pin auth preflight FAILED — falling back to VPS+KVM1. Check the laptop Blinkit session."
  exit 2
fi
LOG "laptop preflight PASS"

if [ "$SMOKE" = "1" ]; then
  LOG "BLINKIT_MACDOWN_PREFLIGHT_ONLY=1 — smoke complete (no pointer, no spawns); artifacts in shards/runs/$RUN_ID"
  exit 0
fi

# --- laptop shard-1 runner (.cmd) — dead-drops back and triggers the merge ---
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
if ! laptop_push "$RUN/laptop.run.cmd" "$WIN_RUN_FS/laptop.run.cmd"; then
  LOG "runner push failed — cannot engage"; cleanup_fail; exit 2
fi

printf '%s\n' "$RUN_ID" > "$(team_ptr_path blinkit)"
if ! laptop_spawn_cmd "$WIN_RUN_BS\\laptop.run.cmd"; then
  LOG "laptop spawn FAILED — clearing pointer; caller should use VPS+KVM1"
  clear_active blinkit "$RUN_ID"
  exit 2
fi
LOG "laptop scraping shard-1 ($PIN_COUNT1 pins, detached)"

# --- VPS shard-0, detached (env mirrors blinkit_team_watch.sh rescue_local; the
# wall cap fits a full ~896-pin half at CONCURRENCY=2, ~14.2ks observed 2026-07-13) ---
nohup bash -c "cd '$DIR' && env \
    BLINKIT_AUTH_STATE_FILE='$DIR/$AUTH_VPS' \
    BLINKIT_REQUIRE_AUTH=1 BLINKIT_OOS_PROBE=1 BLINKIT_PDP_OOS_PROBE=1 \
    BLINKIT_PDP_PRICE_PROBE=1 CONCURRENCY='${BLINKIT_MACDOWN_VPS_CONCURRENCY:-2}' \
    SHARD_ROLE='vps-macdown' \
    timeout --foreground -k 60 ${BLINKIT_MACDOWN_WALL_S:-18000}s \
    tools/shards/run_platform_shard.sh blinkit '$SOURCE' 2 0 '$RUN_ID' \
    >> logs/blinkit_team.log 2>&1; \
  tools/laptop/blinkit_team_merge.sh '$RUN_ID' >> logs/blinkit_team.log 2>&1" \
  >/dev/null 2>&1 &

PIN_COUNT0="$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$SOURCE" 2>/dev/null || echo '?')"
LOG "ENGAGED — run $RUN_ID: laptop shard-1 ($PIN_COUNT1 pins) + VPS shard-0 (universe $PIN_COUNT0, half); merge → normal full-universe gates; team watch babysits"
team_tg "🛟 Blinkit mac-down fallback ENGAGED ($RUN_ID): residential laptop shard-1 (${PIN_COUNT1} pins) + VPS shard-0. Merge goes through the normal fail-closed gates; team watch owns rescue."
exit 0
