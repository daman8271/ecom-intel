#!/usr/bin/env python3
# Merge N zepto shard result.jsons -> one result.json. perPin/allRows are per-pincode
# and disjoint across shards, so concat; summary counts re-derived; partial = any partial.
import json, sys
def load(p):
    try: return json.load(open(p))
    except Exception: return None
outs = [x for x in (load(p) for p in sys.argv[2:]) if x]
if not outs:
    sys.exit("merge: no shard outputs")
perPin, allRows, partial = [], [], False
for o in outs:
    perPin += o.get("perPin", [])
    allRows += o.get("allRows", [])
    partial = partial or bool(o.get("partial"))
# summary: prefer summing numeric fields from shard summaries; keep first non-numeric verbatim
summary = {}
base = outs[0].get("summary", {}) or {}
for k, v in base.items():
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        summary[k] = sum((o.get("summary", {}) or {}).get(k, 0) or 0 for o in outs)
    else:
        summary[k] = v
# recompute the load-bearing counts directly from merged rows (authoritative)
summary["pincodes_total"] = len(perPin)
summary["total_rows"] = len(allRows)
withj = sum(1 for p in perPin if (p.get("rows") or p.get("jivo_rows") or p.get("with_jivo")))
if withj: summary["pincodes_with_jivo"] = withj
json.dump({"summary": summary, "perPin": perPin, "allRows": allRows, "partial": partial},
          open(sys.argv[1], "w"))
print(f"merged {len(outs)} shards -> {len(perPin)} pins / {len(allRows)} rows / partial={partial}")
