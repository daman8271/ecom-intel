#!/usr/bin/env python3
"""
Compute EXACT distinct-pincode counts for India (national) and 12 city-groups
from the canonical India Post "All India Pincode Directory".

Dataset: dropdevrahul/pincodes-india  (raw mirror of data.gov.in All India
Pincode Directory; columns: CircleName,RegionName,DivisionName,OfficeName,
Pincode,OfficeType,Delivery,District,StateName,Latitude,Longitude).

Usage:
    python3 compute_pincodes.py /path/to/pincode.csv

A pincode is a 6-digit string. City-group counts are DISTINCT-pincode set
UNIONS over the matched (StateName, District) strings (NOT naive sums), so a
pincode shared by two districts is counted once. Each city also reports a
PREFIX cross-check = distinct pincodes whose first 3 digits are in the city's
known prefix set.
"""
import csv, sys
from collections import defaultdict

PATH = sys.argv[1] if len(sys.argv) > 1 else "drr_pincode.csv"

# (state, district) -> set(pincodes) ;  prefix(3) -> set(pincodes)
dp = defaultdict(set)
pre = defaultdict(set)
allpins = set()
rows = 0
with open(PATH, newline="", encoding="utf-8", errors="replace") as f:
    for row in csv.DictReader(f):
        p = (row["Pincode"] or "").strip()
        if not (len(p) == 6 and p.isdigit()):
            continue
        rows += 1
        st = (row["StateName"] or "").strip().upper()
        di = (row["District"] or "").strip().upper()
        dp[(st, di)].add(p)
        pre[p[:3]].add(p)
        allpins.add(p)

def union(*pairs):
    s = set()
    for pr in pairs:
        s |= dp.get(pr, set())
    return s

def prefixset(*prefixes):
    s = set()
    for px in prefixes:
        s |= pre.get(px, set())
    return s

print(f"rows(valid 6-digit records): {rows}")
print(f"NATIONAL distinct pincodes : {len(allpins)}")
print("=" * 72)

# Each entry: label -> (list of (state,district) pairs, prefix-crosscheck list)
CITY = {
 "Bengaluru (Bangalore Urban)":      ([("KARNATAKA","BENGALURU URBAN")], ["560"]),
 "Bengaluru +Rural (metro)":         ([("KARNATAKA","BENGALURU URBAN"),
                                       ("KARNATAKA","BENGALURU RURAL")], ["560","562"]),
 "Surat (district)":                 ([("GUJARAT","SURAT")], ["394","395"]),
 "Ahmedabad (district)":             ([("GUJARAT","AHMADABAD")], ["380","382"]),
 "Hyderabad (district)":             ([("TELANGANA","HYDERABAD")], ["500"]),
 "Hyderabad metro (+Medchal+RangaReddy)":
                                     ([("TELANGANA","HYDERABAD"),
                                       ("TELANGANA","MEDCHAL MALKAJGIRI"),
                                       ("TELANGANA","RANGA REDDY")], ["500","501","502"]),
 "Chennai (district)":               ([("TAMIL NADU","CHENNAI")], ["600"]),
 "Chennai metro (+Tiruvallur+Kanchipuram+Chengalpattu)":
                                     ([("TAMIL NADU","CHENNAI"),
                                       ("TAMIL NADU","THIRUVALLUR"),
                                       ("TAMIL NADU","KANCHIPURAM"),
                                       ("TAMIL NADU","CHENGALPATTU")], ["600","601","602","603"]),
 "Mumbai (City+Suburban)":           ([("MAHARASHTRA","MUMBAI"),
                                       ("MAHARASHTRA","MUMBAI SUBURBAN")], ["400"]),
 "Delhi (entire NCT, all 11 districts)":
                                     ([("DELHI","CENTRAL"),("DELHI","EAST"),
                                       ("DELHI","NEW DELHI"),("DELHI","NORTH"),
                                       ("DELHI","NORTH EAST"),("DELHI","NORTH WEST"),
                                       ("DELHI","SHAHDARA"),("DELHI","SOUTH"),
                                       ("DELHI","SOUTH EAST"),("DELHI","SOUTH WEST"),
                                       ("DELHI","WEST")], ["110"]),
 "Chandigarh (UT)":                  ([("CHANDIGARH","CHANDIGARH")], ["160"]),
 "Chandigarh tricity (+Mohali+Panchkula)":
                                     ([("CHANDIGARH","CHANDIGARH"),
                                       ("PUNJAB","S.A.S NAGAR"),
                                       ("HARYANA","PANCHKULA")], ["160","140","134"]),
 "Kolkata (district)":               ([("WEST BENGAL","KOLKATA")], ["700"]),
 "Kolkata metro (+N24Pgs+S24Pgs+Howrah)":
                                     ([("WEST BENGAL","KOLKATA"),
                                       ("WEST BENGAL","24 PARAGANAS NORTH"),
                                       ("WEST BENGAL","24 PARAGANAS SOUTH"),
                                       ("WEST BENGAL","HOWRAH")], ["700","711","743"]),
 "NCR: Gurugram":                    ([("HARYANA","GURUGRAM")], ["122"]),
 "NCR: Faridabad":                   ([("HARYANA","FARIDABAD")], ["121"]),
 "NCR: Noida/Gautam Buddha Nagar":   ([("UTTAR PRADESH","GAUTAM BUDDHA NAGAR")], ["201"]),
 "NCR: Ghaziabad":                   ([("UTTAR PRADESH","GHAZIABAD")], ["201","245"]),
 "NCR four towns COMBINED":          ([("HARYANA","GURUGRAM"),("HARYANA","FARIDABAD"),
                                       ("UTTAR PRADESH","GAUTAM BUDDHA NAGAR"),
                                       ("UTTAR PRADESH","GHAZIABAD")], ["122","121","201","245"]),
 "Pune (district)":                  ([("MAHARASHTRA","PUNE")], ["411","412"]),
 "Jaipur (district)":                ([("RAJASTHAN","JAIPUR")], ["302","303"]),
}

for label, (pairs, prefixes) in CITY.items():
    s = union(*pairs)
    px = prefixset(*prefixes)
    pairstr = " + ".join(f"{st}/{di}" for st, di in pairs)
    print(f"{label}")
    print(f"   district-filter distinct pincodes : {len(s)}")
    print(f"   prefix x-check {prefixes} distinct : {len(px)}")
    print(f"   matched strings: {pairstr}")
    print()
