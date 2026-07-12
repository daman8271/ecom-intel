"""24-city India Post universe for the coverage-guide matrix.

Separate from universe25.py, which belongs to the pincode-leads programme and
uses a different city list. City definitions mirror the live
jivo-city-coverage-guide.vercel.app matrix (district buckets, June-2024 CSV).
"""
import csv
import math


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


def build(csv_path):
    rows = list(csv.DictReader(open(csv_path, newline="", encoding="utf-8",
                                    errors="replace")))
    out = {}
    for name, pred in CITY_SPEC24:
        pins, meta = set(), {}
        for r in rows:
            p = r["Pincode"].strip()
            if not p or not pred(r):
                continue
            pins.add(p)
            m = meta.setdefault(p, {"lat": None, "lon": None,
                                    "locality": r["OfficeName"].strip(),
                                    "urban": False})
            if m["lat"] is None:
                la, lo = _f(r["Latitude"]), _f(r["Longitude"])
                if la is not None and lo is not None:
                    m["lat"], m["lon"] = la, lo
            if _U(r["OfficeType"]) in ("HO", "SO"):
                if not m["urban"]:
                    m["urban"] = True
                    m["locality"] = r["OfficeName"].strip()
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
