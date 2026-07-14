#!/usr/bin/env bash
# Promote only final Mac-built workbooks after receipt/hash validation.
set -uo pipefail

DIR=/opt/ecom-intel
cd "$DIR" || exit 1
. tools/laptop/lib.sh

exec 9>logs/.direct-report-consumer.lock
flock -n 9 || exit 0
exec 7>logs/.direct-report-promotion.lock
flock -n 7 || exit 0

TODAY="$(TZ=Asia/Kolkata date +%F)"
DATES=("$TODAY")
HOUR="$(TZ=Asia/Kolkata date +%H)"
if [ "$((10#$HOUR))" -lt 3 ]; then
  DATES+=("$(TZ=Asia/Kolkata date -d yesterday +%F)")
fi
TOTAL_RC=0

for REPORT_DATE in "${DATES[@]}"; do
  OUTPUT="$(python3 tools/cron/direct_report_consumer.py --date "$REPORT_DATE" \
    2> >(tee -a logs/direct-report-consumer.log >&2))"
  RC=$?
  printf '%s %s\n' "$(date '+%F %T')" "$OUTPUT" >> logs/direct-report-consumer.log
  PENDING="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("pending_delivery", 0))' "$OUTPUT" 2>/dev/null || echo 0)"

  if [ "$RC" -ne 0 ]; then
    TOTAL_RC=1
    team_tg "⚠️ A direct Mac report was rejected by the delivery-host receipt/hash gate. See logs/direct-report-consumer.log."
  fi

  NOW="$(TZ=Asia/Kolkata date +%H%M)"
  if [ "$PENDING" -gt 0 ] \
     && { [ "$REPORT_DATE" != "$TODAY" ] || [ "$((10#$NOW))" -ge 1030 ]; }; then
    PRICE_MAIL_DATE="$REPORT_DATE" MAILER_SKIP_EMAIL=1 MAILER_SKIP_WAIT=1 \
      ./tools/mailer/mail_price_data.sh am \
      || team_tg "⚠️ A promoted direct report still lacks an Ecom delivery receipt for ${REPORT_DATE}; retry will continue every five minutes."
  fi
done
exit "$TOTAL_RC"
