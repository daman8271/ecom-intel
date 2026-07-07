#!/usr/bin/env bash
# Direct-send Blinkit's accepted main workbook to the Ecom WhatsApp group.
# This is for Mac/off-box Blinkit drops that finish after the normal batch path.
set -u

ROOT=/opt/ecom-intel
cd "$ROOT" || exit 1
mkdir -p logs

PASS="${1:-direct-main}"
DATE_IST="${BLINKIT_MAIN_WA_DATE:-${BLINKIT_MONITOR_DATE:-$(TZ=Asia/Kolkata date +%F)}}"
MAIN="${BLINKIT_MONITOR_REPORT:-output/Jivo-Blinkit-Live-Report-${DATE_IST}.xlsx}"
NOT_LISTED="${BLINKIT_MONITOR_NOT_LISTED_REPORT:-output/Jivo-Blinkit-Not-Listed-Pincodes-${DATE_IST}.xlsx}"
CHAT="${BLINKIT_MAIN_WA_CHAT:-120363047864912511@g.us}"
MARKER="logs/blinkit-main-wa-${DATE_IST}.sent"
GW_HEALTH="http://127.0.0.1:3001/health"

if [ "${BLINKIT_SEND_MAIN_WA:-1}" != "1" ]; then
  echo "Blinkit main direct WhatsApp disabled by BLINKIT_SEND_MAIN_WA"
  exit 0
fi

if [ -f "$MARKER" ]; then
  echo "Blinkit main direct WhatsApp already sent for $DATE_IST: $MARKER"
  exit 0
fi

if [ ! -f "$MAIN" ]; then
  echo "Blinkit main direct WhatsApp skipped because main workbook is missing: $MAIN"
  exit 0
fi
if [ ! -f "$NOT_LISTED" ]; then
  echo "Blinkit main direct WhatsApp skipped because not-listed workbook is missing: $NOT_LISTED"
  exit 0
fi

if ! BLINKIT_MONITOR_DRYRUN=1 \
     BLINKIT_MONITOR_EXIT_CODE=1 \
     BLINKIT_MONITOR_DATE="$DATE_IST" \
     BLINKIT_MONITOR_REPORT="$MAIN" \
     BLINKIT_MONITOR_NOT_LISTED_REPORT="$NOT_LISTED" \
     "$ROOT/tools/cron/blinkit_quality_monitor.sh" "$PASS" >/dev/null; then
  echo "Blinkit main direct WhatsApp skipped because quality gate held the report"
  exit 0
fi

if [ "${MAILER_TEST_MODE:-0}" = "1" ] || [ "${BLINKIT_MAIN_WA_TEST:-0}" = "1" ]; then
  echo "TEST WhatsApp direct main: $CHAT $(basename "$MAIN")"
  exit 0
fi

ensure_gateway() {
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/0}"
  export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/0/bus}"
  if curl -s --max-time 5 "$GW_HEALTH" 2>/dev/null | grep -q '"connected"'; then
    echo "gateway: already connected"
    return 0
  fi
  echo "gateway: not connected for Blinkit main direct send — starting hermes-gateway-wa-test.service"
  systemctl --user reset-failed hermes-gateway-wa-test.service 2>/dev/null || true
  systemctl --user start hermes-gateway-wa-test.service 2>/dev/null || true
  for _ in $(seq 1 30); do
    if curl -s --max-time 3 "$GW_HEALTH" 2>/dev/null | grep -q '"connected"'; then
      echo "gateway: connected"
      return 0
    fi
    sleep 1
  done
  echo "WARN: gateway still not connected; Blinkit main direct send may fail"
  return 1
}

send_json() {
  curl -s --max-time "$1" -X POST "$2" -H 'Content-Type: application/json' -d "$3"
}

SUMMARY_LINE="$(
  python3 - "$ROOT/platforms/blinkit/result.json" <<'PY' 2>/dev/null || true
import json, sys
try:
    s = json.load(open(sys.argv[1], encoding="utf-8")).get("summary") or {}
except Exception:
    raise SystemExit(0)
print(
    f"{s.get('pincodes_with_jivo','?')}/{s.get('pincodes_total','?')} pincodes carry Jivo · "
    f"{s.get('unique_skus','?')} SKUs · {s.get('total_rows','?')} rows · "
    f"{s.get('pdp_price_probe_checked','?')} PDP price checks"
)
PY
)"

ensure_gateway || true
SUBJ="Blinkit corrected report — $DATE_IST"
if [ -n "$SUMMARY_LINE" ]; then
  SUBJ="${SUBJ}
Fresh authenticated run passed quality.
${SUMMARY_LINE}"
fi
HEADER_PAYLOAD="$(python3 -c 'import json,sys; print(json.dumps({"chatId": sys.argv[1], "message": sys.argv[2]}))' "$CHAT" "$SUBJ")"
R="$(send_json 60 http://127.0.0.1:3001/send "$HEADER_PAYLOAD")"
echo "WhatsApp direct main header: $R"
echo "$R" | grep -q '"success":true' || exit 1

DOC_PAYLOAD="$(python3 -c 'import json,os,sys; p=os.path.abspath(sys.argv[1]); print(json.dumps({"chatId": sys.argv[2], "filePath": p, "mediaType": "document", "fileName": os.path.basename(p)}))' "$MAIN" "$CHAT")"
R="$(send_json 120 http://127.0.0.1:3001/send-media "$DOC_PAYLOAD")"
echo "WhatsApp direct main doc $(basename "$MAIN"): $R"
echo "$R" | grep -q '"success":true' || exit 1

printf '%s %s %s\n' "$(TZ=Asia/Kolkata date '+%F %T %Z')" "$CHAT" "$(basename "$MAIN")" > "$MARKER"
