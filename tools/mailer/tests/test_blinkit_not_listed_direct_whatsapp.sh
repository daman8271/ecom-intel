#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DATE="2099-01-02"
MISSING_MAIN_DATE="2099-01-03"
HELD_DATE="2099-01-04"
FIXTURE="$ROOT/platforms/blinkit/tests/fixtures/false_oos_price_mismatch.json"
GOOD_RESULT="$(mktemp)"
BAD_RESULT="$(mktemp)"
OUT_GOOD="$(mktemp)"
OUT_MISSING_MAIN="$(mktemp)"
OUT_HELD="$(mktemp)"
BLINKIT_FILE="$ROOT/output/Jivo-Blinkit-Live-Report-${DATE}.xlsx"
NOT_LISTED_FILE="$ROOT/output/Jivo-Blinkit-Not-Listed-Pincodes-${DATE}.xlsx"
MISSING_MAIN_NOT_LISTED_FILE="$ROOT/output/Jivo-Blinkit-Not-Listed-Pincodes-${MISSING_MAIN_DATE}.xlsx"
MISSING_MAIN_ZEPTO_FILE="$ROOT/output/Jivo-Zepto-Live-Report-${MISSING_MAIN_DATE}.xlsx"
HELD_BLINKIT_FILE="$ROOT/output/Jivo-Blinkit-Live-Report-${HELD_DATE}.xlsx"
HELD_NOT_LISTED_FILE="$ROOT/output/Jivo-Blinkit-Not-Listed-Pincodes-${HELD_DATE}.xlsx"
HELD_ZEPTO_FILE="$ROOT/output/Jivo-Zepto-Live-Report-${HELD_DATE}.xlsx"

cleanup() {
  rm -f "$GOOD_RESULT" "$BAD_RESULT" "$OUT_GOOD" "$OUT_MISSING_MAIN" "$OUT_HELD"
  rm -f "$BLINKIT_FILE" "$NOT_LISTED_FILE"
  rm -f "$MISSING_MAIN_NOT_LISTED_FILE" "$MISSING_MAIN_ZEPTO_FILE"
  rm -f "$HELD_BLINKIT_FILE" "$HELD_NOT_LISTED_FILE" "$HELD_ZEPTO_FILE"
  rm -f "$ROOT/logs/blinkit_quality_monitor-${DATE}.log" "$ROOT/logs/blinkit_quality_monitor-${DATE}.state"
  rm -f "$ROOT/logs/blinkit_quality_monitor-${MISSING_MAIN_DATE}.log" "$ROOT/logs/blinkit_quality_monitor-${MISSING_MAIN_DATE}.state"
  rm -f "$ROOT/logs/blinkit_quality_monitor-${HELD_DATE}.log" "$ROOT/logs/blinkit_quality_monitor-${HELD_DATE}.state"
  rm -f "$ROOT/logs/blinkit-not-listed-wa-${DATE}.sent"
  rm -f "$ROOT/logs/blinkit-not-listed-wa-${MISSING_MAIN_DATE}.sent"
  rm -f "$ROOT/logs/blinkit-not-listed-wa-${HELD_DATE}.sent"
}
trap cleanup EXIT

python3 - "$FIXTURE" "$GOOD_RESULT" "$BAD_RESULT" "$BLINKIT_FILE" "$NOT_LISTED_FILE" "$MISSING_MAIN_NOT_LISTED_FILE" "$HELD_BLINKIT_FILE" "$HELD_NOT_LISTED_FILE" <<'PY'
import json
import sys
from openpyxl import Workbook

src, good_result_path, bad_result_path, blinkit_path, not_listed_path, missing_main_not_listed_path, held_blinkit_path, held_not_listed_path = sys.argv[1:]
d = json.load(open(src, encoding="utf-8"))
d["summary"]["captured_at"] = "2099-01-02T04:00:00.000Z"
d["summary"]["pdp_price_probe_enabled"] = 1
d["summary"]["pdp_price_probe_attempted"] = 1
d["summary"]["pdp_price_probe_checked"] = 1
d["summary"]["pdp_price_probe_failed"] = 0
d["summary"]["pdp_price_probe_updates"] = 0
json.dump(d, open(good_result_path, "w", encoding="utf-8"))

bad = json.loads(json.dumps(d))
bad["summary"]["captured_at"] = "2099-01-04T04:00:00.000Z"
for row in [bad["allRows"][0], bad["perPin"][0]["rows"][0]]:
    row["sale"] = 1876
    row.pop("base_sale", None)
    row.pop("offer_sale", None)
    row["discount_pct"] = 62.5
    row["per_litre"] = 375.2
    row["price_source"] = "pdp"
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
not_listed_workbook(missing_main_not_listed_path)
main_workbook(held_blinkit_path)
not_listed_workbook(held_not_listed_path)
PY
printf 'dummy zepto workbook\n' > "$MISSING_MAIN_ZEPTO_FILE"
printf 'dummy zepto workbook\n' > "$HELD_ZEPTO_FILE"

cd "$ROOT"
PRICE_MAIL_DATE="$DATE" \
MAILER_NO_REDIRECT=1 \
MAILER_TEST_MODE=1 \
MAILER_DRY_RUN_SEND=1 \
MAILER_SKIP_WAIT=1 \
BLINKIT_MONITOR_RESULT="$GOOD_RESULT" \
  tools/mailer/mail_price_data.sh test > "$OUT_GOOD"

grep -q "DRYRUN email:" "$OUT_GOOD"
grep -q "TEST WhatsApp group:" "$OUT_GOOD"
grep -q "TEST WhatsApp direct not-listed: 917703818227@s.whatsapp.net Jivo-Blinkit-Not-Listed-Pincodes-${DATE}.xlsx" "$OUT_GOOD"

printf 'already sent\n' > "$ROOT/logs/blinkit-not-listed-wa-${DATE}.sent"
MARKER_OUT="$(BLINKIT_NOT_LISTED_DATE="$DATE" \
  BLINKIT_MONITOR_RESULT=/does/not/exist.json \
  BLINKIT_MONITOR_REPORT="$BLINKIT_FILE" \
  BLINKIT_MONITOR_NOT_LISTED_REPORT="$NOT_LISTED_FILE" \
  MAILER_TEST_MODE=1 \
  "$ROOT/tools/whatsapp/send_blinkit_not_listed_direct.sh" test)"
echo "$MARKER_OUT" | grep -q "already sent for ${DATE}"
if echo "$MARKER_OUT" | grep -q "TEST WhatsApp direct not-listed:"; then
  echo "expected marker to suppress duplicate direct not-listed send" >&2
  echo "$MARKER_OUT" >&2
  exit 1
fi

PRICE_MAIL_DATE="$MISSING_MAIN_DATE" \
MAILER_NO_REDIRECT=1 \
MAILER_TEST_MODE=1 \
MAILER_DRY_RUN_SEND=1 \
MAILER_SKIP_WAIT=1 \
BLINKIT_MONITOR_RESULT="$GOOD_RESULT" \
  tools/mailer/mail_price_data.sh test > "$OUT_MISSING_MAIN"

grep -q "Blinkit not-listed direct WhatsApp skipped because main Blinkit report was not accepted" "$OUT_MISSING_MAIN"
if grep -q "TEST WhatsApp direct not-listed:" "$OUT_MISSING_MAIN"; then
  echo "expected direct not-listed send to be skipped without accepted main Blinkit report" >&2
  cat "$OUT_MISSING_MAIN" >&2
  exit 1
fi

PRICE_MAIL_DATE="$HELD_DATE" \
MAILER_NO_REDIRECT=1 \
MAILER_TEST_MODE=1 \
MAILER_DRY_RUN_SEND=1 \
MAILER_SKIP_WAIT=1 \
BLINKIT_MONITOR_RESULT="$BAD_RESULT" \
  tools/mailer/mail_price_data.sh test > "$OUT_HELD"

grep -q "WARN: Blinkit quality gate failed" "$OUT_HELD"
grep -q "Blinkit not-listed direct WhatsApp skipped because main Blinkit report was held by quality gate" "$OUT_HELD"
if grep -q "TEST WhatsApp direct not-listed:" "$OUT_HELD"; then
  echo "expected direct not-listed send to be skipped when main Blinkit report is held" >&2
  cat "$OUT_HELD" >&2
  exit 1
fi

echo "PASS mailer Blinkit not-listed direct WhatsApp regression"
