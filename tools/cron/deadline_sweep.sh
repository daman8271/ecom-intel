#!/usr/bin/env bash
# deadline_sweep.sh <HH:MM> — deadline-aligned cron entry point.
#
# "Everyone COMES AT the timing, not starts at it": cron fires this EARLY (see
# crontab.proposed.txt); it predicts the serial chain's runtime from history
# (tools/cron/predict_lead.py), sleeps so the sweep STARTS at T-lead and FINISHES
# by the slot time T, then runs ./run_all.sh in DEFER_DELIVERY mode — every
# platform's Telegram payload is spooled, and send_batch.py (hooked at the end of
# run_all.sh) holds the barrier and delivers ALL reports together AT T.
#
# Env honored / passed through:
#   LEAD_MAX            max lead seconds the prediction may claim (default 7200)
#   PLATFORMS_OVERRIDE  space list — TESTING ONLY (W4 sims); run_all honors it
#   RUNNER_OVERRIDE     command run instead of ./run.sh — TESTING ONLY
#
# Fail-safe: a prediction failure falls back to the max lead (starting too early
# only lengthens the barrier wait — reports are still held to T, never lost).
set -uo pipefail

SLOT="${1:?usage: deadline_sweep.sh <HH:MM>  e.g. deadline_sweep.sh 10:00}"
case "$SLOT" in
  [0-2][0-9]:[0-5][0-9]) : ;;
  *) echo "[$(date '+%F %T')] deadline_sweep: bad slot '$SLOT' (want HH:MM)"; exit 1 ;;
esac

DIR="$(cd "$(dirname "$0")/../.." && pwd)"   # tools/cron -> repo root
cd "$DIR"
mkdir -p logs

LEAD_MAX="${LEAD_MAX:-7200}"
NOW="$(date +%s)"
# T = today's occurrence of HH:MM (cron fires us hours before the slot, so T is
# normally in the future; if T already passed — manual late start — we begin
# immediately and the batch goes out marked late).
T="$(date -d "today $SLOT" +%s 2>/dev/null || echo "$NOW")"

# ---- predict the lead (fail-safe: fall back to the max lead) -----------------
PRED="$(python3 tools/cron/predict_lead.py 2>>logs/cron-deadline.err)" || PRED=""
LEAD="$(printf '%s' "$PRED" | python3 -c 'import json,sys
try: print(int(json.load(sys.stdin)["total"]))
except Exception: print(0)' 2>/dev/null)"
if [ -z "$LEAD" ] || [ "$LEAD" -le 0 ] 2>/dev/null; then
  LEAD=$((LEAD_MAX - 120))
  echo "[$(date '+%F %T')] deadline_sweep($SLOT): PREDICTION FAILED -> fallback lead=${LEAD}s (owner: check tools/cron/predict_lead.py / logs/cron-deadline.err)"
fi
echo "[$(date '+%F %T')] deadline_sweep($SLOT): T=$(date -d "@$T" '+%F %T') lead=${LEAD}s per-platform=${PRED:-n/a}"

# ---- sleep until T - lead -----------------------------------------------------
START=$((T - LEAD))
NOW="$(date +%s)"
if [ "$START" -gt "$NOW" ]; then
  echo "[$(date '+%F %T')] deadline_sweep($SLOT): sleeping $((START - NOW))s -> start $(date -d "@$START" '+%F %T')"
  sleep $((START - NOW))
else
  echo "[$(date '+%F %T')] deadline_sweep($SLOT): start time already passed by $((NOW - START))s -> starting immediately (batch may be late)"
fi

# ---- run the sweep in defer mode ----------------------------------------------
SWEEP_ID="$(date -d "@$T" '+%Y-%m-%d')-$(printf '%s' "$SLOT" | tr -d ':')"
export DEFER_DELIVERY=1
export SWEEP_ID
export SWEEP_DEADLINE="$T"
# pass the test hooks through explicitly (run_all.sh honors them — W2)
[ -n "${PLATFORMS_OVERRIDE:-}" ] && export PLATFORMS_OVERRIDE
[ -n "${RUNNER_OVERRIDE:-}" ] && export RUNNER_OVERRIDE

echo "[$(date '+%F %T')] deadline_sweep($SLOT): launching run_all.sh SWEEP_ID=$SWEEP_ID deadline=$(date -d "@$T" '+%F %T')"
exec ./run_all.sh
