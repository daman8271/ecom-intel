#!/usr/bin/env bash
# Promote only final Mac-reviewed competitor packages; never capture or merge.
set -uo pipefail

ROOT=/opt/ecom-intel
cd "$ROOT" || exit 1
# shellcheck disable=SC1091
. tools/laptop/lib.sh

exec 9>logs/.direct-competitor-consumer.lock
flock -n 9 || exit 0

TODAY="$(TZ=Asia/Kolkata date +%F)"
DATES=("$TODAY")
HOUR="$(TZ=Asia/Kolkata date +%H)"
if [ "$((10#$HOUR))" -lt 3 ]; then
  DATES+=("$(TZ=Asia/Kolkata date -d yesterday +%F)")
fi
TOTAL_RC=0

for REPORT_DATE in "${DATES[@]}"; do
  OUTPUT="$(python3 tools/cron/direct_competitor_consumer.py --date "$REPORT_DATE" \
    2> >(tee -a logs/direct-competitor-consumer.log >&2))"
  RC=$?
  printf '%s %s\n' "$(date '+%F %T')" "$OUTPUT" >> logs/direct-competitor-consumer.log
  FAILURES="$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print("; ".join("{} {} phase={} reason={}".format(x.get("platform"),x.get("run_id"),x.get("phase"),x.get("reason")) for x in d.get("endpoint_failures", [])))' "$OUTPUT" 2>/dev/null || true)"
  if [ "$RC" -ne 0 ]; then
    TOTAL_RC=1
    team_tg "[FAIL] A direct Mac competitor package was rejected by its receipt/hash gate. See logs/direct-competitor-consumer.log."
  fi
  if [ -n "$FAILURES" ]; then
    team_tg "[FAIL] Direct competitor endpoint failure recorded: $FAILURES. No VPS/KVM fallback was started."
  fi
done

exit "$TOTAL_RC"
