#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SENDER="$ROOT/tools/competitor/send_blinkit_top8_whatsapp.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

DATE=2099-01-02
REPORT="$TMP/Competitor-Price-Watch-Blinkit-${DATE}.xlsx"
AUDIT="$TMP/audit.json"
RECEIPT="$TMP/receipt.json"
MARKER="$TMP/sent.marker"
LOCK="$TMP/sender.lock"
CALLS="$TMP/curl.calls"
MOCK_BIN="$TMP/bin"
mkdir -p "$MOCK_BIN"

python3 - "$REPORT" "$AUDIT" "$DATE" <<'PY'
import json
import sys

from openpyxl import Workbook

report, audit, date = sys.argv[1:]
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

printf 'blinkit top8 WhatsApp receipt tests passed\n'
