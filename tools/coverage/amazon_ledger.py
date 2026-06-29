#!/usr/bin/env python3
"""Emit coverage-ledger rows for an Amazon platform from its merged result.json.

Amazon's per-pincode result carries an explicit `serviceable` bool + `rows`
(Jivo products found), so classification is direct (no history reconciliation):
  serviceable=False          -> not_serviceable
  serviceable=True, rows>0    -> price_captured
  serviceable=True, rows==0   -> serviceable_no_jivo

  usage: python3 amazon_ledger.py <platform> <run_id> <date_ist> [result.json] [ledger.csv]
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from ledger import record, DEFAULT

def emit(platform, run_id, date_ist, result_path=None, ledger_path=DEFAULT):
    base = f"/opt/ecom-intel/platforms/{platform}"
    result_path = result_path or f"{base}/result.json"
    d = json.load(open(result_path))
    n = {"price_captured": 0, "serviceable_no_jivo": 0, "not_serviceable": 0}
    for x in d.get("perPin", []):
        pin = str(x.get("pincode", "")).strip()
        if not pin:
            continue
        rows = x.get("rows") or []
        if not x.get("serviceable"):
            st = "not_serviceable"
        elif rows:
            st = "price_captured"
        else:
            st = "serviceable_no_jivo"
        price = ""
        for r in rows:
            v = str(r.get("sale") or r.get("price") or "").strip()
            if v:
                price = v; break
        record(platform, pin, x.get("city", ""), st, run_id, date_ist,
               sku_count=len(rows), price_seen=price, path=ledger_path)
        n[st] += 1
    print(f"[{platform}] ledger: {sum(n.values())} rows  "
          f"(price_captured={n['price_captured']} serviceable_no_jivo={n['serviceable_no_jivo']} "
          f"not_serviceable={n['not_serviceable']})")
    return n

if __name__ == "__main__":
    a = sys.argv
    emit(a[1], a[2], a[3], a[4] if len(a) > 4 else None, a[5] if len(a) > 5 else DEFAULT)
