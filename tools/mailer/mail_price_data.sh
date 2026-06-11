#!/usr/bin/env bash
# mail_price_data.sh <slot> — combine today's report workbooks into one .xlsx
# and email it to the price-data recipient (default dev04@jivo.in, override
# with PRICE_MAIL_TO in secrets.env).
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

TS=$(date +%H%M)
OUT="output/mail/Jivo-Price-Data-$D-$TS.xlsx"
python3 tools/mailer/combine_reports.py --out "$OUT" "${PRESENT[@]}" \
  || { echo "ERROR: combine failed"; alert "combine failed"; exit 1; }

TO="${PRICE_MAIL_TO:-dev04@jivo.in}"
SUBJ="Jivo Price Data — $(date '+%-I:%M %p') IST — $D"
BODY="Combined price data workbook attached (${#PRESENT[@]}/9 reports, all sheets): $(basename -a "${PRESENT[@]}" | paste -sd ', ' -)"

python3 tools/send_email.py --to "$TO" --from-name "Jivo Intel" \
  --subject "$SUBJ" --body "$BODY" --attach "$OUT" \
  || { echo "ERROR: send failed"; alert "Gmail send to $TO failed — check GMAIL_APP_PASSWORD in secrets.env"; exit 1; }

echo "=== $(date '+%F %T') mailer done -> $TO ($OUT) ==="
