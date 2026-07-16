#!/usr/bin/env bash
# Send one quality-checked competitor workbook to the Ecom WhatsApp group.
set -uo pipefail

ROOT="${COMPETITOR_ROOT:-/opt/ecom-intel}"
CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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
PROMOTION_ROOT="${DIRECT_COMPETITOR_PROMOTION_ROOT:-$ROOT/logs/direct-competitor-report-receipts}"
SNAPSHOT_ROOT="${DIRECT_COMPETITOR_SNAPSHOT_ROOT:-$ROOT/logs/direct-competitor-send-snapshots}"

log() {
  printf '[%s] competitor_wa(%s): %s\n' "$(TZ=Asia/Kolkata date '+%F %T %Z')" "$PLATFORM" "$*"
}

exec 9>"$LOCK"
flock -n 9 || { log "another sender holds the lock"; exit 0; }
[ -s "$REPORT" ] || { log "workbook missing: $REPORT"; exit 1; }
[ -s "$CAPTURE" ] || { log "capture missing: $CAPTURE"; exit 1; }
SEND_REPORT="$REPORT"
QUALITY_CAPTURE="$CAPTURE"
if [ "$PLATFORM" = "zepto" ]; then
  GATE_JSON="$(python3 "$CODE_ROOT/tools/cron/direct_competitor_is_accepted.py" \
    --file "$REPORT" --date "$DATE_IST" --platform zepto --receipts "$PROMOTION_ROOT" \
    --snapshot-root "$SNAPSHOT_ROOT")" \
    || { log "workbook has no exact accepted direct-competitor promotion"; exit 1; }

  snapshot_fields() {
    python3 - "$GATE_JSON" "$REPORT" "$CAPTURE" "$DATE_IST" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import sys

raw, report, capture, date = sys.argv[1:]
value = json.loads(raw)
if value.get("schema") != "jivo-direct-competitor-accepted-snapshot-v1" \
   or value.get("platform") != "zepto" or value.get("date_ist") != date:
    raise SystemExit("invalid accepted snapshot manifest")
artifacts = value.get("artifacts")
if not isinstance(artifacts, list) or len(artifacts) != 3:
    raise SystemExit("accepted snapshot manifest does not have three artifacts")
by_kind = {item.get("kind"): item for item in artifacts if isinstance(item, dict)}
if set(by_kind) != {"workbook", "merged_capture", "delivery_audit"}:
    raise SystemExit("accepted snapshot manifest artifact kinds are invalid")
if by_kind["workbook"].get("original_path") != os.path.abspath(report):
    raise SystemExit("accepted snapshot workbook identity mismatch")
if by_kind["merged_capture"].get("original_path") != os.path.abspath(capture):
    raise SystemExit("accepted snapshot capture identity mismatch")
for item in by_kind.values():
    path = Path(str(item.get("snapshot_path") or ""))
    if path.is_symlink() or not path.is_file():
        raise SystemExit(f"snapshot is missing or symlinked: {path}")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if path.stat().st_size != item.get("bytes") or digest != item.get("sha256"):
        raise SystemExit(f"snapshot hash/size mismatch: {path}")
print(by_kind["workbook"]["snapshot_path"])
print(by_kind["merged_capture"]["snapshot_path"])
print(by_kind["delivery_audit"]["snapshot_path"])
print(by_kind["workbook"]["sha256"])
print(by_kind["workbook"]["bytes"])
PY
  }

  SNAPSHOT_VALUES="$(snapshot_fields)" || { log "accepted snapshot validation failed"; exit 1; }
  mapfile -t SNAPSHOT_FIELDS <<< "$SNAPSHOT_VALUES"
  [ "${#SNAPSHOT_FIELDS[@]}" -eq 5 ] || { log "accepted snapshot fields are incomplete"; exit 1; }
  SEND_REPORT="${SNAPSHOT_FIELDS[0]}"
  QUALITY_CAPTURE="${SNAPSHOT_FIELDS[1]}"
  SHA="${SNAPSHOT_FIELDS[3]}"
  SIZE="${SNAPSHOT_FIELDS[4]}"
else
  SHA="$(sha256sum "$REPORT" | awk '{print $1}')"
  SIZE="$(stat -c %s "$REPORT")"
fi

SUMMARY="$(python3 - "$QUALITY_CAPTURE" "$SEND_REPORT" "$PLATFORM" "$DATE_IST" <<'PY'
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

if [ "$PLATFORM" = "zepto" ]; then
  snapshot_fields >/dev/null || { log "accepted snapshot changed before media send"; exit 1; }
fi
BODY="$(python3 -c 'import json,os,sys; p=os.path.abspath(sys.argv[1]); print(json.dumps({"chatId":sys.argv[3],"filePath":p,"mediaType":"document","fileName":os.path.basename(sys.argv[2])}))' "$SEND_REPORT" "$REPORT" "$CHAT")"
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
