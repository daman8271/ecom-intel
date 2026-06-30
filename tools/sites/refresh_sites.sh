#!/usr/bin/env bash
# refresh_sites.sh — regenerate + redeploy the 3 Jivo ecom availability sites from the
# latest ecom-intel coverage data, AFTER the day's scrape cron has actually landed.
# Deterministic builders (no LLM); deploy via the logged-in Vercel CLI (dp605702-1914).
#
#   ecom-availability-app.vercel.app  <- /root/pa-clients/jivo-data-bank/reports/ecom-availability-app (data.js)
#   coverage-report-site.vercel.app   <- /root/coverage-report-site (index.html)
#   eloo-bangalore-report.vercel.app  <- /root/eloo-bangalore-report (index.html)
#
# Order guarantee: a DATA-READY GATE blocks until today's scrape data exists (or times
# out -> skip + alert), so this always runs AFTER the noon data cron is complete, even if
# that cron overran. Telegram-notifies on success, skip, or failure.
set -uo pipefail
cd /opt/ecom-intel || exit 9
mkdir -p logs
LOG=logs/sites_refresh.log
ts(){ date '+%F %T %Z'; }
say(){ echo "[$(ts)] $*" | tee -a "$LOG"; }

CONSOLE_DIR=${CONSOLE_DIR:-/root/pa-clients/jivo-data-bank/reports/ecom-availability-app}
COVERAGE_DIR=${COVERAGE_DIR:-/root/coverage-report-site}
ELOO_DIR=${ELOO_DIR:-/root/eloo-bangalore-report}
DEPLOY=${DEPLOY:-1}                       # DEPLOY=0 = build only (no vercel, no telegram)
MIN_DATA_DATE=${MIN_DATA_DATE:-$(date +%F)}   # require scrape data on/after this IST date
DATA_WAIT_MAX=${DATA_WAIT_MAX:-9000}      # gate timeout (s) — default 2.5h
DATA_WAIT_INTERVAL=${DATA_WAIT_INTERVAL:-300}

notify(){ # $1 text — best-effort Telegram to the owner (only on real runs)
  [ "$DEPLOY" = "1" ] || return 0
  [ -f secrets.env ] || { say "notify skipped (no secrets.env)"; return 0; }
  set -a; . ./secrets.env 2>/dev/null; set +a
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] || { say "notify skipped (no telegram creds)"; return 0; }
  curl -s --max-time 20 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=$1" >/dev/null 2>&1 && say "owner notified (Telegram)" || say "telegram send failed"
}

say "==== site refresh start (min_data_date=$MIN_DATA_DATE) ===="

# 0) DATA-READY GATE — wait until today's scrape has landed (date_ist >= MIN_DATA_DATE on a QC platform)
data_ready(){ awk -F, -v d="$MIN_DATA_DATE" 'FNR>1 && $2>=d{print;exit}' \
  data/blinkit/history.csv data/zepto/history.csv data/flipkart-minutes/history.csv 2>/dev/null | grep -q .; }
waited=0
until data_ready; do
  if [ "$waited" -ge "$DATA_WAIT_MAX" ]; then
    say "DATA TIMEOUT: no scrape data >= $MIN_DATA_DATE after ${waited}s — skipping (sites left untouched)"
    notify $'⚠️ Jivo ecom sites NOT refreshed\n\nToday\'s ('"$MIN_DATA_DATE"$') scrape data never landed within '"$((DATA_WAIT_MAX/3600))"$'h. Sites left on the previous good version (fail-closed). Check the noon cron / logs.'
    exit 20
  fi
  say "waiting for scrape data >= $MIN_DATA_DATE ... (${waited}s elapsed)"
  sleep "$DATA_WAIT_INTERVAL"; waited=$((waited + DATA_WAIT_INTERVAL))
done
say "data-ready gate passed (scrape data present for >= $MIN_DATA_DATE)"

# 1) freshness visibility (writes DATA-FRESHNESS.md + alerts owner on actionable RED)
if python3 tools/freshness_guard.py --alert >>"$LOG" 2>&1; then
  FRESH="freshness OK"; say "freshness guard: OK (no actionable RED)"
else
  FRESH="freshness RED (see DATA-FRESHNESS.md)"; say "freshness guard: actionable RED present — proceeding (builders use census+floor)"
fi

# 2) regenerate all three (fail-closed: any build failure aborts before any deploy + alerts)
runbuild(){ # $1 label  $2 script  -> echoes captured output, returns rc
  local label="$1" script="$2" out rc
  out=$(python3 "$script" 2>&1); rc=$?
  echo "$out" | tee -a "$LOG" >&2
  if [ $rc -ne 0 ]; then
    say "FATAL: $label build failed (rc=$rc)"
    notify $'❌ Jivo ecom sites refresh FAILED\n\n'"$label"$' build errored (rc='"$rc"$'). Sites left on the previous good version. See logs/sites_refresh.log.'
    exit $((10 + rc % 80))
  fi
  echo "$out"
}
say "building availability console ..."
C_OUT=$(CONSOLE_DIR="$CONSOLE_DIR" runbuild "console" tools/sites/build_availability_console.py)
say "building coverage report ..."
V_OUT=$(COVERAGE_DIR="$COVERAGE_DIR" runbuild "coverage" tools/sites/build_coverage_report.py)
say "building ELOO report ..."
E_OUT=$(ELOO_DIR="$ELOO_DIR" runbuild "eloo" tools/sites/build_eloo_report.py)

C_M=$(echo "$C_OUT" | grep -oE 'pincodes=[0-9]+ platforms=[0-9]+ states=[0-9]+ skus=[0-9]+' | head -1)
V_M=$(echo "$V_OUT" | grep -oE 'reachable=[0-9]+ jivo=[0-9]+ universe=[0-9]+' | head -1)
E_M=$(echo "$E_OUT" | grep -oE 'union=[0-9]+ both=[0-9]+ single=[0-9]+ blind=[0-9]+' | head -1)

# 3) deploy each (linked via .vercel/project.json; --yes for non-interactive cron)
SUMMARY=""
deploy(){ # $1 dir  $2 url  $3 metric
  local dir="$1" url="$2" metric="$3" out rc
  [ "$DEPLOY" = "1" ] || { say "deploy skipped (DEPLOY=0): $url"; SUMMARY+="• $url ($metric) [build-only]"$'\n'; return 0; }
  out=$(cd "$dir" && vercel deploy --prod --yes 2>&1); rc=$?
  if [ $rc -eq 0 ]; then say "deployed -> $url"; SUMMARY+="✅ $url"$'\n'"   $metric"$'\n'
  else say "DEPLOY FAILED $url (rc=$rc): $(echo "$out" | tail -1)"; SUMMARY+="❌ $url (deploy failed)"$'\n'; fi
}
deploy "$CONSOLE_DIR"  "https://ecom-availability-app.vercel.app/" "$C_M"
deploy "$COVERAGE_DIR" "https://coverage-report-site.vercel.app/"  "$V_M"
deploy "$ELOO_DIR"     "https://eloo-bangalore-report.vercel.app/" "$E_M"

# 4) verify console live feed (best-effort)
sleep 5
LIVE=$(curl -s --max-time 20 https://ecom-availability-app.vercel.app/data.js | head -c 400 | grep -o '"generatedAt":"[0-9-]*"' | head -1)
say "console live feed: ${LIVE:-unreadable}"

# 5) notify owner — always, on the real run
notify $'🗺️ Jivo ecom sites refreshed — '"$(date +%F)"$'\ndata >= '"$MIN_DATA_DATE"$' · '"$FRESH"$'\nlive feed: '"${LIVE:-?}"$'\n\n'"$SUMMARY"
say "==== site refresh done ===="
