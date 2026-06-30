#!/usr/bin/env bash
# Daily competitor price-watch (quick-commerce): Blinkit + Zepto across the 25-pin set,
# then build the per-platform + combined Excel reports.
#
# Scheduled at 02:00 IST -- a clean window with NO JIVO q-commerce scraping running
# (the JIVO deadline sweep finishes by 12:00 noon the previous day; BigBasket runs 03:00).
# This is NOT the JIVO revenue pipeline and shares none of its state. FKM is excluded until
# its logged-in browser path is validated.
#
# GUARDRAILS: capture lands only under tools/competitor/data; reports under output/ with the
# "Competitor-Price-Watch-" prefix (the daily mailer only globs "Jivo-*.xlsx", so these are
# never auto-emailed); the price-match master is untouched.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
mkdir -p logs

# Single-flight: never let two competitor runs overlap.
exec 9> "$ROOT/tools/competitor/.daily.lock"
if ! flock -n 9; then echo "[comp-daily] another competitor run holds the lock; exiting"; exit 0; fi

# Safety: never co-scrape while a JIVO sweep is active (shared VPS IP -> block risk).
if [ -e "$ROOT/logs/.sweep-chain.lock" ] && ! flock -n "$ROOT/logs/.sweep-chain.lock" true 2>/dev/null; then
  echo "[comp-daily] a JIVO sweep is active -- skipping this run to avoid same-IP contention"
  exit 0
fi

export PINCODES_FILE="$ROOT/tools/competitor/pincodes_25.json"
DATE_IST="$(TZ='Asia/Kolkata' date +%F)"
echo "[comp-daily] START $(TZ='Asia/Kolkata' date '+%F %H:%M') date=$DATE_IST pins=$PINCODES_FILE"

for P in blinkit zepto; do
  echo "[comp-daily] --- $P ---"
  if bash "$ROOT/tools/competitor/run_competitor.sh" "$P"; then
    echo "[comp-daily] $P ok"
  else
    echo "[comp-daily] $P FAILED (continuing to next platform)"
  fi
done

echo "[comp-daily] DONE $(TZ='Asia/Kolkata' date '+%H:%M'). reports: output/Competitor-Price-Watch-{Blinkit,Zepto,AllQcomm}-${DATE_IST}.xlsx"
