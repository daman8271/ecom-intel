#!/usr/bin/env bash
# blinkit_rescue_resume.sh <run_id> [shard_index] — agent-2 (fleet-blinkfix).
#
# RESUMABLE VPS rescue for a dead Blinkit device-team shard. Instead of the old
# rescue_local() behaviour (re-scrape the ENTIRE shard from scratch at C=2 once
# the Mac is provably idle — mathematically unable to hit 10:30), this:
#   1. Claims an anti-double-scrape marker (whoever writes it first wins), so the
#      Mac-side resume (agent-5) and this VPS rescue never scrape the same pins.
#   2. Pulls the Mac's in-progress partial READ-ONLY (progress/out-file), keeps
#      the pins that already passed every per-pin ingest gate, and computes the
#      REMAINING pins only.
#   3. Scrapes ONLY the remaining pins on the VPS at C=3 (override
#      BLINKIT_TEAM_RESCUE_CONCURRENCY), with a wall sized to the remaining count.
#   4. Combines kept-partial + rescue into one shard result.json that is
#      indistinguishable from a clean full shard, then chains team-merge.
#
# Fail-safe by construction: a missing/corrupt/0-pin partial degrades to a full
# rescue; a partial that already covers the whole shard skips scraping entirely.
# All output still passes 100% through the normal fail-closed ingest gates.
set -uo pipefail
DIR=/opt/ecom-intel
cd "$DIR" || exit 0
. tools/laptop/lib.sh

RUN_ID="${1:?usage: blinkit_rescue_resume.sh <run_id> [shard_index]}"
IDX="${2:-0}"
TOTAL=2
RUN="shards/runs/$RUN_ID/blinkit"
SHARD_DIR="$RUN/shard-${IDX}-of-${TOTAL}"
SHARD_CFG="$SHARD_DIR/pincodes.${IDX}-of-${TOTAL}.json"
MANIFEST="$SHARD_DIR/manifest.${IDX}-of-${TOTAL}.json"
RESULT="$SHARD_DIR/result.json"
CLAIM="$SHARD_DIR/.rescue-claimed-by"
AUTH_VPS="secrets/blinkit-auth-state.json"

# Shard runner is overridable ONLY so the no-live-scrape test harness can inject
# a stub; production leaves it unset and uses the real authenticated runner.
SHARD_RUNNER="${BLINKIT_RESCUE_SHARD_RUNNER:-tools/shards/run_platform_shard.sh}"
CONCURRENCY="${BLINKIT_TEAM_RESCUE_CONCURRENCY:-3}"
PERPIN_S="${BLINKIT_TEAM_RESCUE_PERPIN_S:-16}"     # ~16s/pin at C=3 incl. margin
WALL_MARGIN_S="${BLINKIT_TEAM_RESCUE_MARGIN_S:-600}"
WALL_CAP="${BLINKIT_TEAM_RESCUE_WALL_S:-18000}"
STALE_S="${BLINKIT_TEAM_RESCUE_STALE_S:-19800}"    # marker reclaim horizon
DEADLINE_HHMM="${BLINKIT_TEAM_DEADLINE:-10:00}"

LOG(){ echo "[$(date '+%F %T')] blinkit_rescue_resume($RUN_ID s$IDX): $*" | tee -a logs/blinkit_team.log; }
# notify: Telegram alert, suppressible for the no-live-scrape test harness.
notify(){ [ "${BLINKIT_RESCUE_TG_DISABLE:-0}" = "1" ] && return 0; team_tg "$@"; }

[ -d "$SHARD_DIR" ] || { LOG "no shard dir $SHARD_DIR — nothing to rescue"; exit 0; }
[ -s "$SHARD_CFG" ] || { LOG "shard config $SHARD_CFG missing — cannot rescue"; exit 1; }
[ -s "$MANIFEST" ]  || { LOG "manifest $MANIFEST missing — cannot rescue"; exit 1; }
if [ -s "$RESULT" ]; then LOG "shard result already present — nothing to do"; exit 0; fi
[ -s "$AUTH_VPS" ] || { LOG "missing $AUTH_VPS — cannot rescue on VPS"; exit 1; }

# one rescue per run/shard on this box
exec 8>"logs/.blinkit-rescue-${RUN_ID}-s${IDX}.lock"
flock -n 8 || { LOG "another rescue for this shard is already running here — exiting"; exit 0; }

# ---- anti-double-scrape claim (whoever writes CLAIM first wins) --------------
claim() {
  local m="$1"
  if ( set -o noclobber; printf 'vps-rescue:%s:%s\n' "$$" "$(date +%s)" > "$m" ) 2>/dev/null; then
    return 0
  fi
  local age; age=$(( $(date +%s) - $(stat -c %Y "$m" 2>/dev/null || date +%s) ))
  if [ "$age" -ge "$STALE_S" ] && ! pgrep -f "run_platform_shard.sh blinkit" >/dev/null 2>&1; then
    printf 'vps-rescue:%s:%s (reclaimed stale after %ss)\n' "$$" "$(date +%s)" "$age" > "$m"
    return 0
  fi
  return 1
}
if ! claim "$CLAIM"; then
  LOG "rescue already claimed by '$(tr -d '\n' < "$CLAIM" 2>/dev/null)' — backing off (no double-scrape)"
  exit 0
fi
LOG "claimed rescue via $CLAIM"

# ---- pull the Mac partial READ-ONLY -----------------------------------------
MAC_PARTIAL="$SHARD_DIR/mac-partial.json"
MAC_RUNS="/Users/danny./VPS-Migration/imported/ecom-intel/platforms/blinkit/mac-runs"
pull_partial() {
  local override="${BLINKIT_MAC_PARTIAL_PATH:-}"
  if [ -n "$override" ]; then
    if [[ "$override" == /* || "$override" == *:* ]]; then
      # explicit local path or host:path
      case "$override" in
        *:*) timeout 90 scp -q -o BatchMode=yes "$override" "$MAC_PARTIAL" 2>/dev/null && return 0 ;;
        *)   [ -s "$override" ] && cp "$override" "$MAC_PARTIAL" && return 0 ;;
      esac
    fi
    timeout 90 scp -q -o BatchMode=yes "macpro:$override" "$MAC_PARTIAL" 2>/dev/null && return 0
  fi
  # discover the newest team progress/out-file for today (exclude repair/preflight)
  local today remote
  today="$(date +%Y%m%d)"
  remote="$(timeout 30 ssh -o BatchMode=yes -o ConnectTimeout=15 macpro \
    "ls -t $MAC_RUNS/blinkit-${today}-[0-9]*.progress.json $MAC_RUNS/blinkit-${today}-[0-9]*.json 2>/dev/null \
       | grep -Ev 'repair|preflight' | head -1" 2>/dev/null | tr -d '\r')"
  [ -n "$remote" ] || return 1
  LOG "pulling Mac partial: $remote"
  timeout 120 scp -q -o BatchMode=yes "macpro:$remote" "$MAC_PARTIAL" 2>/dev/null
}
if ! pull_partial || [ ! -s "$MAC_PARTIAL" ]; then
  LOG "no Mac partial available — degrading to FULL rescue of shard-$IDX"
  MAC_PARTIAL=""
fi

# ---- plan: kept vs remaining ------------------------------------------------
REMAINING="$SHARD_DIR/remaining.${IDX}.json"
PLAN="$(python3 tools/laptop/blinkit_resume_combine.py plan \
  --shard-config "$SHARD_CFG" \
  ${MAC_PARTIAL:+--partial "$MAC_PARTIAL"} \
  --out-remaining "$REMAINING")" || { LOG "plan failed"; exit 1; }
echo "$PLAN" | tee -a logs/blinkit_team.log >/dev/null
REMAIN_N="$(python3 -c 'import json,sys;print(json.loads(sys.stdin.read())["remaining"])' <<<"$PLAN")"
KEPT_N="$(python3 -c 'import json,sys;print(json.loads(sys.stdin.read())["kept"])' <<<"$PLAN")"
MODE="$(python3 -c 'import json,sys;print(json.loads(sys.stdin.read())["mode"])' <<<"$PLAN")"
LOG "plan: kept=$KEPT_N remaining=$REMAIN_N mode=$MODE"

# ---- deadline projection ----------------------------------------------------
WALL=$(( REMAIN_N * PERPIN_S + WALL_MARGIN_S ))
[ "$WALL" -gt "$WALL_CAP" ] && WALL="$WALL_CAP"
[ "$WALL" -lt 300 ] && WALL=300
NOW=$(date +%s)
FINISH=$(( NOW + WALL ))
DEADLINE=$(date -d "$(date +%F) $DEADLINE_HHMM" +%s 2>/dev/null || echo 0)
LOG "projected: rescue-scrape $REMAIN_N pins at C=$CONCURRENCY, wall=${WALL}s -> finish ~$(date -d "@$FINISH" '+%F %T') (+merge/ingest after)"
if [ "$DEADLINE" -gt 0 ] && [ "$FINISH" -gt "$DEADLINE" ]; then
  LOG "⚠️ RESCUE DEADLINE RISK: projected shard finish $(date -d "@$FINISH" '+%H:%M') is PAST the $DEADLINE_HHMM slot (remaining=$REMAIN_N). Merge+ingest add more. Escalating."
  notify "⚠️ Blinkit rescue $RUN_ID s$IDX: projected shard finish ~$(date -d "@$FINISH" '+%H:%M') IST is PAST $DEADLINE_HHMM (remaining=$REMAIN_N pins @C=$CONCURRENCY). Report will likely be late."
fi

# ---- scrape the remaining pins (unless nothing to do) -----------------------
# OWNER POLICY (LEAD ruling 2026-07-15): VPS/datacenter-direct Blinkit scraping is
# gated OFF by default. finalize-only (no pins to scrape) always proceeds — it
# does no scraping. The actual scrape leg runs only with an explicit opt-in.
RESCUE_RESULT=""
if [ "$REMAIN_N" -gt 0 ] && [ "${BLINKIT_ALLOW_VPS_RESCUE:-0}" != "1" ]; then
  LOG "VPS rescue scrape DISABLED by owner policy (BLINKIT_ALLOW_VPS_RESCUE!=1); would re-scrape $REMAIN_N pins. Alert-only — kept $KEPT_N verified pins are NOT finalized (need the missing pins for a full shard). Set BLINKIT_ALLOW_VPS_RESCUE=1 to enable."
  notify "⚠️ Blinkit rescue $RUN_ID s$IDX: Mac shard died, $REMAIN_N pins missing. VPS rescue scrape is OFF by owner policy — NOT scraping. Set BLINKIT_ALLOW_VPS_RESCUE=1 to allow the DC-direct last-resort rescue."
  rm -f "$CLAIM"   # release so a Mac-side resume (agent-5) can still claim
  exit 0
fi
if [ "$REMAIN_N" -gt 0 ]; then
  RESCUE_RUN_ID="${RUN_ID}-rescue-s${IDX}"
  RESCUE_DIR="shards/runs/$RESCUE_RUN_ID/blinkit/shard-0-of-1"
  RESCUE_RESULT="$RESCUE_DIR/result.json"
  LOG "scraping $REMAIN_N remaining pins on the VPS (C=$CONCURRENCY, role=vps-rescue, wall=${WALL}s)"
  notify "🛠 Blinkit rescue $RUN_ID s$IDX: Mac shard died — resuming on VPS. Keeping $KEPT_N verified pins, re-scraping $REMAIN_N at C=$CONCURRENCY."
  rc=0
  env \
    BLINKIT_AUTH_STATE_FILE="$DIR/$AUTH_VPS" \
    BLINKIT_REQUIRE_AUTH=1 BLINKIT_OOS_PROBE=1 BLINKIT_PDP_OOS_PROBE=1 \
    BLINKIT_PDP_PRICE_PROBE=1 CONCURRENCY="$CONCURRENCY" \
    SHARD_ROLE="vps-rescue" \
    timeout --foreground -k 60 "${WALL}s" \
    "$SHARD_RUNNER" blinkit "$REMAINING" 1 0 "$RESCUE_RUN_ID" \
    >> logs/blinkit_team.log 2>&1 || rc=$?
  if [ "$rc" != 0 ] || [ ! -s "$RESCUE_RESULT" ]; then
    LOG "rescue scrape failed (rc=$rc, result present=$([ -s "$RESCUE_RESULT" ] && echo yes || echo no)) — leaving claim so a later tick can reclaim if stale; NOT finalizing"
    notify "❌ Blinkit rescue $RUN_ID s$IDX: VPS re-scrape of remaining pins failed (rc=$rc). Guards own recovery."
    exit 1
  fi
  LOG "rescue scrape done -> $RESCUE_RESULT"
else
  LOG "no remaining pins — Mac partial already covers the shard; finalizing without scraping"
fi

# ---- combine kept-partial + rescue into the shard result --------------------
LOG "combining kept-partial + rescue into $RESULT"
python3 tools/laptop/blinkit_resume_combine.py combine \
  --shard-config "$SHARD_CFG" \
  ${MAC_PARTIAL:+--partial "$MAC_PARTIAL"} \
  ${RESCUE_RESULT:+--rescue "$RESCUE_RESULT"} \
  --out "$RESULT" >> logs/blinkit_team.log 2>&1 || { LOG "combine failed — not writing shard result"; rm -f "$RESULT"; exit 1; }
LOG "combined shard-$IDX result written ($(python3 -c 'import json,sys;s=json.load(open(sys.argv[1]))["summary"];print(f"{s[\"pincodes_total\"]} pins, {s[\"total_rows\"]} rows, auth_verified={s[\"auth_verified\"]} ({s[\"auth_verified_pincodes\"]}), unresolved={s[\"pincodes_unresolved\"]}")' "$RESULT" 2>/dev/null || echo '?'))"

# ---- chain the normal team merge (idempotent; waits if the other shard lags) -
LOG "chaining blinkit_team_merge.sh"
tools/laptop/blinkit_team_merge.sh "$RUN_ID" >> logs/blinkit_team.log 2>&1 || true
exit 0
