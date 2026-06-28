import csv, json, os, sys
from collections import defaultdict
from universe25 import build_universe

WAVE1 = ["blinkit", "zepto", "flipkart-minutes"]
BASE = os.path.join(os.path.dirname(__file__), "..", "..")

def load_centroids(csv_path):
    acc = defaultdict(lambda: [0.0, 0.0, 0])
    for r in csv.DictReader(open(csv_path, newline="", encoding="utf-8", errors="replace")):
        p = r["Pincode"].strip()
        try:
            lat = float(r["Latitude"]); lon = float(r["Longitude"])
        except (ValueError, KeyError):
            continue
        if not p or lat == 0.0 or lon == 0.0:
            continue
        a = acc[p]; a[0] += lat; a[1] += lon; a[2] += 1
    return {p: (a[0]/a[2], a[1]/a[2]) for p, a in acc.items() if a[2]}

def gen_config(city_pins, pin_city, centroids, cities=None):
    out = []
    for city, pins in city_pins.items():
        if cities and city not in cities:
            continue
        for p in sorted(pins):
            lat, lon = centroids.get(p, (None, None))
            out.append({"city": city, "pincode": p, "tier": 1,
                        "represents": 1, "pincodes": [p], "lat": lat, "lon": lon})
    return out

def write_platform_configs(csv_path):
    cp, pc = build_universe(csv_path)
    cents = load_centroids(csv_path)
    cfg = gen_config(cp, pc, cents)
    for plat in WAVE1:
        path = os.path.join(BASE, "platforms", plat, "pincodes.full25.json")
        with open(path, "w") as f:
            json.dump(cfg, f, indent=2)
        print(f"wrote {len(cfg)} pincodes -> {path}")

if __name__ == "__main__":
    write_platform_configs(sys.argv[1] if len(sys.argv) > 1 else
        os.path.join(BASE, "docs", "pincodes", "drr_pincode.csv"))
