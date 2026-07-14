#!/usr/bin/env bash
# Alert once when a valid Zepto competitor document receipt misses its deadline.
set -u

ROOT="${COMPETITOR_ROOT:-/opt/ecom-intel}"
cd "$ROOT" || exit 1
DATE_IST="${COMPETITOR_SEND_DATE:-$(TZ=Asia/Kolkata date +%F)}"
REPORT="${COMPETITOR_REPORT:-$ROOT/output/Competitor-Price-Watch-Zepto-${DATE_IST}.xlsx}"
RECEIPT="${COMPETITOR_WA_RECEIPT:-$ROOT/logs/delivery-receipts/$DATE_IST/$(basename "$REPORT").json}"
STATE="${ZEPTO_COMPETITOR_DEADLINE_STATE:-$ROOT/logs/zepto-competitor-${DATE_IST}.state}"
LOCK="${ZEPTO_COMPETITOR_DEADLINE_LOCK:-$ROOT/logs/.zepto-competitor-deadline.lock}"
CHAT="${COMPETITOR_WA_CHAT:-120363047864912511@g.us}"
SECRETS_FILE="${ZEPTO_COMPETITOR_SECRETS_FILE:-$ROOT/secrets.env}"

mkdir -p "$(dirname "$STATE")" "$(dirname "$LOCK")"
exec 9>"$LOCK"
flock -n 9 || exit 0

if [ -s "$REPORT" ] && [ -s "$RECEIPT" ]; then
  SHA="$(sha256sum "$REPORT" | awk '{print $1}')"
  SIZE="$(stat -c %s "$REPORT")"
  if python3 - "$RECEIPT" "$REPORT" "$SHA" "$SIZE" "$CHAT" "$DATE_IST" <<'PY'
import datetime
import json
import os
import sys

receipt_path, report_path, sha256, size, target, date = sys.argv[1:]
try:
    with open(receipt_path, encoding="utf-8") as handle:
        receipt = json.load(handle)
    sent_at = receipt.get("sent_at")
    parsed_sent_at = datetime.datetime.fromisoformat(str(sent_at).replace("Z", "+00:00"))
except (OSError, TypeError, ValueError, json.JSONDecodeError):
    raise SystemExit(1)
checks = {
    "platform": receipt.get("platform") == "zepto",
    "date": receipt.get("date") == date,
    "file": receipt.get("file") == os.path.abspath(report_path),
    "sha256": receipt.get("sha256") == sha256,
    "size": receipt.get("size") == int(size),
    "target": receipt.get("target") == target,
    "messageId": isinstance(receipt.get("messageId"), str) and bool(receipt["messageId"].strip()),
    "sent_at": parsed_sent_at.tzinfo is not None,
}
raise SystemExit(0 if all(checks.values()) else 1)
PY
  then
    echo "[zepto_competitor_deadline] delivered"
    exit 0
  fi
fi

touch "$STATE"
grep -qxF deadline-missed "$STATE" 2>/dev/null && exit 0
printf '%s\n' deadline-missed >> "$STATE"
(
  set +e
  # shellcheck disable=SC1090
  [ -f "$SECRETS_FILE" ] && . "$SECRETS_FILE"
  owner_chat="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "$owner_chat" ] || exit 0
  message="[FAIL] Zepto competitor workbook missed the 12:00 IST Ecom-group delivery deadline for ${DATE_IST}. The control-host sender will keep retrying a valid device-built workbook; no VPS scrape or merge was started."
  curl -s --max-time 30 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=$owner_chat" --data-urlencode "text=$message" >/dev/null
) || true
echo "[zepto_competitor_deadline] deadline missed; retry remains enabled"
