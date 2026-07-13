#!/usr/bin/env bash
# Alert after the 12:00 IST Ecom-group deadline without stopping late recovery.
set -u

ROOT=/opt/ecom-intel
cd "$ROOT" || exit 1
DATE_IST="${BLINKIT_TOP8_DATE:-$(TZ=Asia/Kolkata date +%F)}"
SENT="$ROOT/logs/blinkit-top8-wa-${DATE_IST}.sent"
STATE="$ROOT/logs/blinkit-top8-${DATE_IST}.state"
POINTER="$ROOT/shards/runs/ACTIVE-blinkit-top8"

[ -s "$SENT" ] && { echo "[blinkit_top8_deadline] delivered"; exit 0; }
touch "$STATE"
grep -qxF deadline-missed "$STATE" 2>/dev/null && exit 0
run_id="$(head -1 "$POINTER" 2>/dev/null || echo none)"
printf '%s\n' deadline-missed >> "$STATE"
(
  set +e
  [ -f "$ROOT/secrets.env" ] && . "$ROOT/secrets.env"
  chat="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "$chat" ] || exit 0
  message="[FAIL] Blinkit top-8 competitor workbook missed the 12:00 IST Ecom-group deadline for ${DATE_IST}. Active run: ${run_id}. Late recovery remains enabled."
  curl -s --max-time 30 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=$chat" --data-urlencode "text=$message" >/dev/null
) || true
echo "[blinkit_top8_deadline] deadline missed; run=$run_id"
