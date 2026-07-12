"""Greedy geographic anchor clustering — the house model from
cluster_anchors.py (deterministic seed = lowest pincode, anchor = member
nearest the cluster centroid), made importable and scratchpad-free."""
import math


def _hav(a, b):
    R = 6371.0
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dp = math.radians(b[0] - a[0])
    dl = math.radians(b[1] - a[1])
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(min(1, math.sqrt(h)))


def cluster(points, density=3):
    """points: [{"pincode","lat","lon","locality"}] -> full-schema anchors
    (caller stamps "city")."""
    unassigned = {p["pincode"]: p for p in points}
    anchors = []
    while unassigned:
        seed = unassigned.pop(min(unassigned))
        others = sorted(unassigned.values(),
                        key=lambda g: _hav((seed["lat"], seed["lon"]),
                                           (g["lat"], g["lon"])))
        members = [seed] + others[:density - 1]
        for m in members[1:]:
            unassigned.pop(m["pincode"], None)
        clat = sum(m["lat"] for m in members) / len(members)
        clon = sum(m["lon"] for m in members) / len(members)
        anchor = min(members, key=lambda m: _hav((clat, clon), (m["lat"], m["lon"])))
        anchors.append({"pincode": anchor["pincode"], "tier": 1,
                        "represents": len(members),
                        "pincodes": sorted(m["pincode"] for m in members),
                        "lat": anchor["lat"], "lon": anchor["lon"],
                        "locality": anchor["locality"]})
    return anchors
