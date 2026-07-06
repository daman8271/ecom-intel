#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DATE="2099-01-01"
FIXTURE="$ROOT/platforms/blinkit/tests/fixtures/false_oos_price_mismatch.json"
BAD_RESULT="$(mktemp)"
OUT="$(mktemp)"
BLINKIT_FILE="$ROOT/output/Jivo-Blinkit-Live-Report-${DATE}.xlsx"
ZEPTO_FILE="$ROOT/output/Jivo-Zepto-Live-Report-${DATE}.xlsx"

cleanup() {
  rm -f "$BAD_RESULT" "$OUT" "$BLINKIT_FILE" "$ZEPTO_FILE"
  rm -f "$ROOT/logs/blinkit_quality_monitor-${DATE}.log" "$ROOT/logs/blinkit_quality_monitor-${DATE}.state"
}
trap cleanup EXIT

python3 - "$FIXTURE" "$BAD_RESULT" <<'PY'
import json, sys
src, out = sys.argv[1:]
d = json.load(open(src, encoding="utf-8"))
d["summary"]["captured_at"] = "2099-01-01T04:00:00.000Z"
for row in [d["allRows"][0], d["perPin"][0]["rows"][0]]:
    row["sale"] = 1876
    row.pop("base_sale", None)
    row.pop("offer_sale", None)
    row["discount_pct"] = 62.5
    row["per_litre"] = 375.2
    row["price_source"] = "pdp"
json.dump(d, open(out, "w", encoding="utf-8"))
PY

mkdir -p "$ROOT/output"
printf 'dummy blinkit workbook\n' > "$BLINKIT_FILE"
printf 'dummy zepto workbook\n' > "$ZEPTO_FILE"

cd "$ROOT"
PRICE_MAIL_DATE="$DATE" \
MAILER_NO_REDIRECT=1 \
MAILER_TEST_MODE=1 \
MAILER_SKIP_WAIT=1 \
MAILER_LIST_ONLY=1 \
BLINKIT_MONITOR_RESULT="$BAD_RESULT" \
  tools/mailer/mail_price_data.sh test > "$OUT"

if grep -qx "output/Jivo-Blinkit-Live-Report-${DATE}.xlsx" "$OUT"; then
  echo "expected Blinkit to be held back from mailer list" >&2
  cat "$OUT" >&2
  exit 1
fi
grep -qx "output/Jivo-Zepto-Live-Report-${DATE}.xlsx" "$OUT"
grep -q "Blinkit quality gate failed" "$OUT"

echo "PASS mailer Blinkit quality holdback regression"
