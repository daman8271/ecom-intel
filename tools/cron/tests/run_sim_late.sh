#!/usr/bin/env bash
# run_sim_late.sh — W4 LATE-path simulation: durations overshoot the deadline.
# T = next minute boundary (<=80s away); lead(180s) > time-to-T => deadline_sweep must
# log "start time already passed" and start immediately; gamma sleeps 120s so the chain
# (~157s) overruns T by >60s => send_batch must skip the barrier, log the LATE path,
# send immediately, and (dead creds) keep the spool. SIM ONLY.
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
cd "$ROOT"

export PLATFORMS_OVERRIDE="alpha beta gamma"
export RUNNER_OVERRIDE="$TESTS_DIR/stub_run.sh"
export LEAD_MAX=300
export HELD_PLATFORM=gamma
export STUB_SLEEP_GAMMA=120
export SIM_LOG="$TESTS_DIR/sim-late.log"
export DURATIONS_FILE="$TESTS_DIR/durations.sim.jsonl"
[ -f "$DURATIONS_FILE" ] || "$TESTS_DIR/seed_durations.sh" "$DURATIONS_FILE"
export TELEGRAM_BOT_TOKEN="000000000:SIMULATED-INVALID-TOKEN"
export TELEGRAM_CHAT_ID="-1"
export TELEGRAM_OWNER_CHAT_ID="-1"
unset TG_DRY_RUN
export SECRETS_FILE="$TESTS_DIR/secrets.sim.env"

NOW=$(date +%s)
T=$(( (NOW / 60 + 1) * 60 ))                  # next minute boundary: 1..60s away
HHMM=$(date -d "@$T" '+%H:%M')
SWEEP_ID="$(date -d "@$T" '+%F-%H%M')"
rm -rf "output/.batch/$SWEEP_ID" 2>/dev/null || true
: > "$SIM_LOG"
OUT="$TESTS_DIR/sweep-late-stdout.log"
echo "LATE-SIM: T=$HHMM (epoch $T, $((T - NOW))s away); chain ~157s must overrun by >60s"
bash tools/cron/deadline_sweep.sh "$HHMM" > "$OUT" 2>&1
RC=$?
END=$(date +%s)
echo "LATE-SIM: sweep exited rc=$RC at $(date -d "@$END" '+%T') (T+$((END - T))s)"

PASS=0; FAIL=0
ok()  { echo "PASS: $*"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $*"; FAIL=$((FAIL+1)); }

grep -q "start time already passed" "$OUT" \
  && ok "(late.start) deadline_sweep detected past start time and started immediately" \
  || bad "(late.start) no 'start time already passed' line"
grep -q "holding batch" "$OUT" \
  && bad "(late.nobarrier) barrier engaged on an overrun chain (must not)" \
  || ok "(late.nobarrier) no barrier hold on the late path"
grep -q "LATE path — chain overran deadline" "$OUT" \
  && ok "(late.marked) send_batch logged the LATE path with overrun minutes" \
  || bad "(late.marked) no LATE-path log line"
# send must begin immediately after chain end (gamma END epoch ~= first send ts)
G_END=$(awk '/stub: gamma END/{print $1}' "$SIM_LOG" | tr -d '[]' | tail -1)
S_TS=$(grep -E "send_batch: .*header ->" "$OUT" | head -1 | sed -E 's/^\[([0-9-]+ [0-9:]+)\].*/\1/')
if [ -n "$G_END" ] && [ -n "$S_TS" ]; then
  S_EPOCH=$(date -d "$S_TS" +%s)
  D=$(( S_EPOCH - G_END )); [ $D -lt 0 ] && D=$(( -D ))
  [ "$D" -le 10 ] && ok "(late.immediate) batch fired ${D}s after chain end (no extra wait)" \
                  || bad "(late.immediate) ${D}s gap between chain end and first send"
else
  bad "(late.immediate) missing gamma END or header-send timestamps"
fi
[ "$(ls -1 output/.batch/$SWEEP_ID/*.json 2>/dev/null | wc -l)" -ge 3 ] \
  && ok "(late.preserve) dead-creds late send kept all 3 spool files" \
  || bad "(late.preserve) spool files missing after late send"

echo "==== LATE RESULT: $PASS pass / $FAIL fail ===="
[ "$FAIL" -eq 0 ]
