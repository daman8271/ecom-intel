#!/usr/bin/env bash
# kvm1_ingest.sh <platform> <drop.json> — VPS-side ingest for KVM1 trio dead-drops.
#
# Phase 2 split (2026-07-07): flipkart-minutes/flipkart/zepto scrape on KVM1
# (bin/kvm1_run_trio.sh there) and rsync their result.json here, exactly like
# the Mac Pro blinkit feeder. This script replays the NORMAL run.sh pipeline on
# the drop via the SCRAPE_RESULT_DROP hook (run.sh skips the local scrape and
# copies the drop into platforms/<p>/result.json, then does excel -> predict ->
# pricematch -> availability -> dashboard -> review VERDICT GATE -> history ->
# coverage ledger -> Telegram spool/send). So the batch, the guards
# (reviews/<p>-<RUN_ID>.json), selfheal and the vault see a KVM1 run exactly as
# they saw a local run — same gates, nothing loosened.
#
# Batch join: if today's 10:00 batch is still pending (launched-* marker, no
# sent-*), run.sh is invoked in DEFER mode with that SWEEP_ID so the report
# joins the batch; otherwise it ships immediately (late-run behavior, same as
# the selfheal backstop). SWEEP_ID env (from the caller) wins when set.
set -uo pipefail
DIR=/opt/ecom-intel
cd "$DIR" || exit 1
P="${1:?usage: kvm1_ingest.sh <flipkart-minutes|flipkart|zepto> <drop.json>}"
DROP="${2:?drop json path}"
LOG(){ echo "[$(date '+%F %T')] kvm1_ingest($P): $*"; }

case "$P" in flipkart-minutes|flipkart|zepto) : ;; *) LOG "refusing platform '$P' (trio only)"; exit 2 ;; esac
[ -s "$DROP" ] || { LOG "drop missing/empty: $DROP"; exit 1; }
python3 - "$DROP" <<'PY' || { LOG "drop is not valid JSON / has no summary — refused"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
if not isinstance(d.get("summary"), dict):
    raise SystemExit("no summary object")
PY

# one ingest per platform at a time
exec 8>"logs/.kvm1_ingest_${P}.lock"
if ! flock -w 600 8; then LOG "another ingest for $P holds the lock >10m — exit"; exit 1; fi

# never clobber platforms/<p>/result.json under a live local run of the same
# platform (guard rescue / selfheal). Wait up to 40m, then give up loudly.
WAITED=0
while pgrep -f "run\.sh ${P}\$" >/dev/null 2>&1; do
  [ "$WAITED" -ge 2400 ] && { LOG "local run.sh $P still active after ${WAITED}s — drop left at $DROP, NOT ingested"; exit 1; }
  [ "$WAITED" -eq 0 ] && LOG "local run.sh $P active — waiting for it to finish"
  sleep 60; WAITED=$((WAITED + 60))
done

# pending-batch discovery (same detection as tools/cron/spool_into_batch.sh)
SID="${SWEEP_ID:-}"
if [ -z "$SID" ]; then
  TODAY="$(date +%F)"
  for l in output/.batch/launched-"$TODAY"-*; do
    [ -e "$l" ] || continue
    s="${l##*/launched-}"
    [ -e "output/.batch/sent-$s" ] && continue
    SID="$s"
  done
fi

RC=0
if [ -n "$SID" ]; then
  LOG "ingesting $DROP in DEFER mode (sweep $SID)"
  DEFER_DELIVERY=1 SWEEP_ID="$SID" COVERAGE_DAILY=1 SCRAPE_RESULT_DROP="$DROP" \
    timeout 1800 ./run.sh "$P" >> "logs/run-${P}.out" 2>&1 || RC=$?
else
  LOG "no pending batch — ingesting $DROP in IMMEDIATE mode"
  DEFER_DELIVERY= SWEEP_ID= COVERAGE_DAILY=1 SCRAPE_RESULT_DROP="$DROP" \
    timeout 1800 ./run.sh "$P" >> "logs/run-${P}.out" 2>&1 || RC=$?
fi

V="$(ls -t reviews/${P}-$(date +%F)-*.json 2>/dev/null | grep -Ev -- '-(unhold|doctor|probe|w2probe)\.json$' | head -1)"
VERDICT="none"; [ -n "$V" ] && VERDICT="$(python3 -c 'import json,sys;print((json.load(open(sys.argv[1])).get("verdict") or "?").upper())' "$V" 2>/dev/null || echo '?')"
LOG "done rc=$RC verdict=$VERDICT ($(basename "${V:-none}"))"
exit "$RC"
