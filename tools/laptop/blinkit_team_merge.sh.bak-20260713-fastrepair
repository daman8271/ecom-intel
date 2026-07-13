#!/usr/bin/env bash
# blinkit_team_merge.sh <run_id> — merge the Mac (shard-0) + laptop (shard-1)
# Blinkit device-team shards back into the FULL pincode universe and push the
# merged result through the normal ingest gates (identical to the proven
# merge_and_ingest step of blinkit_vps_kvm_fallback.sh).
#
# Idempotent + quiet: exits 0 while shards are still missing (callers fire it
# opportunistically — the Mac wrapper, the laptop .cmd, and the watch cron).
set -uo pipefail
DIR=/opt/ecom-intel
cd "$DIR" || exit 0
. tools/laptop/lib.sh
RUN_ID="${1:?usage: blinkit_team_merge.sh <run_id>}"
RUN="shards/runs/$RUN_ID/blinkit"
LOG(){ echo "[$(date '+%F %T')] blinkit_team_merge($RUN_ID): $*"; }

[ -d "$RUN" ] || { LOG "no such run dir"; exit 1; }
exec 9>"logs/.blinkit-team-merge.lock"
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
if ! python3 tools/shards/merge_platform_shards.py blinkit "$MERGED" \
    "$M0" "$R0" "$M1" "$R1" >> "$RUN/merge.log" 2>&1; then
  LOG "merge FAILED (see $RUN/merge.log)"
  team_tg "❌ Blinkit team merge failed for $RUN_ID — shards did not reassemble the full universe. Watch/guard will rescue."
  exit 1
fi

if [ "${TEAM_MERGE_NO_INGEST:-0}" = "1" ]; then
  LOG "TEAM_MERGE_NO_INGEST=1 — stopping after merge (test mode)"
  exit 0
fi

TODAY="$(date +%F)"
REPORT="output/Jivo-Blinkit-Live-Report-${TODAY}.xlsx"
LOG "ingesting merged team result through normal Blinkit gates (--deliver)"
rc=0
BLINKIT_REQUIRE_AUTH_DROP=1 platforms/blinkit/ingest.sh "$MERGED" --deliver \
  >> logs/blinkit-team-ingest.log 2>&1 || rc=$?
if [ -f "$REPORT" ]; then
  touch "$RUN/.ingested"
  clear_active blinkit "$RUN_ID"
  counts="$(python3 -c 'import json,sys;s=json.load(open(sys.argv[1])).get("summary") or {};print(f"{s.get(\"pincodes_total\")} pins, {s.get(\"total_rows\")} rows, {s.get(\"pincodes_with_jivo\")} with Jivo")' "$MERGED" 2>/dev/null || echo "?")"
  LOG "SUCCESS — report built from Mac+laptop team run ($counts)"
  team_tg "✅ Blinkit ${TODAY} report built from the Mac+laptop device-team run ($counts)."
else
  clear_active blinkit "$RUN_ID"
  LOG "ingest did not produce the report (rc=$rc) — merged drop held/refused by normal gates; pointer cleared so guards take over"
  team_tg "⚠️ Blinkit team run $RUN_ID: merged result was held/refused by ingest gates (rc=$rc). Guards own recovery now."
fi
exit 0
