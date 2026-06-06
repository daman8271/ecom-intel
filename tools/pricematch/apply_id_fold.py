#!/usr/bin/env python3
"""Apply a verified id_fold_proposal.json onto sku_map.json (idempotent enrichment).

Fills the listing ids/urls (blinkit prids, flipkart-minutes pids) that were unrecoverable
offline at map-build time, and attaches platform EANs where the scrape now exposes them.
Only touches entries whose CURRENT id is the canonical slug (the offline placeholder) or,
for bigbasket, whose id matches the proposal's id (EAN attach). Mappings are never changed —
only identity fields enriched. Safe to re-run after a fragments re-merge.

Usage: apply_id_fold.py <proposal.json> [sku_map.json]
"""
import json, sys, pathlib

HERE = pathlib.Path(__file__).parent
prop = json.loads(pathlib.Path(sys.argv[1]).read_text())
map_path = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else HERE / "sku_map.json"
sm = json.loads(map_path.read_text())

applied, skipped = [], []
for sku, entry in sm["skus"].items():
    for plat, le in (entry.get("platforms") or {}).items():
        p = prop.get(plat) or {}
        if not le or not p:
            continue
        cur = str(le.get("id") or "")
        # slug-placeholder match (blinkit / flipkart-minutes)
        if cur in p:
            new = p[cur]
            le["id"], le["url"] = new["id"], new["url"]
            le["id_folded"] = "2026-06-06 first post-patch run (gate-passed)"
            applied.append((sku, plat, new["id"]))
            continue
        # bigbasket: attach ean where ids agree
        for slug, new in p.items():
            if str(new.get("id")) == cur and new.get("ean") and not le.get("ean"):
                le["ean"] = new["ean"]
                le["id_folded"] = "ean attached 2026-06-06 (gate-passed)"
                applied.append((sku, plat, f"ean={new['ean']}"))

map_path.write_text(json.dumps(sm, indent=1, ensure_ascii=False))
print(f"applied {len(applied)}:")
for a in applied:
    print("  %-22s %-18s %s" % a)
