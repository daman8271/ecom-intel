#!/usr/bin/env bash
# zepto_team_merge.sh <run_id> — merge the Mac (shard-0) + laptop (shard-1)
# Zepto device-team shards back into the FULL pincode universe and replay the
# normal pipeline via macpro_zepto_ingest.sh (ZEPTO_TEAM_BYPASS=1 so the
# team-stash hook does not re-intercept the merged full drop).
#
# Idempotent + quiet: exits 0 while shards are still missing (fired
# opportunistically by the ingest stash hook, the laptop .cmd, and the watch).
set -uo pipefail
DIR=/opt/ecom-intel
cd "$DIR" || exit 0
. tools/laptop/lib.sh
RUN_ID="${1:?usage: zepto_team_merge.sh <run_id>}"
RUN="shards/runs/$RUN_ID/zepto"
LOG(){ echo "[$(date '+%F %T')] zepto_team_merge($RUN_ID): $*"; }

[ -d "$RUN" ] || { LOG "no such run dir"; exit 1; }
exec 9>"logs/.zepto-team-merge.lock"
flock -w 120 9 || { LOG "merge lock busy"; exit 0; }
[ -f "$RUN/.ingested" ] && { LOG "already ingested"; exit 0; }

M0="$RUN/shard-0-of-2/manifest.0-of-2.json"
R0="$RUN/shard-0-of-2/result.json"
M1="$RUN/shard-1-of-2/manifest.1-of-2.json"
R1="$RUN/shard-1-of-2/result.json"
for f in "$M0" "$M1"; do
  [ -s "$f" ] || { LOG "manifest missing: $f"; exit 1; }
done
missing=""
[ -s "$R0" ] || missing="$missing shard-0(mac)"
[ -s "$R1" ] || missing="$missing shard-1(laptop)"
if [ -n "$missing" ]; then
  LOG "waiting for:$missing"
  exit 0
fi

MERGED="$RUN/merged-result.json"
LOG "merging shard-0 (Mac) + shard-1 (laptop) -> $MERGED"
if ! python3 tools/shards/merge_platform_shards.py zepto "$MERGED" \
    "$M0" "$R0" "$M1" "$R1" >> "$RUN/merge.log" 2>&1; then
  LOG "merge FAILED (see $RUN/merge.log)"
  team_tg "❌ Zepto team merge failed for $RUN_ID — shards did not reassemble the full universe. Guard rescue will handle."
  exit 1
fi

if [ "${TEAM_MERGE_NO_INGEST:-0}" = "1" ]; then
  LOG "TEAM_MERGE_NO_INGEST=1 — stopping after merge (test mode)"
  exit 0
fi

TODAY="$(date +%F)"
REPORT="output/Jivo-Zepto-Live-Report-${TODAY}.xlsx"
LOG "ingesting merged team result through the normal run.sh drop pipeline"
rc=0
ZEPTO_TEAM_BYPASS=1 tools/cron/macpro_zepto_ingest.sh "$DIR/$MERGED" \
  >> logs/zepto-team-ingest.log 2>&1 || rc=$?
if [ -f "$REPORT" ]; then
  touch "$RUN/.ingested"
  clear_active zepto "$RUN_ID"
  counts="$(python3 -c 'import json,sys;s=json.load(open(sys.argv[1])).get("summary") or {};print(f"{s.get(\"pincodes_total\")} pins, {s.get(\"total_rows\")} rows, {s.get(\"pincodes_with_jivo\")} with Jivo")' "$MERGED" 2>/dev/null || echo "?")"
  LOG "SUCCESS — report built from Mac+laptop team run ($counts)"
  team_tg "✅ Zepto ${TODAY} report built from the Mac+laptop device-team run ($counts)."
else
  clear_active zepto "$RUN_ID"
  LOG "ingest did not produce the report (rc=$rc) — held/refused by normal gates; pointer cleared so the guard takes over"
  team_tg "⚠️ Zepto team run $RUN_ID: merged result held/refused by ingest gates (rc=$rc). Guard owns recovery now."
fi
exit 0
