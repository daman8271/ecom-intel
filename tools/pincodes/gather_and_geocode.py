#!/usr/bin/env python3
"""
gather_and_geocode.py — authoritative pincode gather + accurate geocoding.

For each target city (tools/pincodes/cities.json):
  1. enumerate UNIQUE real pincodes from the on-box geonames dump
     (/root/ingest/IN_geonames.txt) by postal prefix,
  2. geocode each via OSM Nominatim (cached, rate-limited, UA per policy),
  3. keep only pincodes whose accurate coord falls inside the city metro bbox
     (this is the geographic filter that drops far-rural same-prefix codes).

Output: scratchpad/<City>.geo.json  -> [{pincode,locality,district,lat,lon,src}]
Geocode cache persisted to tools/pincodes/geocode_cache.json (reused across runs).

No LLM, no fabrication — every pincode is a real postal code, every coord is from
Nominatim (or geonames fallback, flagged via "src").
"""
import json, os, sys, time, urllib.parse, urllib.request, collections

HERE = os.path.dirname(os.path.abspath(__file__))
GEONAMES = "/root/ingest/IN_geonames.txt"
CACHE = os.path.join(HERE, "geocode_cache.json")
OUT = "/tmp/claude-0/-root/a109040d-d8ca-400d-acfe-ff278d391f4e/scratchpad"
UA = "jivo-ecom-pincode-coverage/1.0 (manav.aisub@gmail.com)"
NOMINATIM = "https://nominatim.openstreetmap.org/search"

def load_cities():
    return json.load(open(os.path.join(HERE, "cities.json")))

def geonames_by_prefix(prefixes):
    """unique pincode -> (locality, district, glat, glon) — first/best row per pincode."""
    want = tuple(prefixes)
    best = {}
    with open(GEONAMES, encoding="utf-8", errors="replace") as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) < 12:
                continue
            pin = p[1].strip()
            if len(pin) != 6 or not pin.isdigit() or not pin.startswith(want):
                continue
            try:
                glat, glon = float(p[9]), float(p[10])
            except ValueError:
                continue
            try:
                acc = int(p[11])
            except (ValueError, IndexError):
                acc = 0
            # keep the highest-accuracy row per pincode
            if pin not in best or acc > best[pin][4]:
                best[pin] = (p[2].strip(), p[5].strip(), glat, glon, acc)
    return best

def load_cache():
    if os.path.exists(CACHE):
        try:
            return json.load(open(CACHE))
        except Exception:
            return {}
    return {}

def save_cache(c):
    json.dump(c, open(CACHE, "w"))

def nominatim(pin, cache):
    if pin in cache:
        return cache[pin]
    q = urllib.parse.urlencode({"postalcode": pin, "country": "India",
                                "format": "json", "limit": 1})
    req = urllib.request.Request(NOMINATIM + "?" + q, headers={"User-Agent": UA})
    res = None
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            data = json.load(r)
        if data:
            res = [float(data[0]["lat"]), float(data[0]["lon"])]
    except Exception as e:
        sys.stderr.write(f"  nominatim fail {pin}: {e}\n")
    cache[pin] = res          # cache misses too (None) to avoid re-hammering
    save_cache(cache)
    time.sleep(1.1)           # Nominatim usage policy: <=1 req/s
    return res

def in_bbox(lat, lon, bbox):
    return bbox[0] <= lat <= bbox[1] and bbox[2] <= lon <= bbox[3]

def main():
    cities = load_cities()
    only = sys.argv[1:] or list(cities)
    cache = load_cache()
    os.makedirs(OUT, exist_ok=True)
    for city in only:
        cfg = cities[city]
        rows = geonames_by_prefix(cfg["prefixes"])
        kept, dropped, fell_back = [], 0, 0
        print(f"\n=== {city}: {len(rows)} candidate pincodes from geonames "
              f"(prefixes {cfg['prefixes']}) ===", flush=True)
        for pin in sorted(rows):
            loc, dist, glat, glon, _acc = rows[pin]
            coord = nominatim(pin, cache)
            src = "nominatim"
            if not coord:
                coord, src, fell_back = [glat, glon], "geonames", fell_back + 1
            lat, lon = coord
            if not in_bbox(lat, lon, cfg["bbox"]):
                dropped += 1
                continue
            kept.append({"pincode": pin, "locality": loc or city, "district": dist,
                         "lat": round(lat, 5), "lon": round(lon, 5), "src": src})
        json.dump(kept, open(os.path.join(OUT, f"{city}.geo.json"), "w"), indent=1)
        print(f"    kept {len(kept)} in-bbox  (dropped {dropped} out-of-metro, "
              f"{fell_back} geonames-fallback)  target>={cfg['target']}", flush=True)
    print("\nDONE gather+geocode.")

if __name__ == "__main__":
    main()
