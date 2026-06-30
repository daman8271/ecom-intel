"""sitelib — shared, deterministic data layer for the 3 Jivo ecom availability sites.

Reads the canonical ecom-intel coverage data and exposes the structures every site
generator needs:
  - data/coverage/ledger.csv          serviceability spine (status per platform x pincode)
  - data/<platform>/history.csv       per-SKU price/stock rows

Rules (honest "latest data"):
  - Serviceability footprint per platform = the ledger date with the MOST distinct
    pincodes (the full per-pincode census). Daily Jivo-priced subset runs are smaller
    and must NOT shrink the footprint.
  - Prices/stock = the FRESHEST history row per (platform, pincode, sku). So a daily
    subset run refreshes prices for its pincodes without dropping the rest.

NO LLM. stdlib only. Deterministic ordering for clean diffs.
"""
import csv, os, json, collections

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
LEDGER = os.path.join(ROOT, "data", "coverage", "ledger.csv")
DRR = os.path.join(ROOT, "docs", "pincodes", "drr_pincode.csv")

QC_PLATFORMS = ["blinkit", "zepto", "flipkart-minutes"]
AMAZON_PLATFORMS = ["amazon-fresh", "amazon-now"]
SKU_LEVEL = {"blinkit": True, "zepto": True, "flipkart-minutes": True,
             "amazon-fresh": False, "amazon-now": False}

SERVICEABLE = {"price_captured", "serviceable_no_jivo"}

# Each of the 25 universe cities -> its canonical state (matches the console's 15 states).
CITY_STATE = {
    "Mumbai": "Maharashtra", "Delhi": "Delhi", "Bengaluru": "Karnataka",
    "Hyderabad": "Telangana", "Chennai": "Tamil Nadu", "Pune": "Maharashtra",
    "Ahmedabad": "Gujarat", "Kolkata": "West Bengal", "Surat": "Gujarat",
    "Noida": "Uttar Pradesh", "Gurugram": "Haryana", "Jaipur": "Rajasthan",
    "Lucknow": "Uttar Pradesh", "Chandigarh": "Chandigarh", "Kochi": "Kerala",
    "Indore": "Madhya Pradesh", "Coimbatore": "Tamil Nadu", "Nagpur": "Maharashtra",
    "Visakhapatnam": "Andhra Pradesh", "Vadodara": "Gujarat", "Bhubaneswar": "Odisha",
    "Nashik": "Maharashtra", "Mysuru": "Karnataka", "Vijayawada": "Andhra Pradesh",
    "Thiruvananthapuram": "Kerala",
}


def _num(x):
    x = (x or "").strip()
    if x == "":
        return None
    try:
        f = float(x)
        return int(f) if f == int(f) else round(f, 1)
    except ValueError:
        return None


def load_ledger(path=LEDGER):
    return list(csv.DictReader(open(path, newline="", encoding="utf-8", errors="replace")))


def history_path(platform):
    return os.path.join(ROOT, "data", platform, "history.csv")


def load_history(platform):
    p = history_path(platform)
    if not os.path.exists(p):
        return []
    return list(csv.DictReader(open(p, newline="", encoding="utf-8", errors="replace")))


_STATUS_RANK = {"price_captured": 2, "serviceable_no_jivo": 1, "not_serviceable": 0}


def census_date(rows, platform):
    """The date_ist with the most distinct pincodes for this platform = full census."""
    by_date = collections.defaultdict(set)
    for r in rows:
        if r["platform"] == platform:
            by_date[r["date_ist"]].add(r["pincode"])
    if not by_date:
        return None
    return max(by_date.items(), key=lambda kv: (len(kv[1]), kv[0]))[0]


def census(rows, platform):
    """Return (date, run_id, [deduped census rows]) for a platform's full-census footprint.

    Picks the full-census DATE (max distinct pincodes), then within it the latest RUN
    that still carries the full footprint, then keeps ONE row per pincode by status rank
    (price_captured > serviceable_no_jivo > not_serviceable).
    """
    d = census_date(rows, platform)
    if d is None:
        return None, None, []
    day = [r for r in rows if r["platform"] == platform and r["date_ist"] == d]
    by_run = collections.defaultdict(set)
    for r in day:
        by_run[r["run_id"]].add(r["pincode"])
    run_id = max(by_run.items(), key=lambda kv: (len(kv[1]), kv[0]))[0]
    run_rows = [r for r in day if r["run_id"] == run_id]
    best = {}
    for r in run_rows:
        pin = r["pincode"]
        if pin not in best or _STATUS_RANK.get(r["status"], 0) > _STATUS_RANK.get(best[pin]["status"], 0):
            best[pin] = r
    return d, run_id, list(best.values())


def pin_city_map(rows):
    """pincode -> city, from the ledger's own city column (authoritative per run)."""
    m = {}
    for r in rows:
        pin, city = r["pincode"], (r.get("city") or "").strip()
        if city:
            m.setdefault(pin, city)
    return m


def state_of(city):
    return CITY_STATE.get(city, "")


def freshest_history(platform):
    """(pincode, sku) -> freshest row dict {price,mrp,disc,stock,date,run,city}."""
    best = {}
    for r in load_history(platform):
        pin = (r.get("pincode") or "").strip()
        sku = (r.get("canonical_sku") or "").strip()
        d = r.get("date_ist") or ""
        if not pin or not sku:
            continue
        k = (pin, sku)
        if k not in best or d > best[k]["date"]:
            best[k] = {
                "price": _num(r.get("price")), "mrp": _num(r.get("mrp")),
                "disc": _num(r.get("discount_pct")),
                "stock": 1 if (r.get("in_stock") or "").strip().lower() in ("1", "true", "yes") else 0,
                "date": d, "run": r.get("run_id") or "",
                "city": (r.get("city") or "").strip(),
            }
    return best


def history_dates(platform):
    return sorted({(r.get("date_ist") or "") for r in load_history(platform)} - {""})


if __name__ == "__main__":
    rows = load_ledger()
    print("ledger rows:", len(rows))
    for p in QC_PLATFORMS + AMAZON_PLATFORMS:
        d, rid, cr = census(rows, p)
        serv = sum(1 for r in cr if r["status"] in SERVICEABLE)
        print(f"  {p:18} census={d} run={rid} census_rows={len(cr)} serviceable={serv}")
