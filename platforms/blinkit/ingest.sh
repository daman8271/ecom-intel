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
BLINKIT_MAX_WALL_S="${BLINKIT_MAX_WALL_S:-4000}"            # accepted sharded run was 3383s; the degraded 2026-07-05 run took 5218s
BLINKIT_REQUIRE_AUTH_DROP="${BLINKIT_REQUIRE_AUTH_DROP:-1}"  # fail-closed after 2026-07-06 false-OOS incident
BLINKIT_STORE_LEDGER="${BLINKIT_STORE_LEDGER:-$ROOT/data/blinkit/store_counts.csv}"
BLINKIT_MAX_BLOCKED="${BLINKIT_MAX_BLOCKED:-0}"
BLINKIT_REQUIRE_OOS_PROBE_ENABLED="${BLINKIT_REQUIRE_OOS_PROBE_ENABLED:-1}"
BLINKIT_REQUIRE_PDP_OOS_PROBE_ENABLED="${BLINKIT_REQUIRE_PDP_OOS_PROBE_ENABLED:-1}"
BLINKIT_ALLOW_LEGACY_REPAIRED_OOS="${BLINKIT_ALLOW_LEGACY_REPAIRED_OOS:-1}"
BLINKIT_MAX_UNVERIFIED_OOS="${BLINKIT_MAX_UNVERIFIED_OOS:-0}"
BLINKIT_MAX_MISSING_PRID_RATIO="${BLINKIT_MAX_MISSING_PRID_RATIO:-0}"
BLINKIT_MAX_MISSING_LISTING_URL_RATIO="${BLINKIT_MAX_MISSING_LISTING_URL_RATIO:-0}"
BLINKIT_MAX_BAD_LISTING_URL_RATIO="${BLINKIT_MAX_BAD_LISTING_URL_RATIO:-0}"
BLINKIT_MAX_BAD_PRICE_ROWS="${BLINKIT_MAX_BAD_PRICE_ROWS:-0}"
BLINKIT_REQUIRE_SCREENSHOT_CANARIES="${BLINKIT_REQUIRE_SCREENSHOT_CANARIES:-1}"
BLINKIT_PRICE_MATH_PER_LITRE_EPS="${BLINKIT_PRICE_MATH_PER_LITRE_EPS:-0.05}"
BLINKIT_PRICE_MATH_DISCOUNT_EPS="${BLINKIT_PRICE_MATH_DISCOUNT_EPS:-0.2}"
BLINKIT_INDIA_BBOX="${BLINKIT_INDIA_BBOX:-6.0,68.0,38.5,98.5}"  # min_lat,min_lon,max_lat,max_lon
BLINKIT_REQUIRE_CONFIG_COORDS="${BLINKIT_REQUIRE_CONFIG_COORDS:-1}"
BLINKIT_CONFIG_COORD_ALLOWLIST="${BLINKIT_CONFIG_COORD_ALLOWLIST:-}" # fail closed on config coordinate outliers
BLINKIT_MAX_BAD_CONFIG_COORDS="${BLINKIT_MAX_BAD_CONFIG_COORDS:-0}"
export BLINKIT_EXPECTED_CONFIG BLINKIT_BASELINE_RESULT BLINKIT_MIN_PINCODES
export BLINKIT_MIN_WITH_JIVO BLINKIT_MIN_RESOLVED BLINKIT_MAX_UNRESOLVED
export BLINKIT_MIN_ROWS BLINKIT_MIN_SKUS BLINKIT_MIN_STORES BLINKIT_MAX_BLOCKED
export BLINKIT_MIN_STORES_OVERRIDE BLINKIT_MIN_STORES_ABS BLINKIT_MIN_PERPIN_STORES
export BLINKIT_MIN_ETA_PCT BLINKIT_MAX_FLIP_PCT BLINKIT_MAX_WALL_S BLINKIT_REQUIRE_AUTH_DROP BLINKIT_STORE_LEDGER BLINKIT_VALIDATE_ONLY
export BLINKIT_REQUIRE_OOS_PROBE_ENABLED BLINKIT_REQUIRE_PDP_OOS_PROBE_ENABLED BLINKIT_ALLOW_LEGACY_REPAIRED_OOS
export BLINKIT_MAX_UNVERIFIED_OOS BLINKIT_MAX_MISSING_PRID_RATIO BLINKIT_MAX_MISSING_LISTING_URL_RATIO BLINKIT_MAX_BAD_LISTING_URL_RATIO
export BLINKIT_MAX_BAD_PRICE_ROWS BLINKIT_REQUIRE_SCREENSHOT_CANARIES BLINKIT_PRICE_MATH_PER_LITRE_EPS BLINKIT_PRICE_MATH_DISCOUNT_EPS
export BLINKIT_INDIA_BBOX BLINKIT_REQUIRE_CONFIG_COORDS BLINKIT_CONFIG_COORD_ALLOWLIST BLINKIT_MAX_BAD_CONFIG_COORDS

python3 - "$STAGED" <<'PY'
import csv
import json
import math
import os
import statistics
import sys

path = sys.argv[1]
d = json.load(open(path, encoding="utf-8"))
s = d.get("summary") or {}
per = d.get("perPin") or []
rows = d.get("allRows") or []

def parse_int(value, default=0):
    try:
        if value is None or isinstance(value, bool):
            return default
        return int(value)
    except Exception:
        return default

def parse_float(value, default=None):
    try:
        if value is None or isinstance(value, bool):
            return default
        return float(value)
    except Exception:
        return default

def env_int(name, default):
    return parse_int(os.environ.get(name), int(default))

def env_float(name, default):
    return parse_float(os.environ.get(name), float(default))

def flag_is_one(value):
    if value is True:
        return True
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return value == 1
    return str(value).strip().lower() in {"1", "true", "yes", "y"}

def truthy(value):
    if value is True:
        return True
    if value is False or value is None:
        return False
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return value != 0
    return str(value).strip().lower() in {"1", "true", "yes", "y"}

def env_bool(name, default="0"):
    return truthy(os.environ.get(name, default))

def has_value(value):
    return value is not None and str(value).strip() != ""

def ratio(count, total):
    return float(count) / float(total) if total else 0.0

def js_round(value, digits):
    factor = 10 ** digits
    return math.floor((value * factor) + 0.5) / factor

def row_label(row):
    return ":".join(str(row.get(k) or "") for k in ("city", "pincode", "canonical"))

def load_config_pins(path):
    data = json.load(open(path, encoding="utf-8"))
    pins = []
    cities = set()
    coords = []
    def walk(x):
        if isinstance(x, list):
            for item in x:
                walk(item)
        elif isinstance(x, dict):
            if "pincode" in x:
                pincode = str(x.get("pincode"))
                pins.append(pincode)
                city = str(x.get("city") or x.get("cityName") or "").strip()
                if city:
                    cities.add(city)
                coords.append({
                    "pincode": pincode,
                    "city": city,
                    "lat": x.get("lat"),
                    "lon": x.get("lon"),
                })
            for key, value in x.items():
                if key != "pincode":
                    walk(value)
    walk(data)
    return set(pins), cities, coords

def as_int(name, default=0):
    return parse_int(s.get(name), default)

cfg_pins, cfg_cities, cfg_coords = load_config_pins(os.environ["BLINKIT_EXPECTED_CONFIG"])
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
    "pincodes_with_jivo": env_int("BLINKIT_MIN_WITH_JIVO", "100"),
    "pincodes_resolved": env_int("BLINKIT_MIN_RESOLVED", "857"),
    "total_rows": env_int("BLINKIT_MIN_ROWS", "500"),
    "unique_skus": env_int("BLINKIT_MIN_SKUS", "8"),
}

try:
    min_lat, min_lon, max_lat, max_lon = [float(x.strip()) for x in os.environ.get("BLINKIT_INDIA_BBOX", "").split(",")]
except Exception:
    raise SystemExit("Refusing invalid Blinkit gate config: BLINKIT_INDIA_BBOX must be min_lat,min_lon,max_lat,max_lon")
if min_lat >= max_lat or min_lon >= max_lon:
    raise SystemExit("Refusing invalid Blinkit gate config: BLINKIT_INDIA_BBOX min values must be below max values")

coord_allowlist = {
    p.strip() for p in os.environ.get("BLINKIT_CONFIG_COORD_ALLOWLIST", "").split(",")
    if p.strip()
}
bad_config_coords = []
for rec in cfg_coords:
    pincode = rec.get("pincode") or ""
    if pincode in coord_allowlist:
        continue
    lat = parse_float(rec.get("lat"))
    lon = parse_float(rec.get("lon"))
    reason = None
    if lat is None or lon is None:
        if env_bool("BLINKIT_REQUIRE_CONFIG_COORDS", "1"):
            reason = "missing"
    elif not (min_lat <= lat <= max_lat and min_lon <= lon <= max_lon):
        reason = f"{lat:.6g},{lon:.6g}"
    if reason:
        bad_config_coords.append(f"{rec.get('city') or ''}:{pincode}:{reason}")
max_bad_config_coords = env_int("BLINKIT_MAX_BAD_CONFIG_COORDS", "0")
if len(bad_config_coords) > max_bad_config_coords:
    raise SystemExit(
        "Refusing invalid Blinkit expected-config coordinates: "
        f"bad={len(bad_config_coords)} max={max_bad_config_coords} "
        f"bbox={min_lat},{min_lon},{max_lat},{max_lon} sample={bad_config_coords[:8]}"
    )

# ---- adaptive store floor (2026-07-05, goal #66) ---------------------------
# floor = max(ABS, ceil(0.90 * median store count of the last <=7 ACCEPTED runs));
# 80%-of-median would have passed the degraded 258-store run, 90% would not.
# Falls back to static BLINKIT_MIN_STORES while the ledger has <3 accepted rows.
# One-time adjudications go through BLINKIT_MIN_STORES_OVERRIDE, never by editing this.
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
        return max(env_int("BLINKIT_MIN_STORES_ABS", "250"), math.ceil(0.90 * med)), f"adaptive(median={med})"
    return env_int("BLINKIT_MIN_STORES", "270"), "static"
store_floor, floor_mode = store_floor_and_mode()
max_unresolved = env_int("BLINKIT_MAX_UNRESOLVED", "45")
blocked_max = env_int("BLINKIT_MAX_BLOCKED", "0")

partial = truthy(d.get("partial")) or truthy(s.get("partial"))
auth_session = flag_is_one(s.get("auth_session"))
blocked = as_int("pincodes_blocked")
summary_total = as_int("pincodes_total")
summary_rows = as_int("total_rows")
with_jivo = as_int("pincodes_with_jivo")
resolved = as_int("pincodes_resolved")
unresolved = as_int("pincodes_unresolved")
unique_skus = as_int("unique_skus")
per_pins = {str(p.get("pincode")) for p in per if p.get("pincode") is not None}
per_cities = {str(p.get("city") or "").strip() for p in per if p.get("city")}
bad_perpin_blocks = [p.get("pincode") for p in per if truthy(p.get("blocked")) or truthy(p.get("partial_block"))]
store_ids = {str(r.get("store_id") or "").strip() for r in rows if r.get("store_id")}

if partial:
    raise SystemExit("Refusing partial Blinkit drop: partial=true")
if os.environ.get("BLINKIT_REQUIRE_AUTH_DROP", "1") == "1" and not auth_session:
    raise SystemExit("Refusing unauthenticated Blinkit drop: summary.auth_session is not set")
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

# ---- OOS and row-integrity gates -------------------------------------------
def is_oos_row(row):
    value = row.get("in_stock")
    if value is False or value == 0:
        return True
    if str(value).strip().lower() in {"0", "false", "no"}:
        return True
    status = str(row.get("listing_status") or row.get("status") or row.get("availability") or "").lower()
    return "out_of_stock" in status or "out of stock" in status or status == "oos"

oos_rows = [r for r in rows if is_oos_row(r)]
legacy_repaired_oos = bool(d.get("oos_repair_merge")) or str(s.get("correction") or "") == "full_oos_same_pincode_probe"
allow_legacy_repaired_oos = env_bool("BLINKIT_ALLOW_LEGACY_REPAIRED_OOS", "1")
if oos_rows:
    if env_bool("BLINKIT_REQUIRE_OOS_PROBE_ENABLED", "1") and not flag_is_one(s.get("oos_probe_enabled")):
        raise SystemExit(
            f"Refusing unprobed Blinkit OOS drop: oos_rows={len(oos_rows)} summary.oos_probe_enabled={s.get('oos_probe_enabled')!r}"
        )
    if env_bool("BLINKIT_REQUIRE_PDP_OOS_PROBE_ENABLED", "1") and not flag_is_one(s.get("pdp_oos_probe_enabled")):
        if not (allow_legacy_repaired_oos and legacy_repaired_oos):
            raise SystemExit(
                f"Refusing unverified Blinkit OOS drop: oos_rows={len(oos_rows)} "
                f"summary.pdp_oos_probe_enabled={s.get('pdp_oos_probe_enabled')!r}"
            )

def pdp_verified_oos(row):
    return flag_is_one(row.get("pdp_checked")) or str(row.get("stock_source") or "").strip().lower() == "pdp"

calculated_unverified_oos = sum(1 for r in oos_rows if not pdp_verified_oos(r))
if allow_legacy_repaired_oos and legacy_repaired_oos and s.get("unverified_oos") is None:
    unverified_oos = 0
else:
    summary_unverified_oos = parse_int(s.get("unverified_oos"), calculated_unverified_oos)
    unverified_oos = max(summary_unverified_oos, calculated_unverified_oos)
max_unverified_oos = env_int("BLINKIT_MAX_UNVERIFIED_OOS", "0")
if unverified_oos > max_unverified_oos:
    raise SystemExit(
        f"Refusing excessive unverified Blinkit OOS: unverified_oos={unverified_oos} "
        f"calculated={calculated_unverified_oos} max={max_unverified_oos}"
    )

missing_prid = [r for r in rows if not has_value(r.get("prid"))]
missing_listing_url = [r for r in rows if not has_value(r.get("listing_url"))]
bad_listing_url = []
for r in rows:
    if not has_value(r.get("listing_url")):
        continue
    url = str(r.get("listing_url")).strip()
    prid = str(r.get("prid") or "").strip()
    if "/prid/" not in url or (prid and f"/prid/{prid}" not in url):
        bad_listing_url.append(r)

identity_gates = [
    ("missing PRID", len(missing_prid), env_float("BLINKIT_MAX_MISSING_PRID_RATIO", "0")),
    ("missing listing_url", len(missing_listing_url), env_float("BLINKIT_MAX_MISSING_LISTING_URL_RATIO", "0")),
    ("bad listing_url", len(bad_listing_url), env_float("BLINKIT_MAX_BAD_LISTING_URL_RATIO", "0")),
]
for label, count, max_ratio in identity_gates:
    actual = ratio(count, len(rows))
    if actual > max_ratio:
        raise SystemExit(
            f"Refusing Blinkit row identity regression: {label} rows={count}/{len(rows)} "
            f"ratio={actual:.4f} max={max_ratio:.4f}"
        )

per_litre_eps = env_float("BLINKIT_PRICE_MATH_PER_LITRE_EPS", "0.05")
discount_eps = env_float("BLINKIT_PRICE_MATH_DISCOUNT_EPS", "0.2")
bad_price_rows = []
for r in rows:
    sale = parse_float(r.get("sale"))
    mrp = parse_float(r.get("mrp"))
    vol_ml = parse_float(r.get("vol_ml"))
    per_litre = parse_float(r.get("per_litre"))
    discount_pct = parse_float(r.get("discount_pct"))
    reasons = []
    if sale is None or mrp is None or vol_ml is None or per_litre is None or discount_pct is None:
        reasons.append("missing numeric price field")
    else:
        if sale <= 0 or mrp <= 0 or vol_ml <= 0:
            reasons.append("non-positive price/volume")
        if sale > mrp:
            reasons.append(f"sale {sale:g} > mrp {mrp:g}")
        if sale > 0 and vol_ml > 0:
            expected_per_litre = js_round(sale / (vol_ml / 1000.0), 2)
            if abs(per_litre - expected_per_litre) > per_litre_eps:
                reasons.append(f"per_litre {per_litre:g} != {expected_per_litre:g}")
        if mrp > 0 and sale <= mrp:
            expected_discount = js_round(((mrp - sale) / mrp) * 100.0, 1)
            if abs(discount_pct - expected_discount) > discount_eps:
                reasons.append(f"discount_pct {discount_pct:g} != {expected_discount:g}")
    if reasons:
        bad_price_rows.append(f"{row_label(r)}:{'; '.join(reasons[:2])}")
max_bad_price_rows = env_int("BLINKIT_MAX_BAD_PRICE_ROWS", "0")
if len(bad_price_rows) > max_bad_price_rows:
    raise SystemExit(
        f"Refusing Blinkit bad price math: bad_rows={len(bad_price_rows)} "
        f"max={max_bad_price_rows} sample={bad_price_rows[:8]}"
    )

# ---- screenshot canaries: block known false-OOS / stale-price signatures --------
if env_bool("BLINKIT_REQUIRE_SCREENSHOT_CANARIES", "1"):
    def row_matches(row, pin, prid):
        return str(row.get("pincode")) == pin and str(row.get("prid")) == prid

    def verified_oos(row):
        return pdp_verified_oos(row) or str(row.get("stock_source") or "").strip().lower() == "pdp_probe"

    def price_evidence(row):
        return str(row.get("price_source") or "").strip().lower()

    def has_offer_or_pdp_evidence(row):
        src = price_evidence(row)
        return has_value(row.get("offer_sale")) or "offer" in src or "pdp" in src

    canary_failures = []

    pomace = [r for r in rows if row_matches(r, "110094", "407561")]
    for r in pomace:
        sale = parse_float(r.get("sale"))
        if is_oos_row(r) and sale == 1876 and not verified_oos(r):
            canary_failures.append(f"110094 Pomace 5L old false-OOS signature: {row_label(r)}")
        if not is_oos_row(r) and sale == 1876 and not has_offer_or_pdp_evidence(r):
            canary_failures.append(f"110094 Pomace 5L stale price without PDP/offer evidence: {row_label(r)}")

    canola_1l = [r for r in rows if row_matches(r, "110012", "407851")]
    for r in canola_1l:
        if is_oos_row(r) and not verified_oos(r):
            canary_failures.append(f"110012 Canola 1L unverified OOS signature: {row_label(r)}")

    canola_5l = [r for r in rows if row_matches(r, "110012", "406593")]
    for r in canola_5l:
        sale = parse_float(r.get("sale"))
        if is_oos_row(r) and not verified_oos(r):
            canary_failures.append(f"110012 Canola 5L unverified OOS signature: {row_label(r)}")
        if not is_oos_row(r) and sale == 1198 and not has_offer_or_pdp_evidence(r):
            canary_failures.append(f"110012 Canola 5L stale price without PDP/offer evidence: {row_label(r)}")

    if canary_failures:
        raise SystemExit(f"Refusing Blinkit screenshot-canary regression: sample={canary_failures[:5]}")

# ---- scrape-health guards (2026-07-05, goal #66) ----------------------------
# The 258-store run was a degraded scrape (7.4x wall time, eta extraction collapse,
# 23% same-pin store flips), NOT Blinkit consolidation. These catch that signature
# directly, independent of the store count.
perpin_stores = {str(p.get("store_id") or "").strip() for p in per if p.get("store_id")}
min_perpin = env_int("BLINKIT_MIN_PERPIN_STORES", "455")
if len(perpin_stores) < min_perpin:
    raise SystemExit(f"Refusing store-collapsed Blinkit drop: perPin universe stores={len(perpin_stores)} min={min_perpin}")

eta_ok = sum(1 for r in rows if isinstance(r.get("eta_min"), (int, float)))
eta_pct = 100.0 * eta_ok / len(rows) if rows else 0.0
min_eta_pct = env_float("BLINKIT_MIN_ETA_PCT", "90")
if eta_pct < min_eta_pct:
    raise SystemExit(f"Refusing degraded Blinkit drop: eta_min present on {eta_pct:.1f}% of rows, min {min_eta_pct:.0f}%")

wall_s = s.get("wall_s")
max_wall = env_int("BLINKIT_MAX_WALL_S", "4000")
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
        max_flip = env_float("BLINKIT_MAX_FLIP_PCT", "10")
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
    "oos_rows": len(oos_rows),
    "unverified_oos": unverified_oos,
    "bad_config_coords": len(bad_config_coords),
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
NOT_LISTED_XLSX="$PDIR/Jivo-Blinkit-Not-Listed-Pincodes-$(date +%F).xlsx"
[ -f "$NOT_LISTED_XLSX" ] || { restore_old_result; echo "[blinkit-ingest] build_excel produced no not-listed report: $NOT_LISTED_XLSX" >&2; exit 1; }

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
  cp "$NOT_LISTED_XLSX" "$ROOT/output/$(basename "$NOT_LISTED_XLSX")"
  echo "[blinkit-ingest] delivered -> output/$(basename "$NOT_LISTED_XLSX")"
  "$ROOT/tools/cron/spool_into_batch.sh" blinkit "Blinkit" "$ROOT/output/$(basename "$XLSX")" || true
fi
