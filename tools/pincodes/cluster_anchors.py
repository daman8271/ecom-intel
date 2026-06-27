#!/usr/bin/env python3
"""
cluster_anchors.py <City> — turn a city's geocoded pincodes into scrape ANCHORS.

The house model: each entry is an anchor pincode that REPRESENTS a compact cluster
of nearby real pincodes (one dark-store catchment). The scraper visits the anchor;
the cluster's pincodes[] are the coverage it accounts for.

  - excludes pincodes already covered anywhere (scratchpad/covered.json) -> NET-NEW only
  - greedy geographic clustering at ~DENSITY real pincodes per anchor (default 3)
  - anchor = the cluster member nearest the cluster centroid; its Nominatim coord is used
  - emits FULL-schema anchors -> scratchpad/<City>.anchors.json

Deterministic (seed = lowest pincode), no network, no LLM.
"""
import json, os, sys, math

OUT = "/tmp/claude-0/-root/a109040d-d8ca-400d-acfe-ff278d391f4e/scratchpad"
DENSITY = int(os.environ.get("DENSITY", "3"))

def hav(a, b):
    R = 6371.0
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dp = math.radians(b[0] - a[0]); dl = math.radians(b[1] - a[1])
    h = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 2*R*math.asin(min(1, math.sqrt(h)))

def main():
    city = sys.argv[1]
    geo = json.load(open(os.path.join(OUT, f"{city}.geo.json")))
    covered = set(json.load(open(os.path.join(OUT, "covered.json"))))
    pts = [g for g in geo if g["pincode"] not in covered]
    skipped = len(geo) - len(pts)

    unassigned = {g["pincode"]: g for g in pts}
    clusters = []
    while unassigned:
        seed = min(unassigned)                       # deterministic seed
        s = unassigned.pop(seed)
        others = sorted(unassigned.values(),
                        key=lambda g: hav((s["lat"], s["lon"]), (g["lat"], g["lon"])))
        members = [s] + others[:DENSITY - 1]
        for m in members[1:]:
            unassigned.pop(m["pincode"], None)
        clusters.append(members)

    anchors = []
    for members in clusters:
        clat = sum(m["lat"] for m in members) / len(members)
        clon = sum(m["lon"] for m in members) / len(members)
        a = min(members, key=lambda m: hav((clat, clon), (m["lat"], m["lon"])))
        pins = sorted(m["pincode"] for m in members)
        anchors.append({
            "city": city,
            "tier": 1,
            "pincode": a["pincode"],
            "locality": a["locality"],
            "landmark": f"{a['locality']}, {city}, {a['pincode']}, India",
            "lat": a["lat"],
            "lon": a["lon"],
            "represents": len(pins),
            "pincodes": pins,
        })
    anchors.sort(key=lambda x: x["pincode"])
    json.dump(anchors, open(os.path.join(OUT, f"{city}.anchors.json"), "w"), indent=1)
    real = sum(a["represents"] for a in anchors)
    print(json.dumps({
        "city": city,
        "geocoded_in_bbox": len(geo),
        "already_covered_skipped": skipped,
        "net_new_real_pincodes": real,
        "anchors": len(anchors),
        "density": round(real/len(anchors), 2) if anchors else 0,
    }, indent=1))

if __name__ == "__main__":
    main()
