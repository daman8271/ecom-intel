#!/usr/bin/env python3
"""Honest per-platform x per-city pincode coverage vs the 25-city universe.

'Covered' = distinct pincodes that actually appear in a platform's scraped
history (real data rows), intersected with each city's authoritative
district-defined pincode set. National-price platforms (flipkart/amazon/
bigbasket, pincode='-') have NO pincode granularity and are reported separately.

Usage: python3 coverage_matrix.py
"""
import csv
import json
import functools
from collections import defaultdict

BASE = "/opt/ecom-intel"
DIR = f"{BASE}/docs/pincodes"
rows = list(csv.DictReader(open(f"{DIR}/drr_pincode.csv", newline="", encoding="utf-8", errors="replace")))


def U(x):
    return x.strip().upper()


def by_district(state, *ds):
    s = {d.upper() for d in ds}
    return lambda r: U(r["StateName"]) == state and U(r["District"]) in s


def by_state(state):
    return lambda r: U(r["StateName"]) == state


def by_division(div):
    return lambda r: U(r["DivisionName"]) == div


SPEC = [
    ("Mumbai", by_district("MAHARASHTRA", "MUMBAI", "MUMBAI SUBURBAN")),
    ("Delhi", by_state("DELHI")),
    ("Bengaluru", by_district("KARNATAKA", "BENGALURU URBAN")),
    ("Hyderabad", by_district("TELANGANA", "HYDERABAD")),
    ("Chennai", by_district("TAMIL NADU", "CHENNAI")),
    ("Pune", by_district("MAHARASHTRA", "PUNE")),
    ("Ahmedabad", by_district("GUJARAT", "AHMADABAD")),
    ("Kolkata", by_district("WEST BENGAL", "KOLKATA")),
    ("Surat", by_district("GUJARAT", "SURAT")),
    ("Noida", by_district("UTTAR PRADESH", "GAUTAM BUDDHA NAGAR")),
    ("Gurugram", by_district("HARYANA", "GURUGRAM")),
    ("Jaipur", by_district("RAJASTHAN", "JAIPUR")),
    ("Lucknow", by_district("UTTAR PRADESH", "LUCKNOW")),
    ("Chandigarh", by_district("CHANDIGARH", "CHANDIGARH")),
    ("Kochi", by_district("KERALA", "ERNAKULAM")),
    ("Indore", by_district("MADHYA PRADESH", "INDORE")),
    ("Coimbatore", by_district("TAMIL NADU", "COIMBATORE")),
    ("Nagpur", by_district("MAHARASHTRA", "NAGPUR")),
    ("Visakhapatnam", by_division("VISAKHAPATNAM DIVISION")),
    ("Vadodara", by_district("GUJARAT", "VADODARA")),
    ("Bhubaneswar", by_district("ODISHA", "KHORDHA")),
    ("Nashik", by_district("MAHARASHTRA", "NASHIK")),
    ("Mysuru", by_district("KARNATAKA", "MYSURU")),
    ("Vijayawada", by_division("VIJAYAWADA DIVISION")),
    ("Thiruvananthapuram", by_district("KERALA", "THIRUVANANTHAPURAM")),
]

# city -> set of pincodes ; pincode -> city
city_pins = {}
pin_city = {}
for name, pred in SPEC:
    pins = {r["Pincode"].strip() for r in rows if pred(r) and r["Pincode"].strip()}
    city_pins[name] = pins
    for p in pins:
        pin_city.setdefault(p, name)  # first wins (sets are disjoint here)

UNIVERSE = set(pin_city)  # 1885

PINCODE_PLATFORMS = ["flipkart-minutes", "blinkit", "zepto", "amazon-fresh", "amazon-now"]
NATIONAL_PLATFORMS = ["flipkart", "amazon", "bigbasket"]


def latest_and_core(p):
    h = list(csv.DictReader(open(f"{BASE}/data/{p}/history.csv")))
    dates = sorted({r["date_ist"] for r in h})
    last3 = dates[-3:]
    sets = {dt: {r["pincode"].strip() for r in h if r["date_ist"] == dt
                 and r["pincode"].strip() and r["pincode"].strip() != "-"} for dt in last3}
    latest = sets[last3[-1]]
    core = functools.reduce(lambda a, b: a & b, sets.values()) if sets else set()
    return last3[-1], latest, core


# gather coverage
platform_latest = {}
for p in PINCODE_PLATFORMS:
    dt, latest, core = latest_and_core(p)
    platform_latest[p] = (dt, latest, core)

# matrix: city x platform = covered distinct pins in latest run
print("=== HONEST pincode coverage: distinct scraped pincodes per city per platform (latest run) ===\n")
hdr = f"{'City':20s} {'univ':>4} | " + " ".join(f"{p[:8]:>8s}" for p in PINCODE_PLATFORMS) + f" | {'ANYplat':>7}"
print(hdr)
print("-" * len(hdr))
col_tot = defaultdict(int)
any_union_total = 0
for name, _ in SPEC:
    cset = city_pins[name]
    cells = []
    any_union = set()
    for p in PINCODE_PLATFORMS:
        cov = platform_latest[p][1] & cset
        cells.append(len(cov))
        col_tot[p] += len(cov)
        any_union |= cov
    any_union_total += len(any_union)
    cellstr = " ".join(f"{c:>8d}" if c else f"{'.':>8s}" for c in cells)
    print(f"{name:20s} {len(cset):>4d} | {cellstr} | {len(any_union):>7d}")
print("-" * len(hdr))
totrow = " ".join(f"{col_tot[p]:>8d}" for p in PINCODE_PLATFORMS)
print(f"{'TOTAL (in 25 cities)':20s} {len(UNIVERSE):>4d} | {totrow} | {any_union_total:>7d}")

print("\n=== Per-platform honesty summary ===")
print(f"{'platform':18s} {'latest':>7} {'in25cty':>8} {'outside':>8} {'stablecore':>11} {'anchors':>8} {'claimed':>8}")
for p in PINCODE_PLATFORMS:
    dt, latest, core = platform_latest[p]
    anc = json.load(open(f"{BASE}/platforms/{p}/pincodes.json"))
    nanchor = len({x['pincode'] for x in anc if isinstance(x, dict) and 'pincode' in x})
    claimed = set()
    for x in anc:
        if isinstance(x, dict):
            claimed |= set(x.get('pincodes', [x.get('pincode')]))
    in25 = latest & UNIVERSE
    print(f"{p:18s} {len(latest):>7d} {len(in25):>8d} {len(latest-UNIVERSE):>8d} {len(core):>11d} {nanchor:>8d} {len(claimed):>8d}")

print("\nNATIONAL platforms (single price, pincode='-', NO pincode-level coverage):")
for p in NATIONAL_PLATFORMS:
    print(f"  {p}: national price only")
