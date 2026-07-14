#!/usr/bin/env bash
# Daily competitor price-watch for Zepto and Amazon. Blinkit moved to the dedicated
# post-Blinkit 25-city x 3-pincode top-8 device run on 2026-07-14.
#
# Called EVENT-DRIVEN at the tail of the noon sweep (deadline_sweep.sh, ~12:02 IST), right
# after run_all finishes -- so competitor prices are captured within ~15 min of the JIVO prices for a same-time,
# apples-to-apples comparison (vs a ~10h gap if run overnight). It must run AFTER, never
# DURING, the JIVO sweep: both scrape blinkit+zepto from the same VPS IP, so concurrent runs
# would double the request rate and risk a bot soft-block on BOTH datasets. The sweep-lock
# guard below enforces this -- if the JIVO sweep is somehow still scraping when this fires (a late
# batch), this run skips itself rather than contend. NOT the JIVO pipeline; shares no state.
# FKM excluded until its logged-in browser path is validated.
#
# GUARDRAILS: capture lands only under tools/competitor/data; reports under output/ with the
# "Competitor-Price-Watch-" prefix (the daily mailer only globs "Jivo-*.xlsx", so these are
# never auto-emailed); the price-match master is untouched.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 1
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

for P in zepto amazon-now amazon-fresh; do
  echo "[comp-daily] --- $P ---"
  if bash "$ROOT/tools/competitor/run_competitor.sh" "$P"; then
    echo "[comp-daily] $P ok"
    if [ "$P" = "zepto" ] || [ "$P" = "amazon-now" ] || [ "$P" = "amazon-fresh" ]; then
      "$ROOT/tools/competitor/send_platform_whatsapp.sh" "$P" \
        || echo "[comp-daily] $P workbook passed build but Ecom delivery failed; receipt retry is required"
    fi
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

# ---- PUSH 2: propagate to the JIVO data bank (rebuild -> verify -> PUSH both remotes) ----
# Use run_daily.sh, NOT daily_rebuild.sh: daily_rebuild only COMMITS locally, whereas
# run_daily wraps rebuild + push_both (private remote + embedded ecom-intel copy) + notify.
# Since the fixed 13:30 data-bank cron was removed (goal #35), THIS is now the path that
# actually pushes the data bank — so it must be the full run_daily wrapper.
if [ "${COMP_SKIP_DATABANK:-0}" != "1" ] && [ -x /root/jivo-data-bank/bin/run_daily.sh ]; then
  echo "[comp-daily] triggering JIVO data bank fusion (rebuild + verify + PUSH both remotes) ..."
  if bash /root/jivo-data-bank/bin/run_daily.sh >> "$ROOT/logs/competitor-databank.log" 2>&1; then
    echo "[comp-daily] data bank fused + pushed"
  else
    echo "[comp-daily] data bank fusion non-zero exit (competitor data is still safe in ecom-intel; retries next run)"
  fi
fi

echo "[comp-daily] DONE $(TZ='Asia/Kolkata' date '+%H:%M'). Blinkit top-8 is built separately after the authenticated Blinkit delivery."

# --- eager today/ hook (instant-per-source rule): publish the competitors slice
# into the data-bank today/ the moment its daily report is folded. Self-gates +
# no-ops if unchanged; never blocks this run. ---
/opt/ecom-intel/bin/advance_today_section.sh competitors --date "${DATE_IST}" >> /opt/ecom-intel/bin/build_today.log 2>&1 || true
