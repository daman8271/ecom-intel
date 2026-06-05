#!/usr/bin/env bash
# run_sim.sh — W4 end-to-end deadline-sweep simulation driver. SIM ONLY:
# fake platforms (alpha/beta/gamma), stub runner, dead Telegram creds.
# NEVER touches real platforms; refuses to start unless the safety contract holds.
#
# Usage: tools/cron/tests/run_sim.sh [lead-minutes-to-deadline (default 3)]
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
cd "$ROOT"
MIN_TO_T="${1:-3}"

DS="tools/cron/deadline_sweep.sh"
SB="tools/cron/send_batch.py"
RD="tools/cron/record_duration.sh"

fail() { echo "PRECHECK-FAIL: $*" >&2; exit 1; }

# ---------- safety prechecks: refuse to simulate if the contract isn't there ----------
[ -x "$DS" ] || [ -f "$DS" ] || fail "$DS missing (W1 not done?)"
[ -f "$SB" ] || fail "$SB missing (W1 not done?)"
grep -q "PLATFORMS_OVERRIDE" run_all.sh || fail "run_all.sh does not honor PLATFORMS_OVERRIDE (W2 not done?) — sim would launch REAL platforms"
grep -q "RUNNER_OVERRIDE"   run_all.sh || fail "run_all.sh does not honor RUNNER_OVERRIDE — sim would run real ./run.sh"
# Telegram safety: send_batch must let pre-set env/dry-run win over secrets.env,
# otherwise the sim would send REAL telegram messages. Accept any of these mechanisms.
if ! grep -qE "TG_DRY_RUN|SECRETS_FILE|TELEGRAM_BOT_TOKEN:-|already.*set|getenv\(.TELEGRAM" "$SB"; then
  fail "send_batch.py shows no env-precedence/dry-run mechanism — cannot guarantee no real Telegram sends"
fi

# ---------- sim parameters ----------
export PLATFORMS_OVERRIDE="alpha beta gamma"
export RUNNER_OVERRIDE="$TESTS_DIR/stub_run.sh"
export LEAD_MAX=300
export HELD_PLATFORM=gamma
export SIM_LOG="$TESTS_DIR/sim.log"
# dead creds — every send must FAIL GRACEFULLY (spool preserved). TG_DRY_RUN is
# deliberately NOT set for the sweep itself: the failure path is what we test here;
# assert_sim.sh re-runs send_batch with TG_DRY_RUN=1 afterwards to test resume+retire.
export TELEGRAM_BOT_TOKEN="000000000:SIMULATED-INVALID-TOKEN"
export TELEGRAM_CHAT_ID="-1"
export TELEGRAM_OWNER_CHAT_ID="-1"
unset TG_DRY_RUN
export SECRETS_FILE="$TESTS_DIR/secrets.sim.env"
cat > "$SECRETS_FILE" <<'EOF'
TELEGRAM_BOT_TOKEN="000000000:SIMULATED-INVALID-TOKEN"
TELEGRAM_CHAT_ID="-1"
TELEGRAM_OWNER_CHAT_ID="-1"
EOF

# hermetic durations file if supported, else seed+restore the real one
DUR_REAL="tools/cron/durations.jsonl"
if grep -qs "DURATIONS_FILE" "$SB" tools/cron/predict_lead.py "$RD" 2>/dev/null; then
  export DURATIONS_FILE="$TESTS_DIR/durations.sim.jsonl"
  "$TESTS_DIR/seed_durations.sh" "$DURATIONS_FILE"
  DUR_FILE="$DURATIONS_FILE"
else
  echo "WARN: no DURATIONS_FILE support — seeding real $DUR_REAL (alpha/beta/gamma records; backup kept)"
  [ -f "$DUR_REAL" ] && cp "$DUR_REAL" "$TESTS_DIR/durations.pre-sim.bak.jsonl"
  "$TESTS_DIR/seed_durations.sh" /tmp/w4-seed.jsonl
  cat /tmp/w4-seed.jsonl >> "$DUR_REAL"
  DUR_FILE="$DUR_REAL"
fi
DUR_BASE_COUNT=$(wc -l < "$DUR_FILE" 2>/dev/null || echo 0)

# ---------- compute the deadline T (next minute boundary >= now + MIN_TO_T min) ----------
NOW=$(date +%s)
T=$(( ( (NOW + MIN_TO_T*60) / 60 + 1 ) * 60 ))   # round up to a clean minute boundary
HHMM=$(date -d "@$T" '+%H:%M')
SWEEP_ID_GUESS="$(date -d "@$T" '+%F')-$(date -d "@$T" '+%H%M')"
echo "SIM: deadline T=$HHMM (epoch $T, $(( T - NOW ))s away). Guessed SWEEP_ID=$SWEEP_ID_GUESS"
: > "$SIM_LOG"
rm -rf "output/.batch/$SWEEP_ID_GUESS" 2>/dev/null || true

# ---------- launch the sweep ----------
SWEEP_OUT="$TESTS_DIR/sweep-stdout.log"
LAUNCH_EPOCH=$(date +%s)
echo "SIM: launching $DS $HHMM at $(date '+%F %T') (epoch $LAUNCH_EPOCH)"
bash "$DS" "$HHMM" > "$SWEEP_OUT" 2>&1 &
SWEEP_PID=$!

# ---------- monitor: snapshot spool state every 2s until T+90 or sweep exit ----------
MON="$TESTS_DIR/monitor.log"
: > "$MON"
while :; do
  S=$(date +%s)
  {
    echo "=== $S ($(date -d "@$S" '+%T')) sweep_alive=$(kill -0 "$SWEEP_PID" 2>/dev/null && echo yes || echo no)"
    for d in output/.batch/*/ ; do
      [ -d "$d" ] || continue
      ls -l --time-style=+%s "$d" 2>/dev/null | tail -n +2 | awk -v d="$d" '{print d $NF, "mtime="$6, "size="$5}'
    done
  } >> "$MON"
  if ! kill -0 "$SWEEP_PID" 2>/dev/null && [ "$S" -gt "$T" ]; then break; fi
  if [ "$S" -gt $(( T + 180 )) ]; then echo "SIM: TIMEOUT waiting for sweep" >> "$MON"; kill "$SWEEP_PID" 2>/dev/null; break; fi
  sleep 2
done
wait "$SWEEP_PID" 2>/dev/null; SWEEP_RC=$?
END_EPOCH=$(date +%s)
echo "SIM: sweep exited rc=$SWEEP_RC at $(date -d "@$END_EPOCH" '+%T')"

# ---------- restore real durations file if we polluted it ----------
if [ "$DUR_FILE" = "$DUR_REAL" ] && [ -f "$TESTS_DIR/durations.pre-sim.bak.jsonl" ]; then
  # keep the polluted copy for the assertion step, restore happens in assert via flag
  cp "$DUR_REAL" "$TESTS_DIR/durations.post-sim.jsonl"
fi

# ---------- assertions ----------
bash "$TESTS_DIR/assert_sim.sh" "$SWEEP_ID_GUESS" "$T" "$LAUNCH_EPOCH" "$DUR_FILE" "$DUR_BASE_COUNT" "$SWEEP_OUT"
RC=$?

# restore real durations.jsonl if we had seeded it
if [ "$DUR_FILE" = "$DUR_REAL" ] && [ -f "$TESTS_DIR/durations.pre-sim.bak.jsonl" ]; then
  grep -v '"sweep": *"sim-seed' "$DUR_REAL" > "$DUR_REAL.tmp" && mv "$DUR_REAL.tmp" "$DUR_REAL"
  echo "SIM: stripped sim-seed records from $DUR_REAL (stub-run records left for inspection)"
fi
exit $RC
