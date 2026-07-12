"""24-city India Post universe for the coverage-guide matrix.

Separate from universe25.py, which belongs to the pincode-leads programme and
uses a different city list. City definitions mirror the live
jivo-city-coverage-guide.vercel.app matrix (district buckets, June-2024 CSV).
"""
import csv
import math
import statistics


INDIA_BBOX = (6.0, 38.5, 68.0, 98.0)
MAX_CITY_DISTANCE_KM = 250.0


def _U(x):
    return x.strip().upper()


def _district(state, *ds):
    s = {d.upper() for d in ds}
    return lambda r: _U(r["StateName"]) == state and _U(r["District"]) in s


def _state(state):
    return lambda r: _U(r["StateName"]) == state


CITY_SPEC24 = [
    ("Delhi", _state("DELHI")),
    ("Mumbai", _district("MAHARASHTRA", "MUMBAI", "MUMBAI SUBURBAN")),
    ("Pune", _district("MAHARASHTRA", "PUNE")),
    ("Nagpur", _district("MAHARASHTRA", "NAGPUR")),
    ("Nashik", _district("MAHARASHTRA", "NASHIK")),
    ("Noida", _district("UTTAR PRADESH", "GAUTAM BUDDHA NAGAR")),
    ("Lucknow", _district("UTTAR PRADESH", "LUCKNOW")),
    ("Ghaziabad", _district("UTTAR PRADESH", "GHAZIABAD")),
    ("Gurugram", _district("HARYANA", "GURUGRAM")),
    ("Faridabad", _district("HARYANA", "FARIDABAD")),
    ("Ludhiana", _district("PUNJAB", "LUDHIANA")),
    ("Amritsar", _district("PUNJAB", "AMRITSAR")),
    ("Jalandhar", _district("PUNJAB", "JALANDHAR")),
    ("Mohali", _district("PUNJAB", "S.A.S NAGAR")),
    ("Bangalore", _district("KARNATAKA", "BENGALURU URBAN")),
    ("Mysore", _district("KARNATAKA", "MYSURU")),
    ("Mangalore", _district("KARNATAKA", "DAKSHINA KANNADA")),
    ("Hyderabad", _district("TELANGANA", "HYDERABAD")),
    ("Kolkata", _district("WEST BENGAL", "KOLKATA")),
    ("Howrah", _district("WEST BENGAL", "HOWRAH")),
    ("Chandigarh", _state("CHANDIGARH")),
    ("Chennai", _district("TAMIL NADU", "CHENNAI")),
    ("Coimbatore", _district("TAMIL NADU", "COIMBATORE")),
    ("Madurai", _district("TAMIL NADU", "MADURAI")),
]


def _f(v):
    try:
        x = float(v)
        return x if math.isfinite(x) and x != 0 else None
    except (TypeError, ValueError):
        return None


def _valid_coord(lat, lon):
    return (
        lat is not None and lon is not None
        and INDIA_BBOX[0] <= lat <= INDIA_BBOX[1]
        and INDIA_BBOX[2] <= lon <= INDIA_BBOX[3]
    )


def _distance_km(a, b):
    lat1, lon1 = map(math.radians, a)
    lat2, lon2 = map(math.radians, b)
    dlat, dlon = lat2 - lat1, lon2 - lon1
    h = (math.sin(dlat / 2) ** 2
         + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2)
    return 2 * 6371.0088 * math.asin(min(1.0, math.sqrt(h)))


def _robust_city_center(rows):
    points = []
    for r in rows:
        lat, lon = _f(r.get("Latitude")), _f(r.get("Longitude"))
        if _valid_coord(lat, lon):
            points.append((lat, lon))
    if not points:
        return None
    center = (statistics.median(p[0] for p in points),
              statistics.median(p[1] for p in points))
    local = [p for p in points if _distance_km(center, p) <= MAX_CITY_DISTANCE_KM]
    if local:
        center = (statistics.median(p[0] for p in local),
                  statistics.median(p[1] for p in local))
    return center


def build(csv_path):
    rows = list(csv.DictReader(open(csv_path, newline="", encoding="utf-8",
                                    errors="replace")))
    out = {}
    for name, pred in CITY_SPEC24:
        city_rows = [r for r in rows if pred(r)]
        center = _robust_city_center(city_rows)
        pins, meta = set(), {}
        candidates = {}
        for r in city_rows:
            p = r["Pincode"].strip()
            if not p:
                continue
            pins.add(p)
            m = meta.setdefault(p, {"lat": None, "lon": None,
                                    "locality": r["OfficeName"].strip(),
                                    "urban": False})
            lat, lon = _f(r["Latitude"]), _f(r["Longitude"])
            if _valid_coord(lat, lon) and center is not None:
                distance = _distance_km(center, (lat, lon))
                if distance <= MAX_CITY_DISTANCE_KM:
                    candidates.setdefault(p, []).append((distance, lat, lon))
            if _U(r["OfficeType"]) in ("HO", "SO"):
                if not m["urban"]:
                    m["urban"] = True
                    m["locality"] = r["OfficeName"].strip()
        for p, values in candidates.items():
            _, lat, lon = min(values)
            meta[p]["lat"], meta[p]["lon"] = lat, lon
        out[name] = {"pins": pins, "meta": meta}
    return out


def city_centroid(city_data_entry):
    """Mean coordinate of a city's geo-known pins (fallback for pins whose
    CSV rows carry no usable Latitude/Longitude)."""
    pts = [(m["lat"], m["lon"]) for m in city_data_entry["meta"].values()
           if m["lat"] is not None]
    if not pts:
        return None, None
    return (sum(p[0] for p in pts) / len(pts),
            sum(p[1] for p in pts) / len(pts))


def select_targets(city_data, tracked, pct=1.0):
    """Per city: top ceil(pct*n) pins (pct=1.0 -> the full universe).
    Rank = already-tracked first, then urban (HO/SO), then rural (BO);
    pincode asc within each band — so scrapers hit proven pins first and
    any excluded remainder is the most-rural block."""
    tg = {}
    for city, d in city_data.items():
        n = len(d["pins"])
        take = min(n, -(-int(n * pct * 100) // 100))  # ceil, float-fuzz free
        take = max(take, -(-4 * n // 5))              # never below 80%
        ranked = sorted(d["pins"], key=lambda p: (
            0 if p in tracked else 1,
            0 if d["meta"][p]["urban"] else 1,
            p))
        tg[city] = ranked[:take]
    return tg
