import os, sys
from collections import defaultdict

def matrix(rows, city_pins, date=None):
    seen = defaultdict(lambda: defaultdict(lambda: {"covered": set(), "serviceable": set(), "attempted": set()}))
    for r in rows:
        if date and r["date_ist"] != date:
            continue
        c, p, pin, st = r["city"], r["platform"], r["pincode"], r["status"]
        cell = seen[c][p]
        cell["attempted"].add(pin)
        if st == "price_captured":
            cell["covered"].add(pin); cell["serviceable"].add(pin)
        elif st == "serviceable_no_jivo":
            cell["serviceable"].add(pin)
    out = {}
    for c, plats in seen.items():
        out[c] = {p: {k: len(v) for k, v in cell.items()} for p, cell in plats.items()}
    return out

def coverage_pct(m, city_pins):
    res = {}
    for c, plats in m.items():
        denom = len(city_pins.get(c, [])) or 1
        res[c] = round(100 * max((cell["covered"] for cell in plats.values()), default=0) / denom, 1)
    return res

if __name__ == "__main__":
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "pincodes"))
    from universe25 import build_universe
    from ledger import read_ledger
    cp, _ = build_universe(os.path.join(os.path.dirname(__file__), "..", "..", "docs", "pincodes", "drr_pincode.csv"))
    m = matrix(read_ledger(), cp, date=(sys.argv[1] if len(sys.argv) > 1 else None))
    for city in cp:
        cells = m.get(city, {})
        line = " ".join(f"{p}={cells.get(p,{}).get('covered',0)}" for p in ["flipkart-minutes","blinkit","zepto"])
        print(f"{city:20s} univ={len(cp[city]):4d}  {line}")
