# tools/coverage/emit_ledger_from_history.py
# Derive an honest coverage ledger from a run's history.csv slice + the full config.
# Every CONFIGURED pincode gets exactly one status row:
#   price_captured       — at least one history row with a non-empty price
#   serviceable_no_jivo  — history row(s) present but no price (store served, no Jivo stock)
#   not_serviceable      — configured but absent from history (no rows for this run/date)
# This keeps the live scrape path untouched: we classify from the output, not in the loop.
import csv, json, os, sys
from ledger import record

def _resolved_pincodes(result_path):
    """Set of pincodes a scraper marked resolved=true (store re-resolved = the location
    IS served), even when no Jivo SKU was found. Some scrapers (e.g. Blinkit) only write
    history rows when a Jivo SKU is present, so a served-but-no-Jivo pincode is ABSENT from
    history.csv. result.json's per-pincode `resolved` flag is the honest serviceability
    signal that lets us record `serviceable_no_jivo` instead of mislabeling it not_serviceable.
    Optional + fail-safe: missing/unreadable result.json -> empty set (history-only behavior)."""
    if not result_path or not os.path.exists(result_path):
        return set()
    try:
        d = json.load(open(result_path))
    except Exception:
        return set()
    out = set()
    for p in d.get("perPin", []):
        if p.get("resolved") and (p.get("pincode") is not None):
            out.add(str(p["pincode"]).strip())
    return out

def emit_for_run(platform, run_id, date_ist, history_path, config_path, ledger_path, result_path=None):
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
    resolved = _resolved_pincodes(result_path)
    n = 0
    for pin, city in configured.items():
        if pin in seen and seen[pin]["price"]:
            st, sku, pr = "price_captured", seen[pin]["sku"], seen[pin]["price"]
        elif pin in seen:
            st, sku, pr = "serviceable_no_jivo", seen[pin]["sku"], ""
        elif pin in resolved:
            # store re-resolved (location served) but no Jivo SKU + no history row
            st, sku, pr = "serviceable_no_jivo", 0, ""
        else:
            st, sku, pr = "not_serviceable", 0, ""
        record(platform, pin, city, st, run_id, date_ist, sku_count=sku, price_seen=pr, path=ledger_path)
        n += 1
    return n

if __name__ == "__main__":
    args = sys.argv[1:]
    plat, run_id, date_ist, hist, cfg, led = args[:6]
    result_path = args[6] if len(args) > 6 else None
    print("ledger rows:", emit_for_run(plat, run_id, date_ist, hist, cfg, led, result_path))
