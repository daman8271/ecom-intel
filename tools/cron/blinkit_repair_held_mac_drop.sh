#!/usr/bin/env bash
# Repair a held Blinkit Mac drop by rerunning only bad pincodes on Mac Pro.
#
# This does not loosen quality gates. It targets pincodes with unverified OOS,
# PDP price probe failures, or per-pincode auth failures, patches those full
# pincode results into the held Mac drop, then sends the patched drop through the
# normal platforms/blinkit/ingest.sh gate.
set -uo pipefail

ROOT=/opt/ecom-intel
cd "$ROOT" || exit 1

DATE_IST="${BLINKIT_REPAIR_DATE:-$(TZ=Asia/Kolkata date +%F)}"
DATE_COMPACT="${DATE_IST//-/}"
LOG="logs/blinkit-mac-drop-repair-${DATE_IST}.log"
LOCK="logs/.blinkit-mac-drop-repair.lock"
SOURCE_CONFIG="$ROOT/platforms/blinkit/pincodes.daily.json"
MAC_BASE="/Users/danny./VPS-Migration"
MAC_PROJECT="$MAC_BASE/imported/ecom-intel/platforms/blinkit"
MAC_AUTH="$MAC_BASE/secrets/blinkit-auth-state.json"

mkdir -p logs platforms/blinkit/mac-repairs

log() {
  printf '[%s] blinkit_mac_drop_repair: %s\n' "$(TZ=Asia/Kolkata date '+%F %T %Z')" "$*" | tee -a "$LOG"
}

exec 9>"$LOCK"
if ! flock -n 9; then
  log "another repair holds $LOCK; exiting"
  exit 0
fi

# Callers (e.g. blinkit_team_merge.sh pre-verify) may point the repair straight at
# an already-merged drop instead of the newest mac-drop glob. When set and non-empty,
# BLINKIT_REPAIR_BASE_DROP wins; otherwise fall back to the mac-drop discovery below.
if [ -n "${BLINKIT_REPAIR_BASE_DROP:-}" ] && [ -s "${BLINKIT_REPAIR_BASE_DROP:-}" ]; then
  BASE_DROP="$BLINKIT_REPAIR_BASE_DROP"
  log "using caller-provided base drop: $BASE_DROP"
else
BASE_DROP="$(python3 - "$DATE_IST" "$DATE_COMPACT" <<'PY'
from __future__ import annotations
import glob, os, sys
date_ist, compact = sys.argv[1:3]
patterns = [
    f"/opt/ecom-intel/platforms/blinkit/mac-drops/blinkit-{compact}-*.json",
    f"/opt/ecom-intel/platforms/blinkit/mac-drops/blinkit-{compact}T*.json",
]
paths = []
for pattern in patterns:
    paths.extend(glob.glob(pattern))
paths = [p for p in paths if os.path.getsize(p) > 0]
paths.sort(key=os.path.getmtime, reverse=True)
print(paths[0] if paths else "")
PY
)"
fi

if [ -z "$BASE_DROP" ] || [ ! -s "$BASE_DROP" ]; then
  log "no Mac drop found for $DATE_IST"
  exit 0
fi

STAMP="logs/.blinkit-mac-drop-repair-${DATE_IST}-$(basename "$BASE_DROP").stamp"
if [ -f "$STAMP" ] && [ "$(( $(date +%s) - $(stat -c %Y "$STAMP" 2>/dev/null || echo 0) ))" -lt "${BLINKIT_MAC_DROP_REPAIR_THROTTLE_S:-1800}" ]; then
  log "repair recently attempted for $(basename "$BASE_DROP"); throttled"
  exit 0
fi
touch "$STAMP"

RUN_ID="blinkit-mac-repair-${DATE_COMPACT}-$(TZ=Asia/Kolkata date +%H%M%S)"
TARGET_CONFIG="$ROOT/platforms/blinkit/mac-repairs/${RUN_ID}-pincodes.json"
TARGET_RESULT="$ROOT/platforms/blinkit/mac-repairs/${RUN_ID}-result.json"
PATCHED_DROP="$ROOT/platforms/blinkit/mac-repairs/${RUN_ID}-patched.json"
REMOTE_CONFIG="/tmp/${RUN_ID}-pincodes.json"
REMOTE_LOG="$MAC_BASE/logs/blinkit/${RUN_ID}.log"
REMOTE_PROGRESS="/tmp/${RUN_ID}.progress.json"
TARGET_CONFIG_LOG="$(mktemp)"
trap 'rm -f "$TARGET_CONFIG_LOG"' EXIT

python3 - "$BASE_DROP" "$SOURCE_CONFIG" "$TARGET_CONFIG" >"$TARGET_CONFIG_LOG" 2>&1 <<'PY'
import json, sys
from pathlib import Path

base_path, source_path, target_path = map(Path, sys.argv[1:4])
data = json.loads(base_path.read_text(encoding="utf-8"))
source = json.loads(source_path.read_text(encoding="utf-8"))

def truthy(value):
    if value is True:
        return True
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return value == 1
    return str(value).strip().lower() in {"1", "true", "yes", "y"}

def pin(value):
    return str(value or "").strip()

def is_oos(row):
    value = row.get("in_stock")
    if value is False or value == 0:
        return True
    if str(value).strip().lower() in {"0", "false", "no"}:
        return True
    status = str(row.get("listing_status") or row.get("status") or row.get("availability") or "").lower()
    return "out_of_stock" in status or "out of stock" in status or status == "oos"

def is_stock_unverified(row):
    # Mirrors platforms/blinkit/ingest.sh is_stock_unverified_row (the gate that
    # refused Delhi:110040:jivo-pomace-olive-oil-5l on 2026-07-13/14). A fail-closed
    # search-card OOS row that no probe could verify (in_stock=null,
    # listing_status=stock_unverified, stock_source=*_unverified). The prior bad-pin
    # detection missed these entirely (in_stock=null is neither False/0 nor an OOS
    # status string), so a lone unverified row was never rescraped -> the whole drop
    # sat held. Rescraping the pin re-runs the OOS/PDP probes and clears it.
    status = str(row.get("listing_status") or "").strip().lower()
    source = str(row.get("stock_source") or "").strip().lower()
    return bool(row.get("stock_unverified")) or status == "stock_unverified" or source.endswith("_unverified")

bad = set()
for rec in data.get("perPin") or []:
    if isinstance(rec, dict) and pin(rec.get("pincode")) and not truthy(rec.get("auth_accepted")):
        bad.add(pin(rec.get("pincode")))
for row in data.get("allRows") or []:
    if not isinstance(row, dict):
        continue
    p = pin(row.get("pincode"))
    if not p:
        continue
    stock_source = str(row.get("stock_source") or "").strip().lower()
    if row.get("pdp_price_probe_failed"):
        bad.add(p)
    if is_stock_unverified(row):
        bad.add(p)
    if is_oos(row) and not truthy(row.get("pdp_checked")) and stock_source not in {"pdp", "pdp_probe"}:
        bad.add(p)

if not bad:
    print("no bad pincodes in latest Mac drop")
    raise SystemExit(3)

source_by_pin = {pin(rec.get("pincode")): rec for rec in source if isinstance(rec, dict)}
missing = sorted(p for p in bad if p not in source_by_pin)
if missing:
    raise SystemExit(f"bad pincodes missing from source config: {missing}")

target = [source_by_pin[p] for p in sorted(bad)]
Path(target_path).write_text(json.dumps(target, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(json.dumps({"base_drop": str(base_path), "target_config": str(target_path), "bad_pincodes": sorted(bad)}, indent=2))
PY
rc=$?
tee -a "$LOG" < "$TARGET_CONFIG_LOG" >/dev/null
if [ "$rc" != "0" ]; then
  if [ "$rc" = "3" ]; then
    log "latest Mac drop has no repairable bad pincodes"
    exit 0
  fi
  log "failed to build targeted repair config"
  exit 1
fi

log "copying targeted config to Mac Pro: $REMOTE_CONFIG"
rsync -az "$TARGET_CONFIG" "macpro:$REMOTE_CONFIG" >>"$LOG" 2>&1 || { log "failed to copy target config to Mac Pro"; exit 1; }

remote_script=$(cat <<EOF
set -euo pipefail
mkdir -p "$MAC_BASE/logs/blinkit" "$MAC_PROJECT/mac-runs"
. "$MAC_BASE/bin/node22-env.sh"
cd "$MAC_PROJECT"
OUT="$MAC_PROJECT/mac-runs/${RUN_ID}.json"
export CONCURRENCY="${BLINKIT_MAC_REPAIR_CONCURRENCY:-1}"
export BLINKIT_REQUIRE_AUTH=1
export BLINKIT_OOS_PROBE=1
export BLINKIT_PDP_OOS_PROBE=1
export BLINKIT_PDP_PRICE_PROBE=1
echo "[\$(date)] Blinkit targeted repair start config=$REMOTE_CONFIG out=\$OUT" >> "$REMOTE_LOG"
if command -v caffeinate >/dev/null 2>&1; then
  caffeinate -dimsu env PINCODES_FILE="$REMOTE_CONFIG" OUT_FILE="\$OUT" BLINKIT_PROGRESS_FILE="$REMOTE_PROGRESS" BLINKIT_AUTH_STATE_FILE="$MAC_AUTH" node scrape.js >> "$REMOTE_LOG" 2>&1
else
  PINCODES_FILE="$REMOTE_CONFIG" OUT_FILE="\$OUT" BLINKIT_PROGRESS_FILE="$REMOTE_PROGRESS" BLINKIT_AUTH_STATE_FILE="$MAC_AUTH" node scrape.js >> "$REMOTE_LOG" 2>&1
fi
[ -s "\$OUT" ]
printf '%s\n' "\$OUT"
EOF
)

log "running targeted repair on Mac Pro"
REMOTE_RESULT="$(ssh -o BatchMode=yes -o ConnectTimeout=20 macpro "bash -lc $(printf '%q' "$remote_script")" | tail -1)"
if [ -z "$REMOTE_RESULT" ]; then
  log "Mac Pro targeted repair did not return a result path"
  exit 1
fi

log "copying targeted result from Mac Pro: $REMOTE_RESULT"
rsync -az "macpro:$REMOTE_RESULT" "$TARGET_RESULT" >>"$LOG" 2>&1 || { log "failed to copy target result"; exit 1; }

log "validating targeted result"
python3 - "$TARGET_RESULT" <<'PY' | tee -a "$LOG"
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
s = d.get("summary") or {}
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
    raise SystemExit("targeted repair failed auth verification")
if int(s.get("unverified_oos") or 0) != 0:
    raise SystemExit("targeted repair still has unverified OOS")
if int(s.get("pdp_price_probe_failed") or 0) != 0:
    raise SystemExit("targeted repair still has PDP price probe failures")
PY
if [ "${PIPESTATUS[0]}" != "0" ]; then
  log "targeted result failed quality validation"
  exit 1
fi

log "patching targeted pins into held Mac drop"
python3 "$ROOT/tools/cron/blinkit_apply_targeted_shard_repair.py" \
  "$BASE_DROP" "$TARGET_RESULT" "$PATCHED_DROP" >>"$LOG" 2>&1 || exit 1

log "ingesting patched drop through normal Blinkit gates"
# Repair keeps auth/OOS/price gates strict. ETA is non-price metadata and Blinkit
# sometimes omits it on otherwise healthy in-stock search cards; allow a bounded
# repair-only floor instead of fabricating ETA values.
BLINKIT_MAX_WALL_S="${BLINKIT_MAX_WALL_S:-9000}" BLINKIT_REQUIRE_AUTH_DROP=1 BLINKIT_MIN_ETA_PCT="${BLINKIT_REPAIR_MIN_ETA_PCT:-85}" \
  "$ROOT/platforms/blinkit/ingest.sh" "$PATCHED_DROP" --deliver >>"$LOG" 2>&1 || exit 1

log "done"
