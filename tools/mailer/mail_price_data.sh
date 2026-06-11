#!/usr/bin/env bash
# mail_price_data.sh <slot> — email today's report workbooks AS-IS (each .xlsx
# an individual attachment, nothing merged or modified) to the ecom team list,
# then post the same files to the WhatsApp "Ecom team" group.
#
# Slots: am (10:00 cron) waits up to 3h for the morning chain to finish
# writing ALL of today's files (batches land ~12:00); pm (16:00 cron) expects
# the 15:00 batch to be on disk already; test sends immediately with whatever
# is present. A file counts as ready only when it exists AND its mtime is
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

case "$SLOT" in
  am) MAX_WAIT=10800 ;;
  pm) MAX_WAIT=1200 ;;
  *)  MAX_WAIT=60 ;;
esac

EXPECTED=(
  "output/Jivo-Amazon-Live-Report-$D.xlsx"
  "output/Jivo-AmazonFresh-Live-Report-$D.xlsx"
  "output/Jivo-AmazonNow-Live-Report-$D.xlsx"
  "output/Jivo-Bigbasket-Live-Report-$D.xlsx"
  "output/Jivo-Blinkit-Live-Report-$D.xlsx"
  "output/Jivo-Flipkart-Live-Report-$D.xlsx"
  "output/Jivo-FlipkartMinutes-Live-Report-$D.xlsx"
  "output/Jivo-Zepto-Live-Report-$D.xlsx"
  "output/Jivo-Price-Match-$D.xlsx"
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
for f in "${EXPECTED[@]}"; do [ -f "$f" ] && PRESENT+=("$f"); done
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
BODY="Today's price data reports attached (${#PRESENT[@]}/9 files): $(basename -a "${PRESENT[@]}" | paste -sd ', ' -)"
ATTACH=()
for f in "${PRESENT[@]}"; do ATTACH+=(--attach "$f"); done

python3 tools/send_email.py --to "$TO" --from-name "Jivo Intel" \
  --subject "$SUBJ" --body "$BODY" "${ATTACH[@]}" \
  || { echo "ERROR: send failed"; alert "Gmail send failed — check GMAIL_APP_PASSWORD in secrets.env"; exit 1; }

# Also post the same files to the WhatsApp "Ecom team" group via the Hermes
# gateway bridge (127.0.0.1:3001 — the live WhatsApp pipe, owner-approved; the
# old Baileys dummy-number session is dead): one header text, then each report
# as its own document. Best-effort: a WhatsApp failure never undoes the
# already-sent email — it just alerts the owner.
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
