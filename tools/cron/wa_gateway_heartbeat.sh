#!/usr/bin/env bash
# wa_gateway_heartbeat.sh — keep the local WhatsApp gateway (127.0.0.1:3001,
# systemd --user unit hermes-gateway-wa-test.service) alive.
#
# WHY: on 2026-07-11 the owner CUT the email leg — the WhatsApp "Ecom team" group
# (120363047864912511@g.us) is now the ONLY delivery channel for the daily price
# batch and every guard resend. That makes this gateway the single point of failure.
# The mailer already best-effort-restarts it at 10:00, but nothing watches it the
# rest of the day. This heartbeat does: every 10 min it health-checks :3001, and if
# it is not connected it restarts the systemd --user unit and alerts the owner.
#
# Cron (installed 2026-07-11):
#   */10 * * * * cd /opt/ecom-intel && ./tools/cron/wa_gateway_heartbeat.sh \
#       >> logs/wa_gateway_heartbeat.log 2>&1   # WhatsApp gateway heartbeat (sole delivery channel since 2026-07-11)
#
# Alerts are Telegram-ONLY here on purpose: right after a gateway outage the
# WhatsApp pipe is exactly what's untrustworthy, so a "recovered/down" note can't
# be relied on to travel over it. Anti-spam: a state file records healthy/down and
# the last loud-alert time so the "still down" cry repeats at most once per hour,
# and a single "recovered" note fires on the transition back to healthy.
# Never prints secret values.
set -u
DIR=/opt/ecom-intel
cd "$DIR" || exit 0
mkdir -p logs
LOG(){ echo "[$(date '+%F %T')] wa_gateway_heartbeat: $*"; }

# Single-flight: a restart + up-to-60s wait must never stack across ticks.
exec 9>"logs/.wa_gateway_heartbeat.lock"
if ! flock -n 9; then LOG "another heartbeat run holds the lock — exit"; exit 0; fi

# ---------- Telegram-only alert (mirror the other guards) ----------
tg(){ ( set +e
  [ -f "$DIR/secrets.env" ] && . "$DIR/secrets.env"
  CH="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "$CH" ] || exit 0
  curl -s --max-time 30 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CH}" --data-urlencode "text=$1" >/dev/null ) || true; }

GW_HEALTH="http://127.0.0.1:3001/health"
SVC="hermes-gateway-wa-test.service"
STATE_FILE="logs/.wa_gateway_heartbeat.state"

# Healthy = the gateway reports "connected". Match the quoted token exactly (as the
# mailer/morning-guard do) so a "disconnected" body can never false-positive.
gw_healthy(){ curl -s --max-time "${1:-5}" "$GW_HEALTH" 2>/dev/null | grep -q '"connected"'; }

# ---------- state (healthy|down + last loud-alert epoch) ----------
PREV_STATUS=healthy; LAST_DOWN_ALERT=0
if [ -f "$STATE_FILE" ]; then
  PREV_STATUS="$(sed -n 's/^STATUS=//p'          "$STATE_FILE" | head -1)"; PREV_STATUS="${PREV_STATUS:-healthy}"
  LAST_DOWN_ALERT="$(sed -n 's/^LAST_DOWN_ALERT=//p' "$STATE_FILE" | head -1)"; LAST_DOWN_ALERT="${LAST_DOWN_ALERT:-0}"
fi
case "$LAST_DOWN_ALERT" in ''|*[!0-9]*) LAST_DOWN_ALERT=0 ;; esac
write_state(){ printf 'STATUS=%s\nLAST_DOWN_ALERT=%s\n' "$1" "$2" > "$STATE_FILE"; }

NOW="$(date +%s)"

# ---------- healthy on first check ----------
if gw_healthy 5; then
  if [ "$PREV_STATUS" = "down" ]; then
    LOG "gateway is CONNECTED again (was down) — sending recovered note"
    tg "✅ WhatsApp gateway RECOVERED — it is connected again. Ecom-team group deliveries are working (sole channel since 2026-07-11)."
  else
    LOG "gateway healthy — OK (no-op)"
  fi
  write_state healthy 0
  exit 0
fi

# ---------- unhealthy: attempt a systemd --user restart ----------
LOG "gateway health check FAILED — restarting $SVC via systemctl --user"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/0}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/0/bus}"
systemctl --user reset-failed "$SVC" 2>/dev/null || true
systemctl --user start        "$SVC" 2>/dev/null || true

RECOVERED=0
for _ in $(seq 1 60); do
  if gw_healthy 3; then RECOVERED=1; break; fi
  sleep 1
done

if [ "$RECOVERED" = "1" ]; then
  LOG "gateway recovered after auto-restart"
  tg "🛠 WhatsApp gateway was DOWN, auto-restarted OK — it is connected again. (Sole delivery channel since 2026-07-11.)"
  write_state healthy 0
  exit 0
fi

# ---------- still down after restart: loud alert, hourly cap ----------
LOG "gateway STILL DOWN after restart attempt — WhatsApp deliveries are dead until re-pair"
if [ "$(( NOW - LAST_DOWN_ALERT ))" -ge 3600 ]; then
  tg "🚨 WhatsApp gateway is DOWN and would NOT restart. This is the ONLY delivery channel (email cut 2026-07-11) — the Ecom team group gets NOTHING until it's back. It likely needs a phone RE-PAIR on the box (owner action). Repeating at most hourly while down."
  write_state down "$NOW"
else
  LOG "still-down alert suppressed (last sent $(( (NOW - LAST_DOWN_ALERT) / 60 ))m ago; hourly cap)"
  write_state down "$LAST_DOWN_ALERT"
fi
exit 0
