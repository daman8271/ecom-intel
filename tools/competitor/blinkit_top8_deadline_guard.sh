#!/usr/bin/env bash
# Alert after the 12:00 IST Ecom-group deadline without stopping late recovery.
set -u

ROOT=/opt/ecom-intel
cd "$ROOT" || exit 1
DATE_IST="${BLINKIT_TOP8_DATE:-$(TZ=Asia/Kolkata date +%F)}"
REPORT="${BLINKIT_TOP8_REPORT:-$ROOT/output/Competitor-Price-Watch-Blinkit-${DATE_IST}.xlsx}"
RECEIPT="${BLINKIT_TOP8_WA_RECEIPT:-$ROOT/logs/delivery-receipts/$DATE_IST/$(basename "$REPORT").json}"
STATE="${BLINKIT_TOP8_DEADLINE_STATE:-$ROOT/logs/blinkit-top8-${DATE_IST}.state}"
POINTER="${BLINKIT_TOP8_ACTIVE_POINTER:-$ROOT/shards/runs/ACTIVE-blinkit-top8}"
CHAT="${BLINKIT_TOP8_WA_CHAT:-120363047864912511@g.us}"
SECRETS_FILE="${BLINKIT_TOP8_SECRETS_FILE:-$ROOT/secrets.env}"

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
    "platform": receipt.get("platform") == "blinkit",
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
    echo "[blinkit_top8_deadline] delivered"
    exit 0
  fi
fi
touch "$STATE"
grep -qxF deadline-missed "$STATE" 2>/dev/null && exit 0
run_id="$(head -1 "$POINTER" 2>/dev/null || echo none)"
printf '%s\n' deadline-missed >> "$STATE"
(
  set +e
  # shellcheck disable=SC1090
  [ -f "$SECRETS_FILE" ] && . "$SECRETS_FILE"
  chat="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "$chat" ] || exit 0
  message="[FAIL] Blinkit top-8 competitor workbook missed the 12:00 IST Ecom-group deadline for ${DATE_IST}. Active run: ${run_id}. Late recovery remains enabled."
  curl -s --max-time 30 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=$chat" --data-urlencode "text=$message" >/dev/null
) || true
echo "[blinkit_top8_deadline] deadline missed; run=$run_id"
