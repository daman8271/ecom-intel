#!/usr/bin/env bash
# Send the quality-approved daily Blinkit top-8 workbook to the Ecom group.
set -uo pipefail

ROOT=/opt/ecom-intel
CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 1
DATE_IST="${BLINKIT_TOP8_DATE:-$(TZ=Asia/Kolkata date +%F)}"
PASS="${1:-direct}"
REPORT="${BLINKIT_TOP8_REPORT:-$ROOT/output/Competitor-Price-Watch-Blinkit-${DATE_IST}.xlsx}"
AUDIT="${BLINKIT_TOP8_AUDIT:-$ROOT/logs/blinkit-top8-${DATE_IST}.audit.json}"
MARKER="${BLINKIT_TOP8_SENT_MARKER:-$ROOT/logs/blinkit-top8-wa-${DATE_IST}.sent}"
RECEIPT_DIR="$ROOT/logs/delivery-receipts/$DATE_IST"
RECEIPT="${BLINKIT_TOP8_WA_RECEIPT:-$RECEIPT_DIR/$(basename "$REPORT").json}"
LOCK="${BLINKIT_TOP8_WA_LOCK:-$ROOT/logs/.blinkit-top8-wa.lock}"
CHAT="${BLINKIT_TOP8_WA_CHAT:-120363047864912511@g.us}"
PROMOTION_ROOT="${DIRECT_COMPETITOR_PROMOTION_ROOT:-$ROOT/logs/direct-competitor-report-receipts}"
GW_HEALTH=http://127.0.0.1:3001/health

log() {
  printf '[%s] blinkit_top8_wa(%s): %s\n' "$(TZ=Asia/Kolkata date '+%F %T %Z')" "$PASS" "$*"
}

exec 9>"$LOCK"
flock -n 9 || { log "another sender holds the lock"; exit 0; }
[ -s "$REPORT" ] || { log "waiting for workbook: $REPORT"; exit 1; }
[ -s "$AUDIT" ] || { log "quality audit is missing: $AUDIT"; exit 1; }
python3 "$CODE_ROOT/tools/cron/direct_competitor_is_accepted.py" \
  --file "$REPORT" --date "$DATE_IST" --platform blinkit --receipts "$PROMOTION_ROOT" \
  || { log "workbook has no exact accepted direct-competitor promotion"; exit 1; }

SUMMARY="$({ python3 - "$AUDIT" "$REPORT" "$DATE_IST" <<'PY'
import hashlib, json, sys
from openpyxl import load_workbook

audit_path, report_path, date = sys.argv[1:]
audit = json.load(open(audit_path, encoding="utf-8"))
summary = audit.get("summary") or {}
required = {
    "date": audit.get("date") == date,
    "pins": summary.get("pincodes_total") == 75,
    "resolved": summary.get("pincodes_resolved") == 75,
    "auth": summary.get("auth_verified") == 1 and summary.get("auth_verified_pincodes") == 75,
    "partial": summary.get("partial") is False,
    "rows": int(summary.get("total_rows") or 0) > 0,
}
if not all(required.values()):
    raise SystemExit(f"quality audit failed: {required}")
brands = (summary.get("scope") or {}).get("competitors")
if not isinstance(brands, list) or not brands:
    raise SystemExit("quality audit is missing the reviewed competitor brand set")
normalized_brands = sorted({" ".join(str(brand).split()).casefold() for brand in brands if str(brand).strip()})
if len(normalized_brands) != len(brands):
    raise SystemExit("quality audit competitor brand set is blank or duplicated")
brand_set_sha256 = hashlib.sha256(
    json.dumps(normalized_brands, separators=(",", ":"), ensure_ascii=True).encode("ascii")
).hexdigest()
bound_brand_hash = audit.get("brand_set_sha256") or (summary.get("scope") or {}).get("brand_set_sha256")
if bound_brand_hash and bound_brand_hash != brand_set_sha256:
    raise SystemExit("quality audit competitor brand-set hash mismatch")
wb = load_workbook(report_path, read_only=True, data_only=False)
expected = ["Summary", "City-Pin-SKU Prices", "Run Scope", "Anchor Watch", "Master Data"]
if wb.sheetnames != expected or wb["Run Scope"].max_row != 82:
    raise SystemExit(f"workbook structure failed: {wb.sheetnames}")
wb.close()
print(
    f"25 cities × 3 pincodes · 75/75 authenticated · "
    f"{summary.get('total_rows')} datapoints · {len(normalized_brands)} competitors"
)
PY
} 2>&1)" || {
  log "quality gate failed: $SUMMARY"
  exit 1
}

SHA="$(sha256sum "$REPORT" | awk '{print $1}')"
SIZE="$(stat -c %s "$REPORT")"
if [ -s "$RECEIPT" ] && python3 - "$RECEIPT" "$REPORT" "$SHA" "$SIZE" "$CHAT" "$DATE_IST" <<'PY'
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
  log "confirmed document receipt already exists; skipping duplicate"
  exit 0
fi

if [ "${BLINKIT_TOP8_WA_TEST:-0}" = "1" ] || [ "${MAILER_TEST_MODE:-0}" = "1" ]; then
  log "TEST send: $CHAT $(basename "$REPORT") | $SUMMARY"
  exit 0
fi

ensure_gateway() {
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/0}"
  export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/0/bus}"
  if curl -s --max-time 5 "$GW_HEALTH" 2>/dev/null | grep -q '"connected"'; then
    return 0
  fi
  systemctl --user reset-failed hermes-gateway-wa-test.service 2>/dev/null || true
  systemctl --user start hermes-gateway-wa-test.service 2>/dev/null || true
  for _ in $(seq 1 30); do
    curl -s --max-time 3 "$GW_HEALTH" 2>/dev/null | grep -q '"connected"' && return 0
    sleep 1
  done
  return 1
}

send_json() {
  curl -s --max-time "$1" -X POST "$2" -H 'Content-Type: application/json' -d "$3"
}

ensure_gateway || log "gateway did not confirm connected; attempting send"
SUBJECT="Blinkit Competitor Price Watch — ${DATE_IST}
${SUMMARY}"
HEADER_PAYLOAD="$(python3 -c 'import json,sys; print(json.dumps({"chatId":sys.argv[1],"message":sys.argv[2]}))' "$CHAT" "$SUBJECT")"
response="$(send_json 60 http://127.0.0.1:3001/send "$HEADER_PAYLOAD")"
log "header response: $response"
grep -q '"success":true' <<<"$response" || exit 1

DOC_PAYLOAD="$(python3 -c 'import json,os,sys; p=os.path.abspath(sys.argv[1]); print(json.dumps({"chatId":sys.argv[2],"filePath":p,"mediaType":"document","fileName":os.path.basename(p)}))' "$REPORT" "$CHAT")"
response="$(send_json 120 http://127.0.0.1:3001/send-media "$DOC_PAYLOAD")"
log "document response: $response"

mkdir -p "$(dirname "$RECEIPT")"
python3 - "$RECEIPT" "$REPORT" "$SHA" "$SIZE" "$CHAT" "$DATE_IST" "$response" <<'PY'
import datetime
import json
import os
import sys

receipt_path, report_path, sha256, size, target, date, raw = sys.argv[1:]
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
    "platform": "blinkit",
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
