#!/usr/bin/env python3
"""Merge per-city Amazon coverage chunk outputs into one result.json.

The chunked runner (amazon_chunked.sh) writes one {summary,perPin,allRows} file
per city under platforms/<p>/.cov-chunks/out/. This concatenates them into the
platform's result.json (the shape build_excel.py expects) and recomputes summary.

  usage: python3 amazon_merge.py <amazon-fresh|amazon-now>
"""
import csv, glob, json, os, sys

def main(p):
    base = f"/opt/ecom-intel/platforms/{p}"
    files = sorted(glob.glob(f"{base}/.cov-chunks/out/*.json"))
    perPin, allRows, wall = [], [], 0
    for f in files:
        try:
            d = json.load(open(f))
        except Exception as e:
            print(f"  WARN skip {f}: {e}"); continue
        perPin += d.get("perPin", [])
        allRows += d.get("allRows", [])
        wall += d.get("summary", {}).get("wall_s", 0)
    serviceable = sum(1 for x in perPin if x.get("serviceable"))
    with_jivo = sum(1 for x in perPin if x.get("rows"))
    skus = {r.get("canonical") or r.get("canonical_sku") or r.get("sku_raw") for r in allRows}
    skus.discard(None)
    summary = {"pincodes_total": len(perPin), "pincodes_serviceable": serviceable,
               "pincodes_with_jivo": with_jivo, "total_rows": len(allRows),
               "unique_skus": len(skus), "wall_s": wall, "merged_cities": len(files)}
    out = {"summary": summary, "perPin": perPin, "allRows": allRows}
    json.dump(out, open(f"{base}/result.json", "w"), indent=1)
    print(f"[{p}] merged {len(files)} cities -> result.json | pincodes={len(perPin)} "
          f"serviceable={serviceable} with_jivo={with_jivo} rows={len(allRows)} skus={len(skus)}")
    return summary

if __name__ == "__main__":
    main(sys.argv[1])
