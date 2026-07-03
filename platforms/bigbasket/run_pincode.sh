#!/usr/bin/env bash
# RETIRED: old BigBasket PINCODE-WISE pull via the licensed QuickCommerce API.
# BigBasket now runs off-box on the Mac Pro/residential IP and drops JSON to
# platforms/bigbasket/ingest.sh. This script is kept only as an explicit emergency
# diagnostic path and refuses to call the paid API unless ALLOW_BIGBASKET_QC_API=1.
set -uo pipefail
cd "$(dirname "$0")"
LOG=/opt/ecom-intel/logs/bigbasket-pincode.log
echo "[$(date '+%F %T')] bigbasket-pincode START" >> "$LOG"

if [ "${ALLOW_BIGBASKET_QC_API:-0}" != "1" ]; then
  echo "[$(date '+%F %T')] REFUSED: QuickCommerce API path is retired; use Mac Pro -> platforms/bigbasket/ingest.sh" >> "$LOG"
  echo "BigBasket QuickCommerce API path is retired. Use Mac Pro browser runner -> platforms/bigbasket/ingest.sh." >&2
  exit 2
fi

PINCODES_FILE="${PINCODES_FILE:-pincodes_jivo.json}" QC_LIMIT="${QC_LIMIT:-999}" python3 qc_pull.py >> "$LOG" 2>&1 || { echo "[$(date '+%F %T')] qc_pull FAILED" >> "$LOG"; exit 1; }
python3 build_excel_pincode.py >> "$LOG" 2>&1 || { echo "[$(date '+%F %T')] build_excel FAILED" >> "$LOG"; exit 1; }

F=$(ls -t Jivo-BigBasket-Pincode-Report-*.xlsx 2>/dev/null | head -1)
# copy into output/ so BOTH deadline sweeps (run_all.sh) and the mailer pick it up
[ -n "$F" ] && cp "$F" /opt/ecom-intel/output/ 2>/dev/null && echo "[$(date '+%F %T')] report -> output/$(basename "$F") (batches + mailer deliver it)" >> "$LOG" || true
echo "[$(date '+%F %T')] bigbasket-pincode DONE" >> "$LOG"
