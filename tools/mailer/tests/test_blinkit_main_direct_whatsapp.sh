#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DATE="2099-01-05"
MISSING_DATE="2099-01-06"
HELD_DATE="2099-01-07"
FIXTURE="$ROOT/platforms/blinkit/tests/fixtures/false_oos_price_mismatch.json"
GOOD_RESULT="$(mktemp)"
BAD_RESULT="$(mktemp)"
OUT_GOOD="$(mktemp)"
OUT_MISSING="$(mktemp)"
OUT_HELD="$(mktemp)"
BLINKIT_FILE="$ROOT/output/Jivo-Blinkit-Live-Report-${DATE}.xlsx"
NOT_LISTED_FILE="$ROOT/output/Jivo-Blinkit-Not-Listed-Pincodes-${DATE}.xlsx"
MISSING_NOT_LISTED_FILE="$ROOT/output/Jivo-Blinkit-Not-Listed-Pincodes-${MISSING_DATE}.xlsx"
HELD_BLINKIT_FILE="$ROOT/output/Jivo-Blinkit-Live-Report-${HELD_DATE}.xlsx"
HELD_NOT_LISTED_FILE="$ROOT/output/Jivo-Blinkit-Not-Listed-Pincodes-${HELD_DATE}.xlsx"

cleanup() {
  rm -f "$GOOD_RESULT" "$BAD_RESULT" "$OUT_GOOD" "$OUT_MISSING" "$OUT_HELD"
  rm -f "$BLINKIT_FILE" "$NOT_LISTED_FILE" "$MISSING_NOT_LISTED_FILE" "$HELD_BLINKIT_FILE" "$HELD_NOT_LISTED_FILE"
  rm -f "$ROOT/logs/blinkit-main-wa-${DATE}.sent"
  rm -f "$ROOT/logs/blinkit-main-wa-${MISSING_DATE}.sent"
  rm -f "$ROOT/logs/blinkit-main-wa-${HELD_DATE}.sent"
  rm -f "$ROOT/logs/blinkit_quality_monitor-${DATE}.log" "$ROOT/logs/blinkit_quality_monitor-${DATE}.state"
  rm -f "$ROOT/logs/blinkit_quality_monitor-${MISSING_DATE}.log" "$ROOT/logs/blinkit_quality_monitor-${MISSING_DATE}.state"
  rm -f "$ROOT/logs/blinkit_quality_monitor-${HELD_DATE}.log" "$ROOT/logs/blinkit_quality_monitor-${HELD_DATE}.state"
}
trap cleanup EXIT

python3 - "$FIXTURE" "$GOOD_RESULT" "$BAD_RESULT" "$BLINKIT_FILE" "$NOT_LISTED_FILE" "$MISSING_NOT_LISTED_FILE" "$HELD_BLINKIT_FILE" "$HELD_NOT_LISTED_FILE" <<'PY'
import json
import sys
from openpyxl import Workbook

src, good_result_path, bad_result_path, blinkit_path, not_listed_path, missing_not_listed_path, held_blinkit_path, held_not_listed_path = sys.argv[1:]
d = json.load(open(src, encoding="utf-8"))
d["summary"]["captured_at"] = "2099-01-05T04:00:00.000Z"
d["summary"]["pdp_price_probe_enabled"] = 1
d["summary"]["pdp_price_probe_attempted"] = 1
d["summary"]["pdp_price_probe_checked"] = 1
d["summary"]["pdp_price_probe_failed"] = 0
d["summary"]["pdp_price_probe_updates"] = 0
json.dump(d, open(good_result_path, "w", encoding="utf-8"))

bad = json.loads(json.dumps(d))
bad["summary"]["captured_at"] = "2099-01-07T04:00:00.000Z"
bad["summary"]["pdp_price_probe_attempted"] = 2
bad["summary"]["pdp_price_probe_failed"] = 1
json.dump(bad, open(bad_result_path, "w", encoding="utf-8"))

def main_workbook(path):
    wb = Workbook()
    ws = wb.active
    ws.title = "Master Data"
    ws.append(["Product status", "Stock source", "Price source", "Base Sale Rs", "Offer Rs"])
    wb.create_sheet("Listing Status").append(["City", "Pincode", "SKU", "Product status", "Source"])
    wb.create_sheet("Not Listed Pincodes").append(["City", "Pincode", "SKU", "Source"])
    wb.save(path)

def not_listed_workbook(path):
    nl = Workbook()
    nl.active.title = "Not Listed Pincodes"
    nl.active.append(["City", "Pincode", "SKU", "Source"])
    nl.save(path)

main_workbook(blinkit_path)
not_listed_workbook(not_listed_path)
not_listed_workbook(missing_not_listed_path)
main_workbook(held_blinkit_path)
not_listed_workbook(held_not_listed_path)
PY

cd "$ROOT"
BLINKIT_MAIN_WA_DATE="$DATE" \
BLINKIT_MONITOR_RESULT="$GOOD_RESULT" \
BLINKIT_MONITOR_REPORT="$BLINKIT_FILE" \
BLINKIT_MONITOR_NOT_LISTED_REPORT="$NOT_LISTED_FILE" \
MAILER_TEST_MODE=1 \
  "$ROOT/tools/whatsapp/send_blinkit_main_direct.sh" test > "$OUT_GOOD"

grep -q "TEST WhatsApp direct main: 120363047864912511@g.us Jivo-Blinkit-Live-Report-${DATE}.xlsx" "$OUT_GOOD"

printf 'already sent\n' > "$ROOT/logs/blinkit-main-wa-${DATE}.sent"
MARKER_OUT="$(BLINKIT_MAIN_WA_DATE="$DATE" \
  BLINKIT_MONITOR_RESULT=/does/not/exist.json \
  BLINKIT_MONITOR_REPORT="$BLINKIT_FILE" \
  BLINKIT_MONITOR_NOT_LISTED_REPORT="$NOT_LISTED_FILE" \
  MAILER_TEST_MODE=1 \
  "$ROOT/tools/whatsapp/send_blinkit_main_direct.sh" test)"
echo "$MARKER_OUT" | grep -q "already sent for ${DATE}"
if echo "$MARKER_OUT" | grep -q "TEST WhatsApp direct main:"; then
  echo "expected marker to suppress duplicate direct main send" >&2
  echo "$MARKER_OUT" >&2
  exit 1
fi

BLINKIT_MAIN_WA_DATE="$MISSING_DATE" \
BLINKIT_MONITOR_RESULT="$GOOD_RESULT" \
BLINKIT_MONITOR_REPORT="$ROOT/output/Jivo-Blinkit-Live-Report-${MISSING_DATE}.xlsx" \
BLINKIT_MONITOR_NOT_LISTED_REPORT="$MISSING_NOT_LISTED_FILE" \
MAILER_TEST_MODE=1 \
  "$ROOT/tools/whatsapp/send_blinkit_main_direct.sh" test > "$OUT_MISSING"
grep -q "main workbook is missing" "$OUT_MISSING"

BLINKIT_MAIN_WA_DATE="$HELD_DATE" \
BLINKIT_MONITOR_RESULT="$BAD_RESULT" \
BLINKIT_MONITOR_REPORT="$HELD_BLINKIT_FILE" \
BLINKIT_MONITOR_NOT_LISTED_REPORT="$HELD_NOT_LISTED_FILE" \
MAILER_TEST_MODE=1 \
  "$ROOT/tools/whatsapp/send_blinkit_main_direct.sh" test > "$OUT_HELD"
grep -q "quality gate held the report" "$OUT_HELD"

echo "PASS mailer Blinkit main direct WhatsApp regression"
