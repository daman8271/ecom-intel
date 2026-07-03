#!/usr/bin/env bash
# BigBasket — VPS dead-drop ingest.
#
# The scraper should run on the Mac Pro/residential IP and drop one JSON file
# here. This script is the VPS side: it accepts either the current national
# result.json shape or the pincode-wise result_pincode.json shape, builds the
# matching workbook, and optionally copies it to output/ for delivery.
#
#   Usage: ingest.sh /path/to/bigbasket-result.json [--deliver]
set -euo pipefail

ROOT=/opt/ecom-intel
PDIR="$ROOT/platforms/bigbasket"
DROP_DIR="$PDIR/mac-drops"
SCAN="${1:?usage: ingest.sh <bigbasket-json> [--deliver]}"
DELIVER="${2:-}"

[ -f "$SCAN" ] || { echo "[bb-ingest] no such file: $SCAN" >&2; exit 1; }
mkdir -p "$DROP_DIR"

STAMP=$(date +%Y%m%dT%H%M%S)
STAGED="$DROP_DIR/bigbasket-${STAMP}.json"
cp "$SCAN" "$STAGED"

SHAPE="$(python3 - "$STAGED" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
s = d.get("summary") or {}
per = d.get("perPin") or []
rows = d.get("allRows") or []
real_pins = {str(p.get("pincode")) for p in per if p.get("pincode") not in (None, "-")}
real_pins.update(str(r.get("pincode")) for r in rows if r.get("pincode") not in (None, "-"))
if int(s.get("pincodes_total") or 0) > 1 or len(real_pins) > 1:
    print("pincode")
else:
    print("national")
PY
)"

cd "$PDIR"
if [ "$SHAPE" = "pincode" ]; then
  cp "$STAGED" "$PDIR/result_pincode.json"
  python3 build_excel_pincode.py
  XLSX=$(ls -t "$PDIR"/Jivo-BigBasket-Pincode-Report-*.xlsx 2>/dev/null | head -1)
  cp "$PDIR/result_pincode.json" "$PDIR/result.last-good.json"
else
  cp "$STAGED" "$PDIR/result.json"
  python3 build_excel.py
  XLSX=$(ls -t "$PDIR"/Jivo-Bigbasket-Live-Report-*.xlsx 2>/dev/null | head -1)
  [ -n "$XLSX" ] || { echo "[bb-ingest] build_excel produced no report" >&2; exit 1; }
  python3 "$ROOT/tools/predict.py"          bigbasket "$XLSX" || echo "[bb-ingest] predict skipped"
  python3 "$ROOT/tools/report_dashboard.py" bigbasket "$XLSX" || echo "[bb-ingest] dashboard skipped"
fi

[ -n "${XLSX:-}" ] || { echo "[bb-ingest] no workbook produced" >&2; exit 1; }
echo "[bb-ingest] built $(basename "$XLSX") from $SHAPE drop"

if [ "$DELIVER" = "--deliver" ]; then
  cp "$XLSX" "$ROOT/output/$(basename "$XLSX")"
  echo "[bb-ingest] delivered -> output/$(basename "$XLSX")"
fi
