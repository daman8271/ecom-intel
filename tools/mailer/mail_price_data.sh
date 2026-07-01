#!/usr/bin/env bash
# mail_price_data.sh <slot> — email today's report workbooks AS-IS (each .xlsx
# an individual attachment, nothing merged or modified) to the ecom team list,
# then post the same files to the WhatsApp "Ecom team" group.
#
# Slots: am (10:00 cron, the ONLY scheduled slot) waits up to 3h for the daily
# serial chain to finish writing ALL of today's files (the noon batch lands ~12:00).
# pm/test are manual-only (pm was retired with the 15:00 sweep 2026-06-28) and send
# with whatever is present. A file counts as ready only when it exists AND its mtime is
# >=90s old (never attach a mid-write workbook). On wait timeout it sends the
# files that ARE present and lists them in the body; if none exist for today
# it sends nothing and exits non-zero.
#
# Runs inside its own tmux session from cron (mailgw-am-YYYYMMDD /
# mailgw-pm-YYYYMMDD); log: logs/mailer.log
set -u
cd /opt/ecom-intel
mkdir -p logs output/mail
exec >> logs/mailer.log 2>&1

SLOT="${1:-test}"
D=$(date +%F)
echo "=== $(date '+%F %T') mailer start slot=$SLOT date=$D ==="

set -a; . ./secrets.env; set +a

# Best-effort owner alert on failure (same philosophy as run.sh delivery).
alert() {
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] || return 0
  curl -s --max-time 30 -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d text="⚠️ price-data mailer ($SLOT $D): $1" >/dev/null || true
}

# Ensure the WhatsApp gateway is CONNECTED before posting. A known
# failure mode (Jun 12-14) was the gateway being down at cron time: a dead
# :3001 returns an empty curl body, which fails the '"success":true' check and
# flags every file as failed. Health-check it; if it's not connected, (re)start
# the systemd --user service and wait up to 30s. Cron/tmux has a bare env, so we
# set XDG_RUNTIME_DIR / DBUS explicitly to reach root's `systemctl --user`.
# Best-effort: if it still won't come up we fall through and the WhatsApp block
# fails-and-alerts as before (the email already went out).
GW_HEALTH="http://127.0.0.1:3001/health"
ensure_gateway() {
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/0}"
  export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/0/bus}"
  if curl -s --max-time 5 "$GW_HEALTH" 2>/dev/null | grep -q '"connected"'; then
    echo "gateway: already connected"; return 0
  fi
  echo "gateway: not connected at $SLOT run — starting hermes-gateway-wa-test.service"
  systemctl --user reset-failed hermes-gateway-wa-test.service 2>/dev/null || true
  systemctl --user start       hermes-gateway-wa-test.service 2>/dev/null || true
  for i in $(seq 1 30); do
    if curl -s --max-time 3 "$GW_HEALTH" 2>/dev/null | grep -q '"connected"'; then
      echo "gateway: connected after ${i}s"; return 0
    fi
    sleep 1
  done
  echo "WARN: gateway still not connected after 30s — WhatsApp posts will likely fail"
  alert "WhatsApp gateway down at $SLOT run and would not start — group post likely failed"
  return 1
}

case "$SLOT" in
  am) MAX_WAIT=10800 ;;
  pm) MAX_WAIT=1200 ;;
  *)  MAX_WAIT=60 ;;
esac

EXPECTED=(
  "output/Jivo-Amazon-Live-Report-$D.xlsx"
  "output/Jivo-AmazonFresh-Live-Report-$D.xlsx"
  "output/Jivo-AmazonNow-Live-Report-$D.xlsx"
  "output/Jivo-BigBasket-Pincode-Report-$D.xlsx"
  "output/Jivo-Blinkit-Live-Report-$D.xlsx"
  "output/Jivo-Flipkart-Live-Report-$D.xlsx"
  "output/Jivo-FlipkartMinutes-Live-Report-$D.xlsx"
  "output/Jivo-Zepto-Live-Report-$D.xlsx"
  "output/Jivo-Price-Match-$D.xlsx"
)

# Swiggy Instamart is produced OFF-BOX (Mac, residential IP — this datacenter IP is
# WAF-blocked on Swiggy search) and dropped in via scp+ingest.sh ~04:00 IST. Attach it
# if present, but it must NEVER gate the wait loop: a missing/late Swiggy report must not
# stall the whole team's batch. So it lives in EXTRA, not EXPECTED.
EXTRA=(
  "output/Jivo-SwiggyInstamart-Live-Report-$D.xlsx"
)

deadline=$(( $(date +%s) + MAX_WAIT ))
while :; do
  now=$(date +%s); ready=1
  for f in "${EXPECTED[@]}"; do
    if [ ! -f "$f" ] || [ $(( now - $(stat -c %Y "$f") )) -lt 90 ]; then
      ready=0; break
    fi
  done
  [ "$ready" -eq 1 ] && break
  if [ "$now" -ge "$deadline" ]; then
    echo "WARN: wait timed out after ${MAX_WAIT}s; sending the files that are present"
    break
  fi
  sleep 60
done

PRESENT=()
for f in "${EXPECTED[@]}" "${EXTRA[@]}"; do [ -f "$f" ] && PRESENT+=("$f"); done
if [ ${#PRESENT[@]} -eq 0 ]; then
  echo "ERROR: no report files for $D — nothing sent"
  alert "no report files for $D — nothing sent"
  exit 1
fi

# Ecom team distribution list (owner-specified 2026-06-11); PRICE_MAIL_TO in
# secrets.env overrides.
TEAM="dev04@jivo.in,ecom4@jivo.in,ecom3@jivo.in,ecom1@jivo.in,ecom8@jivo.in,pr@jivo.in,tanuj@jivo.in,ecomoperations@jivo.in,marketplace@jivo.in,ecomb2b@jivo.in,manav@jivo.in,kamaldeep@jivo.in,ps@jivo.in"
TO="${PRICE_MAIL_TO:-$TEAM}"
SUBJ="Jivo Price Data — $(date '+%-I:%M %p') IST — $D"
BODY="Today's price data reports attached (${#PRESENT[@]}/$(( ${#EXPECTED[@]} + ${#EXTRA[@]} )) files): $(basename -a "${PRESENT[@]}" | paste -sd ', ' -)"
ATTACH=()
for f in "${PRESENT[@]}"; do ATTACH+=(--attach "$f"); done

python3 tools/send_email.py --to "$TO" --from-name "Jivo Intel" \
  --subject "$SUBJ" --body "$BODY" "${ATTACH[@]}" \
  || { echo "ERROR: send failed"; alert "Gmail send failed — check GMAIL_APP_PASSWORD in secrets.env"; exit 1; }

# Also post the same files to the WhatsApp "Ecom team" group via the Hermes
# gateway bridge (127.0.0.1:3001 — the live WhatsApp pipe, owner-approved;
# wa-test profile, dummy number 88990 11758): one header text, then each report
# as its own document. Best-effort: a WhatsApp failure never undoes the
# already-sent email — it just alerts the owner. Make sure the gateway is up
# first so a dead :3001 at cron time doesn't silently drop every file.
ensure_gateway || true
WA_GROUP="120363047864912511@g.us"
WA_FAIL=0
R=$(curl -s --max-time 60 -X POST http://127.0.0.1:3001/send \
  -H 'Content-Type: application/json' \
  -d "$(python3 -c 'import json,sys; print(json.dumps({"chatId": sys.argv[1], "message": sys.argv[2]}))' "$WA_GROUP" "$SUBJ")")
echo "WhatsApp header: $R"
echo "$R" | grep -q '"success":true' || WA_FAIL=1
for f in "${PRESENT[@]}"; do
  B=$(python3 -c 'import json,sys; p=sys.argv[1]; print(json.dumps({"chatId": sys.argv[2], "filePath": p, "mediaType": "document", "fileName": p.rsplit("/",1)[-1]}))' "$PWD/$f" "$WA_GROUP")
  R=$(curl -s --max-time 120 -X POST http://127.0.0.1:3001/send-media \
    -H 'Content-Type: application/json' -d "$B")
  echo "WhatsApp doc $(basename "$f"): $R"
  echo "$R" | grep -q '"success":true' || WA_FAIL=1
  sleep 2
done
if [ "$WA_FAIL" -eq 0 ]; then
  echo "WhatsApp: posted ${#PRESENT[@]} reports to Ecom team group"
else
  echo "ERROR: some WhatsApp posts failed"
  alert "WhatsApp Ecom-group post failed for one or more files (email did go out)"
fi

echo "=== $(date '+%F %T') mailer done -> $TO + WhatsApp group (${#PRESENT[@]} files) ==="
