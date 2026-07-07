#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PINS="$TMP/pincodes.json"
PROGRESS="$TMP/progress.json"
OUT="$TMP/result.json"
STDOUT="$TMP/stdout.log"
STDERR="$TMP/stderr.log"

python3 - "$PINS" "$PROGRESS" <<'PY'
import json
import sys

pins_path, progress_path = sys.argv[1:]
pins = [
    {"city": "Test", "pincode": f"900{i:03d}", "locality": f"Locality {i}", "lat": 28.6, "lon": 77.2}
    for i in range(1, 21)
]
progress = {}
for pin in pins:
    row = {
        "city": pin["city"],
        "pincode": pin["pincode"],
        "locality": pin["locality"],
        "store_id": "sim",
        "store_name": "sim-store",
        "sku_raw": "Jivo Sim Oil",
        "canonical": "jivo-sim-oil-1l",
        "pack": "1 l",
        "vol_ml": 1000,
        "sale": 199,
        "mrp": 250,
        "discount_pct": 20,
        "per_litre": 199,
        "eta_min": 10,
        "in_stock": 1,
    }
    progress[pin["pincode"]] = {
        **pin,
        "store_id": "sim",
        "store_name": "sim-store",
        "resolved": True,
        "blocked": None,
        "auth_accepted": 0,
        "rows": [row],
    }
json.dump(pins, open(pins_path, "w", encoding="utf-8"))
json.dump(progress, open(progress_path, "w", encoding="utf-8"))
PY

START_MS="$(python3 - <<'PY'
import time
print(int(time.monotonic() * 1000))
PY
)"
BLINKIT_REQUIRE_AUTH=0 \
BLINKIT_SIM=1 \
PINCODES_FILE="$PINS" \
BLINKIT_PROGRESS_FILE="$PROGRESS" \
OUT_FILE="$OUT" \
CONCURRENCY=2 \
  node "$ROOT/platforms/blinkit/scrape.js" > "$STDOUT" 2> "$STDERR"
END_MS="$(python3 - <<'PY'
import time
print(int(time.monotonic() * 1000))
PY
)"
ELAPSED=$((END_MS - START_MS))

python3 - "$OUT" <<'PY'
import json
import sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d["summary"]["pincodes_total"] == 20, d["summary"]
assert len(d["perPin"]) == 20, len(d["perPin"])
assert len({p["pincode"] for p in d["perPin"]}) == 20
assert d["summary"]["total_rows"] == 20, d["summary"]
PY

grep -q "\[resume\] 20 pincodes already done" "$STDERR"
if [ "$ELAPSED" -gt 5000 ]; then
  echo "checkpoint resume took ${ELAPSED}ms; expected fast skip under 5000ms" >&2
  cat "$STDERR" >&2
  exit 1
fi

echo "PASS blinkit checkpoint resume fast (${ELAPSED}ms)"
