#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Swiggy Instamart — VPS "dead-drop" ingest.
#
# The collector runs on a RESIDENTIAL IP (your Mac), produces a raw scan JSON
# (out/pincodes-jivo-*.json), and drops that ONE file onto the VPS (via git or
# scp). This script is the VPS side: it turns that scan file into the standard
# house report and (with --deliver) places it where the daily batch picks it up.
#
#   Usage:  ingest.sh /path/to/pincodes-jivo-*.json [--deliver]
#
# No live connection between machines is needed — Mac drops a file, VPS bakes it.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
ROOT=/opt/ecom-intel
COLL="$ROOT/collectors/swiggy-instamart"
PDIR="$ROOT/platforms/swiggy-instamart"
SCAN="${1:?usage: ingest.sh <scan-json> [--deliver]}"
DELIVER="${2:-}"
[ -f "$SCAN" ] || { echo "[ingest] no such file: $SCAN" >&2; exit 1; }

# 1) stage the drop where the adapter looks (newest pincodes-jivo-*.json in out/)
mkdir -p "$COLL/out"
STAMP=$(date +%Y%m%dT%H%M%S)
cp "$SCAN" "$COLL/out/pincodes-jivo-${STAMP}.json"

# 2) adapter: raw scan JSON -> house result.json
python3 "$COLL/collector/to_result_json.py"

# 3) house report (build_excel derives the name from the dir: Jivo-SwiggyInstamart-…)
cd "$PDIR"
python3 build_excel.py
XLSX=$(ls -t "$PDIR"/Jivo-SwiggyInstamart-Live-Report-*.xlsx 2>/dev/null | head -1)
[ -n "$XLSX" ] || { echo "[ingest] build_excel produced no report" >&2; exit 1; }

# 4) shared house sheets + informational price-match (best-effort, like run.sh)
python3 "$ROOT/tools/predict.py"          swiggy-instamart "$XLSX" || echo "[ingest] predict skipped"
python3 "$ROOT/tools/report_dashboard.py" swiggy-instamart "$XLSX" || echo "[ingest] dashboard skipped"
python3 "$COLL/collector/swiggy_pricematch_sheet.py" "$XLSX"       || echo "[ingest] pricematch skipped"

echo "[ingest] built $(basename "$XLSX")"

# 5) deliver into the pipeline pickup dir (only when asked)
if [ "$DELIVER" = "--deliver" ]; then
  cp "$XLSX" "$ROOT/output/$(basename "$XLSX")"
  echo "[ingest] delivered -> output/$(basename "$XLSX")"
fi
