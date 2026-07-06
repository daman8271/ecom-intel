#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE="$ROOT/platforms/blinkit/tests/fixtures/false_oos_price_mismatch.json"
MONITOR="$ROOT/tools/cron/blinkit_quality_monitor.sh"

GOOD="$(mktemp)"
BAD="$(mktemp)"
GOOD_OUT="$(mktemp)"
BAD_OUT="$(mktemp)"
trap 'rm -f "$GOOD" "$BAD" "$GOOD_OUT" "$BAD_OUT" "$ROOT/logs/blinkit_quality_monitor-2099-01-01.log" "$ROOT/logs/blinkit_quality_monitor-2099-01-01.state"' EXIT

python3 - "$FIXTURE" "$GOOD" "$BAD" <<'PY'
import json, sys
src, good_path, bad_path = sys.argv[1:]
good = json.load(open(src, encoding="utf-8"))
good["summary"]["captured_at"] = "2099-01-01T04:00:00.000Z"
json.dump(good, open(good_path, "w", encoding="utf-8"))

bad = json.loads(json.dumps(good))
for row in [bad["allRows"][0], bad["perPin"][0]["rows"][0]]:
    row["sale"] = 1876
    row.pop("base_sale", None)
    row.pop("offer_sale", None)
    row["discount_pct"] = 62.5
    row["per_litre"] = 375.2
    row["price_source"] = "pdp"
json.dump(bad, open(bad_path, "w", encoding="utf-8"))
PY

cd "$ROOT"

BLINKIT_MONITOR_DRYRUN=1 \
BLINKIT_MONITOR_DATE=2099-01-01 \
BLINKIT_MONITOR_RESULT="$GOOD" \
BLINKIT_MONITOR_REPORT=/tmp/no-such-blinkit-report.xlsx \
  "$MONITOR" test > "$GOOD_OUT"
grep -q '"ok": true' "$GOOD_OUT"
grep -q 'quality OK for 2099-01-01' "$GOOD_OUT"

BLINKIT_MONITOR_DRYRUN=1 \
BLINKIT_MONITOR_DATE=2099-01-01 \
BLINKIT_MONITOR_RESULT="$BAD" \
BLINKIT_MONITOR_REPORT=/tmp/no-such-blinkit-report.xlsx \
  "$MONITOR" test > "$BAD_OUT"
grep -q '"ok": false' "$BAD_OUT"
grep -q 'canary_110094_old_price' "$BAD_OUT"

echo "PASS blinkit quality monitor canary regression"
