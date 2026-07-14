#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DATE="2099-02-01"
OUT="$(mktemp)"
PIN="$ROOT/output/Jivo-BigBasket-Pincode-Report-${DATE}.xlsx"
AMAZON="$ROOT/output/Jivo-Amazon-Live-Report-${DATE}.xlsx"

cleanup() {
  rm -f "$OUT" "$PIN" "$AMAZON"
}
trap cleanup EXIT

mkdir -p "$ROOT/output"
printf 'pincode fixture\n' > "$PIN"
printf 'amazon fixture\n' > "$AMAZON"

cd "$ROOT"
PRICE_MAIL_DATE="$DATE" \
MAILER_NO_REDIRECT=1 \
MAILER_TEST_MODE=1 \
MAILER_SKIP_WAIT=1 \
MAILER_LIST_ONLY=1 \
  tools/mailer/mail_price_data.sh test > "$OUT"

grep -qx "output/Jivo-BigBasket-Pincode-Report-${DATE}.xlsx" "$OUT"
grep -q "required reports are missing or unstable" "$OUT"

BUILD_BODY="$(sed -n '/^build_run() {/,/^}/p' platforms/bigbasket/team_run_pincode.sh)"
if grep -q 'send_group' <<<"$BUILD_BODY"; then
  echo "BigBasket build_run must queue the workbook, not send it immediately" >&2
  exit 1
fi
grep -q 'queued for the 10:30 Ecom batch' <<<"$BUILD_BODY"

grep -q 'WhatsApp: posted complete delivery set to Ecom team group' tools/cron/morning_report_guard.sh
if grep -qE 'f && / reports to Ecom team group/' tools/cron/morning_report_guard.sh; then
  echo "morning guard still accepts the legacy partial-batch success line" >&2
  exit 1
fi

echo "PASS 10:30 batch membership and completion contract"
