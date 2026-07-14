#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SENDER="$ROOT/tools/competitor/send_blinkit_top8_whatsapp.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

DATE=2099-01-02
REPORT="$TMP/Competitor-Price-Watch-Blinkit-${DATE}.xlsx"
AUDIT="$TMP/blinkit-top8-${DATE}.audit.json"
CAPTURE="$TMP/blinkit_competitor_${DATE}.json"
RECEIPT="$TMP/receipt.json"
MARKER="$TMP/sent.marker"
LOCK="$TMP/sender.lock"
CALLS="$TMP/curl.calls"
PROMOTION_ROOT="$TMP/promotion"
MOCK_BIN="$TMP/bin"
mkdir -p "$MOCK_BIN" "$PROMOTION_ROOT/$DATE"

python3 - "$REPORT" "$AUDIT" "$CAPTURE" "$DATE" <<'PY'
import json
import sys

from openpyxl import Workbook

report, audit, capture, date = sys.argv[1:]
workbook = Workbook()
summary = workbook.active
summary.title = "Summary"
for name in ["City-Pin-SKU Prices", "Run Scope", "Anchor Watch", "Master Data"]:
    workbook.create_sheet(name)
for row in range(1, 83):
    workbook["Run Scope"].cell(row=row, column=1, value=f"row-{row}")
workbook.save(report)
with open(audit, "w", encoding="utf-8") as handle:
    json.dump(
        {
            "date": date,
            "summary": {
                "auth_verified": 1,
                "auth_verified_pincodes": 75,
                "partial": False,
                "pincodes_resolved": 75,
                "pincodes_total": 75,
                "scope": {"competitors": ["Brand A", "Brand B"]},
                "total_rows": 10,
            },
        },
        handle,
    )
with open(capture, "w", encoding="utf-8") as handle:
    json.dump({"summary": {"platform": "blinkit", "date_ist": date}}, handle)
PY

python3 - "$REPORT" "$CAPTURE" "$AUDIT" "$PROMOTION_ROOT/$DATE/20990102-000000-blinkit-competitor-direct-a01.json" "$DATE" <<'PY'
import hashlib, json, os, sys
report, capture, audit, receipt, date = sys.argv[1:]
def artifact(kind, path):
    data = open(path, "rb").read()
    return {"kind": kind, "destination": os.path.abspath(path),
            "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
json.dump({
    "schema": "jivo-direct-competitor-promotion-receipt-v1",
    "status": "accepted", "platform": "blinkit", "date_ist": date,
    "workflow_kind": "blinkit-top8", "run_id": "20990102-000000-blinkit-competitor-direct-a01",
    "artifacts": [artifact("workbook", report), artifact("merged_capture", capture),
                  artifact("delivery_audit", audit)],
}, open(receipt, "w", encoding="utf-8"))
PY

cat > "$MOCK_BIN/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BLINKIT_TOP8_TEST_CALLS"
case " $* " in
  *"http://127.0.0.1:3001/health"*) printf '%s\n' '{"connected":true}' ;;
  *"http://127.0.0.1:3001/send-media"*) printf '%s\n' '{"success":true,"messageId":"doc-message-123"}' ;;
  *) printf '%s\n' '{"success":true,"messageId":"header-message-456"}' ;;
esac
SH
chmod +x "$MOCK_BIN/curl"

run_sender() {
  PATH="$MOCK_BIN:$PATH" \
    BLINKIT_TOP8_DATE="$DATE" \
    BLINKIT_TOP8_REPORT="$REPORT" \
    BLINKIT_TOP8_AUDIT="$AUDIT" \
    BLINKIT_TOP8_WA_RECEIPT="$RECEIPT" \
    BLINKIT_TOP8_SENT_MARKER="$MARKER" \
    BLINKIT_TOP8_WA_LOCK="$LOCK" \
    DIRECT_COMPETITOR_PROMOTION_ROOT="$PROMOTION_ROOT" \
    BLINKIT_TOP8_TEST_CALLS="$CALLS" \
    "$SENDER" test
}

# Test mode performs validation but never sends or records delivery.
BLINKIT_TOP8_WA_TEST=1 run_sender
[ ! -e "$CALLS" ]
[ ! -e "$RECEIPT" ]

# A real successful document response creates a complete durable receipt.
run_sender
python3 - "$RECEIPT" "$REPORT" "$DATE" <<'PY'
import datetime
import hashlib
import json
import os
import sys

receipt_path, report_path, date = sys.argv[1:]
with open(receipt_path, encoding="utf-8") as handle:
    receipt = json.load(handle)
with open(report_path, "rb") as handle:
    digest = hashlib.sha256(handle.read()).hexdigest()
assert receipt["platform"] == "blinkit"
assert receipt["date"] == date
assert receipt["file"] == os.path.abspath(report_path)
assert receipt["sha256"] == digest
assert receipt["size"] == os.path.getsize(report_path)
assert receipt["target"] == "120363047864912511@g.us"
assert receipt["messageId"] == "doc-message-123"
assert datetime.datetime.fromisoformat(receipt["sent_at"]).tzinfo is not None
PY
FIRST_CALLS="$(wc -l < "$CALLS")"

# A valid receipt is authoritative even if the legacy marker is absent.
rm -f "$MARKER"
run_sender
[ "$(wc -l < "$CALLS")" -eq "$FIRST_CALLS" ]

# A receipt for different bytes is invalid and must not suppress a send.
python3 - "$RECEIPT" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    receipt = json.load(handle)
receipt["size"] += 1
with open(path, "w", encoding="utf-8") as handle:
    json.dump(receipt, handle)
PY
run_sender
[ "$(wc -l < "$CALLS")" -gt "$FIRST_CALLS" ]

# Even a valid-looking workbook/audit cannot send without its accepted promotion.
rm -f "$PROMOTION_ROOT/$DATE"/*.json
CALLS_BEFORE="$(wc -l < "$CALLS")"
if BLINKIT_TOP8_WA_TEST=1 run_sender; then
  echo "unaccepted Blinkit workbook unexpectedly passed the send gate" >&2
  exit 1
fi
[ "$(wc -l < "$CALLS")" -eq "$CALLS_BEFORE" ]

printf 'blinkit top8 WhatsApp receipt tests passed\n'
