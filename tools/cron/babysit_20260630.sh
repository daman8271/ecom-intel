#!/usr/bin/env bash
# One-night independent babysitter for the 2026-06-30 runs.
# Launched with nohup/setsid so it survives this Claude session dying. Three jobs:
#   A) CLOBBER-GUARD @05:38 — stop the Amazon coverage runners before the daily cron
#      scrapes Amazon (shared accounts 259/520 must never run twice at once).
#   B) HEALTH CHECK @12:20 — verify the FIRST COVERAGE_DAILY cron run completed + built
#      the QC reports; Telegram the owner PASS/WARN.
#   C) RESUME — re-launch the Amazon coverage scrape post-cron (per-city, skips done).
# All Telegram is best-effort (same secrets.env pattern as the pipeline).
set -u
DIR=/opt/ecom-intel
LOG="$DIR/logs/babysit-20260630.log"
say(){ echo "$(date '+%F %H:%M:%S') $*" >> "$LOG"; }
tg(){ . "$DIR/secrets.env" 2>/dev/null || true
  local T="${TELEGRAM_BOT_TOKEN:-}"; local C="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
  [ -n "$T" ] && [ -n "$C" ] && curl -s --max-time 30 -X POST "https://api.telegram.org/bot${T}/sendMessage" \
    -d chat_id="$C" --data-urlencode text="$1" >/dev/null 2>&1; return 0; }
kill_amz_cov(){ pkill -f "amazon_chunked.sh" 2>/dev/null; sleep 3
  for pid in $(pgrep -x node 2>/dev/null); do
    case "$(readlink /proc/$pid/cwd 2>/dev/null)" in
      *platforms/amazon-now*|*platforms/amazon-fresh*) kill "$pid" 2>/dev/null;; esac; done; }

say "babysitter START pid=$$"
tg "🌙 ecom babysitter armed for 30-Jun: clobber-guard @05:38 · health-check @12:20 · auto-resume Amazon. You'll get pinged at each step."

# ---- A) clobber-guard @05:38 ----
TA=$(date -d "2026-06-30 05:38" +%s)
while [ "$(date +%s)" -lt "$TA" ]; do
  pgrep -f "amazon_chunked.sh" >/dev/null 2>&1 || { say "amazon coverage finished before guard — skip"; break; }
  sleep 120
done
if pgrep -f "amazon_chunked.sh" >/dev/null 2>&1; then
  nf=$(ls "$DIR"/platforms/amazon-now/.cov-chunks/done/*.done 2>/dev/null | wc -l)
  ff=$(ls "$DIR"/platforms/amazon-fresh/.cov-chunks/done/*.done 2>/dev/null | wc -l)
  kill_amz_cov
  say "CLOBBER-GUARD FIRED (now $nf/25 fresh $ff/25)"
  tg "🛡️ ecom 30-Jun: Amazon coverage PAUSED at 05:38 before the cron (now $nf/25, fresh $ff/25 cities). Auto-resumes after noon. No clobber."
fi

# ---- B) health check @12:20 ----
TB=$(date -d "2026-06-30 12:20" +%s)
while [ "$(date +%s)" -lt "$TB" ]; do sleep 300; done
DONE=$(tail -60 "$DIR/logs/cron.log" 2>/dev/null | grep -c "run_all: DONE")
T=$(date +%F); rep=0
for p in blinkit zepto flipkart-minutes; do ls "$DIR"/platforms/$p/Jivo-*"$T".xlsx >/dev/null 2>&1 && rep=$((rep+1)); done
if [ "$DONE" -ge 1 ] && [ "$rep" -ge 2 ]; then
  say "HEALTH OK run_all DONE, $rep/3 QC reports"
  tg "✅ ecom 30-Jun: first COVERAGE_DAILY run OK — cron finished, $rep/3 QC reports built on the 486/693/340 Jivo-priced pincodes. Resuming Amazon."
else
  say "HEALTH WARN DONE=$DONE reports=$rep/3"
  tg "⚠️ ecom 30-Jun: first COVERAGE_DAILY run needs a look — run_all DONE=$DONE, QC reports=$rep/3. See logs/cron.log. Rollback: remove COVERAGE_DAILY=1 from crontab."
fi

# ---- C) resume Amazon coverage (per-city, skips done) ----
for p in amazon-now amazon-fresh; do
  [ -f "$DIR/platforms/$p/.cov-chunks/$p.runfinished" ] && continue
  pgrep -f "amazon_chunked.sh $p" >/dev/null 2>&1 && continue
  ( cd "$DIR" && nohup bash tools/coverage/amazon_chunked.sh "$p" >> "$DIR/logs/amz-$p-resume.log" 2>&1 & )
  say "resumed amazon coverage $p"
done
tg "▶️ ecom 30-Jun: Amazon coverage resumed post-cron (skips finished cities). Final merge+report when it completes."
say "babysitter DONE"
