#!/usr/bin/env bash
# mail_price_data.sh <slot> — post today's report workbooks AS-IS (each .xlsx
# an individual document, nothing merged or modified) to the WhatsApp "Ecom team"
# group. The email leg to the 13-address team list was CUT by owner directive
# 2026-07-11 (Gmail app password revoked + "cut the email thing"); it only runs
# with an explicit MAILER_SKIP_EMAIL=0.
#
# Slots: am (10:00 cron, the ONLY scheduled slot) waits up to 3h for the daily
# serial chain to finish writing ALL of today's files (xlsx ready ~06:17; the batch lands ~10:00 since 2026-07-03, was noon).
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
if [ "${MAILER_NO_REDIRECT:-0}" != "1" ]; then
  exec >> logs/mailer.log 2>&1
fi

SLOT="${1:-test}"
D="${PRICE_MAIL_DATE:-$(date +%F)}"
echo "=== $(date '+%F %T') mailer start slot=$SLOT date=$D ==="

set -a; . ./secrets.env; set +a

# Best-effort owner alert on failure (same philosophy as run.sh delivery).
alert() {
  [ "${MAILER_TEST_MODE:-0}" = "1" ] && { echo "TEST alert: $1"; return 0; }
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
  am) MAX_WAIT=1800 ;;   # 30 min cap (owner 2026-07-05): send by ~10:30 with present files; 3h wait made mail slip to 1 PM when a platform failed
  pm) MAX_WAIT=1200 ;;
  *)  MAX_WAIT=60 ;;
esac
[ "${MAILER_SKIP_WAIT:-0}" = "1" ] && MAX_WAIT=0

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

# Blinkit is Mac/drop-fed and has stricter false-OOS/effective-price gates. The
# ingest path should already refuse bad drops, but the mailer is a final delivery
# surface: if a bad or stale Blinkit workbook somehow exists in output/, hold it
# back from both email and WhatsApp instead of shipping it.
BLINKIT_REPORT="output/Jivo-Blinkit-Live-Report-$D.xlsx"
BLINKIT_HELD=0
BLINKIT_READY=0
if [ -f "$BLINKIT_REPORT" ]; then
  if ! BLINKIT_MONITOR_DRYRUN=1 \
       BLINKIT_MONITOR_EXIT_CODE=1 \
       BLINKIT_MONITOR_DATE="$D" \
       BLINKIT_MONITOR_REPORT="$BLINKIT_REPORT" \
       ./tools/cron/blinkit_quality_monitor.sh pre-whatsapp; then
    echo "WARN: Blinkit quality gate failed; holding back $BLINKIT_REPORT from email/WhatsApp"
    alert "Blinkit report held back from email/WhatsApp: quality gate failed"
    BLINKIT_HELD=1
    FILTERED=()
    for f in "${PRESENT[@]}"; do
      [ "$f" = "$BLINKIT_REPORT" ] && continue
      FILTERED+=("$f")
    done
    PRESENT=("${FILTERED[@]}")
  else
    BLINKIT_READY=1
  fi
fi

if [ ${#PRESENT[@]} -eq 0 ]; then
  echo "ERROR: no report files for $D — nothing sent"
  alert "no report files for $D — nothing sent"
  exit 1
fi

if [ "${MAILER_LIST_ONLY:-0}" = "1" ]; then
  printf '%s\n' "${PRESENT[@]}"
  exit 0
fi

# Ecom team distribution list (owner-specified 2026-06-11); PRICE_MAIL_TO in
# secrets.env overrides.
TEAM="dev04@jivo.in,ecom4@jivo.in,ecom3@jivo.in,ecom1@jivo.in,ecom8@jivo.in,pr@jivo.in,tanuj@jivo.in,ecomoperations@jivo.in,marketplace@jivo.in,ecomb2b@jivo.in,manav@jivo.in,kamaldeep@jivo.in,ps@jivo.in"
TO="${PRICE_MAIL_TO:-$TEAM}"
SUBJ="Jivo Price Data — $(date '+%-I:%M %p') IST — $D"
BODY="Today's price data reports attached (${#PRESENT[@]}/$(( ${#EXPECTED[@]} + ${#EXTRA[@]} )) files): $(basename -a "${PRESENT[@]}" | paste -sd ', ' -)"
ATTACH=()
for f in "${PRESENT[@]}"; do ATTACH+=(--attach "$f"); done

# Email failure must NEVER block the WhatsApp group post (2026-07-11: a revoked
# Gmail app password 535'd here and the exit 1 silently dropped the whole
# Ecom-group batch). Record the failure, alert, and keep going.
EMAIL_FAIL=0
EMAIL_SKIPPED=0
if [ "${MAILER_DRY_RUN_SEND:-0}" = "1" ]; then
  echo "DRYRUN email: to=$TO subject=$SUBJ files=${#PRESENT[@]}"
elif [ "${MAILER_SKIP_EMAIL:-1}" = "1" ]; then
  EMAIL_SKIPPED=1
  # OWNER DIRECTIVE 2026-07-11 ("cut the email thing"): the email leg is CUT —
  # the WhatsApp Ecom-team group is the only delivery channel. Email goes out
  # ONLY if MAILER_SKIP_EMAIL=0 is set explicitly.
  echo "email: skipped (email leg cut per owner 2026-07-11)"
else
  python3 tools/send_email.py --to "$TO" --from-name "Jivo Intel" \
    --subject "$SUBJ" --body "$BODY" "${ATTACH[@]}" \
    || { EMAIL_FAIL=1; echo "ERROR: email send failed — continuing to WhatsApp"; alert "Gmail send failed — check GMAIL_APP_PASSWORD in secrets.env (WhatsApp group post still going out)"; }
fi

# Also post the same files to the WhatsApp "Ecom team" group via the Hermes
# gateway bridge (127.0.0.1:3001 — the live WhatsApp pipe, owner-approved;
# wa-test profile, dummy number 88990 11758): one header text, then each report
# as its own document. Best-effort: a WhatsApp failure never undoes the
# already-sent email — it just alerts the owner. Make sure the gateway is up
# first so a dead :3001 at cron time doesn't silently drop every file.
WA_GROUP="120363047864912511@g.us"
WA_FAIL=0
WA_PRESENT=("${PRESENT[@]}")
BLINKIT_MAIN_WA_MARKER="logs/blinkit-main-wa-$D.sent"
if [ -f "$BLINKIT_MAIN_WA_MARKER" ]; then
  WA_FILTERED=()
  for f in "${WA_PRESENT[@]}"; do
    [ "$f" = "$BLINKIT_REPORT" ] && continue
    WA_FILTERED+=("$f")
  done
  WA_PRESENT=("${WA_FILTERED[@]}")
  echo "WhatsApp group: Blinkit main already sent direct ($BLINKIT_MAIN_WA_MARKER); skipping duplicate group document"
fi
if [ ${#WA_PRESENT[@]} -eq 0 ]; then
  echo "WhatsApp group: no files to post after direct-send filtering; skipped"
elif [ "${MAILER_TEST_MODE:-0}" = "1" ] || [ "${MAILER_DRY_RUN_SEND:-0}" = "1" ]; then
  echo "TEST WhatsApp group: $WA_GROUP ${#WA_PRESENT[@]} files"
else
  ensure_gateway || true
  R=$(curl -s --max-time 60 -X POST http://127.0.0.1:3001/send \
    -H 'Content-Type: application/json' \
    -d "$(python3 -c 'import json,sys; print(json.dumps({"chatId": sys.argv[1], "message": sys.argv[2]}))' "$WA_GROUP" "$SUBJ")")
  echo "WhatsApp header: $R"
  echo "$R" | grep -q '"success":true' || WA_FAIL=1
  for f in "${WA_PRESENT[@]}"; do
    B=$(python3 -c 'import json,sys; p=sys.argv[1]; print(json.dumps({"chatId": sys.argv[2], "filePath": p, "mediaType": "document", "fileName": p.rsplit("/",1)[-1]}))' "$PWD/$f" "$WA_GROUP")
    R=$(curl -s --max-time 120 -X POST http://127.0.0.1:3001/send-media \
      -H 'Content-Type: application/json' -d "$B")
    echo "WhatsApp doc $(basename "$f"): $R"
    echo "$R" | grep -q '"success":true' || WA_FAIL=1
    sleep 2
  done
  if [ "$WA_FAIL" -eq 0 ]; then
    echo "WhatsApp: posted ${#WA_PRESENT[@]} reports to Ecom team group"
  else
    echo "ERROR: some WhatsApp posts failed"
    if [ "$EMAIL_FAIL" -eq 0 ]; then
      alert "WhatsApp Ecom-group post failed for one or more files (email did go out)"
    else
      alert "WhatsApp Ecom-group post failed for one or more files AND email failed — team got nothing"
    fi
  fi
fi

# Send Blinkit's not-listed pincode/SKU workbook separately to the requested
# direct WhatsApp contact. Keep it out of the team batch, and never send it when
# the main Blinkit workbook was held back by the quality gate.
BLINKIT_NOT_LISTED_REPORT="output/Jivo-Blinkit-Not-Listed-Pincodes-$D.xlsx"
BLINKIT_NOT_LISTED_WA_CHAT="${BLINKIT_NOT_LISTED_WA_CHAT:-917703818227@s.whatsapp.net}"
if [ "${BLINKIT_SEND_NOT_LISTED_WA:-1}" = "1" ] && [ "$BLINKIT_READY" -eq 1 ] && [ -f "$BLINKIT_NOT_LISTED_REPORT" ]; then
  BLINKIT_NOT_LISTED_DATE="$D" \
  BLINKIT_MONITOR_REPORT="$BLINKIT_REPORT" \
  BLINKIT_MONITOR_NOT_LISTED_REPORT="$BLINKIT_NOT_LISTED_REPORT" \
  BLINKIT_NOT_LISTED_WA_CHAT="$BLINKIT_NOT_LISTED_WA_CHAT" \
    ./tools/whatsapp/send_blinkit_not_listed_direct.sh mailer \
    || alert "Blinkit not-listed WhatsApp send failed for $BLINKIT_NOT_LISTED_WA_CHAT"
elif [ -f "$BLINKIT_NOT_LISTED_REPORT" ] && [ "$BLINKIT_HELD" -eq 1 ]; then
  echo "Blinkit not-listed direct WhatsApp skipped because main Blinkit report was held by quality gate"
elif [ -f "$BLINKIT_NOT_LISTED_REPORT" ] && [ "$BLINKIT_READY" -ne 1 ]; then
  echo "Blinkit not-listed direct WhatsApp skipped because main Blinkit report was not accepted"
fi

if [ "$EMAIL_FAIL" -eq 1 ]; then
  echo "=== $(date '+%F %T') mailer done WITH EMAIL FAILURE -> WhatsApp group only (${#PRESENT[@]} files) ==="
  exit 1
fi
if [ "$EMAIL_SKIPPED" -eq 1 ]; then
  echo "=== $(date '+%F %T') mailer done -> WhatsApp group only, email leg cut (${#PRESENT[@]} files) ==="
else
  echo "=== $(date '+%F %T') mailer done -> $TO + WhatsApp group (${#PRESENT[@]} files) ==="
fi
