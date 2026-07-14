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

# ---- PRE-VERIFY + PROACTIVE HEAL (2026-07-15 fleet fix) --------------------
# Before ingesting, count the rows the ingest gate would refuse as UNVERIFIED
# using the gate's OWN row predicates (copied verbatim from
# platforms/blinkit/ingest.sh — no thresholds re-implemented here). If a SMALL
# number of pincodes carry those rows (<= BLINKIT_TEAM_PREVERIFY_MAX), heal them
# FIRST via the targeted Mac rescrape, then ingest once clean — turning the old
# refuse -> repair -> re-ingest loop (~1h, e.g. the recurring
# Delhi:110040:jivo-pomace-olive-oil-5l stock_unverified refusals of 7/13+7/14)
# into a single verify -> heal -> ingest pass. The gate stays the final backstop:
# 0 unverified, too-many, or a non-row failure (wall_s, store floor, auth summary)
# all fall through to the normal ingest below, exactly as before.
PREVERIFY_PINS_FILE="$(mktemp)"
if python3 - "$MERGED" >"$PREVERIFY_PINS_FILE" 2>>"$RUN/merge.log" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
rows = d.get("allRows") or []
per = d.get("perPin") or []

def pin(v):
    return str(v or "").strip()

def truthy(v):
    if v is True:
        return True
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return v == 1
    return str(v).strip().lower() in {"1", "true", "yes", "y"}

# --- gate predicates, verbatim from platforms/blinkit/ingest.sh ---
def is_oos_row(row):
    value = row.get("in_stock")
    if value is False or value == 0:
        return True
    if str(value).strip().lower() in {"0", "false", "no"}:
        return True
    status = str(row.get("listing_status") or row.get("status") or row.get("availability") or "").lower()
    return "out_of_stock" in status or "out of stock" in status or status == "oos"

def is_stock_unverified_row(row):
    status = str(row.get("listing_status") or "").strip().lower()
    source = str(row.get("stock_source") or "").strip().lower()
    return bool(row.get("stock_unverified")) or status == "stock_unverified" or source.endswith("_unverified")

def pdp_verified_oos(row):
    return truthy(row.get("pdp_checked")) or str(row.get("stock_source") or "").strip().lower() == "pdp"

bad = set()
# per-pin auth failures (targeted repair rescrapes these too)
for rec in per:
    if isinstance(rec, dict) and pin(rec.get("pincode")) and not truthy(rec.get("auth_accepted")):
        bad.add(pin(rec.get("pincode")))
for row in rows:
    if not isinstance(row, dict):
        continue
    p = pin(row.get("pincode"))
    if not p:
        continue
    if is_stock_unverified_row(row):
        bad.add(p)
    elif is_oos_row(row) and not pdp_verified_oos(row):
        bad.add(p)
    if row.get("pdp_price_probe_failed"):
        bad.add(p)
for p in sorted(bad):
    print(p)
PY
then
  NPINS="$(grep -c . "$PREVERIFY_PINS_FILE" 2>/dev/null || echo 0)"
  PREVERIFY_MAX="${BLINKIT_TEAM_PREVERIFY_MAX:-25}"
  if [ "$NPINS" -gt 0 ] && [ "$NPINS" -le "$PREVERIFY_MAX" ]; then
    PINLIST="$(tr '\n' ' ' <"$PREVERIFY_PINS_FILE")"
    LOG "pre-verify: $NPINS repairable unverified pin(s) [$PINLIST] — healing via targeted repair BEFORE ingest"
    team_tg "🔧 Blinkit team $RUN_ID: $NPINS unverified pin(s) [$PINLIST] — pre-verify heal before ingest (avoids the refuse→repair loop)."
    BLINKIT_REPAIR_BASE_DROP="$DIR/$MERGED" BLINKIT_REPAIR_DATE="$TODAY" \
      tools/cron/blinkit_repair_held_mac_drop.sh >> logs/blinkit_team.log 2>&1 || true
    if [ -f "$REPORT" ]; then
      touch "$RUN/.ingested"
      clear_active blinkit "$RUN_ID"
      counts="$(python3 -c 'import json,sys;s=json.load(open(sys.argv[1])).get("summary") or {};print(f"{s.get(\"pincodes_total\")} pins, {s.get(\"total_rows\")} rows, {s.get(\"pincodes_with_jivo\")} with Jivo")' "$MERGED" 2>/dev/null || echo "?")"
      LOG "pre-verify SUCCESS — targeted repair healed $NPINS pin(s) and ingested in ONE pass ($counts)"
      team_tg "✅ Blinkit ${TODAY} report built in one pass (pre-verify healed $NPINS pin(s); $counts)."
      rm -f "$PREVERIFY_PINS_FILE"
      exit 0
    fi
    LOG "pre-verify heal did not produce the report — falling through to normal ingest (gate backstop owns recovery)"
  elif [ "$NPINS" -gt "$PREVERIFY_MAX" ]; then
    LOG "pre-verify: $NPINS unverified pin(s) exceeds max=$PREVERIFY_MAX — deferring to normal ingest + gate backstop"
  else
    LOG "pre-verify: 0 repairable unverified rows — proceeding to normal ingest"
  fi
else
  LOG "pre-verify check errored (see merge.log) — proceeding to normal ingest unchanged"
fi
rm -f "$PREVERIFY_PINS_FILE"

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
  # 2026-07-13 miss: refusal at 10:21 sat unnoticed until the agent-hook repair
  # pass at 10:50. Kick the targeted repair NOW; its own flock+stamp throttle
  # keeps this safe against the cron-driven passes.
  LOG "triggering targeted repair immediately (held drop → bad-pin rescrape)"
  nohup tools/cron/blinkit_repair_held_mac_drop.sh >> logs/blinkit_team.log 2>&1 </dev/null &
fi
exit 0
