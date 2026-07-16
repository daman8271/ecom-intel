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
SNAPSHOT_ROOT="$TMP/snapshots"
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
    brands = ["borges", "del monte", "figaro", "fortune", "gulab", "hudson", "oreal", "saffola", "sundrop", "tata"]
    brand_hash = __import__("hashlib").sha256(
        json.dumps(brands, separators=(",", ":")).encode("ascii")
    ).hexdigest()
    json.dump(
        {
            "schema": "jivo-direct-competitor-delivery-audit-v1",
            "platform": "blinkit",
            "workflow_kind": "blinkit-top8",
            "date_ist": date,
            "run_id": "20990102-000000-blinkit-competitor-direct-a01",
            "attempt_id": "01",
            "status": "OK",
            "pincodes_total": 75,
            "total_rows": 10,
            "brand_set": brands,
            "brand_set_count": len(brands),
            "brand_set_sha256": brand_hash,
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
brands = ["borges", "del monte", "figaro", "fortune", "gulab", "hudson", "oreal", "saffola", "sundrop", "tata"]
brand_hash = hashlib.sha256(json.dumps(brands, separators=(",", ":")).encode("ascii")).hexdigest()
json.dump({
    "schema": "jivo-direct-competitor-promotion-receipt-v1",
    "status": "accepted", "platform": "blinkit", "date_ist": date,
    "workflow_kind": "blinkit-top8", "run_id": "20990102-000000-blinkit-competitor-direct-a01",
    "attempt_id": "01", "plan_sha256": "a" * 64, "source_sha256": "b" * 64,
    "scraper_sha256": "c" * 64, "merge_receipt_sha256": "d" * 64,
    "source_receipt_sha256": "e" * 64, "merged_sha256": artifact("merged_capture", capture)["sha256"],
    "brand_set_sha256": brand_hash,
    "input_result_sha256": {"macpro": "1" * 64, "windows": "2" * 64},
    "input_progress_sha256": {"macpro": "3" * 64, "windows": "4" * 64},
    "input_terminal_sha256": {"macpro": "5" * 64, "windows": "6" * 64},
    "support_files": [{"name": "support.json", "sha256": "7" * 64}],
    "code_files": [{"name": "builder.py", "sha256": "8" * 64}],
    "quality_policy": {"require_auth": True}, "baseline": {"total_rows": 1},
    "anchor_brands": ["Jivo", "Sano"], "competitor_brands": brands,
    "capture_brands": ["Jivo", "Sano", *brands],
    "brand_set": brands, "brand_set_count": len(brands),
    "pincodes_total": 75, "total_rows": 10,
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
  *)
    if [ "${BLINKIT_TOP8_MUTATE_AT_HEADER:-0}" = "1" ]; then
      printf 'changed-after-acceptance' >> "$BLINKIT_TOP8_MUTATE_REPORT"
      printf 'changed-after-acceptance' >> "$BLINKIT_TOP8_MUTATE_CAPTURE"
      printf 'changed-after-acceptance' >> "$BLINKIT_TOP8_MUTATE_AUDIT"
    fi
    printf '%s\n' '{"success":true,"messageId":"header-message-456"}'
    ;;
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
    DIRECT_COMPETITOR_SNAPSHOT_ROOT="$SNAPSHOT_ROOT" \
    BLINKIT_TOP8_TEST_CALLS="$CALLS" \
    BLINKIT_TOP8_MUTATE_AT_HEADER="${BLINKIT_TOP8_MUTATE_AT_HEADER:-0}" \
    BLINKIT_TOP8_MUTATE_REPORT="$REPORT" \
    BLINKIT_TOP8_MUTATE_CAPTURE="$CAPTURE" \
    BLINKIT_TOP8_MUTATE_AUDIT="$AUDIT" \
    "$SENDER" test
}

# Test mode performs validation but never sends or records delivery.
BLINKIT_TOP8_WA_TEST=1 run_sender
[ ! -e "$CALLS" ]
[ ! -e "$RECEIPT" ]

# A real successful document response creates a complete durable receipt.
run_sender
[ "$(find "$SNAPSHOT_ROOT" -type f | wc -l)" -eq 3 ]
grep -Fq "$SNAPSHOT_ROOT" "$CALLS"
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
ORIGINAL_SHA="$(sha256sum "$REPORT" | awk '{print $1}')"
ORIGINAL_SIZE="$(stat -c %s "$REPORT")"
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
BLINKIT_TOP8_MUTATE_AT_HEADER=1 run_sender
[ "$(wc -l < "$CALLS")" -gt "$FIRST_CALLS" ]
python3 - "$RECEIPT" "$REPORT" "$ORIGINAL_SHA" "$ORIGINAL_SIZE" <<'PY'
import hashlib
import json
import sys

receipt_path, report_path, accepted_sha, accepted_size = sys.argv[1:]
receipt = json.load(open(receipt_path, encoding="utf-8"))
assert receipt["file"] == report_path
assert receipt["sha256"] == accepted_sha
assert receipt["size"] == int(accepted_size)
assert hashlib.sha256(open(report_path, "rb").read()).hexdigest() != accepted_sha
PY

# Even a valid-looking workbook/audit cannot send without its accepted promotion.
rm -f "$PROMOTION_ROOT/$DATE"/*.json
CALLS_BEFORE="$(wc -l < "$CALLS")"
if BLINKIT_TOP8_WA_TEST=1 run_sender; then
  echo "unaccepted Blinkit workbook unexpectedly passed the send gate" >&2
  exit 1
fi
[ "$(wc -l < "$CALLS")" -eq "$CALLS_BEFORE" ]

printf 'blinkit top8 WhatsApp receipt tests passed\n'
