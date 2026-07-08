#!/usr/bin/env bash
# Finish a targeted Blinkit repair: wait for a small KVM rerun, patch those
# pincodes into a failed shard result, merge the normal shards, ingest, and send.
set -u

ROOT=/opt/ecom-intel
cd "$ROOT" || exit 1

BASE_RUN="${1:?usage: blinkit_finish_targeted_repair.sh <base-run-id> <target-run-id> <target-index> <not-before-epoch>}"
TARGET_RUN="${2:?usage: blinkit_finish_targeted_repair.sh <base-run-id> <target-run-id> <target-index> <not-before-epoch>}"
TARGET_INDEX="${3:?usage: blinkit_finish_targeted_repair.sh <base-run-id> <target-run-id> <target-index> <not-before-epoch>}"
NOT_BEFORE="${4:?usage: blinkit_finish_targeted_repair.sh <base-run-id> <target-run-id> <target-index> <not-before-epoch>}"

DATE_IST="${BLINKIT_REPAIR_DATE:-$(TZ=Asia/Kolkata date +%F)}"
LOG="logs/blinkit-targeted-repair-finish-${DATE_IST}.log"
BASE_DIR="$ROOT/shards/runs/$BASE_RUN/blinkit"
TARGET_RESULT="$ROOT/shards/runs/$TARGET_RUN/blinkit/shard-0-of-1/result.json"
BASE_RESULT="$BASE_DIR/shard-${TARGET_INDEX}-of-2/result.json"
PATCHED_RESULT="$BASE_DIR/shard-${TARGET_INDEX}-of-2/result.targeted-repaired.json"
MERGED="$BASE_DIR/merged-result.json"
mkdir -p logs

log() {
  printf '[%s] blinkit_targeted_repair_finish(%s): %s\n' \
    "$(TZ=Asia/Kolkata date '+%F %T %Z')" "$TARGET_RUN" "$*" | tee -a "$LOG"
}

file_mtime() {
  stat -c %Y "$1" 2>/dev/null || echo 0
}

log "waiting for target result after epoch $NOT_BEFORE: $TARGET_RESULT"
for _ in $(seq 1 "${BLINKIT_TARGET_REPAIR_WAIT_LOOPS:-120}"); do
  if [ -s "$TARGET_RESULT" ] && [ "$(file_mtime "$TARGET_RESULT")" -ge "$NOT_BEFORE" ]; then
    log "target result present"
    break
  fi
  sleep "${BLINKIT_TARGET_REPAIR_WAIT_STEP:-30}"
done

if [ ! -s "$TARGET_RESULT" ] || [ "$(file_mtime "$TARGET_RESULT")" -lt "$NOT_BEFORE" ]; then
  log "target result did not arrive in time"
  exit 1
fi

log "target summary"
python3 - "$TARGET_RESULT" <<'PY' | tee -a "$LOG"
import json, sys
s = json.load(open(sys.argv[1], encoding="utf-8")).get("summary") or {}
print(json.dumps({
    "pincodes_total": s.get("pincodes_total"),
    "auth_verified": s.get("auth_verified"),
    "auth_verified_pincodes": s.get("auth_verified_pincodes"),
    "total_rows": s.get("total_rows"),
    "unverified_oos": s.get("unverified_oos"),
    "pdp_price_probe_failed": s.get("pdp_price_probe_failed"),
    "captured_at": s.get("captured_at"),
}, indent=2))
if s.get("auth_verified") != 1 or s.get("auth_verified_pincodes") != s.get("pincodes_total"):
    raise SystemExit("target result failed auth verification")
if int(s.get("unverified_oos") or 0) != 0:
    raise SystemExit("target result still has unverified OOS")
if int(s.get("pdp_price_probe_failed") or 0) != 0:
    raise SystemExit("target result still has PDP price probe failures")
PY
if [ "${PIPESTATUS[0]}" != "0" ]; then
  log "target quality failed"
  exit 1
fi

log "patching target pins into base shard $TARGET_INDEX"
python3 "$ROOT/tools/cron/blinkit_apply_targeted_shard_repair.py" \
  "$BASE_RESULT" "$TARGET_RESULT" "$PATCHED_RESULT" >>"$LOG" 2>&1 || exit 1
cp -f "$BASE_RESULT" "${BASE_RESULT}.pre-targeted-repair"
mv -f "$PATCHED_RESULT" "$BASE_RESULT"

pairs=()
for idx in 0 1; do
  pairs+=("$BASE_DIR/shard-${idx}-of-2/manifest.${idx}-of-2.json" "$BASE_DIR/shard-${idx}-of-2/result.json")
done

log "merging repaired shards"
python3 "$ROOT/tools/shards/merge_platform_shards.py" blinkit "$MERGED" "${pairs[@]}" >>"$LOG" 2>&1 || exit 1

log "ingesting through normal Blinkit gates"
"$ROOT/platforms/blinkit/ingest.sh" "$MERGED" --deliver >>"$LOG" 2>&1 || exit 1

log "running quality gate"
BLINKIT_MONITOR_DRYRUN=1 BLINKIT_MONITOR_EXIT_CODE=1 BLINKIT_MONITOR_DATE="$DATE_IST" \
  "$ROOT/tools/cron/blinkit_quality_monitor.sh" targeted-repair >>"$LOG" 2>&1 || exit 1

log "sending WhatsApp"
"$ROOT/tools/whatsapp/send_blinkit_main_direct.sh" targeted-repair >>"$LOG" 2>&1 || exit 1
"$ROOT/tools/whatsapp/send_blinkit_not_listed_direct.sh" targeted-repair >>"$LOG" 2>&1 || exit 1

log "done"
