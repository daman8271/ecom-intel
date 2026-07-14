#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$ROOT/tools/competitor/blinkit_top8_deadline_guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

DATE=2099-01-02
CHAT=120363047864912511@g.us
REPORT="$TMP/Competitor-Price-Watch-Blinkit-${DATE}.xlsx"
RECEIPT="$TMP/receipt.json"
STATE="$TMP/state"
POINTER="$TMP/active-run"
NO_SECRETS="$TMP/no-secrets.env"
printf 'workbook fixture\n' > "$REPORT"
printf 'blinkit-top8-test-run\n' > "$POINTER"

write_receipt() {
  local date="$1"
  local sha="$2"
  python3 - "$RECEIPT" "$REPORT" "$date" "$sha" "$CHAT" <<'PY'
import datetime
import json
import os
import sys

receipt_path, report_path, date, sha256, target = sys.argv[1:]
with open(report_path, "rb") as handle:
    size = len(handle.read())
with open(receipt_path, "w", encoding="utf-8") as handle:
    json.dump(
        {
            "date": date,
            "file": os.path.abspath(report_path),
            "messageId": "document-message-123",
            "platform": "blinkit",
            "sent_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "sha256": sha256,
            "size": size,
            "target": target,
        },
        handle,
    )
PY
}

run_guard() {
  BLINKIT_TOP8_DATE="$DATE" \
    BLINKIT_TOP8_REPORT="$REPORT" \
    BLINKIT_TOP8_WA_RECEIPT="$RECEIPT" \
    BLINKIT_TOP8_DEADLINE_STATE="$STATE" \
    BLINKIT_TOP8_ACTIVE_POINTER="$POINTER" \
    BLINKIT_TOP8_WA_CHAT="$CHAT" \
    BLINKIT_TOP8_SECRETS_FILE="$NO_SECRETS" \
    "$GUARD"
}

SHA="$(sha256sum "$REPORT" | awk '{print $1}')"

# Only a receipt matching the current dated workbook proves delivery.
write_receipt "$DATE" "$SHA"
OUTPUT="$(run_guard)"
grep -qxF '[blinkit_top8_deadline] delivered' <<<"$OUTPUT"
[ ! -e "$STATE" ]

# A receipt from another date is stale and cannot suppress the deadline alert.
write_receipt 2099-01-01 "$SHA"
OUTPUT="$(run_guard)"
grep -q 'deadline missed; run=blinkit-top8-test-run' <<<"$OUTPUT"
grep -qxF deadline-missed "$STATE"

# A current-date receipt for different workbook bytes is also not delivery proof.
rm -f "$STATE"
write_receipt "$DATE" "$(printf stale | sha256sum | awk '{print $1}')"
OUTPUT="$(run_guard)"
grep -q 'deadline missed; run=blinkit-top8-test-run' <<<"$OUTPUT"
grep -qxF deadline-missed "$STATE"

printf 'blinkit top8 deadline receipt tests passed\n'
