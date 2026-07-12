#!/usr/bin/env bash
# One-shot 10:40 wrapper (2026-07-13): run the coverage100 morning verifier,
# Telegram the result to the owner, then remove its own cron line.
set -u
DIR=/opt/ecom-intel
cd "$DIR" || exit 1
OUT="$(./tools/cron/verify_coverage80.sh 2>&1)"
RC=$?
[ -f secrets.env ] && . secrets.env
CH="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "$CH" ]; then
  ICON="✅"; [ "$RC" -ne 0 ] && ICON="⚠️"
  curl -s --max-time 30 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CH}" \
    --data-urlencode "text=${ICON} coverage100 first-morning verify (goal #80):
$(printf '%s' "$OUT" | head -c 3500)" >/dev/null
fi
crontab -l | grep -v verify_coverage80_oneshot | crontab -
