#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$ROOT/tools/competitor/zepto_competitor_deadline_guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

DATE=2099-01-02
CHAT=120363047864912511@g.us
REPORT="$TMP/Competitor-Price-Watch-Zepto-${DATE}.xlsx"
RECEIPT="$TMP/receipt.json"
STATE="$TMP/state"
LOCK="$TMP/guard.lock"
NO_SECRETS="$TMP/no-secrets.env"
printf 'workbook fixture\n' > "$REPORT"

write_receipt() {
  local platform="$1"
  local date="$2"
  local sha="$3"
  python3 - "$RECEIPT" "$REPORT" "$platform" "$date" "$sha" "$CHAT" <<'PY'
import datetime
import json
import os
import sys

receipt_path, report_path, platform, date, sha256, target = sys.argv[1:]
with open(receipt_path, "w", encoding="utf-8") as handle:
    json.dump(
        {
            "date": date,
            "file": os.path.abspath(report_path),
            "messageId": "zepto-document-123",
            "platform": platform,
            "sent_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "sha256": sha256,
            "size": os.path.getsize(report_path),
            "target": target,
        },
        handle,
    )
PY
}

run_guard() {
  COMPETITOR_ROOT="$TMP" \
    COMPETITOR_SEND_DATE="$DATE" \
    COMPETITOR_REPORT="$REPORT" \
    COMPETITOR_WA_RECEIPT="$RECEIPT" \
    COMPETITOR_WA_CHAT="$CHAT" \
    ZEPTO_COMPETITOR_DEADLINE_STATE="$STATE" \
    ZEPTO_COMPETITOR_DEADLINE_LOCK="$LOCK" \
    ZEPTO_COMPETITOR_SECRETS_FILE="$NO_SECRETS" \
    "$GUARD"
}

SHA="$(sha256sum "$REPORT" | awk '{print $1}')"

# Only a receipt bound to today's exact Zepto workbook proves delivery.
write_receipt zepto "$DATE" "$SHA"
OUTPUT="$(run_guard)"
grep -qxF '[zepto_competitor_deadline] delivered' <<<"$OUTPUT"
[ ! -e "$STATE" ]

# A receipt for another platform cannot hide a missed Zepto delivery.
write_receipt amazon-now "$DATE" "$SHA"
OUTPUT="$(run_guard)"
grep -q 'deadline missed; retry remains enabled' <<<"$OUTPUT"
grep -qxF deadline-missed "$STATE"

# The failure notification is one-shot even though delivery retries continue.
OUTPUT="$(run_guard)"
[ -z "$OUTPUT" ]
[ "$(grep -c '^deadline-missed$' "$STATE")" -eq 1 ]

# A current Zepto receipt for different workbook bytes is also invalid.
rm -f "$STATE"
write_receipt zepto "$DATE" "$(printf stale | sha256sum | awk '{print $1}')"
OUTPUT="$(run_guard)"
grep -q 'deadline missed; retry remains enabled' <<<"$OUTPUT"

printf 'Zepto competitor deadline receipt tests passed\n'
