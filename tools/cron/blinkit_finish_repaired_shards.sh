#!/usr/bin/env bash
# Finish a Blinkit shard repair run after one or more shards have been re-run.
# It waits for the repaired shard result to sync back, merges all shard results,
# ingests through the normal Blinkit gates, then triggers marker-safe WhatsApp
# sends. This intentionally does not bypass auth or false-OOS quality gates.
set -u

ROOT=/opt/ecom-intel
cd "$ROOT" || exit 1

RUN_ID="${1:?usage: blinkit_finish_repaired_shards.sh <run-id> <total> <repaired-index> [not-before-epoch]}"
TOTAL="${2:?usage: blinkit_finish_repaired_shards.sh <run-id> <total> <repaired-index> [not-before-epoch]}"
REPAIRED_INDEX="${3:?usage: blinkit_finish_repaired_shards.sh <run-id> <total> <repaired-index> [not-before-epoch]}"
NOT_BEFORE="${4:-0}"
DATE_IST="${BLINKIT_REPAIR_DATE:-$(TZ=Asia/Kolkata date +%F)}"
LOG="logs/blinkit-repair-finish-${DATE_IST}.log"
RUN_DIR="$ROOT/shards/runs/$RUN_ID/blinkit"
MERGED="$RUN_DIR/merged-result.json"

mkdir -p logs

log() {
  printf '[%s] blinkit_repair_finish(%s): %s\n' \
    "$(TZ=Asia/Kolkata date '+%F %T %Z')" "$RUN_ID" "$*" | tee -a "$LOG"
}

file_mtime() {
  stat -c %Y "$1" 2>/dev/null || echo 0
}

log "waiting for repaired shard $REPAIRED_INDEX/$TOTAL after epoch $NOT_BEFORE"
REPAIRED_RESULT="$RUN_DIR/shard-${REPAIRED_INDEX}-of-${TOTAL}/result.json"
for _ in $(seq 1 "${BLINKIT_REPAIR_WAIT_LOOPS:-180}"); do
  if [ -s "$REPAIRED_RESULT" ] && [ "$(file_mtime "$REPAIRED_RESULT")" -ge "$NOT_BEFORE" ]; then
    log "repaired shard result present: $REPAIRED_RESULT"
    break
  fi
  sleep "${BLINKIT_REPAIR_WAIT_STEP:-60}"
done

if [ ! -s "$REPAIRED_RESULT" ] || [ "$(file_mtime "$REPAIRED_RESULT")" -lt "$NOT_BEFORE" ]; then
  log "repaired shard did not arrive in time: $REPAIRED_RESULT"
  exit 1
fi

pairs=()
for idx in $(seq 0 "$((TOTAL - 1))"); do
  manifest="$RUN_DIR/shard-${idx}-of-${TOTAL}/manifest.${idx}-of-${TOTAL}.json"
  result="$RUN_DIR/shard-${idx}-of-${TOTAL}/result.json"
  if [ ! -s "$manifest" ] || [ ! -s "$result" ]; then
    log "missing shard pair idx=$idx manifest=$manifest result=$result"
    exit 1
  fi
  pairs+=("$manifest" "$result")
done

log "merging $TOTAL shards"
python3 "$ROOT/tools/shards/merge_platform_shards.py" blinkit "$MERGED" "${pairs[@]}" >>"$LOG" 2>&1 || exit 1

log "merged summary"
python3 - "$MERGED" <<'PY' | tee -a "$LOG"
import json, sys
s = json.load(open(sys.argv[1], encoding="utf-8")).get("summary") or {}
keys = [
    "pincodes_total", "pincodes_resolved", "pincodes_with_jivo", "total_rows",
    "unique_skus", "auth_verified", "auth_verified_pincodes",
    "oos_probe_flips", "pdp_price_probe_checked", "pdp_price_probe_failed",
    "unverified_oos", "captured_at",
]
print(json.dumps({k: s.get(k) for k in keys}, indent=2))
PY

log "ingesting through normal gates"
"$ROOT/platforms/blinkit/ingest.sh" "$MERGED" --deliver >>"$LOG" 2>&1 || exit 1

log "running quality gate"
BLINKIT_MONITOR_DRYRUN=1 \
BLINKIT_MONITOR_EXIT_CODE=1 \
BLINKIT_MONITOR_DATE="$DATE_IST" \
  "$ROOT/tools/cron/blinkit_quality_monitor.sh" repair-finish >>"$LOG" 2>&1 || exit 1

log "triggering WhatsApp sends"
"$ROOT/tools/whatsapp/send_blinkit_main_direct.sh" repair-finish >>"$LOG" 2>&1 || exit 1
"$ROOT/tools/whatsapp/send_blinkit_not_listed_direct.sh" repair-finish >>"$LOG" 2>&1 || exit 1

log "done"
