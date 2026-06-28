# tools/coverage/emit_ledger_from_history.py
# Derive an honest coverage ledger from a run's history.csv slice + the full config.
# Every CONFIGURED pincode gets exactly one status row:
#   price_captured       — at least one history row with a non-empty price
#   serviceable_no_jivo  — history row(s) present but no price (store served, no Jivo stock)
#   not_serviceable      — configured but absent from history (no rows for this run/date)
# This keeps the live scrape path untouched: we classify from the output, not in the loop.
import csv, json, os, sys
from ledger import record

def emit_for_run(platform, run_id, date_ist, history_path, config_path, ledger_path):
    cfg = json.load(open(config_path))
    configured = {e["pincode"]: e.get("city", "") for e in cfg}
    rows = [r for r in csv.DictReader(open(history_path))
            if r.get("date_ist") == date_ist and r.get("platform") == platform]
    seen = {}
    for r in rows:
        pin = (r.get("pincode") or "").strip()
        if pin not in configured:
            continue
        has_price = bool((r.get("price") or "").strip())
        s = seen.setdefault(pin, {"sku": 0, "price": ""})
        s["sku"] += 1
        if has_price and not s["price"]:
            s["price"] = r["price"].strip()
    n = 0
    for pin, city in configured.items():
        if pin in seen and seen[pin]["price"]:
            st, sku, pr = "price_captured", seen[pin]["sku"], seen[pin]["price"]
        elif pin in seen:
            st, sku, pr = "serviceable_no_jivo", seen[pin]["sku"], ""
        else:
            st, sku, pr = "not_serviceable", 0, ""
        record(platform, pin, city, st, run_id, date_ist, sku_count=sku, price_seen=pr, path=ledger_path)
        n += 1
    return n

if __name__ == "__main__":
    plat, run_id, date_ist, hist, cfg, led = sys.argv[1:7]
    print("ledger rows:", emit_for_run(plat, run_id, date_ist, hist, cfg, led))
