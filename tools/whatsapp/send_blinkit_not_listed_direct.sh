#!/usr/bin/env bash
# Direct-send Blinkit's standalone not-listed pincode/SKU workbook to the owner
# contact, but only after the main Blinkit report passes the quality monitor.
set -u

ROOT=/opt/ecom-intel
cd "$ROOT" || exit 1
mkdir -p logs

PASS="${1:-direct-not-listed}"
DATE_IST="${BLINKIT_NOT_LISTED_DATE:-${BLINKIT_MONITOR_DATE:-$(TZ=Asia/Kolkata date +%F)}}"
MAIN="${BLINKIT_MONITOR_REPORT:-output/Jivo-Blinkit-Live-Report-${DATE_IST}.xlsx}"
NOT_LISTED="${BLINKIT_MONITOR_NOT_LISTED_REPORT:-output/Jivo-Blinkit-Not-Listed-Pincodes-${DATE_IST}.xlsx}"
CHAT="${BLINKIT_NOT_LISTED_WA_CHAT:-917703818227@s.whatsapp.net}"
MARKER="logs/blinkit-not-listed-wa-${DATE_IST}.sent"
GW_HEALTH="http://127.0.0.1:3001/health"

if [ "${BLINKIT_SEND_NOT_LISTED_WA:-1}" != "1" ]; then
  echo "Blinkit not-listed direct WhatsApp disabled by BLINKIT_SEND_NOT_LISTED_WA"
  exit 0
fi

if [ -f "$MARKER" ]; then
  echo "Blinkit not-listed direct WhatsApp already sent for $DATE_IST: $MARKER"
  exit 0
fi

if [ ! -f "$NOT_LISTED" ]; then
  echo "Blinkit not-listed direct WhatsApp skipped because not-listed workbook is missing: $NOT_LISTED"
  exit 0
fi
if [ ! -f "$MAIN" ]; then
  echo "Blinkit not-listed direct WhatsApp skipped because main Blinkit report was not accepted"
  exit 0
fi

if ! BLINKIT_MONITOR_DRYRUN=1 \
     BLINKIT_MONITOR_EXIT_CODE=1 \
     BLINKIT_MONITOR_DATE="$DATE_IST" \
     BLINKIT_MONITOR_REPORT="$MAIN" \
     BLINKIT_MONITOR_NOT_LISTED_REPORT="$NOT_LISTED" \
     "$ROOT/tools/cron/blinkit_quality_monitor.sh" "$PASS" >/dev/null; then
  echo "Blinkit not-listed direct WhatsApp skipped because main Blinkit report was held by quality gate"
  exit 0
fi

if [ "${MAILER_TEST_MODE:-0}" = "1" ] || [ "${BLINKIT_NOT_LISTED_WA_TEST:-0}" = "1" ]; then
  echo "TEST WhatsApp direct not-listed: $CHAT $(basename "$NOT_LISTED")"
  exit 0
fi

ensure_gateway() {
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/0}"
  export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/0/bus}"
  if curl -s --max-time 5 "$GW_HEALTH" 2>/dev/null | grep -q '"connected"'; then
    echo "gateway: already connected"
    return 0
  fi
  echo "gateway: not connected for Blinkit not-listed direct send — starting hermes-gateway-wa-test.service"
  systemctl --user reset-failed hermes-gateway-wa-test.service 2>/dev/null || true
  systemctl --user start hermes-gateway-wa-test.service 2>/dev/null || true
  for _ in $(seq 1 30); do
    if curl -s --max-time 3 "$GW_HEALTH" 2>/dev/null | grep -q '"connected"'; then
      echo "gateway: connected"
      return 0
    fi
    sleep 1
  done
  echo "WARN: gateway still not connected; Blinkit not-listed direct send may fail"
  return 1
}

send_json() {
  curl -s --max-time "$1" -X POST "$2" -H 'Content-Type: application/json' -d "$3"
}

ensure_gateway || true
SUBJ="Blinkit not-listed pincodes/SKUs — $DATE_IST"
HEADER_PAYLOAD="$(python3 -c 'import json,sys; print(json.dumps({"chatId": sys.argv[1], "message": sys.argv[2]}))' "$CHAT" "$SUBJ")"
R="$(send_json 60 http://127.0.0.1:3001/send "$HEADER_PAYLOAD")"
echo "WhatsApp direct not-listed header: $R"
echo "$R" | grep -q '"success":true' || exit 1

DOC_PAYLOAD="$(python3 -c 'import json,os,sys; p=os.path.abspath(sys.argv[1]); print(json.dumps({"chatId": sys.argv[2], "filePath": p, "mediaType": "document", "fileName": os.path.basename(p)}))' "$NOT_LISTED" "$CHAT")"
R="$(send_json 120 http://127.0.0.1:3001/send-media "$DOC_PAYLOAD")"
echo "WhatsApp direct not-listed doc $(basename "$NOT_LISTED"): $R"
echo "$R" | grep -q '"success":true' || exit 1

printf '%s %s %s\n' "$(TZ=Asia/Kolkata date '+%F %T %Z')" "$CHAT" "$(basename "$NOT_LISTED")" > "$MARKER"
