import csv

def _U(x): return x.strip().upper()
def _district(state, *ds):
    s = {d.upper() for d in ds}
    return lambda r: _U(r["StateName"]) == state and _U(r["District"]) in s
def _state(state): return lambda r: _U(r["StateName"]) == state
def _division(div): return lambda r: _U(r["DivisionName"]) == div

CITY_SPEC = [
    ("Mumbai", _district("MAHARASHTRA","MUMBAI","MUMBAI SUBURBAN")),
    ("Delhi", _state("DELHI")),
    ("Bengaluru", _district("KARNATAKA","BENGALURU URBAN")),
    ("Hyderabad", _district("TELANGANA","HYDERABAD")),
    ("Chennai", _district("TAMIL NADU","CHENNAI")),
    ("Pune", _district("MAHARASHTRA","PUNE")),
    ("Ahmedabad", _district("GUJARAT","AHMADABAD")),
    ("Kolkata", _district("WEST BENGAL","KOLKATA")),
    ("Surat", _district("GUJARAT","SURAT")),
    ("Noida", _district("UTTAR PRADESH","GAUTAM BUDDHA NAGAR")),
    ("Gurugram", _district("HARYANA","GURUGRAM")),
    ("Jaipur", _district("RAJASTHAN","JAIPUR")),
    ("Lucknow", _district("UTTAR PRADESH","LUCKNOW")),
    ("Chandigarh", _district("CHANDIGARH","CHANDIGARH")),
    ("Kochi", _district("KERALA","ERNAKULAM")),
    ("Indore", _district("MADHYA PRADESH","INDORE")),
    ("Coimbatore", _district("TAMIL NADU","COIMBATORE")),
    ("Nagpur", _district("MAHARASHTRA","NAGPUR")),
    ("Visakhapatnam", _division("VISAKHAPATNAM DIVISION")),
    ("Vadodara", _district("GUJARAT","VADODARA")),
    ("Bhubaneswar", _district("ODISHA","KHORDHA")),
    ("Nashik", _district("MAHARASHTRA","NASHIK")),
    ("Mysuru", _district("KARNATAKA","MYSURU")),
    ("Vijayawada", _division("VIJAYAWADA DIVISION")),
    ("Thiruvananthapuram", _district("KERALA","THIRUVANANTHAPURAM")),
]

def build_universe(csv_path):
    rows = list(csv.DictReader(open(csv_path, newline="", encoding="utf-8", errors="replace")))
    city_pins, pin_city = {}, {}
    for name, pred in CITY_SPEC:
        pins = {r["Pincode"].strip() for r in rows if pred(r) and r["Pincode"].strip()}
        city_pins[name] = pins
        for p in pins:
            pin_city.setdefault(p, name)
    return city_pins, pin_city

def UNIVERSE_PINS(city_pins):
    return set().union(*city_pins.values())
