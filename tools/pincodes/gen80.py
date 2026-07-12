"""Full-coverage list generator (goal #80; spec:
docs/superpowers/specs/2026-07-11-pincode-coverage-80pct-design.md, owner-
upgraded 2026-07-12 to 100% of every city universe).

Dry-run (default) prints the per-cell coverage table and asserts every cell
is full; --apply writes the lists (each original saved as .bak-20260712).
"""
import json
import os
import shutil
import sys

import universe_guide24 as U
from cluster import cluster

ROOT = "/opt/ecom-intel"
CSV = f"{ROOT}/docs/pincodes/drr_pincode.csv"
BAK = ".bak-20260712"
CITY_MAP = {"Bangalore": "Bengaluru", "Mysore": "Mysuru"}  # config-side names
PLAIN = ["blinkit", "zepto", "flipkart-minutes"]
AMAZON = ["amazon-fresh", "amazon-now"]

# One-off Nominatim results for pins the India Post CSV carries no coords for
# (2026-07-12). Pins absent here fall back to the nearest numeric neighbour
# pin's coordinate within the same city (adjacent PINs = adjacent offices).
OVERRIDE_COORDS = {
    "571316": (12.0461829, 76.9119543),
    "571442": (12.0907933, 77.0133564),
}


def _load(p):
    return json.load(open(p))


def _coord(city, pin, uni):
    m = uni[city]["meta"][pin]
    if m["lat"] is not None:
        return m["lat"], m["lon"]
    if pin in OVERRIDE_COORDS:
        return OVERRIDE_COORDS[pin]
    known = sorted((p, mm["lat"], mm["lon"])
                   for p, mm in uni[city]["meta"].items()
                   if mm["lat"] is not None)
    if not known:
        return None, None
    near = min(known, key=lambda t: abs(int(t[0]) - int(pin)))
    return near[1], near[2]


def _entry(city, pin, uni):
    lat, lon = _coord(city, pin, uni)
    return {"city": CITY_MAP.get(city, city), "pincode": pin, "tier": 1,
            "represents": 1, "pincodes": [pin],
            "lat": lat, "lon": lon,
            "locality": uni[city]["meta"][pin]["locality"]}


def expand_plain(existing, targets, uni):
    have = ({e["pincode"] for e in existing}
            | {p for e in existing for p in e.get("pincodes", [])})
    out = list(existing)
    for city, pins in targets.items():
        for p in pins:
            if p not in have:
                out.append(_entry(city, p, uni))
                have.add(p)
    return out


def amazon_tail(core, targets, uni):
    core_pins = {e["pincode"] for e in core}
    return expand_plain([], {c: [p for p in pins if p not in core_pins]
                            for c, pins in targets.items()}, uni)


def expand_instamart(existing, targets, uni):
    covered = {p for a in existing for p in a.get("pincodes", [a["pincode"]])}
    new = []
    for city, pins in targets.items():
        pts = []
        for p in pins:
            if p in covered:
                continue
            lat, lon = _coord(city, p, uni)
            if lat is None:
                continue
            pts.append({"pincode": p, "lat": lat, "lon": lon,
                        "locality": uni[city]["meta"][p]["locality"]})
        for a in cluster(pts, density=3):
            a["city"] = CITY_MAP.get(city, city)
            new.append(a)
    return new


def main(apply=False):
    uni = U.build(CSV)
    lists = {p: _load(f"{ROOT}/platforms/{p}/pincodes.daily.json")
             for p in PLAIN + AMAZON}
    bb = _load(f"{ROOT}/platforms/bigbasket/pincodes_jivo.json")
    inst = _load(f"{ROOT}/platforms/instamart/pincodes.json")
    tracked = ({e["pincode"] for l in lists.values() for e in l}
               | {e["pincode"] for e in bb}
               | {p for a in inst for p in a.get("pincodes", [a["pincode"]])})
    targets = U.select_targets(uni, tracked, pct=1.0)

    new_plain = {p: expand_plain(lists[p], targets, uni) for p in PLAIN}
    tails = {p: amazon_tail(lists[p], targets, uni) for p in AMAZON}
    bb_have = {e["pincode"] for e in bb}
    bb_new = list(bb)
    for c, pins in targets.items():
        for p in pins:
            if p not in bb_have:
                e = _entry(c, p, uni)
                e.pop("represents"), e.pop("pincodes")
                e["pricematch"] = False
                bb_new.append(e)
                bb_have.add(p)
    inst_new = list(inst) + expand_instamart(inst, targets, uni)

    eff = {p: {e["pincode"] for e in new_plain[p]} for p in PLAIN}
    eff |= {p: {e["pincode"] for e in lists[p]} | {e["pincode"] for e in tails[p]}
            for p in AMAZON}
    eff["bigbasket-svc"] = {e["pincode"] for e in bb_new}
    eff["instamart"] = {x for a in inst_new
                        for x in a.get("pincodes", [a["pincode"]])}

    bad = []
    for pl in sorted(eff):
        row = []
        for c in sorted(uni):
            v = len(eff[pl] & uni[c]["pins"]) / len(uni[c]["pins"])
            row.append(f"{c[:4]}={v:.0%}")
            if v < 0.999:
                bad.append((pl, c, round(v, 4)))
        print(f"{pl:16s} " + " ".join(row))
    print("sizes:", {p: len(v) for p, v in new_plain.items()},
          {f"{p}-tail": len(v) for p, v in tails.items()},
          "bb", len(bb_new), "inst-anchors", len(inst_new))
    if bad:
        sys.exit(f"CELLS NOT FULL: {bad}")
    print("ALL CELLS FULL (100%) ✓")
    if not apply:
        print("dry-run only (pass --apply to write)")
        return

    def write(path, data):
        if os.path.exists(path) and not os.path.exists(path + BAK):
            shutil.copy2(path, path + BAK)
        tmp = path + ".tmp"
        json.dump(data, open(tmp, "w"), ensure_ascii=False, indent=0)
        os.replace(tmp, path)

    for p in PLAIN:
        write(f"{ROOT}/platforms/{p}/pincodes.daily.json", new_plain[p])
    for p in AMAZON:
        write(f"{ROOT}/platforms/{p}/pincodes.daily.tail.json", tails[p])
    write(f"{ROOT}/platforms/bigbasket/pincodes_jivo.json", bb_new)
    write(f"{ROOT}/platforms/instamart/pincodes.json", inst_new)
    print("APPLIED")


if __name__ == "__main__":
    main(apply="--apply" in sys.argv)
