#!/usr/bin/env bash
# Emergency authenticated Blinkit fallback for days when the Mac Pro collector is
# unavailable. It runs staged shards across the VPS and KVM1, merges them on the
# VPS, then uses platforms/blinkit/ingest.sh so the normal fail-closed quality,
# review, workbook, batch, and WhatsApp gates still own publication.
set -uo pipefail

DIR=/opt/ecom-intel
cd "$DIR" || exit 1

TODAY="$(TZ=Asia/Kolkata date +%F)"
STAMP="$(TZ=Asia/Kolkata date +%Y%m%d-%H%M%S)"
RUN_ID="${BLINKIT_FALLBACK_RUN_ID:-${STAMP}-blinkit-vps-kvm}"
MODE="${1:-run}"
LOG_FILE="$DIR/logs/blinkit-vps-kvm-fallback-${TODAY}.log"
LOCK_FILE="$DIR/logs/.blinkit-vps-kvm-fallback.lock"
REPORT="$DIR/output/Jivo-Blinkit-Live-Report-${TODAY}.xlsx"
NOT_LISTED="$DIR/output/Jivo-Blinkit-Not-Listed-Pincodes-${TODAY}.xlsx"
SOURCE_CONFIG="$DIR/platforms/blinkit/pincodes.daily.json"
AUTH_FILE="$DIR/secrets/blinkit-auth-state.json"
SHARD_TIMEOUT="${BLINKIT_FALLBACK_SHARD_TIMEOUT:-7200}"
mkdir -p "$DIR/logs" "$DIR/shards/runs"

log() {
  printf '[%s] blinkit_vps_kvm_fallback(%s): %s\n' "$(TZ=Asia/Kolkata date '+%F %T %Z')" "$MODE" "$*" | tee -a "$LOG_FILE"
}

tg() { (
  set +e
  [ -f "$DIR/secrets.env" ] && . "$DIR/secrets.env"
  CH="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "$CH" ] || exit 0
  curl -s --max-time 30 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=$CH" \
    --data-urlencode "text=$1" >/dev/null
) || true; }

have_today_report() {
  [ -s "$REPORT" ] && [ -s "$NOT_LISTED" ]
}

store_open_window() {
  local hhmm
  hhmm="$(TZ=Asia/Kolkata date +%H%M)"
  [ "${BLINKIT_FALLBACK_EARLY_OK:-0}" = "1" ] || [ "$((10#$hhmm))" -ge 630 ]
}

prepare_kvm1() {
  log "preparing KVM1 Blinkit runtime"
  ssh -o BatchMode=yes -o ConnectTimeout=15 kvm1 \
    "mkdir -p /opt/ecom-intel/platforms/blinkit /opt/ecom-intel/tools/shards /opt/ecom-intel/secrets /opt/ecom-intel/shards/runs /opt/ecom-intel/logs && chmod 700 /opt/ecom-intel/secrets" \
    >>"$LOG_FILE" 2>&1 || return 1

  rsync -az --delete \
    --exclude='.git/' \
    --exclude='.progress.*.json' \
    --exclude='result*.json' \
    --exclude='Jivo-*.xlsx' \
    --exclude='mac-drops/' \
    --exclude='__pycache__/' \
    --exclude='*.pyc' \
    "$DIR/platforms/blinkit/" kvm1:/opt/ecom-intel/platforms/blinkit/ \
    >>"$LOG_FILE" 2>&1 || return 1

  rsync -az --delete \
    --exclude='__pycache__/' \
    --exclude='*.pyc' \
    "$DIR/tools/shards/" kvm1:/opt/ecom-intel/tools/shards/ \
    >>"$LOG_FILE" 2>&1 || return 1

  rsync -az "$AUTH_FILE" kvm1:/opt/ecom-intel/secrets/blinkit-auth-state.json \
    >>"$LOG_FILE" 2>&1 || return 1
  ssh -o BatchMode=yes -o ConnectTimeout=15 kvm1 \
    "chmod 600 /opt/ecom-intel/secrets/blinkit-auth-state.json && test -x /root/.cache/ms-playwright/chromium-1223/chrome-linux64/chrome" \
    >>"$LOG_FILE" 2>&1 || return 1
  return 0
}

run_local_shard() {
  local total="$1" index="$2" role="$3"
  log "local shard start index=${index}/${total} role=$role run_id=$RUN_ID"
  env \
    SHARD_ROLE="$role" \
    BLINKIT_AUTH_STATE_FILE="$AUTH_FILE" \
    BLINKIT_REQUIRE_AUTH=1 \
    BLINKIT_OOS_PROBE=1 \
    BLINKIT_PDP_OOS_PROBE=1 \
    BLINKIT_PDP_PRICE_PROBE=1 \
    CONCURRENCY="${BLINKIT_FALLBACK_CONCURRENCY:-2}" \
    timeout --foreground -k 60 "${SHARD_TIMEOUT}s" \
      "$DIR/tools/shards/run_platform_shard.sh" blinkit "$SOURCE_CONFIG" "$total" "$index" "$RUN_ID" \
      >>"$LOG_FILE" 2>&1
}

run_kvm1_shard() {
  local total="$1" index="$2"
  log "KVM1 shard start index=${index}/${total} run_id=$RUN_ID"
  timeout --foreground -k 60 "${SHARD_TIMEOUT}s" ssh -o BatchMode=yes -o ConnectTimeout=15 kvm1 \
    "cd /opt/ecom-intel && env SHARD_ROLE=kvm1 SYNC_DEST='vps:/opt/ecom-intel/shards/runs' BLINKIT_AUTH_STATE_FILE=/opt/ecom-intel/secrets/blinkit-auth-state.json BLINKIT_REQUIRE_AUTH=1 BLINKIT_OOS_PROBE=1 BLINKIT_PDP_OOS_PROBE=1 BLINKIT_PDP_PRICE_PROBE=1 CONCURRENCY='${BLINKIT_FALLBACK_CONCURRENCY:-2}' ./tools/shards/run_platform_shard.sh blinkit platforms/blinkit/pincodes.daily.json '$total' '$index' '$RUN_ID'" \
    >>"$LOG_FILE" 2>&1
}

shard_result() {
  local total="$1" index="$2"
  printf '%s/shards/runs/%s/blinkit/shard-%s-of-%s/result.json' "$DIR" "$RUN_ID" "$index" "$total"
}

shard_manifest() {
  local total="$1" index="$2"
  printf '%s/shards/runs/%s/blinkit/shard-%s-of-%s/manifest.%s-of-%s.json' "$DIR" "$RUN_ID" "$index" "$total" "$index" "$total"
}

ensure_shard_present() {
  local total="$1" index="$2" role="$3" result manifest
  result="$(shard_result "$total" "$index")"
  manifest="$(shard_manifest "$total" "$index")"
  if [ -s "$result" ] && [ -s "$manifest" ]; then
    return 0
  fi
  log "shard ${index}/${total} missing after parallel pass; rescuing locally"
  run_local_shard "$total" "$index" "$role-rescue"
  [ -s "$result" ] && [ -s "$manifest" ]
}

merge_and_ingest() {
  local total="$1" merged pairs=() i
  merged="$DIR/shards/runs/$RUN_ID/blinkit/merged-result.json"
  for i in $(seq 0 "$((total - 1))"); do
    pairs+=("$(shard_manifest "$total" "$i")" "$(shard_result "$total" "$i")")
  done
  log "merging $total Blinkit shard(s) -> $merged"
  python3 "$DIR/tools/shards/merge_platform_shards.py" blinkit "$merged" "${pairs[@]}" >>"$LOG_FILE" 2>&1 || return 1
  log "ingesting merged fallback result through normal Blinkit gates"
  "$DIR/platforms/blinkit/ingest.sh" "$merged" --deliver >>"$LOG_FILE" 2>&1 || return 1
  have_today_report
}

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "another fallback run holds $LOCK_FILE; exiting"
  exit 0
fi

case "$MODE" in
  prepare|prepare-only)
    if [ ! -s "$AUTH_FILE" ]; then
      log "cannot prepare: missing $AUTH_FILE"
      exit 1
    fi
    prepare_kvm1
    exit $?
    ;;
  status)
    have_today_report && log "today report present" || log "today report missing"
    exit 0
    ;;
esac

if have_today_report; then
  log "today's main + not-listed reports already present; no fallback needed"
  exit 0
fi
if [ ! -s "$SOURCE_CONFIG" ]; then
  log "missing source config: $SOURCE_CONFIG"
  exit 1
fi
if [ ! -s "$AUTH_FILE" ]; then
  log "missing Blinkit auth state: $AUTH_FILE"
  tg "[FAIL] Blinkit fallback cannot start: VPS auth state missing at $AUTH_FILE"
  exit 1
fi
if ! store_open_window; then
  log "before 06:30 IST store-open window; refusing full fallback unless BLINKIT_FALLBACK_EARLY_OK=1"
  exit 0
fi

TOTAL=2
KVM_OK=0
if prepare_kvm1; then
  KVM_OK=1
else
  TOTAL=1
  log "KVM1 preparation failed; falling back to one full authenticated VPS shard"
  tg "[WARN] Blinkit fallback: KVM1 prep failed, running the full authenticated scrape on VPS only for ${TODAY}."
fi

log "fallback run start run_id=$RUN_ID total_shards=$TOTAL"
if [ "$KVM_OK" -eq 1 ]; then
  tg "[START] Blinkit fallback started for ${TODAY}: Mac unavailable, running authenticated 2-shard scrape on VPS + KVM1."
else
  tg "[START] Blinkit fallback started for ${TODAY}: Mac unavailable, running authenticated scrape on VPS only."
fi

LOCAL_RC=0
REMOTE_RC=0
run_local_shard "$TOTAL" 0 "vps" &
LOCAL_PID=$!
if [ "$KVM_OK" -eq 1 ]; then
  run_kvm1_shard "$TOTAL" 1 &
  REMOTE_PID=$!
else
  REMOTE_PID=""
fi

wait "$LOCAL_PID" || LOCAL_RC=$?
if [ -n "$REMOTE_PID" ]; then
  wait "$REMOTE_PID" || REMOTE_RC=$?
fi
log "parallel shard pass complete local_rc=$LOCAL_RC remote_rc=$REMOTE_RC"

if ! ensure_shard_present "$TOTAL" 0 "vps"; then
  log "local shard 0 missing/failed after rescue"
  tg "[FAIL] Blinkit fallback failed: VPS shard missing after rescue for ${TODAY}."
  exit 1
fi
if [ "$TOTAL" -gt 1 ] && ! ensure_shard_present "$TOTAL" 1 "kvm1"; then
  log "KVM1 shard 1 missing/failed after local rescue"
  tg "[FAIL] Blinkit fallback failed: KVM1 shard missing after local rescue for ${TODAY}."
  exit 1
fi

if merge_and_ingest "$TOTAL"; then
  log "fallback PASS; report=$REPORT not_listed=$NOT_LISTED"
  tg "[OK] Blinkit fallback finished and passed gates for ${TODAY}; workbook created and WhatsApp delivery hooks ran."
  exit 0
fi

log "fallback failed during merge/ingest; see log"
tg "[FAIL] Blinkit fallback failed during merge/ingest for ${TODAY}; report was not delivered. Check $LOG_FILE"
exit 1
