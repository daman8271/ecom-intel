#!/usr/bin/env bash
# macpro_zepto_ingest.sh <drop.json> — VPS-side ingest for Mac Pro Zepto drops.
#
# Zepto moved off KVM1 on 2026-07-09 after KVM1 showed repeat HTTP 429 pressure.
# The Mac Pro runner scrapes the daily pincode set and dead-drops result.json here.
# This wrapper replays the normal run.sh pipeline in SCRAPE_RESULT_DROP mode, so
# Excel, enrichers, review gates, history, coverage, and batch delivery stay the
# same as a local run.
set -uo pipefail

DIR=/opt/ecom-intel
cd "$DIR" || exit 1
P=zepto
DROP="${1:?usage: macpro_zepto_ingest.sh <drop.json>}"
LOG(){ echo "[$(date '+%F %T')] macpro_zepto_ingest: $*"; }

[ -s "$DROP" ] || { LOG "drop missing/empty: $DROP"; exit 1; }
python3 - "$DROP" <<'PY' || { LOG "drop is not valid JSON / has no summary — refused"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
if not isinstance(d.get("summary"), dict):
    raise SystemExit("no summary object")
PY

# Device-team stash (laptop worker #4, 2026-07-13): when a Zepto team run is
# active, the Mac's drop is only HALF the universe. A half drop must never hit
# run.sh (review/selfheal baselines assume full counts) — stash it as shard-0
# and fire the merge; the merged FULL result re-enters here with
# ZEPTO_TEAM_BYPASS=1. Count mismatch (e.g. a legacy full drop under a stale
# pointer) falls through to the normal path untouched.
ACTIVE_PTR="shards/runs/ACTIVE-zepto-team"
if [ "${ZEPTO_TEAM_BYPASS:-0}" != "1" ] && [ -f "$ACTIVE_PTR" ]; then
  TEAM_ID="$(head -1 "$ACTIVE_PTR" 2>/dev/null || true)"
  if [ -n "$TEAM_ID" ] && [ "${TEAM_ID#"$(date +%Y%m%d)"-}" != "$TEAM_ID" ]; then
    M0="shards/runs/$TEAM_ID/zepto/shard-0-of-2/manifest.0-of-2.json"
    R0="shards/runs/$TEAM_ID/zepto/shard-0-of-2/result.json"
    if [ -s "$M0" ] && [ ! -s "$R0" ]; then
      DROP_PINS="$(python3 -c 'import json,sys;print((json.load(open(sys.argv[1])).get("summary") or {}).get("pincodes_total") or 0)' "$DROP" 2>/dev/null || echo 0)"
      SHARD_PINS="$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1])).get("shard_pincodes") or []))' "$M0" 2>/dev/null || echo -1)"
      if [ "$DROP_PINS" = "$SHARD_PINS" ]; then
        LOG "team run $TEAM_ID active — stashing this ${DROP_PINS}-pin drop as Mac shard-0 and triggering the merge"
        mv "$DROP" "$R0"
        exec tools/laptop/zepto_team_merge.sh "$TEAM_ID"
      fi
      LOG "team run $TEAM_ID active but drop has ${DROP_PINS} pins (shard-0 expects ${SHARD_PINS}) — treating as a legacy full drop"
    fi
  fi
fi

exec 8>"logs/.macpro_ingest_${P}.lock"
if ! flock -w 600 8; then LOG "another Mac Pro ingest for $P holds the lock >10m — exit"; exit 1; fi

WAITED=0
while pgrep -f "run\.sh ${P}\$" >/dev/null 2>&1; do
  [ "$WAITED" -ge 2400 ] && { LOG "local run.sh $P still active after ${WAITED}s — drop left at $DROP, NOT ingested"; exit 1; }
  [ "$WAITED" -eq 0 ] && LOG "local run.sh $P active — waiting for it to finish"
  sleep 60; WAITED=$((WAITED + 60))
done

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
