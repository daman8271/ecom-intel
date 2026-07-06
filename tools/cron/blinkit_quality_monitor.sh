#!/usr/bin/env bash
# blinkit_quality_monitor.sh — read-only quality hook for the Blinkit daily run.
#
# It does not scrape, ingest, build Excel, or send reports. It watches the actual
# accepted Blinkit artifacts and alerts if the false-OOS / wrong-price classes
# from 2026-07-06 can recur.
set -u

DIR=/opt/ecom-intel
cd "$DIR" || exit 0

TODAY="${BLINKIT_MONITOR_DATE:-$(TZ=Asia/Kolkata date +%F)}"
PASS="${1:-poll}"
LOG_DIR="$DIR/logs"
LOG_FILE="$LOG_DIR/blinkit_quality_monitor-${TODAY}.log"
STATE_FILE="$LOG_DIR/blinkit_quality_monitor-${TODAY}.state"
RESULT="${BLINKIT_MONITOR_RESULT:-$DIR/platforms/blinkit/result.json}"
CONFIG="${BLINKIT_EXPECTED_CONFIG:-$DIR/platforms/blinkit/pincodes.daily.json}"
REPORT="${BLINKIT_MONITOR_REPORT:-$DIR/output/Jivo-Blinkit-Live-Report-${TODAY}.xlsx}"
NOT_LISTED_REPORT="${BLINKIT_MONITOR_NOT_LISTED_REPORT:-$DIR/output/Jivo-Blinkit-Not-Listed-Pincodes-${TODAY}.xlsx}"
MAX_UNVERIFIED_OOS="${BLINKIT_MONITOR_MAX_UNVERIFIED_OOS:-0}"
MAX_COORD_ERRORS="${BLINKIT_MONITOR_MAX_COORD_ERRORS:-0}"
STALE_ALERT_AFTER="${BLINKIT_MONITOR_STALE_ALERT_AFTER:-09:15}"
REPORT_ALERT_AFTER="${BLINKIT_MONITOR_REPORT_ALERT_AFTER:-10:05}"
DRY="${BLINKIT_MONITOR_DRYRUN:-0}"
EXIT_CODE="${BLINKIT_MONITOR_EXIT_CODE:-0}"

mkdir -p "$LOG_DIR"

log(){ printf '[%s] blinkit_monitor(%s): %s\n' "$(TZ=Asia/Kolkata date '+%F %T %Z')" "$PASS" "$*" | tee -a "$LOG_FILE"; }

tg(){ ( set +e
  [ "$DRY" = "1" ] && { log "[DRYRUN] would notify: ${1//$'\n'/ }"; exit 0; }
  [ -f "$DIR/secrets.env" ] && . "$DIR/secrets.env"
  CH="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "$CH" ] || exit 0
  curl -s --max-time 30 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CH}" \
    --data-urlencode "text=$1" >/dev/null ) || true; }

alert_once(){
  local key="$1" msg="$2"
  if [ "$DRY" = "1" ]; then
    log "DRYRUN ALERT $key: ${msg//$'\n'/ }"
    tg "$msg"
    return 0
  fi
  touch "$STATE_FILE"
  if grep -qxF "$key" "$STATE_FILE" 2>/dev/null; then
    log "already alerted $key"
    return 0
  fi
  printf '%s\n' "$key" >> "$STATE_FILE"
  log "ALERT $key: ${msg//$'\n'/ }"
  tg "$msg"
}

mac_running(){
  ssh -o BatchMode=yes -o ConnectTimeout=10 macpro \
    "pgrep -f 'run_blinkit_mac_to_vps.sh|platforms/blinkit/scrape.js' >/dev/null" \
    >/dev/null 2>&1
}

if [ ! -f "$RESULT" ]; then
  log "no result.json yet"
  exit 0
fi

if [ ! -f "$REPORT" ]; then
  if mac_running; then
    log "report not present yet; Mac Blinkit job appears active"
  else
    log "report not present and no Mac Blinkit process detected"
  fi
fi

VALIDATION_JSON="$(
  RESULT="$RESULT" CONFIG="$CONFIG" REPORT="$REPORT" NOT_LISTED_REPORT="$NOT_LISTED_REPORT" TODAY="$TODAY" \
  MAX_UNVERIFIED_OOS="$MAX_UNVERIFIED_OOS" MAX_COORD_ERRORS="$MAX_COORD_ERRORS" \
  PASS="$PASS" STALE_ALERT_AFTER="$STALE_ALERT_AFTER" REPORT_ALERT_AFTER="$REPORT_ALERT_AFTER" \
  python3 - <<'PY'
import json, os, sys, datetime, math

result_path = os.environ["RESULT"]
config_path = os.environ["CONFIG"]
report_path = os.environ["REPORT"]
not_listed_report_path = os.environ.get("NOT_LISTED_REPORT") or ""
today = os.environ["TODAY"]
max_unverified_oos = int(os.environ.get("MAX_UNVERIFIED_OOS") or 0)
max_coord_errors = int(os.environ.get("MAX_COORD_ERRORS") or 0)
monitor_pass = os.environ.get("PASS") or "poll"
stale_alert_after = os.environ.get("STALE_ALERT_AFTER") or "09:15"
report_alert_after = os.environ.get("REPORT_ALERT_AFTER") or "10:05"
IST = datetime.timezone(datetime.timedelta(hours=5, minutes=30))

issues = []
warnings = []
facts = {}

def issue(code, msg):
    issues.append({"code": code, "message": msg})

def warn(code, msg):
    warnings.append({"code": code, "message": msg})

def parse_dt(s):
    if not s:
        return None
    try:
        return datetime.datetime.fromisoformat(str(s).replace("Z", "+00:00"))
    except Exception:
        return None

def after_cutoff(hhmm):
    now = datetime.datetime.now(IST)
    now_date = now.date().isoformat()
    if now_date != today:
        return now_date > today
    try:
        hh, mm = [int(x) for x in str(hhmm).split(":", 1)]
    except Exception:
        hh, mm = 9, 15
    return (now.hour * 60 + now.minute) >= (hh * 60 + mm)

try:
    d = json.load(open(result_path, encoding="utf-8"))
except Exception as e:
    print(json.dumps({"ok": False, "issues": [{"code": "result_unreadable", "message": str(e)}]}))
    raise SystemExit(0)

s = d.get("summary") or {}
rows = d.get("allRows") or []
per = d.get("perPin") or []
facts.update({
    "captured_at": s.get("captured_at"),
    "total_rows": len(rows),
    "pincodes_total": s.get("pincodes_total"),
    "pincodes_resolved": s.get("pincodes_resolved"),
    "auth_verified_pincodes": s.get("auth_verified_pincodes", None),
    "oos_rows": sum(1 for r in rows if not r.get("in_stock")),
    "oos_probe_flips": s.get("oos_probe_flips", 0),
    "pdp_oos_probe_flips": s.get("pdp_oos_probe_flips", 0),
    "unverified_oos": s.get("unverified_oos", None),
})

cap = parse_dt(s.get("captured_at"))
if cap:
    ist_date = cap.astimezone(IST).date().isoformat()
    facts["captured_ist_date"] = ist_date
    if ist_date != today:
        if monitor_pass == "poll" and not after_cutoff(stale_alert_after):
            warn("stale_result_grace", f"Blinkit result is still {ist_date}; waiting until {stale_alert_after} IST for today's drop")
            print(json.dumps({
                "ok": True,
                "waiting": True,
                "issues": issues,
                "warnings": warnings,
                "facts": facts,
            }, ensure_ascii=False))
            raise SystemExit(0)
        issue("stale_result", f"Blinkit result captured_at IST date {ist_date}, expected {today}")
else:
    issue("missing_captured_at", "Blinkit summary.captured_at missing/unparseable")

if s.get("auth_session") != 1 or s.get("auth_required") != 1 or s.get("auth_verified") != 1:
    issue("auth_not_enforced", f"auth_session={s.get('auth_session')} auth_required={s.get('auth_required')} auth_verified={s.get('auth_verified')}")
if s.get("auth_required") == 1 and s.get("auth_verified_pincodes") != s.get("pincodes_total"):
    issue("auth_not_all_pincodes", f"auth_verified_pincodes={s.get('auth_verified_pincodes')} pincodes_total={s.get('pincodes_total')}")

if sum(1 for r in rows if not r.get("in_stock")):
    if s.get("oos_probe_enabled") != 1:
        issue("oos_probe_disabled", "OOS rows exist but summary.oos_probe_enabled != 1")
    if s.get("pdp_oos_probe_enabled") != 1:
        issue("pdp_probe_disabled", "OOS rows exist but summary.pdp_oos_probe_enabled != 1")

if s.get("pdp_price_probe_enabled") != 1:
    issue("pdp_price_probe_disabled", f"summary.pdp_price_probe_enabled={s.get('pdp_price_probe_enabled')} != 1")

calculated_unverified_oos = sum(1 for r in rows if not r.get("in_stock") and not r.get("pdp_checked") and r.get("stock_source") not in ("pdp", "pdp_probe"))
summary_unverified_oos = s.get("unverified_oos")
try:
    summary_unverified_oos = int(summary_unverified_oos) if summary_unverified_oos is not None else None
except Exception:
    summary_unverified_oos = None
unverified = calculated_unverified_oos if summary_unverified_oos is None else max(summary_unverified_oos, calculated_unverified_oos)
facts["summary_unverified_oos"] = summary_unverified_oos
facts["calculated_unverified_oos"] = calculated_unverified_oos
facts["computed_unverified_oos"] = unverified
if unverified > max_unverified_oos:
    issue("unverified_oos_high", f"unverified_oos={unverified} > {max_unverified_oos}")

missing_id = sum(1 for r in rows if not r.get("prid") or not r.get("listing_url"))
facts["missing_prid_or_url"] = missing_id
if rows and missing_id / len(rows) > 0.005:
    issue("missing_prid_url_high", f"{missing_id}/{len(rows)} rows missing PRID/listing_url")

bad_price = []
for r in rows:
    sale, mrp, vol = r.get("sale"), r.get("mrp"), r.get("vol_ml")
    if sale is None or mrp is None:
        continue
    try:
        sale = float(sale); mrp = float(mrp)
    except Exception:
        bad_price.append((r.get("pincode"), r.get("sku_raw"), "non_numeric"))
        continue
    if sale <= 0 or mrp <= 0 or mrp < sale:
        bad_price.append((r.get("pincode"), r.get("sku_raw"), f"sale={sale} mrp={mrp}"))
        continue
    if vol:
        expected = round((sale / (float(vol) / 1000.0)) * 100) / 100
        got = r.get("per_litre")
        if got is not None and abs(float(got) - expected) > 0.75:
            bad_price.append((r.get("pincode"), r.get("sku_raw"), f"per_litre={got} expected={expected}"))
if bad_price:
    issue("bad_price_math", f"{len(bad_price)} rows failed price math; first={bad_price[:3]}")

pomace = [
    r for r in rows
    if str(r.get("pincode")) == "110094" and str(r.get("prid")) == "407561"
]
if pomace:
    best = sorted(pomace, key=lambda r: (1 if r.get("in_stock") else 0, -abs(float(r.get("sale") or 0) - 1766)), reverse=True)[0]
    facts["canary_110094_407561"] = {k: best.get(k) for k in ("sale", "base_sale", "offer_sale", "mrp", "in_stock", "store_id", "stock_probe_label", "stock_source", "price_source", "search_sale")}
    if not best.get("in_stock") and best.get("sale") == 1876 and best.get("stock_source") not in ("pdp", "pdp_probe"):
        issue("canary_110094_old_failure", "110094 Pomace 5L still looks like old 1876/search-OOS failure")
    price_source = str(best.get("price_source") or "").strip().lower()
    price_verified = bool(best.get("pdp_price_checked")) or bool(best.get("pdp_checked")) or "pdp" in price_source or "offer" in price_source
    if best.get("in_stock") and not price_verified:
        issue("canary_110094_407561_unverified_price", "110094 Pomace 5L is in stock but price is not PDP/offer verified; this can repeat the stale-search-price class from the user screenshots")
    if best.get("in_stock") and best.get("sale") == 1876 and not best.get("offer_sale") and "offer" not in str(best.get("price_source") or ""):
        issue("canary_110094_old_price", "110094 Pomace 5L is in stock but still shows old ₹1876 without offer/effective-price evidence")
else:
    warn("canary_absent", "110094/407561 not present in current rows; cannot canary-check screenshot case")

def canary_compact(row):
    return {k: row.get(k) for k in ("sale", "base_sale", "offer_sale", "mrp", "in_stock", "store_id", "listing_status", "stock_probe_label", "stock_source", "price_source", "search_sale", "pdp_checked", "pdp_price_checked")}

def verified_oos(row):
    return bool(row.get("pdp_checked")) or str(row.get("stock_source") or "").strip().lower() in ("pdp", "pdp_probe")

for pin, prid, label, stale_sale in (
    ("110012", "407851", "Canola 1L", None),
    ("110012", "406593", "Canola 5L", 1198),
):
    matches = [r for r in rows if str(r.get("pincode")) == pin and str(r.get("prid")) == prid]
    fact_key = f"canary_{pin}_{prid}"
    if not matches:
        warn(f"{fact_key}_absent", f"{pin}/{prid} {label} not present in current rows; cannot canary-check user screenshot case")
        continue
    best = sorted(matches, key=lambda r: (1 if r.get("in_stock") else 0, 1 if "pdp" in str(r.get("price_source") or "") or "offer" in str(r.get("price_source") or "") else 0), reverse=True)[0]
    facts[fact_key] = canary_compact(best)
    if not best.get("in_stock") and not verified_oos(best):
        issue(f"{fact_key}_unverified_oos", f"{pin} {label} is OOS without PDP verification; this matches the false-OOS class from the user screenshots")
    price_source = str(best.get("price_source") or "").strip().lower()
    price_verified = bool(best.get("pdp_price_checked")) or bool(best.get("pdp_checked")) or "pdp" in price_source or "offer" in price_source
    if best.get("in_stock") and not price_verified:
        issue(f"{fact_key}_unverified_price", f"{pin} {label} is in stock but price is not PDP/offer verified; this can repeat the stale-search-price class from the user screenshots")
    if stale_sale is not None and best.get("in_stock") and best.get("sale") == stale_sale and not best.get("offer_sale") and "pdp" not in str(best.get("price_source") or "") and "offer" not in str(best.get("price_source") or ""):
        issue(f"{fact_key}_stale_price", f"{pin} {label} is in stock but still shows stale/search price ₹{stale_sale} without PDP/offer evidence")

coord_bad = []
if os.path.exists(config_path):
    try:
        cfg = json.load(open(config_path, encoding="utf-8"))
        def walk(x):
            if isinstance(x, list):
                for y in x: walk(y)
            elif isinstance(x, dict):
                if "pincode" in x:
                    lat, lon = x.get("lat"), x.get("lon")
                    try:
                        latf, lonf = float(lat), float(lon)
                        if not (6.0 <= latf <= 38.5 and 68.0 <= lonf <= 98.0):
                            coord_bad.append((x.get("city"), x.get("pincode"), lat, lon))
                    except Exception:
                        coord_bad.append((x.get("city"), x.get("pincode"), lat, lon))
                for v in x.values(): walk(v)
        walk(cfg)
    except Exception as e:
        issue("config_unreadable", f"{config_path}: {e}")
else:
    warn("config_missing", f"{config_path} missing")
facts["coord_bad"] = len(coord_bad)
if len(coord_bad) > max_coord_errors:
    issue("bad_coordinates", f"{len(coord_bad)} configured pincode coordinates outside India bbox; first={coord_bad[:5]}")

if os.path.exists(report_path):
    try:
        from openpyxl import load_workbook
        wb = load_workbook(report_path, read_only=True, data_only=True)
        facts["workbook_sheets"] = wb.sheetnames
        if "Listing Status" not in wb.sheetnames:
            issue("missing_listing_status_sheet", "Workbook missing Listing Status sheet")
        if "Not Listed Pincodes" not in wb.sheetnames:
            issue("missing_not_listed_sheet", "Workbook missing Not Listed Pincodes sheet")
        if "Master Data" in wb.sheetnames:
            ws = wb["Master Data"]
            header = [c.value for c in next(ws.iter_rows(min_row=1, max_row=1))]
            for h in ("Product status", "Stock source", "Price source", "Base Sale Rs", "Offer Rs"):
                if h not in header:
                    issue("missing_master_column", f"Master Data missing {h}")
    except Exception as e:
        issue("workbook_check_failed", str(e))
    if not_listed_report_path:
        if os.path.exists(not_listed_report_path):
            try:
                nl_wb = load_workbook(not_listed_report_path, read_only=True, data_only=True)
                facts["not_listed_workbook_sheets"] = nl_wb.sheetnames
                if "Not Listed Pincodes" not in nl_wb.sheetnames:
                    issue("not_listed_workbook_missing_sheet", f"{not_listed_report_path} missing Not Listed Pincodes sheet")
            except Exception as e:
                issue("not_listed_workbook_check_failed", f"{not_listed_report_path}: {e}")
        else:
            issue("missing_not_listed_workbook", f"{not_listed_report_path} missing")
else:
    if after_cutoff(report_alert_after):
        issue("workbook_missing_after_cutoff", f"{report_path} missing after {report_alert_after} IST")
    else:
        warn("workbook_missing", f"{report_path} missing")

print(json.dumps({
    "ok": not issues,
    "issues": issues,
    "warnings": warnings,
    "facts": facts,
}, ensure_ascii=False))
PY
)"

log "$VALIDATION_JSON"

OK="$(python3 - <<'PY' "$VALIDATION_JSON"
import json, sys
try:
    print("1" if json.loads(sys.argv[1]).get("ok") else "0")
except Exception:
    print("0")
PY
)"

if [ "$OK" = "1" ]; then
  if [ "$PASS" = "poll" ] && [ ! -f "$REPORT" ]; then
    log "quality checks are waiting for workbook: $REPORT"
    exit 0
  fi
  if [ "$DRY" = "1" ]; then
    log "quality OK for $TODAY (dry-run; state not written)"
    tg "✅ Blinkit quality monitor: ${TODAY} result passed auth + OOS/PDP + coordinate/report checks."
    exit 0
  fi
  if ! grep -qxF "ok" "$STATE_FILE" 2>/dev/null; then
    printf 'ok\n' >> "$STATE_FILE"
    log "quality OK for $TODAY"
    tg "✅ Blinkit quality monitor: ${TODAY} result passed auth + OOS/PDP + coordinate/report checks."
  else
    log "quality still OK"
  fi
else
  python3 - <<'PY' "$VALIDATION_JSON" > /tmp/blinkit-monitor-msg.txt
import json, sys
d=json.loads(sys.argv[1])
lines=["🔴 Blinkit quality monitor FAILED"]
for i in d.get("issues", [])[:8]:
    lines.append(f"- {i.get('code')}: {i.get('message')}")
facts=d.get("facts") or {}
lines.append(f"facts: rows={facts.get('total_rows')} oos={facts.get('oos_rows')} unverified={facts.get('computed_unverified_oos')} coord_bad={facts.get('coord_bad')}")
print("\n".join(lines))
PY
  alert_once "fail-$(python3 - <<'PY' "$VALIDATION_JSON"
import json, sys
d=json.loads(sys.argv[1])
print("-".join(i.get("code","issue") for i in d.get("issues", [])[:4]) or "unknown")
PY
	)" "$(cat /tmp/blinkit-monitor-msg.txt)"
  if [ "$EXIT_CODE" = "1" ]; then
    exit 1
  fi
fi
