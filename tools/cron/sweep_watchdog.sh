#!/usr/bin/env bash
# sweep_watchdog.sh <HH:MM> — catch-up + liveness guard for the deadline sweep.
#
# WHY THIS EXISTS (root cause, 2026-07-01):
#   The daily batch is armed by ONE once-a-day cron tick:
#     30 0 * * *  ... deadline_sweep.sh 10:00   (was 12:00 until goal #60, 2026-07-03)
#   On 2026-07-01 the crontab was being live-edited at ~00:30 (goal-#35 rework);
#   cron RELOADed across the 00:30 minute and DROPPED that minute's dispatch, so
#   the sweep never launched. A missed */15 job self-heals next tick, but a missed
#   once-a-day job is gone for the whole day — and nothing noticed until the
#   mailer timed out hours later and shipped 2 of ~10 reports. Single trigger, no
#   catch-up, no alarm = a whole silent-lost day.
#
# WHAT THIS DOES: runs on MANY ticks across the launch window (see crontab). Each tick:
#   - sweep already armed (marker / batch dir / delivered / running proc) -> quiet no-op
#   - not armed, still enough runtime to finish by the slot -> LAUNCH it (catch-up) + info ping
#   - not armed, too late for a clean finish -> LOUD owner alarm AND best-effort launch
#   flock-guarded + a startup grace so it never premature-launches or double-launches.
#
# It only ever LAUNCHES the same deadline_sweep.sh the primary cron would have run,
# with the same env — so a catch-up day is byte-identical to a normal day, just later.
#
# Test hooks (production-safe, default off):
#   WATCHDOG_DRYRUN=1        launch()/notify() only log what they WOULD do
#   WATCHDOG_NOW_OVERRIDE=<epoch>   pretend "now" is this instant (feasibility math)
set -uo pipefail

SLOT="${1:-10:00}"
cd "$(cd "$(dirname "$0")/../.." && pwd)" || exit 9
mkdir -p logs output/.batch
LOG=logs/sweep_watchdog.log
ts(){ date '+%F %T %Z'; }
say(){ echo "[$(ts)] watchdog($SLOT): $*" >>"$LOG" 2>&1; }

DRYRUN="${WATCHDOG_DRYRUN:-0}"
now_epoch(){ if [ -n "${WATCHDOG_NOW_OVERRIDE:-}" ]; then printf '%s' "$WATCHDOG_NOW_OVERRIDE"; else date +%s; fi; }

DATE="$(date -d "@$(now_epoch)" +%F)"
SWEEP_ID="${DATE}-$(printf '%s' "$SLOT" | tr -d ':')"
MARK="output/.batch/launched-${SWEEP_ID}"

# guard the 10:00 production slot only
[ "$SLOT" = "10:00" ] || { say "non-10:00 slot '$SLOT' — ignoring"; exit 0; }

notify(){ # $1 text — best-effort Telegram to owner (same mechanism as refresh_sites.sh)
  if [ "$DRYRUN" = "1" ]; then say "[DRYRUN] would notify: ${1//$'\n'/ }"; return 0; fi
  [ -f secrets.env ] || { say "notify skipped (no secrets.env)"; return 0; }
  set -a; . ./secrets.env 2>/dev/null; set +a
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] || { say "notify skipped (no telegram creds)"; return 0; }
  curl -s --max-time 20 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" --data-urlencode "text=$1" >/dev/null 2>&1 \
    && say "owner notified (Telegram)" || say "telegram send failed"
}

armed(){ # true if today's noon sweep is already launched / running / delivered
  [ -e "$MARK" ] && return 0                             # launch marker (written at sweep start)
  [ -d "output/.batch/${SWEEP_ID}" ] && return 0         # run_all spooled the batch
  [ -d "output/.batch/sent-${SWEEP_ID}" ] && return 0    # batch already delivered
  pgrep -f "deadline_sweep.sh ${SLOT}" >/dev/null 2>&1 && return 0   # armed & sleeping
  pgrep -f "run_all.sh" >/dev/null 2>&1 && return 0                  # mid-sweep
  return 1
}

NOW=$(now_epoch)
T=$(date -d "$DATE $SLOT" +%s)

# startup grace: give the primary 00:30 tick a 5-min head start so we never
# premature-launch before it, and never double-launch alongside it.
EARLIEST=$(date -d "$DATE 00:35" +%s)
if [ "$NOW" -lt "$EARLIEST" ]; then
  say "before 00:35 grace — primary cron owns the launch; exit"
  exit 0
fi

if armed; then
  say "sweep already armed (marker/dir/proc) — nothing to do"
  exit 0
fi

# not armed. serialize the check-and-launch so overlapping ticks can't double-fire.
exec 8>output/.batch/.watchdog.lock
if ! flock -n 8; then say "another watchdog holds the lock — exit"; exit 0; fi
if armed; then say "armed under lock — exit"; exit 0; fi   # re-check under lock

REMAIN=$(( T - NOW ))
# predicted serial runtime; fail-safe floor so a lowball prediction can never fool
# us into thinking there's plenty of time. The batch is SPOOLED ~1h51m into the
# chain (loop done ~02:53 on a ~01:02 start) and delivery only needs the spool done
# before T; 4h floor covers a slow day + margin and keeps the clean-launch cutoff
# (T - FLOOR - 45m ≈ 05:15 IST for the 10:00 slot) honest without crying wolf.
PRED=$(python3 tools/cron/predict_lead.py 2>/dev/null | python3 -c 'import json,sys
try: print(int(json.load(sys.stdin)["total"]))
except Exception: print(0)' 2>/dev/null)
[ -n "$PRED" ] && [ "$PRED" -gt 0 ] 2>/dev/null || PRED=0
FLOOR=14400                       # 4h
[ "$PRED" -lt "$FLOOR" ] && PRED=$FLOOR
NEED=$(( PRED + 2700 ))           # + 45 min margin

launch(){ # start the real sweep, detached, same env as the primary cron line
  : > "$MARK"
  if [ "$DRYRUN" = "1" ]; then
    say "[DRYRUN] would LAUNCH deadline_sweep.sh $SLOT (remain=${REMAIN}s pred=${PRED}s need=${NEED}s)"
    return 0
  fi
  say "LAUNCHING catch-up sweep (remain=${REMAIN}s pred=${PRED}s need=${NEED}s)"
  setsid env LEAD_MAX="${LEAD_MAX:-32400}" COVERAGE_DAILY="${COVERAGE_DAILY:-1}" \
    ./tools/cron/deadline_sweep.sh "$SLOT" >> logs/cron.log 2>&1 &
  say "catch-up sweep launched (pid $!)"
}

if [ "$REMAIN" -ge "$NEED" ]; then
  launch
  notify "⚠️ Jivo 10:00 sweep watchdog
The 00:30 cron did NOT arm today's ($DATE) 10:00 sweep. Watchdog launched it as catch-up at $(date -d "@$NOW" '+%H:%M') IST — on track to finish by 10:00. Likely a crontab-edit race dropped the launch tick."
else
  launch
  notify "🚨 Jivo 10:00 batch AT RISK
Today's ($DATE) 10:00 sweep was never armed and it is now $(date -d "@$NOW" '+%H:%M') IST — too little runtime to finish a full chain by 10:00. Launched best-effort; the 10:00 batch will likely be LATE or PARTIAL. Manual check needed."
fi
exit 0
