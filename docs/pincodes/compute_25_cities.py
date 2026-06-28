#!/usr/bin/env python3
"""Exact distinct-pincode counts for the 25-city JIVO target list.

Counts distinct 6-digit PINs per city from the canonical India Post
All-India Pincode Directory, using India Post District strings (and, for the
two pre-reorg Andhra Pradesh mega-districts, the postal Division which is the
right city-level unit). Prints per-city counts, the naive sum, and the
distinct UNION across all 25 (the true "total pincodes for these areas").

Usage: python3 compute_25_cities.py drr_pincode.csv
Stdlib only; no secrets.
"""
import csv
import sys


def U(x):
    return x.strip().upper()


def main(path):
    rows = list(csv.DictReader(open(path, newline="", encoding="utf-8", errors="replace")))

    def by_district(state, *districts):
        ds = {d.upper() for d in districts}
        return lambda r: U(r["StateName"]) == state and U(r["District"]) in ds

    def by_state(state):
        return lambda r: U(r["StateName"]) == state

    def by_division(div):
        return lambda r: U(r["DivisionName"]) == div

    # (label, predicate, note)  — order = user's list
    spec = [
        ("Mumbai",             by_district("MAHARASHTRA", "MUMBAI", "MUMBAI SUBURBAN"), "City + Suburban districts"),
        ("Delhi",              by_state("DELHI"),                                       "entire NCT (11 districts)"),
        ("Bengaluru",          by_district("KARNATAKA", "BENGALURU URBAN"),             "Bengaluru Urban district"),
        ("Hyderabad",          by_district("TELANGANA", "HYDERABAD"),                   "Hyderabad district (metro 140 w/ Medchal+RangaReddy)"),
        ("Chennai",            by_district("TAMIL NADU", "CHENNAI"),                    "Chennai district (metro 214 w/ suburbs)"),
        ("Pune",               by_district("MAHARASHTRA", "PUNE"),                      "single district (city+PCMC+rural)"),
        ("Ahmedabad",          by_district("GUJARAT", "AHMADABAD"),                     "spelling AHMADABAD"),
        ("Kolkata",            by_district("WEST BENGAL", "KOLKATA"),                   "Kolkata district (metro 332 w/ 24-Pgs+Howrah)"),
        ("Surat",              by_district("GUJARAT", "SURAT"),                         ""),
        ("Noida",              by_district("UTTAR PRADESH", "GAUTAM BUDDHA NAGAR"),     "= Gautam Buddha Nagar district"),
        ("Gurugram",           by_district("HARYANA", "GURUGRAM"),                      "not 'Gurgaon'"),
        ("Jaipur",             by_district("RAJASTHAN", "JAIPUR"),                      "single district"),
        ("Lucknow",            by_district("UTTAR PRADESH", "LUCKNOW"),                 ""),
        ("Chandigarh",         by_district("CHANDIGARH", "CHANDIGARH"),                 "UT (tricity 66 w/ Mohali+Panchkula)"),
        ("Kochi",              by_district("KERALA", "ERNAKULAM"),                      "= Ernakulam district (> Kochi city)"),
        ("Indore",             by_district("MADHYA PRADESH", "INDORE"),                 ""),
        ("Coimbatore",         by_district("TAMIL NADU", "COIMBATORE"),                 ""),
        ("Nagpur",             by_district("MAHARASHTRA", "NAGPUR"),                    ""),
        ("Visakhapatnam",      by_division("VISAKHAPATNAM DIVISION"),                   "postal division (old 'district' bucket = 93)"),
        ("Vadodara",           by_district("GUJARAT", "VADODARA"),                      ""),
        ("Bhubaneswar",        by_district("ODISHA", "KHORDHA"),                        "= Khordha district"),
        ("Nashik",             by_district("MAHARASHTRA", "NASHIK"),                    ""),
        ("Mysuru",             by_district("KARNATAKA", "MYSURU"),                      ""),
        ("Vijayawada",         by_division("VIJAYAWADA DIVISION"),                      "postal division (Krishna district = 119)"),
        ("Thiruvananthapuram", by_district("KERALA", "THIRUVANANTHAPURAM"),            ""),
    ]

    national = {r["Pincode"].strip() for r in rows if r["Pincode"].strip()}
    print(f"NATIONAL distinct pincodes: {len(national)}\n")

    union = set()
    total_sum = 0
    print(f"{'#':>2}  {'City':22s} {'PINs':>5}   note")
    for i, (label, pred, note) in enumerate(spec, 1):
        pins = {r["Pincode"].strip() for r in rows if pred(r) and r["Pincode"].strip()}
        union |= pins
        total_sum += len(pins)
        print(f"{i:>2}. {label:22s} {len(pins):>5}   {note}")

    print()
    print(f"Naive SUM of the 25 city counts : {total_sum}")
    print(f"DISTINCT UNION across all 25    : {len(union)}  <-- total pincodes for these areas")
    print(f"Overlap removed by union        : {total_sum - len(union)}")
    print(f"Share of national 19,300        : {100*len(union)/len(national):.1f}%")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "drr_pincode.csv")
