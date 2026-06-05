#!/usr/bin/env bash
# assert_sim.sh <sweep_id> <deadline_epoch> <launch_epoch> <durations_file> <dur_base_count> <sweep_stdout>
# W4 assertion battery over the artifacts left by run_sim.sh. Prints PASS/FAIL per check;
# exit 0 only if all hard assertions pass.
set -uo pipefail
SWEEP_ID="${1:?}"; T="${2:?}"; LAUNCH="${3:?}"; DUR_FILE="${4:?}"; DUR_BASE="${5:?}"; SWEEP_OUT="${6:?}"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
cd "$ROOT"
SIM_LOG="$TESTS_DIR/sim.log"
PASS=0; FAIL=0
ok()   { echo "PASS: $*"; PASS=$((PASS+1)); }
bad()  { echo "FAIL: $*"; FAIL=$((FAIL+1)); }

SPOOL="output/.batch/$SWEEP_ID"
SENT="output/.batch/sent-$SWEEP_ID"

# ---------- (a) sane lead + start time ----------
# expected: total = sum(p90*1.15+120 per platform) + 600, clamped <= LEAD_MAX-120=180
# alpha/beta/gamma p90 ~ 12/27/42 -> per-platform 134/151/168 -> total 1053 -> clamp 180
FIRST_START=$(awk '/stub: .* START/{print $1; exit}' "$SIM_LOG" | tr -d '[]')
if [ -n "${FIRST_START:-}" ]; then
  EXPECT_START=$(( T - 180 ))
  DRIFT=$(( FIRST_START - EXPECT_START )); [ $DRIFT -lt 0 ] && DRIFT=$(( -DRIFT ))
  if [ "$DRIFT" -le 15 ]; then
    ok "(a) first platform started at T-$(( T - FIRST_START ))s (expected T-180, drift ${DRIFT}s)"
  else
    bad "(a) first start at epoch $FIRST_START, expected ~$EXPECT_START (T-180); drift ${DRIFT}s — check lead clamp order (must cap at LEAD_MAX-120 LAST)"
  fi
else
  bad "(a) no stub START line in $SIM_LOG — sweep never ran the stub runner"
fi

# ---------- (b) serial execution ----------
python3 - "$SIM_LOG" <<'PYEOF' && ok "(b) platforms ran serially (no overlap)" || bad "(b) OVERLAP detected — platforms not serial"
import re, sys
ev = []
for line in open(sys.argv[1]):
    m = re.match(r"\[(\d+)\].*stub: (\S+) (START|END)", line)
    if m: ev.append((int(m.group(1)), m.group(2), m.group(3)))
open_p = None
for ts, p, kind in ev:
    if kind == "START":
        if open_p is not None: sys.exit(1)
        open_p = p
    else:
        if open_p != p: sys.exit(1)
        open_p = None
sys.exit(0 if ev else 1)
PYEOF

# ---------- (c) barrier: early finishers' spool entries untouched until T ----------
MON="$TESTS_DIR/monitor.log"
python3 - "$MON" "$T" "$SWEEP_ID" <<'PYEOF' && ok "(c) spool entries existed before T and mtimes stayed fixed until T (barrier held)" || bad "(c) barrier violated or no pre-deadline spool evidence (see monitor.log)"
import re, sys
mon, T, sid = sys.argv[1], int(sys.argv[2]), sys.argv[3]
# monitor.log: "=== <epoch> (..) sweep_alive=..." then "output/.batch/<sid>/<f> mtime=<m> size=<s>"
snap_t, seen_before_T, mtimes = None, {}, {}
violated = False
for line in open(mon):
    m = re.match(r"=== (\d+)", line)
    if m: snap_t = int(m.group(1)); continue
    m = re.match(rf"output/\.batch/{re.escape(sid)}/(\S+) mtime=(\d+)", line)
    if not m or snap_t is None: continue
    f, mt = m.group(1), int(m.group(2))
    if snap_t < T:
        seen_before_T[f] = True
        if f in mtimes and mtimes[f] != mt: violated = True  # rewritten before deadline
        mtimes[f] = mt
ok_count = sum(1 for f in seen_before_T)
sys.exit(0 if (ok_count >= 2 and not violated) else 1)
PYEOF

# ---------- (d) batch fired AT the deadline ±5s, graceful TG failure, spool preserved ----------
# send_batch logs (stdout -> sweep stdout, mirrored to logs/telegram.log):
#   "[ts] send_batch: sweep <id>: chain done early — holding batch Ns until HH:MM:SS"
#   "[ts] send_batch: sweep <id>: woke at deadline — releasing batch"
echo "---- batch log evidence ----"
grep -h "send_batch:" "$SWEEP_OUT" | head -25
echo "----------------------------"
if grep -q "holding batch" "$SWEEP_OUT"; then
  ok "(d.barrier) send_batch entered the barrier (chain finished early, held)"
else
  bad "(d.barrier) no 'holding batch' line — barrier never engaged"
fi
WOKE_TS=$(grep "woke at deadline" "$SWEEP_OUT" | head -1 | sed -E 's/^\[([0-9-]+ [0-9:]+)\].*/\1/')
if [ -n "$WOKE_TS" ]; then
  WOKE_EPOCH=$(date -d "$WOKE_TS" +%s)
  WDRIFT=$(( WOKE_EPOCH - T )); [ $WDRIFT -lt 0 ] && WDRIFT=$(( -WDRIFT ))
  if [ "$WDRIFT" -le 5 ]; then
    ok "(d.timing) batch released at deadline (woke $WOKE_TS, drift ${WDRIFT}s from T)"
  else
    bad "(d.timing) batch released ${WDRIFT}s away from T ($WOKE_TS vs $(date -d "@$T" '+%T'))"
  fi
else
  bad "(d.timing) no 'woke at deadline' line in send_batch output"
fi
# no send attempt may precede T: first sendMessage/sendDocument log line must be >= T-2
FIRST_SEND_TS=$(grep -E "send_batch: .*(header|sendMessage|sendDocument|TG_DRY_RUN)" "$SWEEP_OUT" | head -1 | sed -E 's/^\[([0-9-]+ [0-9:]+)\].*/\1/')
if [ -n "$FIRST_SEND_TS" ]; then
  FS_EPOCH=$(date -d "$FIRST_SEND_TS" +%s)
  if [ "$FS_EPOCH" -ge $(( T - 2 )) ]; then
    ok "(d.no-early-send) first send attempt at $FIRST_SEND_TS (>= T)"
  else
    bad "(d.no-early-send) send attempt at $FIRST_SEND_TS is BEFORE the deadline"
  fi
else
  bad "(d.no-early-send) no send-attempt lines found at all"
fi
# graceful failure with dead creds: spool must still exist (not moved to sent- on failure)
if [ -d "$SPOOL" ] && [ "$(ls -1 "$SPOOL" 2>/dev/null | wc -l)" -ge 3 ]; then
  ok "(d.preserve) dead-creds send failed gracefully — all 3 spool files preserved in $SPOOL"
elif [ -d "$SENT" ]; then
  bad "(d.preserve) spool moved to $SENT despite dead creds — send_batch treats failed sends as success (REPORT LOSS RISK)"
else
  bad "(d.preserve) spool dir missing entirely after batch — files lost"
fi

# ---------- (e) durations.jsonl gained 3 records ----------
DUR_NOW=$(wc -l < "$DUR_FILE" 2>/dev/null || echo 0)
GAIN=$(( DUR_NOW - DUR_BASE ))
if [ "$GAIN" -eq 3 ]; then
  ok "(e) durations file gained exactly 3 records ($DUR_BASE -> $DUR_NOW)"
  tail -3 "$DUR_FILE"
else
  bad "(e) durations file gained $GAIN records, expected 3 ($DUR_BASE -> $DUR_NOW)"
fi

# ---------- (f) idempotent re-run of send_batch (3 stages) ----------
# f1: re-run with STILL-dead creds -> must fail gracefully again, spool intact
echo "(f1) re-running send_batch with dead creds..."
RERUN1=$(TELEGRAM_BOT_TOKEN="000000000:SIMULATED-INVALID-TOKEN" TELEGRAM_CHAT_ID="-1" \
         SECRETS_FILE="$TESTS_DIR/secrets.sim.env" PLATFORMS_OVERRIDE="alpha beta gamma" \
         python3 tools/cron/send_batch.py "$SWEEP_ID" "$T" 2>&1); RC1=$?
N1=$(ls -1 "$SPOOL"/*.json 2>/dev/null | wc -l)
if [ "$RC1" -eq 0 ] && [ "$N1" -ge 3 ]; then
  ok "(f1) dead-creds re-run exited 0, all $N1 spool files intact"
else
  bad "(f1) dead-creds re-run rc=$RC1, spool files now $N1 (expected >=3): $(echo "$RERUN1" | tail -2)"
fi
# f2: re-run with TG_DRY_RUN=1 -> resume succeeds, OK files -> .json.sent, dir retired to sent-
echo "(f2) re-running send_batch with TG_DRY_RUN=1 (resume + retire)..."
RERUN2=$(TG_DRY_RUN=1 TELEGRAM_BOT_TOKEN="000000000:SIMULATED-INVALID-TOKEN" TELEGRAM_CHAT_ID="-1" \
         SECRETS_FILE="$TESTS_DIR/secrets.sim.env" PLATFORMS_OVERRIDE="alpha beta gamma" \
         python3 tools/cron/send_batch.py "$SWEEP_ID" "$T" 2>&1); RC2=$?
SENT_DIR=$(ls -d output/.batch/sent-"$SWEEP_ID"* 2>/dev/null | head -1)
if [ "$RC2" -eq 0 ] && [ -n "$SENT_DIR" ] && [ ! -d "$SPOOL" ]; then
  if ls "$SENT_DIR"/alpha.json.sent >/dev/null 2>&1 && ls "$SENT_DIR"/beta.json.sent >/dev/null 2>&1 \
     && ls "$SENT_DIR"/gamma.json >/dev/null 2>&1; then
    ok "(f2) dry-run resume delivered + retired spool -> $SENT_DIR (alpha/beta .sent, gamma held kept)"
  else
    bad "(f2) retired dir $SENT_DIR has unexpected contents: $(ls "$SENT_DIR")"
  fi
else
  bad "(f2) dry-run resume rc=$RC2 sent_dir='$SENT_DIR' spool_still_exists=$([ -d "$SPOOL" ] && echo yes || echo no)"
fi
# f3: re-run after retirement -> must be a no-op (nothing resent)
RERUN3=$(TG_DRY_RUN=1 PLATFORMS_OVERRIDE="alpha beta gamma" \
         python3 tools/cron/send_batch.py "$SWEEP_ID" "$T" 2>&1); RC3=$?
if [ "$RC3" -eq 0 ] && echo "$RERUN3" | grep -q "no spool dir"; then
  ok "(f3) post-retirement re-run is a clean no-op (nothing resent)"
else
  bad "(f3) post-retirement re-run rc=$RC3: $(echo "$RERUN3" | tail -2)"
fi

echo
echo "==== RESULT: $PASS pass / $FAIL fail ===="
[ "$FAIL" -eq 0 ]
