#!/usr/bin/env bash
# Daily competitor price-watch (quick-commerce): Blinkit + Zepto across the 25-pin set,
# then build the per-platform + combined Excel reports.
#
# Scheduled at 12:15 IST -- RIGHT AFTER the JIVO noon batch finishes (run_all "DONE" ~12:02),
# so competitor prices are captured within ~15 min of the JIVO prices for a same-time,
# apples-to-apples comparison (vs a ~10h gap if run overnight). It must run AFTER, never
# DURING, the JIVO sweep: both scrape blinkit+zepto from the same VPS IP, so concurrent runs
# would double the request rate and risk a bot soft-block on BOTH datasets. The sweep-lock
# guard below enforces this -- if the JIVO sweep is somehow still scraping at 12:15 (a late
# batch), this run skips itself rather than contend. NOT the JIVO pipeline; shares no state.
# FKM excluded until its logged-in browser path is validated.
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

# ---- PUSH 1: fold the day's capture into the ecom vault + push to ecom-intel ----
echo "[comp-daily] folding into ecom vault + pushing to ecom-intel ..."
python3 "$ROOT/tools/competitor/to_vault.py" "$DATE_IST" || echo "[comp-daily] to_vault failed (continuing)"
(
  cd "$ROOT" || exit 0
  # serialize with the JIVO pipeline's git critical section if it exists
  exec 8>"$ROOT/.gitpush.lock"; flock -w 120 8 2>/dev/null || true
  git add vault/competitor tools/competitor/to_vault.py >/dev/null 2>&1
  if git diff --cached --quiet; then
    echo "[comp-daily] no vault change to commit"
  else
    git commit -q -m "competitor: daily capture ${DATE_IST} (Blinkit+Zepto) -> ecom vault" >/dev/null 2>&1
    git push origin HEAD >/dev/null 2>&1 && echo "[comp-daily] pushed to ecom-intel" || echo "[comp-daily] ecom-intel push failed (committed locally)"
  fi
) || echo "[comp-daily] ecom-intel push step had an issue (continuing)"

# ---- PUSH 2: propagate to the JIVO data bank (losslessly copies the ecom vault, then pushes) ----
if [ "${COMP_SKIP_DATABANK:-0}" != "1" ] && [ -x /root/jivo-data-bank/bin/daily_rebuild.sh ]; then
  echo "[comp-daily] triggering JIVO data bank rebuild (folds competitor data + pushes) ..."
  if bash /root/jivo-data-bank/bin/daily_rebuild.sh >> "$ROOT/logs/competitor-databank.log" 2>&1; then
    echo "[comp-daily] data bank rebuilt + pushed"
  else
    echo "[comp-daily] data bank rebuild non-zero exit (competitor data is still safe in ecom-intel; retries next run)"
  fi
fi

echo "[comp-daily] DONE $(TZ='Asia/Kolkata' date '+%H:%M'). reports: output/Competitor-Price-Watch-{Blinkit,Zepto,AllQcomm}-${DATE_IST}.xlsx"
