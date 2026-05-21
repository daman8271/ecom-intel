#!/usr/bin/env bash
# Daily self-monitor. For each live platform: if the latest run looks broken
# (too few rows or stale), invoke Claude Code to diagnose + repair + commit.
# Best-effort: if claude isn't available, just logs the breakage.
export HOME="${HOME:-/root}"
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

PLATFORMS="blinkit flipkart-minutes"   # keep in sync with setup_cron.sh
MIN_ROWS=20                  # healthy runs return ~100+; <20 = suspicious
MAX_AGE_H=15                 # should run every ~12h

CLAUDE_BIN="$(command -v claude || true)"

for P in $PLATFORMS; do
  RES="platforms/$P/result.json"
  if [ ! -f "$RES" ]; then echo "[health] $P: no result.json (never ran?)"; continue; fi
  ROWS="$(python3 -c "import json;print(json.load(open('$RES'))['summary']['total_rows'])" 2>/dev/null || echo 0)"
  AGE_H="$(( ( $(date +%s) - $(stat -c %Y "$RES" 2>/dev/null || stat -f %m "$RES") ) / 3600 ))"
  echo "[health] $P rows=$ROWS age=${AGE_H}h"
  if [ "${ROWS:-0}" -ge "$MIN_ROWS" ] && [ "${AGE_H:-99}" -le "$MAX_AGE_H" ]; then
    echo "[health] $P OK"; continue
  fi
  echo "[health] $P SUSPICIOUS -> self-heal"
  if [ -z "$CLAUDE_BIN" ]; then
    echo "[health] claude not found; manual fix needed for $P" ; continue
  fi
  "$CLAUDE_BIN" -p "The '$P' scraper in /opt/ecom-intel/platforms/$P looks broken: latest run had rows=$ROWS (expected ~100+) and is ${AGE_H}h old. \
Read platforms/$P/SKILL.md and scrape.js, run 'node scrape.js' yourself, inspect why it returns too few rows (likely a Blinkit/site selector or location change), and IF it is a safe selector/parsing fix, repair scrape.js, re-run, and confirm summary.total_rows>$MIN_ROWS. \
Only when confirmed working: git add -A && git commit -m 'selfheal($P): <what changed>' && git push. \
If you cannot safely fix it (captcha, IP block, login wall), DO NOT edit code — write the diagnosis to logs/$P-DIAGNOSIS.md and stop. \
Never put an LLM inside the per-pincode scrape loop." >> "logs/$P-selfheal.log" 2>&1 || echo "[health] selfheal run errored for $P (see logs/$P-selfheal.log)"
done
