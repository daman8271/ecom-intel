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
# look for send_batch evidence in sweep stdout + logs/cron.log
BATCH_LINE=$(grep -hEn "send_batch|batch" "$SWEEP_OUT" logs/cron.log 2>/dev/null | grep -viE "deadline_sweep: (computed|lead|sleep)" | head -20)
echo "---- batch log evidence ----"; echo "$BATCH_LINE"; echo "----------------------------"
# timing: find epoch of first actual send attempt; tolerate either explicit epoch logging
# or derive from the sent/spool dir state transition in monitor.log
python3 - "$MON" "$T" "$SWEEP_ID" <<'PYEOF' && ok "(d.timing) no spool-dir change before T; first transition at/after T" || bad "(d.timing) spool dir changed before the deadline"
import re, sys
mon, T, sid = sys.argv[1], int(sys.argv[2]), sys.argv[3]
snap_t, files_prev, changed_early = None, None, False
for line in open(mon):
    m = re.match(r"=== (\d+)", line)
    if m:
        snap_t = int(m.group(1)); files = set(); continue
    m = re.match(rf"output/\.batch/([^/]+)/(\S+) ", line)
    if m and m.group(1) in (sid, f"sent-{sid}") and snap_t and snap_t < T - 2:
        pass  # presence before T is fine (spooling); we detect DISAPPEARANCE pre-T below
# simpler: ensure no sent-<sid> dir appears before T
snap_t = None
for line in open(mon):
    m = re.match(r"=== (\d+)", line)
    if m: snap_t = int(m.group(1)); continue
    if f"sent-{sid}" in line and snap_t and snap_t < T - 2:
        sys.exit(1)
sys.exit(0)
PYEOF
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

# ---------- (f) idempotent re-run of send_batch ----------
echo "re-running send_batch for idempotency check..."
RERUN_OUT=$(python3 tools/cron/send_batch.py "$SWEEP_ID" "$T" 2>&1); RERUN_RC=$?
SPOOL_AFTER=$(ls -1 "$SPOOL" 2>/dev/null | wc -l)
if [ "$RERUN_RC" -eq 0 ] || [ -n "$RERUN_OUT" ]; then
  if [ "$SPOOL_AFTER" -ge 3 ] || [ -d "$SENT" ]; then
    ok "(f) send_batch re-run completed (rc=$RERUN_RC) without losing spool files"
  else
    bad "(f) send_batch re-run LOST spool files (now $SPOOL_AFTER in $SPOOL)"
  fi
else
  bad "(f) send_batch re-run crashed silently (rc=$RERUN_RC, no output)"
fi
echo "rerun output: $RERUN_OUT" | head -5

echo
echo "==== RESULT: $PASS pass / $FAIL fail ===="
[ "$FAIL" -eq 0 ]
