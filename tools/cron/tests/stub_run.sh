#!/usr/bin/env bash
# stub_run.sh <platform> — W4 simulation stand-in for ./run.sh <platform>.
# Used via RUNNER_OVERRIDE in run_all.sh. NO network, NO scraping, NO Telegram.
#
# Behavior (mimics W2's DEFER_DELIVERY=1 run.sh contract):
#   - sleeps a fake per-platform duration (STUB_SLEEP_<PLATFORM> env, else built-in:
#     alpha=10 beta=25 gamma=40, else 5)
#   - logs "START"/"END" epoch lines to $SIM_LOG (default tools/cron/tests/sim.log)
#     so the assertion script can prove the platforms ran SERIALLY
#   - writes a fake xlsx into output/ and a spool entry into
#     output/.batch/$SWEEP_ID/<platform>.json using the agreed schema:
#       OK  : {"platform","verdict":"OK","summary","xlsx","caption","ts"}
#       held: {"platform","verdict":"BROKEN","held":true,"reasons"}
#   - the platform named by $HELD_PLATFORM (default "gamma") writes the held marker
set -euo pipefail
P="${1:?usage: stub_run.sh <platform>}"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
SIM_LOG="${SIM_LOG:-$TESTS_DIR/sim.log}"
HELD_PLATFORM="${HELD_PLATFORM:-gamma}"

# fake duration: env override STUB_SLEEP_<P upper> wins, else built-in table
PUP="$(echo "$P" | tr '[:lower:]-' '[:upper:]_')"
SLEEP_VAR="STUB_SLEEP_${PUP}"
SECS="${!SLEEP_VAR:-}"
if [ -z "$SECS" ]; then
  case "$P" in
    alpha) SECS=10 ;;
    beta)  SECS=25 ;;
    gamma) SECS=40 ;;
    *)     SECS=5  ;;
  esac
fi

echo "[$(date +%s)] [$(date '+%F %T')] stub: $P START (sleep ${SECS}s, pid $$)" >> "$SIM_LOG"
sleep "$SECS"

# spool entry — only when the defer contract is active, exactly like run.sh will behave
if [ "${DEFER_DELIVERY:-}" = "1" ] && [ -n "${SWEEP_ID:-}" ]; then
  SPOOL="$ROOT/output/.batch/$SWEEP_ID"
  mkdir -p "$SPOOL"
  if [ "$P" = "$HELD_PLATFORM" ]; then
    python3 - "$P" "$SPOOL/$P.json" <<'PYEOF'
import json, sys, time
p, out = sys.argv[1], sys.argv[2]
json.dump({"platform": p, "verdict": "BROKEN",
           "held": True, "reasons": "simulated broken run (stub held-marker)",
           "ts": int(time.time())},
          open(out, "w"))
PYEOF
    echo "[$(date +%s)] [$(date '+%F %T')] stub: $P spooled HELD marker -> $SPOOL/$P.json" >> "$SIM_LOG"
  else
    DISP="$(echo "${P:0:1}" | tr '[:lower:]' '[:upper:]')${P:1}"
    RDATE="$(date +%F)"
    XLSX="$ROOT/output/Jivo-${DISP}-Live-Report-${RDATE}.sim.xlsx"
    printf 'fake xlsx for %s sweep %s\n' "$P" "$SWEEP_ID" > "$XLSX"
    python3 - "$P" "$SPOOL/$P.json" "$XLSX" "$DISP" "$RDATE" <<'PYEOF'
import json, sys, time
p, out, xlsx, disp, rdate = sys.argv[1:6]
json.dump({"platform": p, "verdict": "OK",
           "summary": f"*Jivo x {disp}* (SIMULATED)\nCoverage: 3/3 pincodes\nSKUs: 2 unique - 6 rows",
           "xlsx": xlsx,
           "caption": f"Jivo × {disp} · {rdate}",
           "ts": int(time.time())},
          open(out, "w"))
PYEOF
    echo "[$(date +%s)] [$(date '+%F %T')] stub: $P spooled OK entry -> $SPOOL/$P.json" >> "$SIM_LOG"
  fi
else
  echo "[$(date +%s)] [$(date '+%F %T')] stub: $P NO spool (DEFER_DELIVERY/SWEEP_ID unset — immediate-send mode)" >> "$SIM_LOG"
fi

echo "[$(date +%s)] [$(date '+%F %T')] stub: $P END" >> "$SIM_LOG"
exit 0
