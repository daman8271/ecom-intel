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
  BLINKIT_MAX_UNVERIFIED_OOS=0
  BLINKIT_MAX_MISSING_PRID_RATIO=0
  BLINKIT_MAX_MISSING_LISTING_URL_RATIO=0
  BLINKIT_MAX_BAD_LISTING_URL_RATIO=0
  BLINKIT_MAX_BAD_PRICE_ROWS=0
  BLINKIT_MAX_BAD_CONFIG_COORDS=0
)

env "${env_common[@]}" "$ROOT/platforms/blinkit/ingest.sh" "$FIXTURE" >/tmp/blinkit-ingest-good.out

bad="$(mktemp)"
trap 'rm -f "$bad"' EXIT
python3 - "$FIXTURE" "$bad" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
d["allRows"][0]["per_litre"] = 375.2
d["perPin"][0]["rows"][0]["per_litre"] = 375.2
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"))
PY

if env "${env_common[@]}" "$ROOT/platforms/blinkit/ingest.sh" "$bad" >/tmp/blinkit-ingest-bad.out 2>&1; then
  echo "expected bad price fixture to fail" >&2
  exit 1
fi
grep -q "Refusing Blinkit bad price math" /tmp/blinkit-ingest-bad.out

echo "PASS blinkit false-OOS effective-price ingest regression"
