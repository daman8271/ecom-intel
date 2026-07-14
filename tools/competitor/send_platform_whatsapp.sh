#!/usr/bin/env bash
# Send one quality-checked competitor workbook to the Ecom WhatsApp group.
set -uo pipefail

ROOT="${COMPETITOR_ROOT:-/opt/ecom-intel}"
cd "$ROOT" || exit 1
PLATFORM="${1:?usage: send_platform_whatsapp.sh <platform>}"
DATE_IST="${COMPETITOR_SEND_DATE:-$(TZ=Asia/Kolkata date +%F)}"
CHAT="${COMPETITOR_WA_CHAT:-120363047864912511@g.us}"
GW_HEALTH=http://127.0.0.1:3001/health

case "$PLATFORM" in
  zepto) LABEL=Zepto ;;
  amazon-now) LABEL='Amazon-Now' ;;
  amazon-fresh) LABEL='Amazon-Fresh' ;;
  *) echo "unsupported competitor platform: $PLATFORM" >&2; exit 2 ;;
esac

REPORT="${COMPETITOR_REPORT:-$ROOT/output/Competitor-Price-Watch-${LABEL}-${DATE_IST}.xlsx}"
CAPTURE="${COMPETITOR_CAPTURE:-$ROOT/tools/competitor/data/${PLATFORM}_competitor_${DATE_IST}.json}"
MARKER="${COMPETITOR_SENT_MARKER:-$ROOT/logs/competitor-${PLATFORM}-wa-${DATE_IST}.sent}"
RECEIPT_DIR="$ROOT/logs/delivery-receipts/$DATE_IST"
RECEIPT="${COMPETITOR_WA_RECEIPT:-$RECEIPT_DIR/$(basename "$REPORT").json}"
LOCK="${COMPETITOR_WA_LOCK:-$ROOT/logs/.competitor-${PLATFORM}-wa.lock}"

log() {
  printf '[%s] competitor_wa(%s): %s\n' "$(TZ=Asia/Kolkata date '+%F %T %Z')" "$PLATFORM" "$*"
}

exec 9>"$LOCK"
flock -n 9 || { log "another sender holds the lock"; exit 0; }
[ -s "$REPORT" ] || { log "workbook missing: $REPORT"; exit 1; }
[ -s "$CAPTURE" ] || { log "capture missing: $CAPTURE"; exit 1; }

SUMMARY="$(python3 - "$CAPTURE" "$REPORT" "$PLATFORM" "$DATE_IST" <<'PY'
import json, sys
from openpyxl import load_workbook

capture_path, report_path, platform, date = sys.argv[1:]
data = json.load(open(capture_path, encoding="utf-8"))
summary = data.get("summary") or {}
checks = {
    "platform": summary.get("platform") == platform,
    "mode": summary.get("mode") == "competitor",
    "date": summary.get("date_ist") == date,
    "partial": summary.get("partial") is False,
    "rows": int(summary.get("total_rows") or 0) > 0,
}
if not all(checks.values()):
    raise SystemExit(f"capture quality failed: {checks}")
wb = load_workbook(report_path, read_only=True, data_only=False)
required = {"Summary", "Anchor Watch", "Master Data"}
if not required.issubset(wb.sheetnames) or wb["Master Data"].max_row <= 1:
    raise SystemExit(f"workbook quality failed: sheets={wb.sheetnames}")
wb.close()
print(f"{summary.get('pincodes_serviceable', summary.get('pincodes_total'))} serviceable pincodes · {summary.get('total_rows')} datapoints")
PY
)" || { log "quality gate failed: $SUMMARY"; exit 1; }

SHA="$(sha256sum "$REPORT" | awk '{print $1}')"
SIZE="$(stat -c %s "$REPORT")"
if [ -s "$RECEIPT" ] && python3 - "$RECEIPT" "$REPORT" "$SHA" "$SIZE" "$CHAT" "$PLATFORM" "$DATE_IST" <<'PY'
import datetime
import json
import os
import sys

receipt_path, report_path, sha256, size, target, platform, date = sys.argv[1:]
try:
    with open(receipt_path, encoding="utf-8") as handle:
        receipt = json.load(handle)
    sent_at = receipt.get("sent_at")
    parsed_sent_at = datetime.datetime.fromisoformat(str(sent_at).replace("Z", "+00:00"))
except (OSError, TypeError, ValueError, json.JSONDecodeError):
    raise SystemExit(1)
checks = {
    "platform": receipt.get("platform") == platform,
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
  log "confirmed document receipt already exists; skipping duplicate"
  exit 0
fi

if [ "${COMPETITOR_WA_TEST:-0}" = "1" ] || [ "${MAILER_TEST_MODE:-0}" = "1" ]; then
  log "TEST send: $CHAT $(basename "$REPORT") | $SUMMARY"
  exit 0
fi

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/0}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/0/bus}"
if ! curl -s --max-time 5 "$GW_HEALTH" | grep -q '"connected"'; then
  systemctl --user reset-failed hermes-gateway-wa-test.service 2>/dev/null || true
  systemctl --user start hermes-gateway-wa-test.service 2>/dev/null || true
  for _ in $(seq 1 30); do
    curl -s --max-time 3 "$GW_HEALTH" | grep -q '"connected"' && break
    sleep 1
  done
fi

HEADER="${LABEL} Competitor Price Watch - ${DATE_IST}
${SUMMARY}"
BODY="$(python3 -c 'import json,sys; print(json.dumps({"chatId":sys.argv[1],"message":sys.argv[2]}))' "$CHAT" "$HEADER")"
RESPONSE="$(curl -s --max-time 60 -X POST http://127.0.0.1:3001/send -H 'Content-Type: application/json' -d "$BODY")"
log "header response: $RESPONSE"
grep -q '"success":true' <<<"$RESPONSE" || exit 1

BODY="$(python3 -c 'import json,os,sys; p=os.path.abspath(sys.argv[1]); print(json.dumps({"chatId":sys.argv[2],"filePath":p,"mediaType":"document","fileName":os.path.basename(p)}))' "$REPORT" "$CHAT")"
RESPONSE="$(curl -s --max-time 120 -X POST http://127.0.0.1:3001/send-media -H 'Content-Type: application/json' -d "$BODY")"
log "document response: $RESPONSE"

mkdir -p "$(dirname "$RECEIPT")"
python3 - "$RECEIPT" "$REPORT" "$SHA" "$SIZE" "$CHAT" "$PLATFORM" "$DATE_IST" "$RESPONSE" <<'PY'
import datetime, json, os, sys

receipt_path, report_path, sha256, size, target, platform, date, raw = sys.argv[1:]
try:
    response = json.loads(raw)
except json.JSONDecodeError:
    raise SystemExit(1)
message_id = response.get("messageId")
if response.get("success") is not True or not message_id:
    raise SystemExit(1)
data = {
    "date": date,
    "file": os.path.abspath(report_path),
    "messageId": str(message_id),
    "platform": platform,
    "sent_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "sha256": sha256,
    "size": int(size),
    "target": target,
}
tmp = receipt_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
os.replace(tmp, receipt_path)
PY
printf '%s %s %s\n' "$(TZ=Asia/Kolkata date '+%F %T %Z')" "$CHAT" "$(basename "$REPORT")" > "$MARKER"
log "sent and receipt recorded: $RECEIPT"
