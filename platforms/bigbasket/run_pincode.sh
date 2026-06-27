#!/usr/bin/env bash
# Daily BigBasket PINCODE-WISE Jivo pull via the licensed QuickCommerce API (PAID key).
# Pulls ONCE/day (03:00) the 227 Jivo pincodes (pincodes_jivo.json, incl. price-match pins +
# the 2026-06-28 tier-1 expansion), builds the report, copies it to output/. Delivery is NOT done
# here — run_all.sh spools this report into the noon deadline batch (12:00) so it lands WITH the
# other platforms on Telegram, and the mailer ships it on WhatsApp + Gmail (10:00). Single PAID key only.
set -uo pipefail
cd "$(dirname "$0")"
LOG=/opt/ecom-intel/logs/bigbasket-pincode.log
echo "[$(date '+%F %T')] bigbasket-pincode START" >> "$LOG"

PINCODES_FILE="${PINCODES_FILE:-pincodes_jivo.json}" QC_LIMIT="${QC_LIMIT:-999}" python3 qc_pull.py >> "$LOG" 2>&1 || { echo "[$(date '+%F %T')] qc_pull FAILED" >> "$LOG"; exit 1; }
python3 build_excel_pincode.py >> "$LOG" 2>&1 || { echo "[$(date '+%F %T')] build_excel FAILED" >> "$LOG"; exit 1; }

F=$(ls -t Jivo-BigBasket-Pincode-Report-*.xlsx 2>/dev/null | head -1)
# copy into output/ so BOTH deadline sweeps (run_all.sh) and the mailer pick it up
[ -n "$F" ] && cp "$F" /opt/ecom-intel/output/ 2>/dev/null && echo "[$(date '+%F %T')] report -> output/$(basename "$F") (batches + mailer deliver it)" >> "$LOG" || true
echo "[$(date '+%F %T')] bigbasket-pincode DONE" >> "$LOG"
