#!/usr/bin/env python3
"""
propagate.py [--apply] — append the new-city anchors into every live pincode config.

Reads scratchpad/<City>.anchors.json for all configured cities and appends them to:
  FULL schema (city,tier,pincode,locality,landmark,lat,lon,represents,pincodes[]):
    /root/pincodes.json                          (master, source-of-truth hygiene)
    platforms/amazon-fresh/pincodes.json         (LIVE in run_all)
    platforms/amazon-now/pincodes.json           (LIVE in run_all)
    platforms/blinkit/pincodes.json              (LIVE in run_all)
    platforms/zepto/pincodes.json                (LIVE in run_all)
  THIN schema (city,tier,pincode,locality,landmark,lat,lon):
    platforms/flipkart-minutes/pincodes.json     (LIVE in run_all)
  BB schema (city,pincode,locality,lat,lon,tier,pricematch) — ANCHOR pincodes only (PAID):
    platforms/bigbasket/pincodes_jivo.json       (LIVE, paid QuickCommerce pull)

Skipped on purpose: instamart (not in run_all; off-box Mac collector), amazon/flipkart
core + bigbasket/pincodes.json (pincode-AGNOSTIC, national).

Idempotent: an anchor already present (by pincode) in a file is not re-added.
Without --apply it's a DRY RUN (prints planned deltas, writes nothing).
Backs up each file once to <file>.prepincode.bak before first mutation.
"""
import json, os, sys, glob, shutil

ROOT = "/opt/ecom-intel"
OUT = "/tmp/claude-0/-root/a109040d-d8ca-400d-acfe-ff278d391f4e/scratchpad"
APPLY = "--apply" in sys.argv

FULL = [
    "/root/pincodes.json",
    f"{ROOT}/platforms/amazon-fresh/pincodes.json",
    f"{ROOT}/platforms/amazon-now/pincodes.json",
    f"{ROOT}/platforms/blinkit/pincodes.json",
    f"{ROOT}/platforms/zepto/pincodes.json",
]
THIN = [f"{ROOT}/platforms/flipkart-minutes/pincodes.json"]
BBJV = f"{ROOT}/platforms/bigbasket/pincodes_jivo.json"

def load(fp):
    return json.load(open(fp))

def existing_pins(data):
    return {str(e.get("pincode")) for e in data if isinstance(e, dict)}

def full_entry(a):
    return {"city": a["city"], "tier": a["tier"], "pincode": a["pincode"],
            "locality": a["locality"], "landmark": a["landmark"],
            "lat": a["lat"], "lon": a["lon"],
            "represents": a["represents"], "pincodes": a["pincodes"]}

def thin_entry(a):
    return {"city": a["city"], "tier": a["tier"], "pincode": a["pincode"],
            "locality": a["locality"], "landmark": a["landmark"],
            "lat": a["lat"], "lon": a["lon"]}

def bb_entry(a):
    return {"city": a["city"], "pincode": a["pincode"], "locality": a["locality"],
            "lat": a["lat"], "lon": a["lon"], "tier": a["tier"], "pricematch": False}

def append_to(fp, new_entries, label):
    data = load(fp)
    have = existing_pins(data)
    add = [e for e in new_entries if str(e["pincode"]) not in have]
    print(f"  {label:50s} {len(data):5d} -> {len(data)+len(add):5d}  (+{len(add)})")
    if APPLY and add:
        bak = fp + ".prepincode.bak"
        if not os.path.exists(bak):
            shutil.copy2(fp, bak)
        data.extend(add)
        json.dump(data, open(fp, "w"), indent=1, ensure_ascii=False)
        json.load(open(fp))   # validate round-trip
    return len(add)

def main():
    anchors = []
    for fp in sorted(glob.glob(os.path.join(OUT, "*.anchors.json"))):
        anchors.extend(load(fp))
    if not anchors:
        sys.exit("no anchor files found in scratchpad — run cluster_anchors first")
    real = sum(a["represents"] for a in anchors)
    print(f"{'APPLY' if APPLY else 'DRY-RUN'}: {len(anchors)} new anchors representing "
          f"{real} real pincodes across {len({a['city'] for a in anchors})} cities\n")
    for fp in FULL:
        append_to(fp, [full_entry(a) for a in anchors], os.path.relpath(fp, ROOT))
    for fp in THIN:
        append_to(fp, [thin_entry(a) for a in anchors], os.path.relpath(fp, ROOT))
    append_to(BBJV, [bb_entry(a) for a in anchors],
              os.path.relpath(BBJV, ROOT) + " (PAID, anchors only)")
    if not APPLY:
        print("\nDRY-RUN only. Re-run with --apply to write.")

if __name__ == "__main__":
    main()
