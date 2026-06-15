#!/usr/bin/env bash
# Daily BigBasket PINCODE-WISE Jivo pull via the licensed QuickCommerce API (PAID key).
# Pulls the 92 Jivo-present pincodes (pincodes_jivo.json, incl. price-match pins),
# builds the report, copies to output/, and delivers to Telegram. Decoupled from the
# deadline sweep on purpose. Single PAID key only — never trial-key rotation.
set -uo pipefail
cd "$(dirname "$0")"
LOG=/opt/ecom-intel/logs/bigbasket-pincode.log
echo "[$(date '+%F %T')] bigbasket-pincode START" >> "$LOG"

PINCODES_FILE="${PINCODES_FILE:-pincodes_jivo.json}" QC_LIMIT="${QC_LIMIT:-999}" python3 qc_pull.py >> "$LOG" 2>&1 || { echo "[$(date '+%F %T')] qc_pull FAILED" >> "$LOG"; exit 1; }
python3 build_excel_pincode.py >> "$LOG" 2>&1 || { echo "[$(date '+%F %T')] build_excel FAILED" >> "$LOG"; exit 1; }

F=$(ls -t Jivo-BigBasket-Pincode-Report-*.xlsx 2>/dev/null | head -1)
[ -n "$F" ] && cp "$F" /opt/ecom-intel/output/ 2>/dev/null || true

if [ -n "${F:-}" ] && [ -f "$HOME/.config/tg/env" ]; then
  set -a; . "$HOME/.config/tg/env"; set +a
  SUM=$(python3 -c "import json;d=json.load(open('result_pincode.json'))['summary'];print(f\"{d['pincodes_with_jivo']}/{d['pincodes_total']} pincodes carry Jivo | {d['unique_skus']} SKUs | {d['total_rows']} rows\")" 2>/dev/null)
  curl -s --max-time 90 -F chat_id="$TELEGRAM_CHAT_ID" -F document=@"$F" \
    -F caption="Jivo × BigBasket pincode-wise (daily, licensed QC API). $SUM" \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" >/dev/null 2>&1 \
    && echo "[$(date '+%F %T')] delivered $F" >> "$LOG" || echo "[$(date '+%F %T')] TG send failed (report still in output/)" >> "$LOG"
fi
echo "[$(date '+%F %T')] bigbasket-pincode DONE" >> "$LOG"
