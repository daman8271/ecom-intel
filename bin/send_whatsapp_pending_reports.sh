#!/usr/bin/env bash
# send_whatsapp_pending_reports.sh — WhatsApp-only sender for late report files.
set -u

ROOT="/opt/ecom-intel"
DATE_IST="${1:-$(TZ=Asia/Kolkata date +%F)}"
MAX_WAIT_SECONDS="${MAX_WAIT_SECONDS:-43200}"
MIN_AGE_SECONDS="${MIN_AGE_SECONDS:-90}"
LOG="$ROOT/logs/whatsapp-pending-${DATE_IST}.log"
WA_GROUP="${WA_GROUP:-}"

cd "$ROOT" || exit 1
mkdir -p logs
exec >>"$LOG" 2>&1

log() { printf '[%s] %s\n' "$(TZ=Asia/Kolkata date '+%F %T %Z')" "$*"; }

if [ -z "$WA_GROUP" ] && [ -f "$ROOT/secrets/whatsapp-target.json" ]; then
  WA_GROUP="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("jid",""))' "$ROOT/secrets/whatsapp-target.json" 2>/dev/null || true)"
fi
WA_GROUP="${WA_GROUP:-120363047864912511@g.us}"

json_text() {
  python3 - "$WA_GROUP" "$1" <<'PY'
import json, sys
print(json.dumps({"chatId": sys.argv[1], "message": sys.argv[2]}))
PY
}

json_file() {
  python3 - "$PWD/$1" "$WA_GROUP" <<'PY'
import json, os, sys
p = sys.argv[1]
print(json.dumps({
    "chatId": sys.argv[2],
    "filePath": p,
    "mediaType": "document",
    "fileName": os.path.basename(p),
    "caption": os.path.basename(p),
}))
PY
}

send_text() {
  json_text "$1" | curl -s --max-time 60 -X POST http://127.0.0.1:3001/send \
    -H 'Content-Type: application/json' -d @-
}

send_file() {
  json_file "$1" | curl -s --max-time 180 -X POST http://127.0.0.1:3001/send-media \
    -H 'Content-Type: application/json' -d @-
}

ready_file() {
  local f="$1" now
  [ -f "$f" ] || return 1
  now="$(date +%s)"
  [ $(( now - $(stat -c %Y "$f") )) -ge "$MIN_AGE_SECONDS" ]
}

quality_ok() {
  local f="$1"
  case "$(basename "$f")" in
    Jivo-Blinkit-Live-Report-*.xlsx)
      BLINKIT_MONITOR_DRYRUN=1 \
      BLINKIT_MONITOR_EXIT_CODE=1 \
      BLINKIT_MONITOR_DATE="$DATE_IST" \
      BLINKIT_MONITOR_REPORT="$f" \
      "$ROOT/tools/cron/blinkit_quality_monitor.sh" pre-whatsapp-pending >/dev/null
      ;;
    *)
      return 0
      ;;
  esac
}

FILES=(
  "output/Jivo-Blinkit-Live-Report-${DATE_IST}.xlsx"
  "output/Jivo-AmazonFresh-Live-Report-${DATE_IST}.xlsx"
)

deadline=$(( $(date +%s) + MAX_WAIT_SECONDS ))
sent=()
log "START date=$DATE_IST max_wait_seconds=$MAX_WAIT_SECONDS group=$WA_GROUP"

while [ ${#sent[@]} -lt ${#FILES[@]} ]; do
  for f in "${FILES[@]}"; do
    case " ${sent[*]} " in *" $f "*) continue ;; esac
    if ready_file "$f"; then
      if ! quality_ok "$f"; then
        log "SKIP $(basename "$f"): Blinkit quality gate failed"
        sent+=("$f")
        continue
      fi
      log "sending $(basename "$f")"
      r="$(send_text "Jivo Price Data — late Excel sheet ready — $(basename "$f")")"
      log "header: $r"
      r="$(send_file "$f")"
      log "doc $(basename "$f"): $r"
      if printf '%s' "$r" | grep -q '"success":true'; then
        sent+=("$f")
      else
        log "WARN send failed for $f; will retry"
      fi
    fi
  done

  [ ${#sent[@]} -ge ${#FILES[@]} ] && break
  if [ "$(date +%s)" -ge "$deadline" ]; then
    log "TIMEOUT waiting for remaining files"
    for f in "${FILES[@]}"; do
      case " ${sent[*]} " in *" $f "*) ;; *) log "missing/unsent: $f" ;; esac
    done
    exit 1
  fi
  sleep 60
done

log "DONE sent ${#sent[@]}/${#FILES[@]} pending reports"
