#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE="$ROOT/platforms/blinkit/tests/fixtures/false_oos_price_mismatch.json"
MONITOR="$ROOT/tools/cron/blinkit_quality_monitor.sh"

GOOD="$(mktemp)"
BAD="$(mktemp)"
BAD_UNVERIFIED="$(mktemp)"
BAD_PRICE_PROBE_DISABLED="$(mktemp)"
BAD_STOCK_UNVERIFIED="$(mktemp)"
BAD_CANOLA_OOS="$(mktemp)"
BAD_CANOLA_PRICE="$(mktemp)"
BAD_CANOLA_UNVERIFIED_PRICE="$(mktemp)"
GOOD_WORKBOOK="$(mktemp --suffix=.xlsx)"
GOOD_NOT_LISTED_WORKBOOK="$(mktemp --suffix=.xlsx)"
BAD_MAIN_MISSING_NL="$(mktemp --suffix=.xlsx)"
BAD_NOT_LISTED_WORKBOOK="$(mktemp --suffix=.xlsx)"
BAD_WORKBOOK="$(mktemp --suffix=.xlsx)"
GOOD_OUT="$(mktemp)"
GOOD_WORKBOOK_OUT="$(mktemp)"
MISSING_NOT_LISTED_OUT="$(mktemp)"
BAD_MAIN_MISSING_NL_OUT="$(mktemp)"
BAD_NOT_LISTED_WORKBOOK_OUT="$(mktemp)"
BAD_OUT="$(mktemp)"
BAD_UNVERIFIED_OUT="$(mktemp)"
BAD_PRICE_PROBE_DISABLED_OUT="$(mktemp)"
BAD_STOCK_UNVERIFIED_OUT="$(mktemp)"
BAD_CANOLA_OOS_OUT="$(mktemp)"
BAD_CANOLA_PRICE_OUT="$(mktemp)"
BAD_CANOLA_UNVERIFIED_PRICE_OUT="$(mktemp)"
BAD_WORKBOOK_OUT="$(mktemp)"
trap 'rm -f "$GOOD" "$BAD" "$BAD_UNVERIFIED" "$BAD_PRICE_PROBE_DISABLED" "$BAD_STOCK_UNVERIFIED" "$BAD_CANOLA_OOS" "$BAD_CANOLA_PRICE" "$BAD_CANOLA_UNVERIFIED_PRICE" "$GOOD_WORKBOOK" "$GOOD_NOT_LISTED_WORKBOOK" "$BAD_MAIN_MISSING_NL" "$BAD_NOT_LISTED_WORKBOOK" "$BAD_WORKBOOK" "$GOOD_OUT" "$GOOD_WORKBOOK_OUT" "$MISSING_NOT_LISTED_OUT" "$BAD_MAIN_MISSING_NL_OUT" "$BAD_NOT_LISTED_WORKBOOK_OUT" "$BAD_OUT" "$BAD_UNVERIFIED_OUT" "$BAD_PRICE_PROBE_DISABLED_OUT" "$BAD_STOCK_UNVERIFIED_OUT" "$BAD_CANOLA_OOS_OUT" "$BAD_CANOLA_PRICE_OUT" "$BAD_CANOLA_UNVERIFIED_PRICE_OUT" "$BAD_WORKBOOK_OUT" "$ROOT/logs/blinkit_quality_monitor-2099-01-01.log" "$ROOT/logs/blinkit_quality_monitor-2099-01-01.state"' EXIT

python3 - "$FIXTURE" "$GOOD" "$BAD" "$BAD_UNVERIFIED" "$BAD_PRICE_PROBE_DISABLED" "$BAD_STOCK_UNVERIFIED" "$BAD_CANOLA_OOS" "$BAD_CANOLA_PRICE" "$BAD_CANOLA_UNVERIFIED_PRICE" <<'PY'
import json, sys
src, good_path, bad_path, bad_unverified_path, bad_price_probe_disabled_path, bad_stock_unverified_path, bad_canola_oos_path, bad_canola_price_path, bad_canola_unverified_price_path = sys.argv[1:]
good = json.load(open(src, encoding="utf-8"))
good["summary"]["captured_at"] = "2099-01-01T04:00:00.000Z"
good["summary"]["pdp_price_probe_enabled"] = 1
good["summary"]["pdp_price_probe_checked"] = 1
good["summary"]["pdp_price_probe_updates"] = 0
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

bad_unverified = json.loads(json.dumps(good))
bad_unverified["summary"]["unverified_oos"] = 1
for row in [bad_unverified["allRows"][0], bad_unverified["perPin"][0]["rows"][0]]:
    row["in_stock"] = 0
    row["listing_status"] = "listed_out_of_stock"
    row["stock_source"] = "search_card_oos"
    row["pdp_checked"] = 0
json.dump(bad_unverified, open(bad_unverified_path, "w", encoding="utf-8"))

bad_price_probe_disabled = json.loads(json.dumps(good))
bad_price_probe_disabled["summary"].pop("pdp_price_probe_enabled", None)
bad_price_probe_disabled["summary"].pop("pdp_price_probe_checked", None)
bad_price_probe_disabled["summary"].pop("pdp_price_probe_updates", None)
json.dump(bad_price_probe_disabled, open(bad_price_probe_disabled_path, "w", encoding="utf-8"))

bad_stock_unverified = json.loads(json.dumps(good))
for row in [bad_stock_unverified["allRows"][0], bad_stock_unverified["perPin"][0]["rows"][0]]:
    row["in_stock"] = None
    row["listing_status"] = "stock_unverified"
    row["stock_source"] = "search_card_oos_unverified"
    row["stock_unverified"] = 1
    row["pdp_checked"] = 0
json.dump(bad_stock_unverified, open(bad_stock_unverified_path, "w", encoding="utf-8"))

def canola_row(prid, pack, vol_ml, sale, mrp):
    row = json.loads(json.dumps(good["allRows"][0]))
    row.update({
        "city": "Delhi",
        "pincode": "110012",
        "locality": "IARI SO",
        "sku_raw": "Jivo Cold Pressed Canola Oil",
        "canonical": f"jivo-cold-pressed-canola-oil-{pack.replace(' ', '')}",
        "pack": pack,
        "vol_ml": vol_ml,
        "sale": sale,
        "base_sale": None,
        "offer_sale": None,
        "mrp": mrp,
        "discount_pct": round((mrp - sale) * 100 / mrp, 1),
        "per_litre": round(sale / (vol_ml / 1000), 2),
        "prid": prid,
        "listing_url": f"https://blinkit.com/prn/jivo-cold-pressed-canola-oil/prid/{prid}",
        "search_sale": sale,
        "pdp_sale": None,
    })
    return row

bad_canola_oos = json.loads(json.dumps(good))
bad_canola_oos["summary"]["unverified_oos"] = 0
row = canola_row("407851", "1 l", 1000, 239, 375)
row.update({
    "in_stock": 0,
    "listing_status": "listed_out_of_stock",
    "stock_source": "search_card_oos",
    "price_source": "search_card_oos",
    "pdp_checked": 0,
    "pdp_in_stock": 0,
})
bad_canola_oos["allRows"].append(row)
json.dump(bad_canola_oos, open(bad_canola_oos_path, "w", encoding="utf-8"))

bad_canola_price = json.loads(json.dumps(good))
row = canola_row("406593", "5 l", 5000, 1198, 1650)
row.update({
    "in_stock": 1,
    "listing_status": "listed_in_stock",
    "stock_source": "search_card",
    "price_source": "search_card",
    "pdp_checked": 0,
    "pdp_in_stock": None,
})
bad_canola_price["allRows"].append(row)
json.dump(bad_canola_price, open(bad_canola_price_path, "w", encoding="utf-8"))

bad_canola_unverified_price = json.loads(json.dumps(good))
row = canola_row("406593", "5 l", 5000, 1193, 1650)
row.update({
    "in_stock": 1,
    "listing_status": "listed_in_stock",
    "stock_source": "search_card",
    "price_source": "search_card",
    "pdp_checked": 0,
    "pdp_price_checked": 0,
    "pdp_in_stock": None,
})
bad_canola_unverified_price["allRows"].append(row)
json.dump(bad_canola_unverified_price, open(bad_canola_unverified_price_path, "w", encoding="utf-8"))
PY

python3 - "$GOOD_WORKBOOK" "$GOOD_NOT_LISTED_WORKBOOK" "$BAD_MAIN_MISSING_NL" "$BAD_NOT_LISTED_WORKBOOK" <<'PY'
import sys
from openpyxl import Workbook

main_path, not_listed_path, bad_main_path, bad_not_listed_path = sys.argv[1:]
wb = Workbook()
ws = wb.active
ws.title = "Master Data"
ws.append(["Product status", "Stock source", "Price source", "Base Sale Rs", "Offer Rs"])
wb.create_sheet("Listing Status").append(["City", "Pincode", "SKU", "Product status", "Source"])
wb.create_sheet("Not Listed Pincodes").append(["City", "Pincode", "SKU", "Source"])
wb.save(main_path)

nl = Workbook()
nl.active.title = "Not Listed Pincodes"
nl.active.append(["City", "Pincode", "SKU", "Source"])
nl.save(not_listed_path)

bad = Workbook()
bad.active.title = "Master Data"
bad.active.append(["Product status", "Stock source", "Price source", "Base Sale Rs", "Offer Rs"])
bad.create_sheet("Listing Status").append(["City", "Pincode", "SKU", "Product status", "Source"])
bad.save(bad_main_path)

open(bad_not_listed_path, "w", encoding="utf-8").write("not a workbook\n")
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
BLINKIT_MONITOR_RESULT="$GOOD" \
BLINKIT_MONITOR_REPORT="$GOOD_WORKBOOK" \
BLINKIT_MONITOR_NOT_LISTED_REPORT="$GOOD_NOT_LISTED_WORKBOOK" \
  "$MONITOR" test > "$GOOD_WORKBOOK_OUT"
grep -q '"ok": true' "$GOOD_WORKBOOK_OUT"

BLINKIT_MONITOR_DRYRUN=1 \
BLINKIT_MONITOR_DATE=2099-01-01 \
BLINKIT_MONITOR_RESULT="$GOOD" \
BLINKIT_MONITOR_REPORT="$GOOD_WORKBOOK" \
BLINKIT_MONITOR_NOT_LISTED_REPORT=/tmp/no-such-blinkit-not-listed.xlsx \
  "$MONITOR" test > "$MISSING_NOT_LISTED_OUT"
grep -q '"ok": false' "$MISSING_NOT_LISTED_OUT"
grep -q 'missing_not_listed_workbook' "$MISSING_NOT_LISTED_OUT"

BLINKIT_MONITOR_DRYRUN=1 \
BLINKIT_MONITOR_DATE=2099-01-01 \
BLINKIT_MONITOR_RESULT="$GOOD" \
BLINKIT_MONITOR_REPORT="$BAD_MAIN_MISSING_NL" \
BLINKIT_MONITOR_NOT_LISTED_REPORT="$GOOD_NOT_LISTED_WORKBOOK" \
  "$MONITOR" test > "$BAD_MAIN_MISSING_NL_OUT"
grep -q '"ok": false' "$BAD_MAIN_MISSING_NL_OUT"
grep -q 'missing_not_listed_sheet' "$BAD_MAIN_MISSING_NL_OUT"

BLINKIT_MONITOR_DRYRUN=1 \
BLINKIT_MONITOR_DATE=2099-01-01 \
BLINKIT_MONITOR_RESULT="$GOOD" \
BLINKIT_MONITOR_REPORT="$GOOD_WORKBOOK" \
BLINKIT_MONITOR_NOT_LISTED_REPORT="$BAD_NOT_LISTED_WORKBOOK" \
  "$MONITOR" test > "$BAD_NOT_LISTED_WORKBOOK_OUT"
grep -q '"ok": false' "$BAD_NOT_LISTED_WORKBOOK_OUT"
grep -q 'not_listed_workbook_check_failed' "$BAD_NOT_LISTED_WORKBOOK_OUT"

BLINKIT_MONITOR_DRYRUN=1 \
BLINKIT_MONITOR_DATE=2099-01-01 \
BLINKIT_MONITOR_RESULT="$BAD" \
BLINKIT_MONITOR_REPORT=/tmp/no-such-blinkit-report.xlsx \
  "$MONITOR" test > "$BAD_OUT"
grep -q '"ok": false' "$BAD_OUT"
grep -q 'canary_110094_old_price' "$BAD_OUT"

BLINKIT_MONITOR_DRYRUN=1 \
BLINKIT_MONITOR_DATE=2099-01-01 \
BLINKIT_MONITOR_RESULT="$BAD_UNVERIFIED" \
BLINKIT_MONITOR_REPORT=/tmp/no-such-blinkit-report.xlsx \
  "$MONITOR" test > "$BAD_UNVERIFIED_OUT"
grep -q '"ok": false' "$BAD_UNVERIFIED_OUT"
grep -q 'unverified_oos_high' "$BAD_UNVERIFIED_OUT"

BLINKIT_MONITOR_DRYRUN=1 \
BLINKIT_MONITOR_DATE=2099-01-01 \
BLINKIT_MONITOR_RESULT="$BAD_PRICE_PROBE_DISABLED" \
BLINKIT_MONITOR_REPORT=/tmp/no-such-blinkit-report.xlsx \
  "$MONITOR" test > "$BAD_PRICE_PROBE_DISABLED_OUT"
grep -q '"ok": false' "$BAD_PRICE_PROBE_DISABLED_OUT"
grep -q 'pdp_price_probe_disabled' "$BAD_PRICE_PROBE_DISABLED_OUT"

BLINKIT_MONITOR_DRYRUN=1 \
BLINKIT_MONITOR_DATE=2099-01-01 \
BLINKIT_MONITOR_RESULT="$BAD_STOCK_UNVERIFIED" \
BLINKIT_MONITOR_REPORT=/tmp/no-such-blinkit-report.xlsx \
  "$MONITOR" test > "$BAD_STOCK_UNVERIFIED_OUT"
grep -q '"ok": false' "$BAD_STOCK_UNVERIFIED_OUT"
grep -q 'stock_unverified_rows' "$BAD_STOCK_UNVERIFIED_OUT"

BLINKIT_MONITOR_DRYRUN=1 \
BLINKIT_MONITOR_DATE=2099-01-01 \
BLINKIT_MONITOR_RESULT="$BAD_CANOLA_OOS" \
BLINKIT_MONITOR_REPORT=/tmp/no-such-blinkit-report.xlsx \
  "$MONITOR" test > "$BAD_CANOLA_OOS_OUT"
grep -q '"ok": false' "$BAD_CANOLA_OOS_OUT"
grep -q 'canary_110012_407851_unverified_oos' "$BAD_CANOLA_OOS_OUT"
grep -q 'unverified_oos_high' "$BAD_CANOLA_OOS_OUT"

BLINKIT_MONITOR_DRYRUN=1 \
BLINKIT_MONITOR_DATE=2099-01-01 \
BLINKIT_MONITOR_RESULT="$BAD_CANOLA_PRICE" \
BLINKIT_MONITOR_REPORT=/tmp/no-such-blinkit-report.xlsx \
  "$MONITOR" test > "$BAD_CANOLA_PRICE_OUT"
grep -q '"ok": false' "$BAD_CANOLA_PRICE_OUT"
grep -q 'canary_110012_406593_stale_price' "$BAD_CANOLA_PRICE_OUT"

BLINKIT_MONITOR_DRYRUN=1 \
BLINKIT_MONITOR_DATE=2099-01-01 \
BLINKIT_MONITOR_RESULT="$BAD_CANOLA_UNVERIFIED_PRICE" \
BLINKIT_MONITOR_REPORT=/tmp/no-such-blinkit-report.xlsx \
  "$MONITOR" test > "$BAD_CANOLA_UNVERIFIED_PRICE_OUT"
grep -q '"ok": false' "$BAD_CANOLA_UNVERIFIED_PRICE_OUT"
grep -q 'canary_110012_406593_unverified_price' "$BAD_CANOLA_UNVERIFIED_PRICE_OUT"

printf 'not a workbook\n' > "$BAD_WORKBOOK"
BLINKIT_MONITOR_DRYRUN=1 \
BLINKIT_MONITOR_DATE=2099-01-01 \
BLINKIT_MONITOR_RESULT="$GOOD" \
BLINKIT_MONITOR_REPORT="$BAD_WORKBOOK" \
  "$MONITOR" test > "$BAD_WORKBOOK_OUT"
grep -q '"ok": false' "$BAD_WORKBOOK_OUT"
grep -q 'workbook_check_failed' "$BAD_WORKBOOK_OUT"

echo "PASS blinkit quality monitor canary regression"
