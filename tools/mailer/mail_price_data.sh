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
LOCK="logs/.mailer-${SLOT}-${D}.lock"
exec 8>"$LOCK"
flock -n 8 || { echo "mailer already running for slot=$SLOT date=$D"; exit 0; }
exec 7>logs/.direct-report-promotion.lock
flock -w 120 7 || { echo "direct report promotion lock timed out"; exit 1; }
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
AM_NOT_BEFORE="${PRICE_MAIL_AM_NOT_BEFORE:-10:30}"

EXPECTED=(
  "output/Jivo-Amazon-Live-Report-$D.xlsx"
  "output/Jivo-AmazonFresh-Live-Report-$D.xlsx"
  "output/Jivo-AmazonNow-Live-Report-$D.xlsx"
  "output/Jivo-Bigbasket-Live-Report-$D.xlsx"
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

# Test fixtures are written immediately before invocation. Production always
# requires 90 seconds of mtime stability so a workbook cannot be sent mid-write.
if [ -n "${MAILER_STABLE_AGE_S+x}" ]; then
  STABLE_AGE_S="$MAILER_STABLE_AGE_S"
elif [ "${MAILER_TEST_MODE:-0}" = "1" ]; then
  STABLE_AGE_S=0
else
  STABLE_AGE_S=90
fi

file_ready() {
  local f="$1" now="${2:-$(date +%s)}"
  [ -f "$f" ] && [ $(( now - $(stat -c %Y "$f") )) -ge "$STABLE_AGE_S" ] || return 1
  case "$(basename "$f")" in
    Jivo-Blinkit-Live-Report-*|Jivo-Blinkit-Not-Listed-Pincodes-*|Jivo-Zepto-Live-Report-*)
      python3 tools/cron/direct_report_is_accepted.py --file "$f" --date "$D" || return 1
      ;;
  esac
  return 0
}

now="$(date +%s)"
not_before=0
deadline=$((now + MAX_WAIT))
if [ "$SLOT" = "am" ] && [ "${MAILER_SKIP_WAIT:-0}" != "1" ]; then
  not_before="${PRICE_MAIL_NOT_BEFORE_EPOCH:-$(TZ=Asia/Kolkata date -d "$D $AM_NOT_BEFORE" +%s)}"
  deadline="$not_before"
  echo "batch release barrier: not before $D $AM_NOT_BEFORE IST"
fi
while :; do
  now=$(date +%s); ready=1
  for f in "${EXPECTED[@]}"; do
    if ! file_ready "$f" "$now"; then
      ready=0; break
    fi
  done
  if [ "$ready" -eq 1 ] && [ "$now" -ge "$not_before" ]; then
    break
  fi
  if [ "$now" -ge "$deadline" ]; then
    echo "WARN: batch release time reached with required files still missing; sending the stable files that are present"
    break
  fi
  sleep_for=$((deadline - now))
  [ "$sleep_for" -gt 60 ] && sleep_for=60
  [ "$sleep_for" -gt 0 ] && sleep "$sleep_for"
done

PRESENT=()
for f in "${EXPECTED[@]}" "${EXTRA[@]}"; do
  file_ready "$f" && PRESENT+=("$f")
done

MISSING=()
for f in "${EXPECTED[@]}"; do
  file_ready "$f" || MISSING+=("$f")
done
if [ ${#MISSING[@]} -gt 0 ]; then
  MISSING_NAMES="$(basename -a "${MISSING[@]}" | paste -sd ', ' -)"
  echo "WARN: ${#MISSING[@]} required reports are missing or unstable: $MISSING_NAMES"
  alert "${#MISSING[@]} required reports missing at batch deadline: $MISSING_NAMES"
fi

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
PINCODE_REPORT="output/Jivo-BigBasket-Pincode-Report-$D.xlsx"
PINCODE_WA_MARKER="logs/bigbasket-pincode-wa-$D.sent"
RECEIPT_DIR="logs/delivery-receipts/$D"

marker_covers_file() {
  local marker="$1" file="$2"
  [ -f "$marker" ] && [ -f "$file" ] &&
    [ "$(stat -c %Y "$marker")" -ge "$(stat -c %Y "$file")" ]
}

receipt_path() {
  printf '%s/%s.json\n' "$RECEIPT_DIR" "$(basename "$1")"
}

receipt_matches() {
  local file="$1" receipt sha
  receipt="$(receipt_path "$file")"
  [ -f "$receipt" ] || return 1
  sha="$(sha256sum "$file" | awk '{print $1}')" || return 1
  python3 - "$receipt" "$PWD/$file" "$sha" "$WA_GROUP" <<'PY'
import json, os, sys

receipt, path, sha256, target = sys.argv[1:]
try:
    data = json.load(open(receipt, encoding="utf-8"))
except (OSError, ValueError):
    raise SystemExit(1)
ok = (
    data.get("file") == os.path.abspath(path)
    and data.get("sha256") == sha256
    and data.get("target") == target
    and bool(data.get("messageId"))
)
raise SystemExit(0 if ok else 1)
PY
}

write_receipt() {
  local file="$1" response="$2" receipt sha size
  receipt="$(receipt_path "$file")"
  sha="$(sha256sum "$file" | awk '{print $1}')" || return 1
  size="$(stat -c %s "$file")" || return 1
  mkdir -p "$RECEIPT_DIR"
  python3 - "$receipt" "$PWD/$file" "$sha" "$size" "$WA_GROUP" "$response" <<'PY'
import datetime, json, os, sys

receipt, path, sha256, size, target, raw = sys.argv[1:]
try:
    response = json.loads(raw)
except ValueError:
    raise SystemExit(1)
message_id = response.get("messageId")
if response.get("success") is not True or not message_id:
    raise SystemExit(1)
data = {
    "file": os.path.abspath(path),
    "sha256": sha256,
    "size": int(size),
    "target": target,
    "messageId": str(message_id),
    "sent_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
tmp = receipt + ".tmp"
with open(tmp, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
os.replace(tmp, receipt)
PY
}

required_delivered() {
  local file="$1"
  if [ "$file" = "$BLINKIT_REPORT" ] && marker_covers_file "$BLINKIT_MAIN_WA_MARKER" "$file"; then
    return 0
  fi
  receipt_matches "$file"
}

if marker_covers_file "$BLINKIT_MAIN_WA_MARKER" "$BLINKIT_REPORT"; then
  WA_FILTERED=()
  for f in "${WA_PRESENT[@]}"; do
    [ "$f" = "$BLINKIT_REPORT" ] && continue
    WA_FILTERED+=("$f")
  done
  WA_PRESENT=("${WA_FILTERED[@]}")
  echo "WhatsApp group: Blinkit main already sent direct ($BLINKIT_MAIN_WA_MARKER); skipping duplicate group document"
fi

# A retry sends only files whose current SHA has no confirmed group receipt.
# This makes the post-batch guard safe to run repeatedly.
WA_FILTERED=()
for f in "${WA_PRESENT[@]}"; do
  if receipt_matches "$f"; then
    echo "WhatsApp group: confirmed receipt already exists for $(basename "$f"); skipping duplicate"
  else
    WA_FILTERED+=("$f")
  fi
done
WA_PRESENT=("${WA_FILTERED[@]}")

WA_SENT_THIS_RUN=0
if [ ${#WA_PRESENT[@]} -eq 0 ]; then
  echo "WhatsApp group: no unconfirmed files to post; skipped"
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
    if echo "$R" | grep -q '"success":true' && write_receipt "$f" "$R"; then
      WA_SENT_THIS_RUN=$((WA_SENT_THIS_RUN + 1))
      [ "$f" = "$PINCODE_REPORT" ] && touch "$PINCODE_WA_MARKER"
      [ "$f" = "$BLINKIT_REPORT" ] && touch "$BLINKIT_MAIN_WA_MARKER"
    else
      WA_FAIL=1
    fi
    sleep 2
  done
  if [ "$WA_FAIL" -ne 0 ]; then
    echo "ERROR: some WhatsApp posts failed"
    if [ "$EMAIL_FAIL" -eq 0 ]; then
      alert "WhatsApp Ecom-group post failed for one or more files (email did go out)"
    else
      alert "WhatsApp Ecom-group post failed for one or more files AND email failed — team got nothing"
    fi
  fi
fi

REQUIRED_PENDING=()
for f in "${EXPECTED[@]}"; do
  if ! file_ready "$f" || ! required_delivered "$f"; then
    REQUIRED_PENDING+=("$f")
  fi
done
if [ "${MAILER_TEST_MODE:-0}" != "1" ] && [ "${MAILER_DRY_RUN_SEND:-0}" != "1" ]; then
  if [ ${#REQUIRED_PENDING[@]} -eq 0 ] && [ "$WA_FAIL" -eq 0 ]; then
    echo "WhatsApp: posted complete delivery set to Ecom team group (${#EXPECTED[@]} required reports; $WA_SENT_THIS_RUN sent this run)"
  else
    echo "WhatsApp: posted partial delivery set to Ecom team group; ${#REQUIRED_PENDING[@]} required missing or unconfirmed"
    if [ ${#REQUIRED_PENDING[@]} -gt 0 ]; then
      PENDING_NAMES="$(basename -a "${REQUIRED_PENDING[@]}" | paste -sd ', ' -)"
      alert "partial Ecom batch: ${#REQUIRED_PENDING[@]} required reports missing or unconfirmed: $PENDING_NAMES"
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
if [ "${MAILER_TEST_MODE:-0}" != "1" ] && [ "${MAILER_DRY_RUN_SEND:-0}" != "1" ] \
   && { [ "$WA_FAIL" -ne 0 ] || [ ${#REQUIRED_PENDING[@]} -gt 0 ]; }; then
  echo "=== $(date '+%F %T') mailer done WITH INCOMPLETE ECOM DELIVERY ==="
  exit 1
fi
if [ "$EMAIL_SKIPPED" -eq 1 ]; then
  echo "=== $(date '+%F %T') mailer done -> WhatsApp group only, email leg cut (${#PRESENT[@]} files) ==="
else
  echo "=== $(date '+%F %T') mailer done -> $TO + WhatsApp group (${#PRESENT[@]} files) ==="
fi
