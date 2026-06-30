#!/usr/bin/env bash
# refresh_sites.sh — regenerate + redeploy the 3 Jivo ecom availability sites from the
# latest ecom-intel coverage data. Deterministic builders (no LLM); deploy via the
# logged-in Vercel CLI (dp605702-1914). Designed to run on cron after the noon batch lands.
#
#   ecom-availability-app.vercel.app  <- /root/pa-clients/jivo-data-bank/reports/ecom-availability-app (data.js)
#   coverage-report-site.vercel.app   <- /root/coverage-report-site (index.html)
#   eloo-bangalore-report.vercel.app  <- /root/eloo-bangalore-report (index.html)
#
# Exit non-zero only if a BUILD fails (fail-closed: never deploy a half-built site).
# A deploy failure is logged + alerted but does not abort the others.
set -uo pipefail
cd /opt/ecom-intel || exit 9
mkdir -p logs
LOG=logs/sites_refresh.log
ts(){ date '+%F %T %Z'; }
say(){ echo "[$(ts)] $*" | tee -a "$LOG"; }

CONSOLE_DIR=${CONSOLE_DIR:-/root/pa-clients/jivo-data-bank/reports/ecom-availability-app}
COVERAGE_DIR=${COVERAGE_DIR:-/root/coverage-report-site}
ELOO_DIR=${ELOO_DIR:-/root/eloo-bangalore-report}
DEPLOY=${DEPLOY:-1}                 # set DEPLOY=0 to build only (no vercel)
SUMMARY=""

say "==== site refresh start ===="

# 1) freshness visibility (writes DATA-FRESHNESS.md + alerts owner on actionable RED).
#    Informational here — the builders themselves exclude stale/frozen series — so a RED
#    on an unrelated platform does not block the QC/availability sites.
if python3 tools/freshness_guard.py --alert >>"$LOG" 2>&1; then
  say "freshness guard: OK (no actionable RED)"
else
  say "freshness guard: actionable RED present (see DATA-FRESHNESS.md) — proceeding; builders use census+floor"
fi

# 2) regenerate all three (fail-closed: any build failure aborts before any deploy)
say "building availability console ..."
CONSOLE_DIR="$CONSOLE_DIR" python3 tools/sites/build_availability_console.py 2>&1 | tee -a "$LOG" || { say "FATAL: console build failed"; exit 11; }
say "building coverage report ..."
COVERAGE_DIR="$COVERAGE_DIR" python3 tools/sites/build_coverage_report.py 2>&1 | tee -a "$LOG" || { say "FATAL: coverage build failed"; exit 12; }
say "building ELOO report ..."
ELOO_DIR="$ELOO_DIR" python3 tools/sites/build_eloo_report.py 2>&1 | tee -a "$LOG" || { say "FATAL: eloo build failed"; exit 13; }

# 3) deploy each (linked via .vercel/project.json; --yes for non-interactive cron)
deploy(){ # $1 dir  $2 label  $3 url
  local dir="$1" label="$2" url="$3" out rc
  [ "$DEPLOY" = "1" ] || { say "deploy skipped (DEPLOY=0): $label"; return 0; }
  out=$(cd "$dir" && vercel deploy --prod --yes 2>&1); rc=$?
  if [ $rc -eq 0 ]; then
    say "deployed $label -> $(echo "$out" | tail -1)"
    SUMMARY+="✅ $url"$'\n'
  else
    say "DEPLOY FAILED $label (rc=$rc): $(echo "$out" | tail -2 | tr '\n' ' ')"
    SUMMARY+="❌ $url (deploy failed)"$'\n'
  fi
}
deploy "$CONSOLE_DIR"  "ecom-availability-app" "https://ecom-availability-app.vercel.app/"
deploy "$COVERAGE_DIR" "coverage-report-site"  "https://coverage-report-site.vercel.app/"
deploy "$ELOO_DIR"     "eloo-bangalore-report" "https://eloo-bangalore-report.vercel.app/"

# 4) verify live freshness of the console data feed (best-effort)
sleep 5
LIVE=$(curl -s --max-time 20 https://ecom-availability-app.vercel.app/data.js | head -c 400 | grep -o '"generatedAt":"[0-9-]*"' | head -1)
say "console live feed: ${LIVE:-unreadable}"

# 5) notify owner (best-effort Telegram via ecom-intel secrets.env)
if [ -f secrets.env ] && [ "$DEPLOY" = "1" ]; then
  set -a; . ./secrets.env 2>/dev/null; set +a
  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
    MSG=$'🗺️ Jivo ecom sites refreshed (latest coverage data)\n\n'"$SUMMARY"
    curl -s --max-time 20 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
      --data-urlencode "text=${MSG}" >/dev/null 2>&1 && say "owner notified (Telegram)"
  fi
fi

say "==== site refresh done ===="
