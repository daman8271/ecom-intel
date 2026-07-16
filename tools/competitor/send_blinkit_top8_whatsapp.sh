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
SNAPSHOT_ROOT="${DIRECT_COMPETITOR_SNAPSHOT_ROOT:-$ROOT/logs/direct-competitor-send-snapshots}"
GW_HEALTH=http://127.0.0.1:3001/health

log() {
  printf '[%s] blinkit_top8_wa(%s): %s\n' "$(TZ=Asia/Kolkata date '+%F %T %Z')" "$PASS" "$*"
}

exec 9>"$LOCK"
flock -n 9 || { log "another sender holds the lock"; exit 0; }

# Owner directive 2026-07-15: the competitor sheet reaches the Ecom group only
# AFTER the Blinkit main sheet is in the group. Hold quietly until the main
# sheet's sent marker exists; COMPETITOR_ALLOW_BEFORE_BLINKIT=1 overrides.
BLINKIT_MAIN_MARKER="${BLINKIT_MAIN_WA_MARKER:-$ROOT/logs/blinkit-main-wa-${DATE_IST}.sent}"
if [ "${COMPETITOR_ALLOW_BEFORE_BLINKIT:-0}" != "1" ] && [ ! -s "$BLINKIT_MAIN_MARKER" ]; then
  log "holding: Blinkit main sheet not in the group yet ($BLINKIT_MAIN_MARKER); competitor sends after it"
  exit 0
fi

[ -s "$REPORT" ] || { log "waiting for workbook: $REPORT"; exit 1; }
[ -s "$AUDIT" ] || { log "quality audit is missing: $AUDIT"; exit 1; }
GATE_JSON="$(python3 "$CODE_ROOT/tools/cron/direct_competitor_is_accepted.py" \
  --file "$REPORT" --date "$DATE_IST" --platform blinkit --receipts "$PROMOTION_ROOT" \
  --snapshot-root "$SNAPSHOT_ROOT")" \
  || { log "workbook has no exact accepted direct-competitor promotion"; exit 1; }

snapshot_fields() {
  python3 - "$GATE_JSON" "$REPORT" "$AUDIT" "$DATE_IST" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import sys

raw, report, audit, date = sys.argv[1:]
value = json.loads(raw)
if value.get("schema") != "jivo-direct-competitor-accepted-snapshot-v1" \
   or value.get("platform") != "blinkit" or value.get("date_ist") != date:
    raise SystemExit("invalid accepted snapshot manifest")
artifacts = value.get("artifacts")
if not isinstance(artifacts, list) or len(artifacts) != 3:
    raise SystemExit("accepted snapshot manifest does not have three artifacts")
by_kind = {item.get("kind"): item for item in artifacts if isinstance(item, dict)}
if set(by_kind) != {"workbook", "merged_capture", "delivery_audit"}:
    raise SystemExit("accepted snapshot manifest artifact kinds are invalid")
if by_kind["workbook"].get("original_path") != os.path.abspath(report):
    raise SystemExit("accepted snapshot workbook identity mismatch")
if by_kind["delivery_audit"].get("original_path") != os.path.abspath(audit):
    raise SystemExit("accepted snapshot audit identity mismatch")
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
SNAPSHOT_REPORT="${SNAPSHOT_FIELDS[0]}"
SNAPSHOT_AUDIT="${SNAPSHOT_FIELDS[2]}"
SHA="${SNAPSHOT_FIELDS[3]}"
SIZE="${SNAPSHOT_FIELDS[4]}"

SUMMARY="$({ python3 - "$SNAPSHOT_AUDIT" "$SNAPSHOT_REPORT" "$DATE_IST" <<'PY'
import hashlib, json, sys
from openpyxl import load_workbook

audit_path, report_path, date = sys.argv[1:]
audit = json.load(open(audit_path, encoding="utf-8"))
required = {
    "schema": audit.get("schema") == "jivo-direct-competitor-delivery-audit-v1",
    "platform": audit.get("platform") == "blinkit",
    "workflow": audit.get("workflow_kind") == "blinkit-top8",
    "date": audit.get("date_ist") == date,
    "status": audit.get("status") == "OK",
    "pins": audit.get("pincodes_total") == 75,
    "rows": int(audit.get("total_rows") or 0) > 0,
}
if not all(required.values()):
    raise SystemExit(f"quality audit failed: {required}")
brands = audit.get("brand_set")
if not isinstance(brands, list) or not brands:
    raise SystemExit("quality audit is missing the reviewed competitor brand set")
normalized_brands = sorted({" ".join(str(brand).split()).casefold() for brand in brands if str(brand).strip()})
if len(normalized_brands) != len(brands):
    raise SystemExit("quality audit competitor brand set is blank or duplicated")
brand_set_sha256 = hashlib.sha256(
    json.dumps(normalized_brands, separators=(",", ":"), ensure_ascii=True).encode("ascii")
).hexdigest()
if audit.get("brand_set_count") != len(normalized_brands) \
   or audit.get("brand_set_sha256") != brand_set_sha256:
    raise SystemExit("quality audit competitor brand-set hash mismatch")
wb = load_workbook(report_path, read_only=True, data_only=False)
expected = ["Summary", "City-Pin-SKU Prices", "Run Scope", "Anchor Watch", "Master Data"]
if wb.sheetnames != expected or wb["Run Scope"].max_row != 82:
    raise SystemExit(f"workbook structure failed: {wb.sheetnames}")
wb.close()
print(
    f"25 cities × 3 pincodes · 75/75 authenticated · "
    f"{audit.get('total_rows')} datapoints · {len(normalized_brands)} competitors"
)
PY
} 2>&1)" || {
  log "quality gate failed: $SUMMARY"
  exit 1
}

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
  log "TEST send: $CHAT $(basename "$REPORT") from accepted snapshot | $SUMMARY"
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

# The inspected snapshot, not the mutable promoted path, is the uploaded file.
snapshot_fields >/dev/null || { log "accepted snapshot changed before media send"; exit 1; }
DOC_PAYLOAD="$(python3 -c 'import json,os,sys; p=os.path.abspath(sys.argv[1]); print(json.dumps({"chatId":sys.argv[3],"filePath":p,"mediaType":"document","fileName":os.path.basename(sys.argv[2])}))' "$SNAPSHOT_REPORT" "$REPORT" "$CHAT")"
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
