#!/usr/bin/env bash
# healthcheck.sh — ecom-intel health entrypoint (cron-facing).
#
# Thin, best-effort wrapper that delegates to the real self-healing routine in
# tools/selfheal.sh. Kept as a stable entrypoint so cron / docs don't change
# when the heal logic evolves. Never crashes; always exits 0.
#
# What self-heal does (see tools/selfheal.sh for detail):
#   - detect a broken/degraded LIVE platform from (a) the latest review verdict
#     reviews/<platform>-<RUN_ID>.json (BROKEN|SUSPECT), (b) staleness (no fresh
#     result.json/Excel today), or (c) row collapse vs baselines/<platform>.json;
#   - auto-recover by re-running ./run.sh <platform> ONCE under a lock file;
#   - if still broken, Telegram-alert + append to logs/health.log.
export HOME="${HOME:-/root}"
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR" || exit 0
mkdir -p logs 2>/dev/null || true

HEAL="$DIR/tools/selfheal.sh"
if [ -x "$HEAL" ]; then
  bash "$HEAL" || echo "[$(date '+%F %T')] healthcheck: selfheal returned non-zero (ignored)" >> "$DIR/logs/health.log"
elif [ -f "$HEAL" ]; then
  bash "$HEAL" || echo "[$(date '+%F %T')] healthcheck: selfheal returned non-zero (ignored)" >> "$DIR/logs/health.log"
else
  echo "[$(date '+%F %T')] healthcheck: tools/selfheal.sh missing; nothing to do" >> "$DIR/logs/health.log"
fi
exit 0
