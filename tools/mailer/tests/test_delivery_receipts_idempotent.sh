#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DATE="2099-02-02"
TMP="$(mktemp -d)"
OUT1="$TMP/first.out"
OUT2="$TMP/second.out"
CURL_LOG="$TMP/curl.log"
GOOD_RESULT="$TMP/result.json"
RECEIPT_DIR="$ROOT/logs/delivery-receipts/$DATE"

FILES=(
  "output/Jivo-Amazon-Live-Report-$DATE.xlsx"
  "output/Jivo-AmazonFresh-Live-Report-$DATE.xlsx"
  "output/Jivo-AmazonNow-Live-Report-$DATE.xlsx"
  "output/Jivo-Bigbasket-Live-Report-$DATE.xlsx"
  "output/Jivo-BigBasket-Pincode-Report-$DATE.xlsx"
  "output/Jivo-Blinkit-Live-Report-$DATE.xlsx"
  "output/Jivo-Blinkit-Not-Listed-Pincodes-$DATE.xlsx"
  "output/Jivo-Flipkart-Live-Report-$DATE.xlsx"
  "output/Jivo-FlipkartMinutes-Live-Report-$DATE.xlsx"
  "output/Jivo-Zepto-Live-Report-$DATE.xlsx"
  "output/Jivo-Price-Match-$DATE.xlsx"
  "output/Jivo-SwiggyInstamart-Live-Report-$DATE.xlsx"
)

cleanup() {
  for file in "${FILES[@]}"; do rm -f "$ROOT/$file"; done
  rm -rf "$RECEIPT_DIR" "$TMP"
  rm -f "$ROOT/logs/blinkit-main-wa-$DATE.sent"
  rm -f "$ROOT/logs/blinkit-not-listed-wa-$DATE.sent"
  rm -f "$ROOT/logs/bigbasket-pincode-wa-$DATE.sent"
  rm -f "$ROOT/logs/blinkit_quality_monitor-$DATE.log"
  rm -f "$ROOT/logs/blinkit_quality_monitor-$DATE.state"
  rm -f "$ROOT/logs/.mailer-am-$DATE.lock"
}
trap cleanup EXIT

mkdir -p "$ROOT/output" "$TMP/bin"
for file in "${FILES[@]}"; do printf 'fixture\n' > "$ROOT/$file"; done

python3 - "$ROOT/platforms/blinkit/tests/fixtures/false_oos_price_mismatch.json" "$GOOD_RESULT" \
  "$ROOT/output/Jivo-Blinkit-Live-Report-$DATE.xlsx" \
  "$ROOT/output/Jivo-Blinkit-Not-Listed-Pincodes-$DATE.xlsx" <<'PY'
import json, sys
from openpyxl import Workbook

fixture, result_path, main_path, not_listed_path = sys.argv[1:]
data = json.load(open(fixture, encoding="utf-8"))
data["summary"].update({
    "captured_at": "2099-02-02T04:00:00.000Z",
    "pdp_price_probe_enabled": 1,
    "pdp_price_probe_attempted": 1,
    "pdp_price_probe_checked": 1,
    "pdp_price_probe_failed": 0,
    "pdp_price_probe_updates": 0,
})
json.dump(data, open(result_path, "w", encoding="utf-8"))

wb = Workbook()
wb.active.title = "Master Data"
wb.active.append(["Product status", "Stock source", "Price source", "Base Sale Rs", "Offer Rs"])
wb.create_sheet("Listing Status").append(["City", "Pincode", "SKU", "Product status", "Source"])
wb.create_sheet("Not Listed Pincodes").append(["City", "Pincode", "SKU", "Source"])
wb.save(main_path)

nl = Workbook()
nl.active.title = "Not Listed Pincodes"
nl.active.append(["City", "Pincode", "SKU", "Source"])
nl.save(not_listed_path)
PY

cat > "$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"
case "$*" in
  *'/health'*) echo '{"connected":true}' ;;
  *'/send-media'*) echo '{"success":true,"messageId":"TEST-DOC-ID"}' ;;
  *'/send'*) echo '{"success":true,"messageId":"TEST-HEADER-ID"}' ;;
  *) echo '{"ok":true}' ;;
esac
SH
chmod +x "$TMP/bin/curl"

run_mailer() {
  PATH="$TMP/bin:$PATH" \
  CURL_LOG="$CURL_LOG" \
  PRICE_MAIL_DATE="$DATE" \
  MAILER_NO_REDIRECT=1 \
  MAILER_SKIP_WAIT=1 \
  MAILER_STABLE_AGE_S=0 \
  MAILER_SKIP_EMAIL=1 \
  BLINKIT_MONITOR_RESULT="$GOOD_RESULT" \
    "$ROOT/tools/mailer/mail_price_data.sh" am
}

# Prove a complete set cannot bypass the configured release barrier.
START_EPOCH="$(date +%s)"
PATH="$TMP/bin:$PATH" \
CURL_LOG="$CURL_LOG" \
PRICE_MAIL_DATE="$DATE" \
PRICE_MAIL_NOT_BEFORE_EPOCH="$((START_EPOCH + 2))" \
MAILER_NO_REDIRECT=1 \
MAILER_TEST_MODE=1 \
MAILER_STABLE_AGE_S=0 \
MAILER_LIST_ONLY=1 \
BLINKIT_MONITOR_RESULT="$GOOD_RESULT" \
  "$ROOT/tools/mailer/mail_price_data.sh" am > "$TMP/barrier.out"
[ $(( $(date +%s) - START_EPOCH )) -ge 2 ]

run_mailer > "$OUT1"
FIRST_MEDIA_COUNT="$(grep -c '/send-media' "$CURL_LOG")"
[ "$FIRST_MEDIA_COUNT" -eq 12 ]
[ "$(find "$RECEIPT_DIR" -maxdepth 1 -name '*.json' | wc -l)" -eq 11 ]
grep -q 'WhatsApp: posted complete delivery set to Ecom team group' "$OUT1"

run_mailer > "$OUT2"
SECOND_MEDIA_COUNT="$(grep -c '/send-media' "$CURL_LOG")"
[ "$SECOND_MEDIA_COUNT" -eq "$FIRST_MEDIA_COUNT" ]
grep -q 'confirmed receipt already exists' "$OUT2"
grep -q 'WhatsApp: posted complete delivery set to Ecom team group' "$OUT2"

echo "PASS delivery receipts are complete and idempotent"
