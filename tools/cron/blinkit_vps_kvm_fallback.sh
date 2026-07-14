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
EFFECTIVE_CONCURRENCY="${BLINKIT_FALLBACK_CONCURRENCY:-2}"
MAX_CLOCK_DRIFT_S="${BLINKIT_MAX_CLOCK_DRIFT_S:-5}"
KVM_PROXY_CHECKED=0
KVM_PROXY_OK=0
mkdir -p "$DIR/logs" "$DIR/shards/runs"

log() {
  printf '[%s] blinkit_vps_kvm_fallback(%s): %s\n' "$(TZ=Asia/Kolkata date '+%F %T %Z')" "$MODE" "$*" | tee -a "$LOG_FILE"
}

if [ "${BLINKIT_ALLOW_MANUAL_DATACENTER_FALLBACK:-0}" != "1" ]; then
  log "REFUSED: datacenter fallback is disabled for production; recover the Mac/Windows device workflow"
  exit 2
fi

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
  [ "${BLINKIT_FALLBACK_EARLY_OK:-0}" = "1" ] || [ "$((10#$hhmm))" -ge 700 ]
}

prepare_kvm1() {
  if ! kvm1_blinkit_proxy_healthy; then
    log "KVM1 Blinkit proxy health failed; refusing KVM1 Blinkit path"
    return 1
  fi
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

kvm1_blinkit_proxy_healthy() {
  if [ "$KVM_PROXY_CHECKED" -eq 1 ]; then
    [ "$KVM_PROXY_OK" -eq 1 ]
    return $?
  fi
  KVM_PROXY_CHECKED=1
  if [ "${BLINKIT_FALLBACK_SKIP_KVM_PROXY_CHECK:-0}" = "1" ]; then
    KVM_PROXY_OK=1
    return 0
  fi
  log "checking KVM1 Blinkit proxy health"
  if ssh -o BatchMode=yes -o ConnectTimeout=15 kvm1 \
      "scrape-proxy-check && blinkit-probe" >>"$LOG_FILE" 2>&1; then
    KVM_PROXY_OK=1
    return 0
  fi
  KVM_PROXY_OK=0
  return 1
}

clocks_healthy() {
  local before after midpoint remote_epoch drift local_ntp remote_ntp
  local_ntp="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)"
  before="$(date +%s)"
  remote_epoch="$(ssh -o BatchMode=yes -o ConnectTimeout=15 kvm1 'date +%s' 2>/dev/null)" || return 1
  after="$(date +%s)"
  remote_ntp="$(ssh -o BatchMode=yes -o ConnectTimeout=15 kvm1 'timedatectl show -p NTPSynchronized --value 2>/dev/null || true' 2>/dev/null)" || return 1
  midpoint=$(( (before + after) / 2 ))
  drift=$(( remote_epoch - midpoint ))
  [ "$drift" -lt 0 ] && drift=$(( -drift ))
  log "clock preflight local_ntp=${local_ntp:-unknown} kvm_ntp=${remote_ntp:-unknown} drift=${drift}s max=${MAX_CLOCK_DRIFT_S}s"
  [ "$local_ntp" = "yes" ] && [ "$remote_ntp" = "yes" ] && [ "$drift" -le "$MAX_CLOCK_DRIFT_S" ]
}

kvm1_busy_with_other_browser_work() {
  ssh -o BatchMode=yes -o ConnectTimeout=15 kvm1 \
    "python3 - <<'PY'
import os
busy = []
for pid in filter(str.isdigit, os.listdir('/proc')):
    try:
        with open(f'/proc/{pid}/cmdline', 'rb') as f:
            cmd = f.read().replace(b'\0', b' ').decode('utf-8', 'ignore')
    except OSError:
        continue
    low = cmd.lower()
    if 'blinkit' in low:
        continue
    if any(x in low for x in [
        'bigbasket',
        'scrape_pincode_browser.js',
        'kvm1_run_trio.sh',
        'platforms/flipkart',
        'platforms/zepto',
        'run_platform_shard.sh',
    ]):
        busy.append(f'{pid} {cmd[:180]}')
if busy:
    print('\\n'.join(busy[:20]))
    raise SystemExit(0)
raise SystemExit(1)
PY" >>"$LOG_FILE" 2>&1
}

local_busy_with_other_browser_work() {
  python3 - <<'PY' >>"$LOG_FILE" 2>&1
import os
busy = []
for pid in filter(str.isdigit, os.listdir('/proc')):
    try:
        with open(f'/proc/{pid}/cmdline', 'rb') as f:
            cmd = f.read().replace(b'\0', b' ').decode('utf-8', 'ignore')
    except OSError:
        continue
    low = cmd.lower()
    if 'blinkit' in low:
        continue
    if any(x in low for x in [
        'bigbasket',
        'scrape_pincode_browser.js',
        'platforms/flipkart',
        'platforms/zepto',
        'run_platform_shard.sh',
    ]):
        busy.append(f'{pid} {cmd[:180]}')
if busy:
    print('\n'.join(busy[:20]))
    raise SystemExit(0)
raise SystemExit(1)
PY
}

refresh_host_busy_state() {
  LOCAL_BUSY=0
  KVM_BUSY=0
  local_busy_with_other_browser_work && LOCAL_BUSY=1
  kvm1_busy_with_other_browser_work && KVM_BUSY=1
}

wait_for_less_contention() {
  local max_wait="${BLINKIT_FALLBACK_BUSY_WAIT:-900}"
  local step="${BLINKIT_FALLBACK_BUSY_WAIT_STEP:-60}"
  local waited=0
  [ "$max_wait" -gt 0 ] || return 0
  [ "$step" -gt 0 ] || step=60
  while [ "$LOCAL_BUSY" -eq 1 ] && [ "$KVM_BUSY" -eq 1 ] && [ "$waited" -lt "$max_wait" ]; do
    log "both VPS and KVM1 have active non-Blinkit browser work; waiting ${step}s before choosing fallback host"
    sleep "$step"
    waited=$((waited + step))
    refresh_host_busy_state
  done
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
    CONCURRENCY="$EFFECTIVE_CONCURRENCY" \
    timeout --foreground -k 60 "${SHARD_TIMEOUT}s" \
      "$DIR/tools/shards/run_platform_shard.sh" blinkit "$SOURCE_CONFIG" "$total" "$index" "$RUN_ID" \
      >>"$LOG_FILE" 2>&1
}

run_kvm1_shard() {
  local total="$1" index="$2"
  log "KVM1 shard start index=${index}/${total} run_id=$RUN_ID"
  timeout --foreground -k 60 "${SHARD_TIMEOUT}s" ssh -o BatchMode=yes -o ConnectTimeout=15 kvm1 \
    "cd /opt/ecom-intel && env SHARD_ROLE=kvm1 SYNC_DEST='vps:/opt/ecom-intel/shards/runs' BLINKIT_AUTH_STATE_FILE=/opt/ecom-intel/secrets/blinkit-auth-state.json BLINKIT_REQUIRE_AUTH=1 BLINKIT_OOS_PROBE=1 BLINKIT_PDP_OOS_PROBE=1 BLINKIT_PDP_PRICE_PROBE=1 CONCURRENCY='$EFFECTIVE_CONCURRENCY' ./tools/shards/run_platform_shard.sh blinkit platforms/blinkit/pincodes.daily.json '$total' '$index' '$RUN_ID'" \
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

validate_shard_quality() {
  local total="$1" index="$2" result
  result="$(shard_result "$total" "$index")"
  python3 - "$result" <<'PY'
import json, sys

path = sys.argv[1]
try:
    d = json.load(open(path, encoding="utf-8"))
except Exception as e:
    raise SystemExit(f"cannot read shard result: {e}")
s = d.get("summary") or {}
rows = d.get("allRows") or []

def as_int(v, default=0):
    try:
        if v is None or isinstance(v, bool):
            return default
        return int(v)
    except Exception:
        return default

issues = []
if as_int(s.get("auth_session")) != 1 or as_int(s.get("auth_required")) != 1 or as_int(s.get("auth_verified")) != 1:
    issues.append(
        f"auth session={s.get('auth_session')} required={s.get('auth_required')} verified={s.get('auth_verified')}"
    )
if as_int(s.get("auth_verified_pincodes")) != as_int(s.get("pincodes_total")):
    issues.append(
        f"auth_pincodes={s.get('auth_verified_pincodes')}/{s.get('pincodes_total')}"
    )
if as_int(s.get("pdp_price_probe_failed")) > 0:
    issues.append(f"pdp_price_probe_failed={s.get('pdp_price_probe_failed')}")
calc_unverified = sum(
    1 for row in rows
    if not row.get("in_stock")
    and not row.get("pdp_checked")
    and str(row.get("stock_source") or "").strip().lower() not in {"pdp", "pdp_probe"}
)
summary_unverified = as_int(s.get("unverified_oos"), calc_unverified)
unverified = max(calc_unverified, summary_unverified)
if unverified > 0:
    issues.append(f"unverified_oos={unverified}")

if issues:
    print("; ".join(issues))
    raise SystemExit(1)
print("ok")
PY
}

write_targeted_repair_config() {
  local total="$1" index="$2" out_config="$3" out_pins="$4" result shard_config
  result="$(shard_result "$total" "$index")"
  shard_config="$DIR/shards/runs/$RUN_ID/blinkit/shard-${index}-of-${total}/pincodes.${index}-of-${total}.json"
  python3 - "$result" "$shard_config" "$out_config" "$out_pins" <<'PY'
import json, os, sys

result_path, shard_config_path, out_config_path, out_pins_path = sys.argv[1:5]
d = json.load(open(result_path, encoding="utf-8"))
source = json.load(open(shard_config_path, encoding="utf-8"))
per = d.get("perPin") or []
rows = d.get("allRows") or []

def pin(value):
    return str(value or "").strip()

def flag(value):
    if value is True:
        return True
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return value == 1
    return str(value).strip().lower() in {"1", "true", "yes", "y"}

bad = set()
for rec in per:
    p = pin(rec.get("pincode"))
    if p and not flag(rec.get("auth_accepted")):
        bad.add(p)

for row in rows:
    p = pin(row.get("pincode"))
    if not p:
        continue
    stock_source = str(row.get("stock_source") or "").strip().lower()
    if row.get("pdp_price_probe_failed"):
        bad.add(p)
    if not row.get("in_stock") and not row.get("pdp_checked") and stock_source not in {"pdp", "pdp_probe"}:
        bad.add(p)

if not bad:
    raise SystemExit("no targetable bad pincodes found")

target = [row for row in source if pin(row.get("pincode")) in bad]
target_pins = [pin(row.get("pincode")) for row in target]
missing = sorted(bad - set(target_pins))
if missing:
    raise SystemExit(f"bad pincodes not found in shard config: {missing[:10]}")

os.makedirs(os.path.dirname(out_config_path), exist_ok=True)
with open(out_config_path, "w", encoding="utf-8") as f:
    json.dump(target, f, indent=2, ensure_ascii=False)
    f.write("\n")
with open(out_pins_path, "w", encoding="utf-8") as f:
    f.write("\n".join(sorted(target_pins)) + "\n")

print(json.dumps({"count": len(target), "pincodes": sorted(target_pins)}, sort_keys=True))
PY
}

run_local_targeted_repair() {
  local target_config="$1" target_run_id="$2" role="$3"
  log "local targeted repair start run_id=$target_run_id config=$target_config"
  env \
    SHARD_ROLE="$role" \
    BLINKIT_AUTH_STATE_FILE="$AUTH_FILE" \
    BLINKIT_REQUIRE_AUTH=1 \
    BLINKIT_OOS_PROBE=1 \
    BLINKIT_PDP_OOS_PROBE=1 \
    BLINKIT_PDP_PRICE_PROBE=1 \
    CONCURRENCY="$EFFECTIVE_CONCURRENCY" \
    timeout --foreground -k 60 "${SHARD_TIMEOUT}s" \
      "$DIR/tools/shards/run_platform_shard.sh" blinkit "$target_config" 1 0 "$target_run_id" \
      >>"$LOG_FILE" 2>&1
}

run_kvm1_targeted_repair() {
  local target_config="$1" target_run_id="$2" remote_dir
  remote_dir="$(dirname "$target_config")"
  log "KVM1 targeted repair start run_id=$target_run_id config=$target_config"
  ssh -o BatchMode=yes -o ConnectTimeout=15 kvm1 "mkdir -p '$remote_dir'" >>"$LOG_FILE" 2>&1 || return 1
  rsync -az "$target_config" "kvm1:$target_config" >>"$LOG_FILE" 2>&1 || return 1
  timeout --foreground -k 60 "${SHARD_TIMEOUT}s" ssh -o BatchMode=yes -o ConnectTimeout=15 kvm1 \
    "cd /opt/ecom-intel && env SHARD_ROLE=kvm1-targeted-repair SYNC_DEST='vps:/opt/ecom-intel/shards/runs' BLINKIT_AUTH_STATE_FILE=/opt/ecom-intel/secrets/blinkit-auth-state.json BLINKIT_REQUIRE_AUTH=1 BLINKIT_OOS_PROBE=1 BLINKIT_PDP_OOS_PROBE=1 BLINKIT_PDP_PRICE_PROBE=1 CONCURRENCY='$EFFECTIVE_CONCURRENCY' ./tools/shards/run_platform_shard.sh blinkit '$target_config' 1 0 '$target_run_id'" \
    >>"$LOG_FILE" 2>&1
}

try_targeted_shard_repair() {
  local total="$1" index="$2" target_run_id target_dir target_config target_pins target_result base_result patched_result backup reason
  target_run_id="${RUN_ID}-targeted-repair-${index}-$(TZ=Asia/Kolkata date +%H%M%S)"
  target_dir="$DIR/shards/runs/$target_run_id/blinkit"
  target_config="$target_dir/target-pincodes.json"
  target_pins="$target_dir/target-pincodes.txt"
  target_result="$DIR/shards/runs/$target_run_id/blinkit/shard-0-of-1/result.json"
  base_result="$(shard_result "$total" "$index")"
  patched_result="${base_result}.targeted-repaired"
  backup="${base_result}.pre-targeted-repair"

  if ! reason="$(write_targeted_repair_config "$total" "$index" "$target_config" "$target_pins" 2>&1)"; then
    log "shard ${index}/${total} targeted repair not possible: $reason"
    return 1
  fi
  log "shard ${index}/${total} targeted repair pins: $reason"

  if [ "$KVM_OK" -ne 1 ]; then
    if prepare_kvm1; then
      KVM_OK=1
    fi
  fi

  if [ "$KVM_OK" -eq 1 ]; then
    run_kvm1_targeted_repair "$target_config" "$target_run_id" || return 1
  else
    run_local_targeted_repair "$target_config" "$target_run_id" "vps-targeted-repair" || return 1
  fi

  [ -s "$target_result" ] || { log "targeted repair result missing: $target_result"; return 1; }

  python3 "$DIR/tools/cron/blinkit_apply_targeted_shard_repair.py" \
    "$base_result" "$target_result" "$patched_result" >>"$LOG_FILE" 2>&1 || return 1
  cp -f "$base_result" "$backup"
  mv -f "$patched_result" "$base_result"

  if reason="$(validate_shard_quality "$total" "$index" 2>&1)"; then
    log "shard ${index}/${total} quality OK after targeted repair"
    return 0
  fi
  log "shard ${index}/${total} still failed after targeted repair: $reason"
  return 1
}

repair_shard_quality_if_needed() {
  local total="$1" index="$2" preferred_role="$3" reason
  if reason="$(validate_shard_quality "$total" "$index" 2>&1)"; then
    log "shard ${index}/${total} quality OK"
    return 0
  fi

  log "shard ${index}/${total} failed quality before merge: $reason"
  tg "[WARN] Blinkit fallback: shard ${index}/${total} failed auth/OOS quality (${reason}); repairing bad pincodes before merge."

  if try_targeted_shard_repair "$total" "$index"; then
    return 0
  fi

  log "targeted repair could not clear shard ${index}/${total}; falling back to one full shard rerun"
  tg "[WARN] Blinkit fallback: targeted repair could not clear shard ${index}/${total}; rerunning the full shard once."

  if [ "$KVM_OK" -ne 1 ]; then
    if prepare_kvm1; then
      KVM_OK=1
    fi
  fi

  if [ "$KVM_OK" -eq 1 ]; then
    run_kvm1_shard "$total" "$index" || return 1
  else
    run_local_shard "$total" "$index" "$preferred_role-quality-rescue" || return 1
  fi

  if reason="$(validate_shard_quality "$total" "$index" 2>&1)"; then
    log "shard ${index}/${total} quality OK after rescue"
    return 0
  fi
  log "shard ${index}/${total} still failed quality after rescue: $reason"
  return 1
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
if ! python3 "$DIR/platforms/blinkit/coordinate_preflight.py" "$SOURCE_CONFIG" --compact --summary >>"$LOG_FILE" 2>&1; then
  log "Blinkit coordinate preflight failed; refusing fallback"
  tg "[FAIL] Blinkit fallback cannot start for ${TODAY}: pincode coordinates failed preflight."
  exit 1
fi
if ! clocks_healthy; then
  log "VPS/KVM1 clock preflight failed; refusing time-unsafe fallback"
  tg "[FAIL] Blinkit fallback cannot start for ${TODAY}: VPS/KVM1 clock sync or drift check failed."
  exit 1
fi
if ! store_open_window; then
  log "before 07:00 IST store-open window; refusing full fallback unless BLINKIT_FALLBACK_EARLY_OK=1"
  exit 0
fi
if ! kvm1_blinkit_proxy_healthy; then
  log "KVM1 Mac Air SOCKS/Blinkit proxy is unavailable; refusing invalid VPS-direct fallback"
  tg "[FAIL] Blinkit fallback cannot start for ${TODAY}: KVM1 Mac Air SOCKS/Blinkit proxy health failed. VPS-direct Blinkit is disabled to avoid bad auth/OOS data."
  exit 1
fi

TOTAL=2
KVM_OK=0
START_LOCAL=1
START_REMOTE=0
LOCAL_BUSY=0
KVM_BUSY=0
refresh_host_busy_state
wait_for_less_contention

if [ "${BLINKIT_ALLOW_VPS_DIRECT_FALLBACK:-0}" != "1" ]; then
  TOTAL=1
  START_LOCAL=0
  START_REMOTE=1
  if [ "$KVM_BUSY" -eq 1 ]; then
    log "KVM1 has active non-Blinkit browser work; refusing VPS-direct Blinkit fallback"
    tg "[FAIL] Blinkit fallback cannot start for ${TODAY}: KVM1 is busy and VPS-direct Blinkit fallback is disabled."
    exit 1
  fi
  if prepare_kvm1; then
    KVM_OK=1
    log "VPS-direct Blinkit fallback disabled; using one authenticated KVM1 proxy-backed shard"
  else
    log "KVM1 preparation failed after proxy health passed; refusing VPS-direct Blinkit fallback"
    tg "[FAIL] Blinkit fallback cannot start for ${TODAY}: KVM1 preparation failed and VPS-direct Blinkit fallback is disabled."
    exit 1
  fi
elif [ "$LOCAL_BUSY" -eq 0 ] && [ "$KVM_BUSY" -eq 0 ] && prepare_kvm1; then
  KVM_OK=1
  START_REMOTE=1
elif [ "$LOCAL_BUSY" -eq 1 ] && [ "$KVM_BUSY" -eq 0 ] && prepare_kvm1; then
  TOTAL=1
  KVM_OK=1
  START_LOCAL=0
  START_REMOTE=1
  log "VPS has active non-Blinkit browser work; using one full authenticated KVM1 shard to avoid local contention"
  tg "[WARN] Blinkit fallback: VPS is busy with other browser work, so ${TODAY} will run as one authenticated KVM1 shard to avoid quality risk."
elif [ "$KVM_BUSY" -eq 1 ] && [ "$LOCAL_BUSY" -eq 0 ]; then
  TOTAL=1
  log "KVM1 has active non-Blinkit browser work; using one full authenticated VPS shard to avoid contention"
  tg "[WARN] Blinkit fallback: KVM1 is busy with other browser work, so ${TODAY} will run as one authenticated VPS shard to avoid quality risk."
elif [ "$LOCAL_BUSY" -eq 1 ] && [ "$KVM_BUSY" -eq 1 ]; then
  TOTAL=1
  EFFECTIVE_CONCURRENCY="${BLINKIT_FALLBACK_BUSY_CONCURRENCY:-1}"
  log "both VPS and KVM1 have active non-Blinkit browser work; using one low-concurrency authenticated VPS shard"
  tg "[WARN] Blinkit fallback: both VPS and KVM1 are busy with other browser work, so ${TODAY} will run as one low-concurrency authenticated VPS shard."
else
  TOTAL=1
  log "KVM1 preparation failed; falling back to one full authenticated VPS shard"
  tg "[WARN] Blinkit fallback: KVM1 prep failed, running the full authenticated scrape on VPS only for ${TODAY}."
fi

log "fallback run start run_id=$RUN_ID total_shards=$TOTAL"
if [ "$START_LOCAL" -eq 1 ] && [ "$START_REMOTE" -eq 1 ]; then
  tg "[START] Blinkit fallback started for ${TODAY}: Mac unavailable, running authenticated 2-shard scrape on VPS + KVM1."
elif [ "$START_REMOTE" -eq 1 ]; then
  tg "[START] Blinkit fallback started for ${TODAY}: Mac unavailable, running authenticated scrape on KVM1 only."
else
  tg "[START] Blinkit fallback started for ${TODAY}: Mac unavailable, running authenticated scrape on VPS only."
fi

LOCAL_RC=0
REMOTE_RC=0
LOCAL_PID=""
REMOTE_PID=""
if [ "$START_LOCAL" -eq 1 ]; then
  run_local_shard "$TOTAL" 0 "vps" &
  LOCAL_PID=$!
fi
if [ "$START_REMOTE" -eq 1 ]; then
  if [ "$START_LOCAL" -eq 1 ]; then
    run_kvm1_shard "$TOTAL" 1 &
  else
    run_kvm1_shard "$TOTAL" 0 &
  fi
  REMOTE_PID=$!
fi

if [ -n "$LOCAL_PID" ]; then
  wait "$LOCAL_PID" || LOCAL_RC=$?
fi
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

for i in $(seq 0 "$((TOTAL - 1))"); do
  if ! repair_shard_quality_if_needed "$TOTAL" "$i" "vps"; then
    log "shard ${i}/${TOTAL} failed quality and could not be rescued"
    tg "[FAIL] Blinkit fallback failed: shard ${i}/${TOTAL} could not pass auth/OOS quality for ${TODAY}."
    exit 1
  fi
done

if merge_and_ingest "$TOTAL"; then
  log "fallback PASS; report=$REPORT not_listed=$NOT_LISTED"
  tg "[OK] Blinkit fallback finished and passed gates for ${TODAY}; workbook created and WhatsApp delivery hooks ran."
  exit 0
fi

log "fallback failed during merge/ingest; see log"
tg "[FAIL] Blinkit fallback failed during merge/ingest for ${TODAY}; report was not delivered. Check $LOG_FILE"
exit 1
