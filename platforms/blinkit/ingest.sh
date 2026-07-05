#!/usr/bin/env bash
# Blinkit — VPS dead-drop ingest.
#
# The scraper runs on the Mac Pro/residential IP and drops one result JSON here.
# This script validates the drop, promotes it into the live Blinkit folder, builds
# the workbook, runs the usual enrichers, and optionally copies the workbook to
# output/ for delivery.
#
#   Usage: ingest.sh /path/to/blinkit-result.json [--deliver]
set -euo pipefail

ROOT=/opt/ecom-intel
PDIR="$ROOT/platforms/blinkit"
DROP_DIR="$PDIR/mac-drops"
SCAN="${1:?usage: ingest.sh <blinkit-json> [--deliver]}"
DELIVER="${2:-}"

[ -f "$SCAN" ] || { echo "[blinkit-ingest] no such file: $SCAN" >&2; exit 1; }
mkdir -p "$DROP_DIR"

STAMP="$(date +%Y%m%dT%H%M%S)"
RUN_ID="mac-${STAMP}"
STAGED="$DROP_DIR/blinkit-${STAMP}.json"
BLINKIT_VALIDATE_ONLY="${BLINKIT_VALIDATE_ONLY:-0}"
if [ "$BLINKIT_VALIDATE_ONLY" = "1" ]; then
  STAGED="$SCAN"   # validate in place, no staging/build/delivery, no ledger write
else
  cp "$SCAN" "$STAGED"
fi

BLINKIT_EXPECTED_CONFIG="${BLINKIT_EXPECTED_CONFIG:-$PDIR/pincodes.daily.json}"
BLINKIT_BASELINE_RESULT="${BLINKIT_BASELINE_RESULT:-$PDIR/result.last-good.json}"
BLINKIT_MIN_PINCODES="${BLINKIT_MIN_PINCODES:-}"
BLINKIT_MIN_WITH_JIVO="${BLINKIT_MIN_WITH_JIVO:-431}"
BLINKIT_MIN_RESOLVED="${BLINKIT_MIN_RESOLVED:-857}"
BLINKIT_MAX_UNRESOLVED="${BLINKIT_MAX_UNRESOLVED:-45}"
BLINKIT_MIN_ROWS="${BLINKIT_MIN_ROWS:-1775}"
BLINKIT_MIN_SKUS="${BLINKIT_MIN_SKUS:-8}"
BLINKIT_MIN_STORES="${BLINKIT_MIN_STORES:-270}"            # static fallback when the ledger is thin (<3 accepted runs)
BLINKIT_MIN_STORES_OVERRIDE="${BLINKIT_MIN_STORES_OVERRIDE:-}"  # one-time adjudication override of the store floor
BLINKIT_MIN_STORES_ABS="${BLINKIT_MIN_STORES_ABS:-250}"     # absolute floor under the adaptive median
BLINKIT_MIN_PERPIN_STORES="${BLINKIT_MIN_PERPIN_STORES:-455}"   # 90% of the 502-507 resolved-universe baseline
BLINKIT_MIN_ETA_PCT="${BLINKIT_MIN_ETA_PCT:-90}"            # rows with numeric eta_min (healthy runs: ~98%)
BLINKIT_MAX_FLIP_PCT="${BLINKIT_MAX_FLIP_PCT:-10}"          # same-pin store flips vs last-good (baseline <=2%)
BLINKIT_MAX_WALL_S="${BLINKIT_MAX_WALL_S:-2500}"            # healthy runs ~700s; the degraded 2026-07-05 run took 5218s
BLINKIT_STORE_LEDGER="${BLINKIT_STORE_LEDGER:-$ROOT/data/blinkit/store_counts.csv}"
BLINKIT_MAX_BLOCKED="${BLINKIT_MAX_BLOCKED:-0}"
export BLINKIT_EXPECTED_CONFIG BLINKIT_BASELINE_RESULT BLINKIT_MIN_PINCODES
export BLINKIT_MIN_WITH_JIVO BLINKIT_MIN_RESOLVED BLINKIT_MAX_UNRESOLVED
export BLINKIT_MIN_ROWS BLINKIT_MIN_SKUS BLINKIT_MIN_STORES BLINKIT_MAX_BLOCKED
export BLINKIT_MIN_STORES_OVERRIDE BLINKIT_MIN_STORES_ABS BLINKIT_MIN_PERPIN_STORES
export BLINKIT_MIN_ETA_PCT BLINKIT_MAX_FLIP_PCT BLINKIT_MAX_WALL_S BLINKIT_STORE_LEDGER BLINKIT_VALIDATE_ONLY

python3 - "$STAGED" <<'PY'
import json
import os
import sys

path = sys.argv[1]
d = json.load(open(path, encoding="utf-8"))
s = d.get("summary") or {}
per = d.get("perPin") or []
rows = d.get("allRows") or []

def load_config_pins(path):
    data = json.load(open(path, encoding="utf-8"))
    pins = []
    cities = set()
    def walk(x):
        if isinstance(x, list):
            for item in x:
                walk(item)
        elif isinstance(x, dict):
            if "pincode" in x:
                pins.append(str(x.get("pincode")))
                city = str(x.get("city") or x.get("cityName") or "").strip()
                if city:
                    cities.add(city)
            for key, value in x.items():
                if key != "pincode":
                    walk(value)
    walk(data)
    return set(pins), cities

def as_int(name, default=0):
    try:
        return int(s.get(name) or default)
    except Exception:
        return default

cfg_pins, cfg_cities = load_config_pins(os.environ["BLINKIT_EXPECTED_CONFIG"])
baseline_cities = set()
baseline_path = os.environ.get("BLINKIT_BASELINE_RESULT") or ""
if baseline_path and os.path.isfile(baseline_path):
    try:
        b = json.load(open(baseline_path, encoding="utf-8"))
        baseline_cities = {
            str(p.get("city") or "").strip()
            for p in (b.get("perPin") or [])
            if p.get("city")
        }
    except Exception:
        baseline_cities = set()

min_pincodes = os.environ.get("BLINKIT_MIN_PINCODES")
if min_pincodes:
    min_pincodes = int(min_pincodes)
else:
    min_pincodes = len(cfg_pins)

mins = {
    "pincodes_total": min_pincodes,
    "pincodes_with_jivo": int(os.environ.get("BLINKIT_MIN_WITH_JIVO", "100")),
    "pincodes_resolved": int(os.environ.get("BLINKIT_MIN_RESOLVED", "857")),
    "total_rows": int(os.environ.get("BLINKIT_MIN_ROWS", "500")),
    "unique_skus": int(os.environ.get("BLINKIT_MIN_SKUS", "8")),
}

# ---- adaptive store floor (2026-07-05, goal #66) ---------------------------
# floor = max(ABS, ceil(0.90 * median store count of the last <=7 ACCEPTED runs));
# 80%-of-median would have passed the degraded 258-store run, 90% would not.
# Falls back to static BLINKIT_MIN_STORES while the ledger has <3 accepted rows.
# One-time adjudications go through BLINKIT_MIN_STORES_OVERRIDE, never by editing this.
import csv, math, statistics
ledger_path = os.environ.get("BLINKIT_STORE_LEDGER") or ""
def store_floor_and_mode():
    ov = os.environ.get("BLINKIT_MIN_STORES_OVERRIDE")
    if ov:
        return int(ov), "override"
    hist = []
    if ledger_path and os.path.isfile(ledger_path):
        with open(ledger_path, newline="", encoding="utf-8") as f:
            for r in csv.DictReader(f):
                if r.get("accepted") == "1" and r.get("allrows_stores"):
                    hist.append((r["run_date"], int(r["allrows_stores"])))
    hist = [n for _, n in sorted(hist)[-7:]]
    if len(hist) >= 3:
        med = statistics.median(hist)
        return max(int(os.environ.get("BLINKIT_MIN_STORES_ABS", "250")), math.ceil(0.90 * med)), f"adaptive(median={med})"
    return int(os.environ.get("BLINKIT_MIN_STORES", "270")), "static"
store_floor, floor_mode = store_floor_and_mode()
max_unresolved = int(os.environ.get("BLINKIT_MAX_UNRESOLVED", "45"))
blocked_max = int(os.environ.get("BLINKIT_MAX_BLOCKED", "0"))

partial = bool(d.get("partial") or s.get("partial"))
blocked = as_int("pincodes_blocked")
summary_total = as_int("pincodes_total")
summary_rows = as_int("total_rows")
with_jivo = as_int("pincodes_with_jivo")
resolved = as_int("pincodes_resolved")
unresolved = as_int("pincodes_unresolved")
unique_skus = as_int("unique_skus")
per_pins = {str(p.get("pincode")) for p in per if p.get("pincode") is not None}
per_cities = {str(p.get("city") or "").strip() for p in per if p.get("city")}
bad_perpin_blocks = [p.get("pincode") for p in per if p.get("blocked") or p.get("partial_block")]
store_ids = {str(r.get("store_id") or "").strip() for r in rows if r.get("store_id")}

if partial:
    raise SystemExit("Refusing partial Blinkit drop: partial=true")
if blocked > blocked_max:
    raise SystemExit(f"Refusing blocked Blinkit drop: pincodes_blocked={blocked} max={blocked_max}")
if bad_perpin_blocks:
    raise SystemExit(f"Refusing blocked Blinkit drop: perPin blocked={bad_perpin_blocks[:10]}")
if not isinstance(per, list) or not isinstance(rows, list):
    raise SystemExit("Refusing malformed Blinkit drop: perPin/allRows must be arrays")
if summary_total != len(cfg_pins):
    raise SystemExit(f"Refusing wrong Blinkit config: summary_total={summary_total} expected={len(cfg_pins)}")
if per_pins != cfg_pins:
    missing = sorted(cfg_pins - per_pins)[:10]
    extra = sorted(per_pins - cfg_pins)[:10]
    raise SystemExit(f"Refusing Blinkit pincode mismatch: missing={missing} extra={extra}")
if baseline_cities and not baseline_cities.issubset(per_cities):
    missing_cities = sorted(baseline_cities - per_cities)
    raise SystemExit(f"Refusing Blinkit city coverage loss: missing={missing_cities}")
if len(per) != summary_total:
    raise SystemExit(f"Refusing incomplete Blinkit drop: perPin={len(per)} summary_total={summary_total}")
if summary_total < mins["pincodes_total"]:
    raise SystemExit(f"Refusing under-covered Blinkit drop: pincodes_total={summary_total} min={mins['pincodes_total']}")
if resolved < mins["pincodes_resolved"]:
    raise SystemExit(f"Refusing low-resolution Blinkit drop: resolved={resolved} min={mins['pincodes_resolved']}")
if unresolved > max_unresolved:
    raise SystemExit(f"Refusing high-unresolved Blinkit drop: unresolved={unresolved} max={max_unresolved}")
if with_jivo < mins["pincodes_with_jivo"]:
    raise SystemExit(f"Refusing thin Blinkit drop: pincodes_with_jivo={with_jivo} min={mins['pincodes_with_jivo']}")
if len(rows) < mins["total_rows"] or summary_rows < mins["total_rows"]:
    raise SystemExit(f"Refusing low-row Blinkit drop: rows={len(rows)} summary_rows={summary_rows} min={mins['total_rows']}")
if unique_skus < mins["unique_skus"]:
    raise SystemExit(f"Refusing SKU-collapsed Blinkit drop: unique_skus={unique_skus} min={mins['unique_skus']}")
if len(store_ids) < store_floor:
    raise SystemExit(f"Refusing store-collapsed Blinkit drop: stores={len(store_ids)} min={store_floor} ({floor_mode})")

# ---- scrape-health guards (2026-07-05, goal #66) ----------------------------
# The 258-store run was a degraded scrape (7.4x wall time, eta extraction collapse,
# 23% same-pin store flips), NOT Blinkit consolidation. These catch that signature
# directly, independent of the store count.
perpin_stores = {str(p.get("store_id") or "").strip() for p in per if p.get("store_id")}
min_perpin = int(os.environ.get("BLINKIT_MIN_PERPIN_STORES", "455"))
if len(perpin_stores) < min_perpin:
    raise SystemExit(f"Refusing store-collapsed Blinkit drop: perPin universe stores={len(perpin_stores)} min={min_perpin}")

eta_ok = sum(1 for r in rows if isinstance(r.get("eta_min"), (int, float)))
eta_pct = 100.0 * eta_ok / len(rows) if rows else 0.0
min_eta_pct = float(os.environ.get("BLINKIT_MIN_ETA_PCT", "90"))
if eta_pct < min_eta_pct:
    raise SystemExit(f"Refusing degraded Blinkit drop: eta_min present on {eta_pct:.1f}% of rows, min {min_eta_pct:.0f}%")

wall_s = s.get("wall_s")
max_wall = int(os.environ.get("BLINKIT_MAX_WALL_S", "2500"))
if isinstance(wall_s, (int, float)) and wall_s > max_wall:
    raise SystemExit(f"Refusing slow/stressed Blinkit drop: wall_s={int(wall_s)} max={max_wall}")

if baseline_path and os.path.isfile(baseline_path):
    try:
        bper = json.load(open(baseline_path, encoding="utf-8")).get("perPin") or []
    except Exception:
        bper = []
    base_map = {str(p.get("pincode")): str(p.get("store_id")) for p in bper if p.get("pincode") is not None and p.get("store_id")}
    cur_map = {str(p.get("pincode")): str(p.get("store_id")) for p in per if p.get("pincode") is not None and p.get("store_id")}
    common = set(base_map) & set(cur_map)
    if len(common) >= 100:
        flips = sum(1 for p in common if base_map[p] != cur_map[p])
        flip_pct = 100.0 * flips / len(common)
        max_flip = float(os.environ.get("BLINKIT_MAX_FLIP_PCT", "10"))
        if flip_pct > max_flip:
            raise SystemExit(f"Refusing re-resolved Blinkit drop: {flips}/{len(common)} pins changed store vs last-good ({flip_pct:.1f}% > {max_flip:.0f}%)")

# ---- store-count ledger (feeds the adaptive floor; accepted runs only) ------
if os.environ.get("BLINKIT_VALIDATE_ONLY") != "1" and ledger_path:
    from datetime import date
    today = date.today().isoformat()
    existing = []
    if os.path.isfile(ledger_path):
        with open(ledger_path, newline="", encoding="utf-8") as f:
            existing = [r for r in csv.DictReader(f) if r.get("run_date") != today]
    existing.append({"run_date": today, "allrows_stores": str(len(store_ids)),
                     "perpin_stores": str(len(perpin_stores)), "accepted": "1"})
    with open(ledger_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["run_date", "allrows_stores", "perpin_stores", "accepted"])
        for r in sorted(existing, key=lambda r: r["run_date"]):
            w.writerow([r["run_date"], r.get("allrows_stores", ""), r.get("perpin_stores", ""), r.get("accepted", "")])

print(json.dumps({
    "ok": True,
    "pincodes_total": summary_total,
    "pincodes_with_jivo": with_jivo,
    "pincodes_resolved": resolved,
    "total_rows": summary_rows,
    "rows": len(rows),
    "cities": len(per_cities),
    "stores": len(store_ids),
}, sort_keys=True))
PY

if [ "$BLINKIT_VALIDATE_ONLY" = "1" ]; then
  echo "[blinkit-ingest] validate-only PASS: $SCAN"
  exit 0
fi

cd "$PDIR"
OLD_RESULT="$(mktemp "$DROP_DIR/previous-result.XXXXXX.json")"
if [ -f "$PDIR/result.json" ]; then
  cp "$PDIR/result.json" "$OLD_RESULT"
else
  : > "$OLD_RESULT"
fi

restore_old_result() {
  if [ -s "$OLD_RESULT" ]; then
    cp "$OLD_RESULT" "$PDIR/result.json"
  fi
}

cp "$STAGED" "$PDIR/result.json"
python3 build_excel.py
XLSX="$(ls -t "$PDIR"/Jivo-Blinkit-Live-Report-*.xlsx 2>/dev/null | head -1)"
[ -n "$XLSX" ] || { restore_old_result; echo "[blinkit-ingest] build_excel produced no report" >&2; exit 1; }

python3 "$ROOT/tools/predict.py" blinkit "$XLSX" || echo "[blinkit-ingest] predict skipped"
python3 "$ROOT/tools/pricematch/add_pricematch_sheet.py" blinkit "$XLSX" || echo "[blinkit-ingest] price-match skipped"
python3 "$ROOT/tools/availability/add_availability_sheet.py" blinkit "$XLSX" || echo "[blinkit-ingest] availability skipped"
python3 "$ROOT/tools/report_dashboard.py" blinkit "$XLSX" || echo "[blinkit-ingest] dashboard skipped"

python3 "$ROOT/tools/review.py" blinkit "$RUN_ID" || true
VERDICT="$(python3 - "$ROOT/reviews/blinkit-${RUN_ID}.json" <<'PY' 2>/dev/null || echo BROKEN
import json, sys
try:
    print((json.load(open(sys.argv[1], encoding="utf-8")).get("verdict") or "BROKEN").upper())
except Exception:
    print("BROKEN")
PY
)"
if [ "$VERDICT" != "OK" ]; then
  restore_old_result
  echo "[blinkit-ingest] refusing delivery: review verdict=$VERDICT" >&2
  exit 1
fi

cp "$PDIR/result.json" "$PDIR/result.last-good.json"
echo "[blinkit-ingest] built $(basename "$XLSX") from Mac drop; review=$VERDICT"

if [ "$DELIVER" = "--deliver" ]; then
  cp "$XLSX" "$ROOT/output/$(basename "$XLSX")"
  echo "[blinkit-ingest] delivered -> output/$(basename "$XLSX")"
  "$ROOT/tools/cron/spool_into_batch.sh" blinkit "Blinkit" "$ROOT/output/$(basename "$XLSX")" || true
fi
