#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SENDER="$ROOT/tools/competitor/send_platform_whatsapp.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

DATE=2099-01-02
CHAT=120363047864912511@g.us
MOCK_BIN="$TMP/bin"
CALLS="$TMP/curl.calls"
mkdir -p "$MOCK_BIN" "$TMP/logs"

make_fixture() {
  local platform="$1"
  local label="$2"
  python3 - "$TMP/Competitor-Price-Watch-${label}-${DATE}.xlsx" "$TMP/${platform}.json" "$platform" "$DATE" <<'PY'
import json
import sys

from openpyxl import Workbook

report, capture, platform, date = sys.argv[1:]
workbook = Workbook()
workbook.active.title = "Summary"
workbook.create_sheet("Anchor Watch")
master = workbook.create_sheet("Master Data")
master.append(["sku"])
master.append(["test-row"])
workbook.save(report)
with open(capture, "w", encoding="utf-8") as handle:
    json.dump(
        {
            "summary": {
                "date_ist": date,
                "mode": "competitor",
                "partial": False,
                "pincodes_serviceable": 25,
                "platform": platform,
                "total_rows": 10,
            }
        },
        handle,
    )
PY
}

make_fixture zepto Zepto
make_fixture amazon-now Amazon-Now
make_fixture amazon-fresh Amazon-Fresh

cat > "$MOCK_BIN/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$COMPETITOR_TEST_CALLS"
case " $* " in
  *"http://127.0.0.1:3001/health"*) printf '%s\n' '{"connected":true}' ;;
  *"http://127.0.0.1:3001/send-media"*) printf '%s\n' '{"success":true,"messageId":"zepto-document-123"}' ;;
  *) printf '%s\n' '{"success":true,"messageId":"header-456"}' ;;
esac
SH
chmod +x "$MOCK_BIN/curl"

run_sender() {
  local platform="$1"
  local label="$2"
  shift 2
  env \
    PATH="$MOCK_BIN:$PATH" \
    COMPETITOR_ROOT="$TMP" \
    COMPETITOR_SEND_DATE="$DATE" \
    COMPETITOR_REPORT="$TMP/Competitor-Price-Watch-${label}-${DATE}.xlsx" \
    COMPETITOR_CAPTURE="$TMP/${platform}.json" \
    COMPETITOR_WA_RECEIPT="$TMP/${platform}.receipt.json" \
    COMPETITOR_SENT_MARKER="$TMP/${platform}.sent" \
    COMPETITOR_WA_LOCK="$TMP/${platform}.lock" \
    COMPETITOR_TEST_CALLS="$CALLS" \
    "$@" "$SENDER" "$platform"
}

# Existing Amazon modes retain their quality validation and dry-run behavior.
OUTPUT="$(run_sender amazon-now Amazon-Now COMPETITOR_WA_TEST=1)"
grep -q 'TEST send:' <<<"$OUTPUT"
OUTPUT="$(run_sender amazon-fresh Amazon-Fresh COMPETITOR_WA_TEST=1)"
grep -q 'TEST send:' <<<"$OUTPUT"
[ ! -e "$CALLS" ]

# A successful Zepto document response records the document message ID and all
# fields needed to prove exactly which workbook reached exactly which group.
run_sender zepto Zepto
RECEIPT="$TMP/zepto.receipt.json"
python3 - "$RECEIPT" "$TMP/Competitor-Price-Watch-Zepto-${DATE}.xlsx" "$DATE" "$CHAT" <<'PY'
import datetime
import hashlib
import json
import os
import sys

receipt_path, report_path, date, target = sys.argv[1:]
with open(receipt_path, encoding="utf-8") as handle:
    receipt = json.load(handle)
with open(report_path, "rb") as handle:
    digest = hashlib.sha256(handle.read()).hexdigest()
assert receipt == {
    "date": date,
    "file": os.path.abspath(report_path),
    "messageId": "zepto-document-123",
    "platform": "zepto",
    "sent_at": receipt["sent_at"],
    "sha256": digest,
    "size": os.path.getsize(report_path),
    "target": target,
}
assert datetime.datetime.fromisoformat(receipt["sent_at"]).tzinfo is not None
PY
cp "$RECEIPT" "$TMP/valid-receipt.json"
FIRST_CALLS="$(wc -l < "$CALLS")"

# A fully matching receipt suppresses duplicate header and document sends.
OUTPUT="$(run_sender zepto Zepto)"
grep -q 'confirmed document receipt already exists' <<<"$OUTPUT"
[ "$(wc -l < "$CALLS")" -eq "$FIRST_CALLS" ]

# Every bound field is authoritative. A stale or incomplete receipt must not
# suppress a retry; test mode proves the sender reaches the send decision.
for field in platform date file sha256 size target messageId sent_at; do
  cp "$TMP/valid-receipt.json" "$RECEIPT"
  python3 - "$RECEIPT" "$field" <<'PY'
import json
import sys

path, field = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    receipt = json.load(handle)
bad = {
    "platform": "blinkit",
    "date": "2099-01-01",
    "file": "/tmp/different.xlsx",
    "sha256": "0" * 64,
    "size": int(receipt["size"]) + 1,
    "target": "different@g.us",
    "messageId": "",
    "sent_at": "not-a-timestamp",
}
receipt[field] = bad[field]
with open(path, "w", encoding="utf-8") as handle:
    json.dump(receipt, handle)
PY
  OUTPUT="$(run_sender zepto Zepto COMPETITOR_WA_TEST=1)"
  grep -q 'TEST send:' <<<"$OUTPUT"
done

printf 'competitor platform WhatsApp receipt tests passed\n'
