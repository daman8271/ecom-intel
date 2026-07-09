#!/bin/bash
set -euo pipefail

BASE="/Users/danny./VPS-Migration"
PROJECT="${BASE}/imported/ecom-intel/platforms/zepto"
LOG_DIR="${BASE}/logs/zepto"
LOCK_DIR="/tmp/com.danny.zepto-mac-to-vps.lock"
VPS="root@187.127.129.132"
REMOTE_DROP="/opt/ecom-intel/platforms/zepto/mac-drops"
REMOTE_INGEST="/opt/ecom-intel/tools/cron/macpro_zepto_ingest.sh"
CONFIG="${PINCODES_FILE:-$PROJECT/pincodes.daily.json}"

mkdir -p "$LOG_DIR"
LOG="${LOG_DIR}/run-$(date +%F-%H%M%S).log"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "[$(date)] another Zepto Mac run is active: $LOCK_DIR" | tee -a "$LOG"
  exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

. "${BASE}/bin/node22-env.sh"
cd "$PROJECT"
mkdir -p mac-runs

if [[ ! -f "$CONFIG" ]]; then
  echo "[$(date)] ERROR: missing pincode config: $CONFIG" | tee -a "$LOG"
  exit 1
fi

RUN_ID="$(date +%Y%m%d-%H%M%S)"
OUT="${PROJECT}/mac-runs/zepto-${RUN_ID}.json"

export CONCURRENCY="${CONCURRENCY:-3}"
export ZEPTO_SEED_VARIANTS="${ZEPTO_SEED_VARIANTS:-1}"
echo "[$(date)] Zepto Mac scrape start config=$CONFIG concurrency=$CONCURRENCY out=$OUT" | tee -a "$LOG"
if command -v caffeinate >/dev/null 2>&1; then
  caffeinate -dimsu env PINCODES_FILE="$CONFIG" OUT_FILE="$OUT" node scrape.js >> "$LOG" 2>&1
else
  PINCODES_FILE="$CONFIG" OUT_FILE="$OUT" node scrape.js >> "$LOG" 2>&1
fi

if [[ ! -s "$OUT" ]]; then
  echo "[$(date)] ERROR: Zepto scrape did not produce $OUT" | tee -a "$LOG"
  exit 1
fi

python3 - "$OUT" >> "$LOG" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
s = d.get("summary") or {}
print({
    "pincodes_total": s.get("pincodes_total"),
    "pincodes_with_jivo": s.get("pincodes_with_jivo"),
    "pincodes_blocked": s.get("pincodes_blocked"),
    "total_rows": s.get("total_rows"),
    "partial": s.get("partial") or d.get("partial"),
})
PY

REMOTE_SCAN="${REMOTE_DROP}/$(basename "$OUT")"
echo "[$(date)] dropping Zepto result to VPS: $REMOTE_SCAN" | tee -a "$LOG"
ssh -o BatchMode=yes "$VPS" "mkdir -p '$REMOTE_DROP'"
rsync -azP "$OUT" "${VPS}:${REMOTE_DROP}/" >> "$LOG" 2>&1

echo "[$(date)] triggering VPS Zepto ingest" | tee -a "$LOG"
ssh -o BatchMode=yes -o ConnectTimeout=20 "$VPS" \
  "cd /opt/ecom-intel && '$REMOTE_INGEST' '$REMOTE_SCAN' >> /opt/ecom-intel/logs/zepto-mac-ingest.log 2>&1"

echo "[$(date)] Zepto Mac scrape/drop/ingest DONE: $OUT" | tee -a "$LOG"
