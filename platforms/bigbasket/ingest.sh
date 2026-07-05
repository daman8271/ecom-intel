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

python3 - "$STAGED" "$SHAPE" "$PDIR" <<'PY'
import json, sys, os, math
d = json.load(open(sys.argv[1]))
shape = sys.argv[2]
pdir = sys.argv[3]
s = d.get("summary") or {}
rows = d.get("allRows") or []
if shape == "national":
    if not s.get("session_ok") or len(rows) == 0:
        raise SystemExit(
            f"Refusing failed BigBasket browser drop: session_ok={s.get('session_ok')} rows={len(rows)}"
        )
else:
    # BUG#2 PERMANENT GUARD (2026-07-04, goal #61): a partial/collapsed pincode pull
    # (e.g. the 2026-07-03 Bengaluru-only 1-pin drop) must NEVER silently overwrite the
    # good report. The floor is anchored to LAST-GOOD (which the VPS controls) so it holds
    # even if the drop lies about — or omits — its own `min_pincodes_required`.
    new_pins = int(s.get("pincodes_total") or 0)
    declared_min = int(s.get("min_pincodes_required") or 0)
    lg_pins = 0
    lgf = os.path.join(pdir, "result.last-good.json")
    if os.path.exists(lgf):
        try:
            lg_pins = int((json.load(open(lgf)).get("summary") or {}).get("pincodes_total") or 0)
        except Exception:
            lg_pins = 0
    anchored = math.ceil(0.75 * lg_pins) if lg_pins else 0
    required = max(declared_min, anchored, 20)   # absolute floor 20, else 75%-of-last-good, else the drop's own min
    if new_pins < required:
        raise SystemExit(
            f"Refusing under-covered BigBasket pincode drop: {new_pins} pincodes "
            f"< required {required} (declared_min={declared_min}, 75%-of-last-good={anchored}, "
            f"last-good={lg_pins}, target={s.get('pincodes_target', '?')}). "
            f"Keeping last-good — investigate the Mac scrape."
        )
PY

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
  "$ROOT/tools/cron/spool_into_batch.sh" bigbasket "BigBasket" "$ROOT/output/$(basename "$XLSX")" || true
fi
