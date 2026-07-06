#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE="$ROOT/platforms/blinkit/tests/fixtures/false_oos_price_mismatch.json"
CONFIG="$ROOT/platforms/blinkit/tests/fixtures/pincodes.one.json"

env_common=(
  BLINKIT_VALIDATE_ONLY=1
  BLINKIT_EXPECTED_CONFIG="$CONFIG"
  BLINKIT_BASELINE_RESULT="$ROOT/platforms/blinkit/tests/fixtures/no-baseline.json"
  BLINKIT_MIN_PINCODES=1
  BLINKIT_MIN_WITH_JIVO=1
  BLINKIT_MIN_RESOLVED=1
  BLINKIT_MIN_ROWS=1
  BLINKIT_MIN_SKUS=1
  BLINKIT_MIN_STORES_OVERRIDE=1
  BLINKIT_MIN_PERPIN_STORES=1
  BLINKIT_MAX_UNRESOLVED=0
  BLINKIT_MAX_BLOCKED=0
  BLINKIT_MAX_WALL_S=9999
  BLINKIT_REQUIRE_AUTH_DROP=1
  BLINKIT_REQUIRE_OOS_PROBE_ENABLED=1
  BLINKIT_REQUIRE_PDP_OOS_PROBE_ENABLED=1
  BLINKIT_REQUIRE_PDP_PRICE_PROBE_ENABLED=1
  BLINKIT_MAX_UNVERIFIED_OOS=0
  BLINKIT_MAX_MISSING_PRID_RATIO=0
  BLINKIT_MAX_MISSING_LISTING_URL_RATIO=0
  BLINKIT_MAX_BAD_LISTING_URL_RATIO=0
  BLINKIT_MAX_BAD_PRICE_ROWS=0
  BLINKIT_MAX_BAD_CONFIG_COORDS=0
)

env "${env_common[@]}" "$ROOT/platforms/blinkit/ingest.sh" "$FIXTURE" >/tmp/blinkit-ingest-good.out

bad="$(mktemp)"
bad_pomace_stale="$(mktemp)"
bad_canola_stale="$(mktemp)"
bad_missing_price_probe="$(mktemp)"
trap 'rm -f "$bad" "$bad_pomace_stale" "$bad_canola_stale" "$bad_missing_price_probe"' EXIT
python3 - "$FIXTURE" "$bad" "$bad_pomace_stale" "$bad_canola_stale" "$bad_missing_price_probe" <<'PY'
import json, sys
src, bad_path, bad_pomace_path, bad_canola_path, bad_missing_price_probe_path = sys.argv[1:]
d = json.load(open(src, encoding="utf-8"))
d["allRows"][0]["per_litre"] = 375.2
d["perPin"][0]["rows"][0]["per_litre"] = 375.2
json.dump(d, open(bad_path, "w", encoding="utf-8"))

missing_price_probe = json.load(open(src, encoding="utf-8"))
for key in ("pdp_price_probe_enabled", "pdp_price_probe_checked", "pdp_price_probe_updates"):
    missing_price_probe["summary"].pop(key, None)
json.dump(missing_price_probe, open(bad_missing_price_probe_path, "w", encoding="utf-8"))

pomace = json.load(open(src, encoding="utf-8"))
for row in [pomace["allRows"][0], pomace["perPin"][0]["rows"][0]]:
    row["sale"] = 1876
    row.pop("base_sale", None)
    row.pop("offer_sale", None)
    row["discount_pct"] = 62.5
    row["per_litre"] = 375.2
    row["price_source"] = "search_card"
    row["stock_source"] = "search_card"
    row["pdp_checked"] = 0
json.dump(pomace, open(bad_pomace_path, "w", encoding="utf-8"))

canola = json.load(open(src, encoding="utf-8"))
row = json.loads(json.dumps(canola["allRows"][0]))
row.update({
    "city": "Delhi",
    "pincode": "110012",
    "locality": "IARI SO",
    "sku_raw": "Jivo Cold Pressed Canola Oil",
    "canonical": "jivo-cold-pressed-canola-oil-5l",
    "pack": "5 l",
    "vol_ml": 5000,
    "sale": 1198,
    "base_sale": None,
    "offer_sale": None,
    "mrp": 1650,
    "discount_pct": 27.4,
    "per_litre": 239.6,
    "in_stock": 1,
    "listing_status": "listed_in_stock",
    "stock_source": "search_card",
    "price_source": "search_card",
    "search_sale": 1198,
    "pdp_checked": 0,
    "pdp_in_stock": None,
    "pdp_sale": None,
    "prid": "406593",
    "listing_url": "https://blinkit.com/prn/jivo-cold-pressed-canola-oil-5-l/prid/406593",
})
canola["allRows"].append(row)
json.dump(canola, open(bad_canola_path, "w", encoding="utf-8"))
PY

if env "${env_common[@]}" "$ROOT/platforms/blinkit/ingest.sh" "$bad" >/tmp/blinkit-ingest-bad.out 2>&1; then
  echo "expected bad price fixture to fail" >&2
  exit 1
fi
grep -q "Refusing Blinkit bad price math" /tmp/blinkit-ingest-bad.out

if env "${env_common[@]}" "$ROOT/platforms/blinkit/ingest.sh" "$bad_missing_price_probe" >/tmp/blinkit-ingest-missing-price-probe.out 2>&1; then
  echo "expected missing PDP price probe fixture to fail" >&2
  exit 1
fi
grep -q "Refusing unpriced Blinkit drop" /tmp/blinkit-ingest-missing-price-probe.out

if env "${env_common[@]}" "$ROOT/platforms/blinkit/ingest.sh" "$bad_pomace_stale" >/tmp/blinkit-ingest-pomace-stale.out 2>&1; then
  echo "expected stale Pomace canary fixture to fail" >&2
  exit 1
fi
grep -q "Refusing Blinkit screenshot-canary regression" /tmp/blinkit-ingest-pomace-stale.out
grep -q "Pomace 5L stale price" /tmp/blinkit-ingest-pomace-stale.out

if env "${env_common[@]}" "$ROOT/platforms/blinkit/ingest.sh" "$bad_canola_stale" >/tmp/blinkit-ingest-canola-stale.out 2>&1; then
  echo "expected stale Canola canary fixture to fail" >&2
  exit 1
fi
grep -q "Refusing Blinkit screenshot-canary regression" /tmp/blinkit-ingest-canola-stale.out
grep -q "Canola 5L stale price" /tmp/blinkit-ingest-canola-stale.out

echo "PASS blinkit false-OOS effective-price ingest regression"
