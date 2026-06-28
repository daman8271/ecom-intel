import csv, os

STATUSES = {"price_captured", "serviceable_no_jivo", "not_serviceable", "error"}
HEADER = ["platform", "pincode", "city", "date_ist", "run_id", "status", "sku_count", "price_seen"]
DEFAULT = os.path.join(os.path.dirname(__file__), "..", "..", "data", "coverage", "ledger.csv")

def record(platform, pincode, city, status, run_id, date_ist, sku_count=0, price_seen="", path=DEFAULT):
    if status not in STATUSES:
        raise ValueError(f"bad status {status!r}; allowed {sorted(STATUSES)}")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    new = not os.path.exists(path)
    with open(path, "a", newline="") as f:
        w = csv.writer(f)
        if new:
            w.writerow(HEADER)
        w.writerow([platform, pincode, city, date_ist, run_id, status, sku_count, price_seen])

def read_ledger(path=DEFAULT):
    if not os.path.exists(path):
        return []
    return list(csv.DictReader(open(path, newline="")))
