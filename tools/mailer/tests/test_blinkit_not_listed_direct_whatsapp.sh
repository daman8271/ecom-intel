#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DATE="2099-01-02"
FIXTURE="$ROOT/platforms/blinkit/tests/fixtures/false_oos_price_mismatch.json"
GOOD_RESULT="$(mktemp)"
OUT="$(mktemp)"
BLINKIT_FILE="$ROOT/output/Jivo-Blinkit-Live-Report-${DATE}.xlsx"
NOT_LISTED_FILE="$ROOT/output/Jivo-Blinkit-Not-Listed-Pincodes-${DATE}.xlsx"

cleanup() {
  rm -f "$GOOD_RESULT" "$OUT" "$BLINKIT_FILE" "$NOT_LISTED_FILE"
  rm -f "$ROOT/logs/blinkit_quality_monitor-${DATE}.log" "$ROOT/logs/blinkit_quality_monitor-${DATE}.state"
}
trap cleanup EXIT

python3 - "$FIXTURE" "$GOOD_RESULT" "$BLINKIT_FILE" "$NOT_LISTED_FILE" <<'PY'
import json
import sys
from openpyxl import Workbook

src, result_path, blinkit_path, not_listed_path = sys.argv[1:]
d = json.load(open(src, encoding="utf-8"))
d["summary"]["captured_at"] = "2099-01-02T04:00:00.000Z"
json.dump(d, open(result_path, "w", encoding="utf-8"))

wb = Workbook()
ws = wb.active
ws.title = "Master Data"
ws.append(["Product status", "Stock source", "Price source", "Base Sale Rs", "Offer Rs"])
wb.create_sheet("Listing Status").append(["City", "Pincode", "SKU", "Product status", "Source"])
wb.create_sheet("Not Listed Pincodes").append(["City", "Pincode", "SKU", "Source"])
wb.save(blinkit_path)

nl = Workbook()
nl.active.title = "Not Listed Pincodes"
nl.active.append(["City", "Pincode", "SKU", "Source"])
nl.save(not_listed_path)
PY

cd "$ROOT"
PRICE_MAIL_DATE="$DATE" \
MAILER_NO_REDIRECT=1 \
MAILER_TEST_MODE=1 \
MAILER_DRY_RUN_SEND=1 \
MAILER_SKIP_WAIT=1 \
BLINKIT_MONITOR_RESULT="$GOOD_RESULT" \
  tools/mailer/mail_price_data.sh test > "$OUT"

grep -q "DRYRUN email:" "$OUT"
grep -q "TEST WhatsApp group:" "$OUT"
grep -q "TEST WhatsApp direct not-listed: 917703818227@s.whatsapp.net Jivo-Blinkit-Not-Listed-Pincodes-${DATE}.xlsx" "$OUT"

echo "PASS mailer Blinkit not-listed direct WhatsApp regression"
