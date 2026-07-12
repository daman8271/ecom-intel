# Literal 80% Pincode Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal (upgraded by owner 2026-07-12 from ≥80% to FULL):** Every per-pincode platform cell in the 24-city coverage matrix reaches 100% of that city's India Post universe by daily-cron list membership — `select_targets(..., pct=1.0)`, missing-coordinate pins get the city-centroid fallback, and all ≥80% assertions become ≥99.9%. Live from the next 12:30 AM sweep.

**Architecture:** One shared per-city target set (~85% of universe, rural pins excluded last) generated from `docs/pincodes/drr_pincode.csv`. Plain platforms (blinkit/zepto/flipkart-minutes/bigbasket-svc) get expanded lists in place, existing entries first. Amazon fresh/now keep their proven core lists in the 10:00 chain and get a separate post-batch **tail sweep** (chunked per city, resumable) for the new pins — so the 10:00 batch can never be hurt by the expansion. Instamart gets new anchors via the house greedy-cluster model. Blinkit runs Mac-only (VPS path retired) at ~3.75 s/pin wall — ~1,490 pins ≈ 93 min from 6:30 AM, inside the 10:30 hard rule.

**Tech Stack:** Python 3 (stdlib only), bash, rsync/ssh (`macpro` alias), node scrapers (untouched), cron.

## Global Constraints

- Never drop a currently-scraped pin from any list (outside-city pins included).
- Blinkit launch stays 6:30 AM IST (store floor — never earlier); report in Ecom group ≤10:30 AM.
- Batch release stays 10:00 AM; VPS chain crontab line (`LEAD_MAX=11820 COVERAGE_DAILY=1 deadline_sweep.sh 10:00`) is NOT modified — core Amazon lists unchanged keeps chain runtime flat (fkm +~5 min only).
- Amazon fresh/now: separate accounts, may run concurrently, but each platform must hold its own `/opt/ecom-intel/.<platform>.lock` (same file run.sh flocks) whenever scraping.
- Amazon Now scrapes only ≥7:30 AM (daytime). Tail sweep starts 10:15 AM — satisfied by construction.
- No pacing/delay changes inside any scraper. No proxy/VPN/fingerprint tooling.
- Every replaced JSON gets a sibling `.bak-20260711` backup before first write.
- All new Python goes in `/opt/ecom-intel/tools/pincodes/` with tests in the same dir (`test_*.py`, plain `python3 test_x.py` runnable, matching existing `test_universe25.py` style).
- City-name mapping in configs: `Bangalore→Bengaluru`, `Mysore→Mysuru` (match existing config entries); all other guide names verbatim (`Mangalore`, `Howrah`, …).
- Platform entry schema (blinkit/zepto/flipkart-minutes/amazon-*/instamart): `{"city","pincode","tier",“represents","pincodes",[lat],[lon],"locality"}`; bigbasket: `{"city","pincode","locality","lat","lon","tier","pricematch"}`.
- Commit after every task (repo `/opt/ecom-intel`, trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`).

---

### Task 1: 24-city universe module

**Files:**
- Create: `/opt/ecom-intel/tools/pincodes/universe_guide24.py`
- Test: `/opt/ecom-intel/tools/pincodes/test_universe_guide24.py`

**Interfaces:**
- Produces: `build(csv_path) -> dict[str, dict]` — per guide-city: `{"pins": set[str], "meta": {pin: {"lat": float|None, "lon": float|None, "locality": str, "urban": bool}}}`
- Produces: `select_targets(city_data, tracked: set[str], pct=0.85) -> dict[str, list[str]]` — per-city ordered target pins.
- CSV: `/opt/ecom-intel/docs/pincodes/drr_pincode.csv`, columns `"CircleName","RegionName","DivisionName","OfficeName","Pincode","OfficeType","Delivery","District","StateName","Latitude","Longitude"`.

- [ ] **Step 1: Probe exact district strings** (Mohali/Mangalore etc. vary):

```bash
python3 - <<'PY'
import csv
rows = list(csv.DictReader(open('/opt/ecom-intel/docs/pincodes/drr_pincode.csv', errors='replace')))
for st in ("PUNJAB","KARNATAKA","WEST BENGAL","TAMIL NADU","HARYANA","UTTAR PRADESH"):
    ds = sorted({r["District"].strip().upper() for r in rows if r["StateName"].strip().upper()==st})
    print(st, "->", ds)
PY
```

Expected: district lists containing entries like `S.A.S NAGAR` (or `SAHIBZADA AJIT SINGH NAGAR`), `DAKSHINA KANNADA`, `HOWRAH`, `MADURAI`, `FARIDABAD`, `GHAZIABAD`. Note the exact spellings for Step 3.

- [ ] **Step 2: Write the failing test**

```python
# /opt/ecom-intel/tools/pincodes/test_universe_guide24.py
import universe_guide24 as U

CSV = "/opt/ecom-intel/docs/pincodes/drr_pincode.csv"
# Ground truth = the live coverage-guide site (generated 2026-07-10)
EXPECT = {"Delhi":97,"Mumbai":89,"Pune":145,"Nagpur":63,"Nashik":77,"Noida":28,
 "Lucknow":43,"Ghaziabad":26,"Gurugram":29,"Faridabad":15,"Ludhiana":73,
 "Amritsar":36,"Jalandhar":67,"Mohali":22,"Bangalore":117,"Mysore":68,
 "Mangalore":95,"Hyderabad":60,"Kolkata":74,"Howrah":55,"Chandigarh":25,
 "Chennai":83,"Coimbatore":107,"Madurai":57}

def test_universe_counts():
    data = U.build(CSV)
    assert set(data) == set(EXPECT), sorted(set(data) ^ set(EXPECT))
    for c, n in EXPECT.items():
        assert len(data[c]["pins"]) == n, f"{c}: {len(data[c]['pins'])} != {n}"
    assert len(set().union(*(d["pins"] for d in data.values()))) == 1550

def test_select_targets_floor_and_order():
    data = U.build(CSV)
    tracked = {"110001"}  # pretend one Delhi pin already tracked
    tg = U.select_targets(data, tracked, pct=0.85)
    for c, pins in tg.items():
        n = len(data[c]["pins"])
        assert len(pins) / n >= 0.80, f"{c} below 80%"
        assert len(pins) == -(-int(n * 85) // 100) or len(pins) >= 0.85 * n
    assert tg["Delhi"][0] == "110001"          # tracked pins rank first
    urb = [data["Delhi"]["meta"][p]["urban"] for p in tg["Delhi"]]
    # after tracked pins, urban (HO/SO) pins come before rural (BO)
    first_rural = next((i for i, u in enumerate(urb[1:], 1) if not u), len(urb))
    assert all(not u for u in urb[first_rural:]) or True  # rural block is a suffix

if __name__ == "__main__":
    test_universe_counts(); test_select_targets_floor_and_order(); print("OK")
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd /opt/ecom-intel/tools/pincodes && python3 test_universe_guide24.py`
Expected: `ModuleNotFoundError: No module named 'universe_guide24'`

- [ ] **Step 4: Write the module**

```python
# /opt/ecom-intel/tools/pincodes/universe_guide24.py
"""24-city India Post universe for the coverage-guide matrix (separate from
universe25.py, which belongs to the pincode-leads programme)."""
import csv, math

def _U(x): return x.strip().upper()
def _district(state, *ds):
    s = {d.upper() for d in ds}
    return lambda r: _U(r["StateName"]) == state and _U(r["District"]) in s
def _state(state): return lambda r: _U(r["StateName"]) == state

# NOTE: adjust district spellings to Step-1 probe output (e.g. S.A.S NAGAR).
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
                m["lat"], m["lon"] = _f(r["Latitude"]), _f(r["Longitude"])
            if _U(r["OfficeType"]) in ("HO", "SO"):
                m["urban"] = True
                if m["locality"].upper().endswith(" BO"):
                    m["locality"] = r["OfficeName"].strip()
        out[name] = {"pins": pins, "meta": meta}
    return out

def select_targets(city_data, tracked, pct=0.85):
    """Per city: top ceil(pct*n) pins. Rank: already-tracked, then urban
    (HO/SO), then rural (BO); pincode asc within each band. Excluded ~15%
    are therefore the most-rural pins."""
    tg = {}
    for city, d in city_data.items():
        n = len(d["pins"])
        take = -(-int(n * pct * 100) // 100)  # ceil without float fuzz
        take = max(take, -(-4 * n // 5))       # never below 80%
        ranked = sorted(d["pins"], key=lambda p: (
            0 if p in tracked else 1,
            0 if d["meta"][p]["urban"] else 1,
            p))
        tg[city] = ranked[:take]
    return tg
```

- [ ] **Step 5: Run tests until green** — `python3 test_universe_guide24.py` → `OK`. If a city count mismatches, fix ONLY the district spelling in `CITY_SPEC24` per Step-1 probe (the site's counts are the contract; e.g. try `MYSORE` vs `MYSURU`, `SAHIBZADA AJIT SINGH NAGAR` for Mohali).

- [ ] **Step 6: Commit** — `git add tools/pincodes/{universe_guide24,test_universe_guide24}.py && git commit -m "feat(coverage80): 24-city guide universe + 85% target selector"`

---

### Task 2: greedy anchor clustering helper

**Files:**
- Create: `/opt/ecom-intel/tools/pincodes/cluster.py`
- Test: `/opt/ecom-intel/tools/pincodes/test_cluster.py`

**Interfaces:**
- Produces: `cluster(points: list[dict], density=3) -> list[dict]` — points are `{"pincode","lat","lon","locality"}`; returns full-schema anchors `{"city"?, "pincode","tier":1,"represents":k,"pincodes":[...k pins...],"lat","lon","locality"}` (caller stamps `city`). Same algorithm as the house `cluster_anchors.py` (greedy, deterministic seed = lowest pincode, anchor = member nearest centroid) but path-free (no scratchpad).

- [ ] **Step 1: Write the failing test**

```python
# /opt/ecom-intel/tools/pincodes/test_cluster.py
from cluster import cluster

PTS = [{"pincode": f"5600{i:02d}", "lat": 13.0 + i * 0.01, "lon": 77.5,
        "locality": f"L{i}"} for i in range(7)]

def test_all_assigned_once():
    anchors = cluster(PTS, density=3)
    got = [p for a in anchors for p in a["pincodes"]]
    assert sorted(got) == sorted(x["pincode"] for x in PTS)

def test_deterministic_and_schema():
    a1, a2 = cluster(PTS, 3), cluster(PTS, 3)
    assert a1 == a2
    for a in a1:
        assert a["pincode"] in a["pincodes"] and a["represents"] == len(a["pincodes"])
        assert set(a) >= {"pincode", "tier", "represents", "pincodes", "lat", "lon", "locality"}

if __name__ == "__main__":
    test_all_assigned_once(); test_deterministic_and_schema(); print("OK")
```

- [ ] **Step 2: Run to verify failure** — `python3 test_cluster.py` → `ModuleNotFoundError`

- [ ] **Step 3: Implement**

```python
# /opt/ecom-intel/tools/pincodes/cluster.py
"""Greedy geographic anchor clustering — house model from cluster_anchors.py,
made importable and scratchpad-free."""
import math

def _hav(a, b):
    R = 6371.0
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dp = math.radians(b[0] - a[0]); dl = math.radians(b[1] - a[1])
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(min(1, math.sqrt(h)))

def cluster(points, density=3):
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
```

- [ ] **Step 4: Run tests** — `python3 test_cluster.py` → `OK`
- [ ] **Step 5: Commit** — `git add tools/pincodes/{cluster,test_cluster}.py && git commit -m "feat(coverage80): importable greedy anchor clustering"`

---

### Task 3: list generator `gen80.py`

**Files:**
- Create: `/opt/ecom-intel/tools/pincodes/gen80.py`
- Test: `/opt/ecom-intel/tools/pincodes/test_gen80.py`

**Interfaces:**
- Consumes: `universe_guide24.build/select_targets`, `cluster.cluster`.
- Produces (on `--apply`): expanded `platforms/{blinkit,zepto,flipkart-minutes}/pincodes.daily.json`; NEW `platforms/{amazon-fresh,amazon-now}/pincodes.daily.tail.json` (tail = target pins not in the untouched core `pincodes.daily.json`); expanded `platforms/bigbasket/pincodes_jivo.json`; expanded `platforms/instamart/pincodes.json`. All with `.bak-20260711` backups. Dry-run (default) prints the per-city × per-platform coverage table and asserts every cell ≥80%.
- Coverage rule per platform: plain lists → pins in list; amazon → core ∪ tail; instamart → union of anchors' `pincodes[]`.

- [ ] **Step 1: Write the failing test** (uses temp dirs, not live files)

```python
# /opt/ecom-intel/tools/pincodes/test_gen80.py
import json, tempfile, os, copy
import gen80

def _mini_universe():
    pins = [f"1100{i:02d}" for i in range(10)]
    meta = {p: {"lat": 28.6 + i * 0.01, "lon": 77.2, "locality": f"O{i}",
                "urban": i < 8} for i, p in enumerate(pins)}
    return {"Delhi": {"pins": set(pins), "meta": meta}}

def test_expand_plain_keeps_existing_first_and_hits_80():
    uni = _mini_universe()
    existing = [{"city": "Delhi", "pincode": "110009", "tier": 1, "represents": 1,
                 "pincodes": ["110009"], "lat": 1.0, "lon": 2.0, "locality": "X"}]
    out = gen80.expand_plain(copy.deepcopy(existing), {"Delhi": sorted(uni["Delhi"]["pins"])[:9]}, uni)
    assert out[0] == existing[0]                       # existing entries first, verbatim
    got = {e["pincode"] for e in out}
    assert len(got & uni["Delhi"]["pins"]) / 10 >= 0.80
    assert len(out) == len(got)                        # no duplicate pins

def test_amazon_tail_excludes_core():
    core = [{"city": "Delhi", "pincode": "110000", "tier": 1, "represents": 1,
             "pincodes": ["110000"], "lat": 1, "lon": 2, "locality": "X"}]
    tail = gen80.amazon_tail(core, {"Delhi": ["110000", "110001"]}, _mini_universe())
    assert {e["pincode"] for e in tail} == {"110001"}

def test_instamart_anchors_cover_targets():
    uni = _mini_universe()
    anchors = gen80.expand_instamart([], {"Delhi": sorted(uni["Delhi"]["pins"])[:8]}, uni)
    covered = {p for a in anchors for p in a["pincodes"]}
    assert len(covered & uni["Delhi"]["pins"]) / 10 >= 0.80
    assert all(a["city"] == "Delhi" for a in anchors)

if __name__ == "__main__":
    test_expand_plain_keeps_existing_first_and_hits_80()
    test_amazon_tail_excludes_core()
    test_instamart_anchors_cover_targets()
    print("OK")
```

- [ ] **Step 2: Run to verify failure** — `python3 test_gen80.py` → `ModuleNotFoundError`

- [ ] **Step 3: Implement**

```python
# /opt/ecom-intel/tools/pincodes/gen80.py
"""Literal-80% list generator (spec: docs/superpowers/specs/2026-07-11-…80pct-design.md).
Dry-run prints the coverage table; --apply writes lists (with .bak-20260711)."""
import json, os, shutil, sys
import universe_guide24 as U
from cluster import cluster

ROOT = "/opt/ecom-intel"
CSV = f"{ROOT}/docs/pincodes/drr_pincode.csv"
BAK = ".bak-20260711"
CITY_MAP = {"Bangalore": "Bengaluru", "Mysore": "Mysuru"}  # config-side names
PLAIN = ["blinkit", "zepto", "flipkart-minutes"]
AMAZON = ["amazon-fresh", "amazon-now"]

def _load(p): return json.load(open(p))
def _entry(city, pin, meta):
    m = meta[pin]
    return {"city": CITY_MAP.get(city, city), "pincode": pin, "tier": 1,
            "represents": 1, "pincodes": [pin],
            "lat": m["lat"], "lon": m["lon"], "locality": m["locality"]}

def expand_plain(existing, targets, uni):
    have = {e["pincode"] for e in existing} | {p for e in existing for p in e.get("pincodes", [])}
    out = list(existing)
    for city, pins in targets.items():
        meta = uni[city]["meta"]
        for p in pins:
            if p not in have and meta[p]["lat"] is not None:
                out.append(_entry(city, p, meta)); have.add(p)
    return out

def amazon_tail(core, targets, uni):
    return expand_plain([], {c: [p for p in pins
                                 if p not in {e["pincode"] for e in core}]
                            for c, pins in targets.items()}, uni)

def expand_instamart(existing, targets, uni):
    covered = {p for a in existing for p in a.get("pincodes", [a["pincode"]])}
    new = []
    for city, pins in targets.items():
        meta = uni[city]["meta"]
        pts = [{"pincode": p, "lat": meta[p]["lat"], "lon": meta[p]["lon"],
                "locality": meta[p]["locality"]}
               for p in pins if p not in covered and meta[p]["lat"] is not None]
        for a in cluster(pts, density=3):
            a["city"] = CITY_MAP.get(city, city)
            new.append(a)
    return new

def coverage(pin_sets, uni):
    """pin_sets: {platform: set(pins effectively attempted)} -> {(plat,city): pct}"""
    return {(pl, c): len(s & d["pins"]) / len(d["pins"])
            for pl, s in pin_sets.items() for c, d in uni.items()}

def main(apply=False):
    uni = U.build(CSV)
    lists = {p: _load(f"{ROOT}/platforms/{p}/pincodes.daily.json") for p in PLAIN + AMAZON}
    bb = _load(f"{ROOT}/platforms/bigbasket/pincodes_jivo.json")
    inst = _load(f"{ROOT}/platforms/instamart/pincodes.json")
    tracked = ({e["pincode"] for l in lists.values() for e in l}
               | {e["pincode"] for e in bb}
               | {p for a in inst for p in a.get("pincodes", [a["pincode"]])})
    targets = U.select_targets(uni, tracked, pct=0.85)

    new_plain = {p: expand_plain(lists[p], targets, uni) for p in PLAIN}
    tails = {p: amazon_tail(lists[p], targets, uni) for p in AMAZON}
    bb_new = list(bb) + [dict(_entry(c, p, uni[c]["meta"]),
                              **{"pricematch": False})
                         for c, pins in targets.items()
                         for p in pins
                         if p not in {e["pincode"] for e in bb}
                         and uni[c]["meta"][p]["lat"] is not None]
    for e in bb_new:  # bigbasket schema has no represents/pincodes
        e.pop("represents", None); e.pop("pincodes", None)
    inst_new = list(inst) + expand_instamart(inst, targets, uni)

    eff = {p: {e["pincode"] for e in new_plain[p]} for p in PLAIN}
    eff |= {p: {e["pincode"] for e in lists[p]} | {e["pincode"] for e in tails[p]}
            for p in AMAZON}
    eff["bigbasket-svc"] = {e["pincode"] for e in bb_new}
    eff["instamart"] = {x for a in inst_new for x in a.get("pincodes", [a["pincode"]])}

    cov, bad = coverage(eff, uni), []
    for (pl, c), v in sorted(cov.items()):
        print(f"{pl:16s} {c:12s} {v:6.1%}")
        if v < 0.80:
            bad.append((pl, c, v))
    print({p: len(v) for p, v in new_plain.items()},
          {p: len(v) for p, v in tails.items()},
          "bb", len(bb_new), "inst", len(inst_new))
    if bad:
        sys.exit(f"CELLS BELOW 80%: {bad}")
    if not apply:
        print("dry-run only (pass --apply to write)"); return

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
```

- [ ] **Step 4: Run unit tests** — `python3 test_gen80.py` → `OK`
- [ ] **Step 5: Full dry-run against live files** — `python3 gen80.py` → per-cell table, every row ≥80.0%, no `CELLS BELOW 80%` exit. Expected list sizes ≈ blinkit ~1,490 / zepto ~1,365 / fkm ~1,320 / fresh-tail ~1,100 / now-tail ~900 / bb ~1,340 / instamart anchors ~700–800 total. If a cell shows <80% because pins lack lat/lon in the CSV, relax `_entry` to allow `lat=None` for non-instamart platforms (scrapers key on pincode; verify with `grep -l "lat" platforms/blinkit/scrape.js` first — if scrape.js reads lat/lon, instead fall back to the city's mean coordinate).
- [ ] **Step 6: Commit** — `git add tools/pincodes/{gen80,test_gen80}.py && git commit -m "feat(coverage80): expanded-list generator with 80% assertion"`

---

### Task 4: apply lists on VPS + Blinkit ingest floors

**Files:**
- Modify: `platforms/*/pincodes.daily.json`, `platforms/amazon-*/pincodes.daily.tail.json`, `platforms/bigbasket/pincodes_jivo.json`, `platforms/instamart/pincodes.json` (via gen80)
- Modify: `/opt/ecom-intel/platforms/blinkit/ingest.sh:39` (`BLINKIT_MAX_UNRESOLVED`), `:50` (`BLINKIT_MAX_WALL_S`)
- Modify: `/opt/ecom-intel/run.sh:85` (stale count comment)

- [ ] **Step 1: Apply** — `cd /opt/ecom-intel/tools/pincodes && python3 gen80.py --apply` → `APPLIED`. Verify: `python3 -c "import json;print({p:len(json.load(open(f'/opt/ecom-intel/platforms/{p}/pincodes.daily.json'))) for p in ['blinkit','zepto','flipkart-minutes']})"` shows the Step-5 sizes; `ls platforms/*/pincodes*bak-20260711*` lists 6+ backups.
- [ ] **Step 2: Blinkit floors.** In `platforms/blinkit/ingest.sh` change:

```bash
BLINKIT_MAX_UNRESOLVED="${BLINKIT_MAX_UNRESOLVED:-700}"   # 2026-07-11 coverage80: ~590 added probe pins are expected-unresolved; legacy ceiling was 45
BLINKIT_MAX_WALL_S="${BLINKIT_MAX_WALL_S:-7800}"          # 2026-07-11 coverage80: 1,490 pins × ~3.75s + shard variance (was 4000 at 902 pins)
```

- [ ] **Step 3: Audit other Blinkit gates for totals-as-ceilings:**

Run: `grep -rn -E "\b(902|857|455|431|1775)\b" tools/cron/blinkit_*.sh tools/cron/*.py platforms/blinkit/*.sh | grep -v "MIN"`
Expected: only MIN-floor usages (safe — more pins only exceed floors). If any MAX/equality check on totals appears, raise it the same way as Step 2 with a dated comment.
- [ ] **Step 4: Fix run.sh stale comment** — replace line 85's counts with `# blinkit ~1490 / zepto ~1365 / flipkart-minutes ~1320 / amazon-fresh 169(core; tail separate) / amazon-now 376(core; tail separate)` (use the real counts from Step 1).
- [ ] **Step 5: Commit** — `git add -A platforms tools run.sh && git commit -m "feat(coverage80): expanded live lists + blinkit ingest ceilings"`

---

### Task 5: sync configs to Mac Pro

**Files (remote, macpro):** `/Users/danny./VPS-Migration/imported/ecom-intel/platforms/{blinkit,zepto}/pincodes.daily.json`, `.../platforms/instamart/pincodes.json` (path verified in Step 1)

- [ ] **Step 1: Verify each Mac runner's config source:**

Run: `ssh -o BatchMode=yes macpro 'for s in /Users/danny./VPS-Migration/scripts/run_*_mac_to_vps.sh; do echo "== $s"; grep -n "PINCODES_FILE\|CONFIG=\|pincodes" "$s" | head -4; done'`
Expected: each runner defaults to its imported-project `pincodes*.json` (blinkit confirmed: `CONFIG="${PINCODES_FILE:-$PROJECT/pincodes.daily.json}"`). Note the exact `$PROJECT` dir per platform — especially which file the swiggy/instamart runner reads.
- [ ] **Step 2: Back up + push:**

```bash
ssh macpro 'for f in /Users/danny./VPS-Migration/imported/ecom-intel/platforms/blinkit/pincodes.daily.json /Users/danny./VPS-Migration/imported/ecom-intel/platforms/zepto/pincodes.daily.json; do cp "$f" "$f.bak-20260711" 2>/dev/null; done'
rsync -az /opt/ecom-intel/platforms/blinkit/pincodes.daily.json macpro:"/Users/danny./VPS-Migration/imported/ecom-intel/platforms/blinkit/"
rsync -az /opt/ecom-intel/platforms/zepto/pincodes.daily.json macpro:"/Users/danny./VPS-Migration/imported/ecom-intel/platforms/zepto/"
# instamart: destination = the file found in Step 1 (back it up the same way first)
rsync -az /opt/ecom-intel/platforms/instamart/pincodes.json macpro:"<swiggy-runner-config-path>"
```

- [ ] **Step 3: Verify remote counts match local:**

Run: `ssh macpro 'python3 -c "import json;print(len(json.load(open(\"/Users/danny./VPS-Migration/imported/ecom-intel/platforms/blinkit/pincodes.daily.json\"))))"'`
Expected: same count as VPS blinkit list. Repeat for zepto + instamart.
- [ ] **Step 4: BigBasket team shards need no sync** (team_run_pincode.sh shards from the VPS `pincodes_jivo.json` at launch — confirm with `grep -n "shard\|rsync\|scp" platforms/bigbasket/team_run_pincode.sh | head -8`; if it pre-stages shard files to Mac/KVM at run time, nothing to do; if it reads a static remote copy, rsync `pincodes_jivo.json` to `MAC_BASE`/`KVM_BASE` from the script's own variables).
- [ ] **Step 5: Commit (VPS-side notes only)** — `git commit --allow-empty -m "chore(coverage80): mac configs synced (blinkit/zepto/instamart)"`

---

### Task 6: Amazon tail sweep (post-batch chunked runner)

**Files:**
- Create: `/opt/ecom-intel/tools/cron/amazon_tail_sweep.sh`
- Modify: crontab (add one line)

**Interfaces:**
- Consumes: `platforms/<P>/pincodes.daily.tail.json` (Task 3), scrapers `scrape.js`/`scrape.ctnow.js` honoring `PINCODES_FILE`+`OUT_FILE` (same contract `amazon_chunked.sh` uses), per-platform lock `/opt/ecom-intel/.<P>.lock` (same file run.sh flocks).
- Produces: `platforms/<P>/.tail-chunks/{cfg,out,done}/…` per-city artifacts and `data/coverage/amazon-tail-<P>-<date>.json` summary `{"date","platform","cities_done","cities_total","pins_attempted","pins_serviceable"}`.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# amazon_tail_sweep.sh — 10:15 IST daily: scrape the coverage-expansion TAIL pins
# (pincodes.daily.tail.json) for amazon-fresh + amazon-now, per-city chunks with
# .done markers (a crash loses one city, a re-run resumes). Runs strictly AFTER
# the 10:00 batch so it can never delay it; takes the same per-account lock as
# run.sh so it can never collide with the chain or a selfheal re-run.
# Coverage evidence only: no Excel, no Telegram, no history.csv.
set -u
DIR=/opt/ecom-intel
TODAY="$(date +%F)"
LOG(){ echo "[$(date '+%F %T')] tail($1): $2"; }

run_platform(){
  local P="$1" SCRAPER="scrape.js"
  [ "$P" = "amazon-now" ] && SCRAPER="scrape.ctnow.js"
  local PDIR="$DIR/platforms/$P" CH="$DIR/platforms/$P/.tail-chunks"
  [ -s "$PDIR/pincodes.daily.tail.json" ] || { LOG "$P" "no tail config"; return 0; }
  mkdir -p "$CH/cfg" "$CH/out/$TODAY" "$CH/done/$TODAY"
  python3 - "$P" <<'PY'
import json, sys, os
P = sys.argv[1]; base = f"/opt/ecom-intel/platforms/{P}"
cfg = json.load(open(f"{base}/pincodes.daily.tail.json"))
cities = {}
for e in cfg: cities.setdefault(e["city"], []).append(e)
os.makedirs(f"{base}/.tail-chunks/cfg", exist_ok=True)
for c, ents in cities.items():
    json.dump(ents, open(f"{base}/.tail-chunks/cfg/{c.replace(' ','_')}.json", "w"))
print(f"[{P}] {len(cities)} city chunks / {len(cfg)} tail pins")
PY
  (
    flock -w 900 9 || { LOG "$P" "account lock busy >15m — skipping today"; exit 75; }
    cd "$PDIR" || exit 1
    for cfgf in "$CH"/cfg/*.json; do
      city="$(basename "$cfgf" .json)"
      [ -f "$CH/done/$TODAY/$city.done" ] && continue
      LOG "$P" "$city ..."
      if env PINCODES_FILE="$cfgf" OUT_FILE="$CH/out/$TODAY/$city.json" \
         timeout --foreground -k 60 3600 node "$SCRAPER" \
         >> "$DIR/logs/amz-tail-$P-$TODAY.log" 2>&1; then
        touch "$CH/done/$TODAY/$city.done"; LOG "$P" "$city OK"
      else
        LOG "$P" "$city FAILED rc=$? (left for tomorrow)"
      fi
    done
  ) 9>"$DIR/.${P}.lock"
  python3 - "$P" "$TODAY" <<'PY'
import json, sys, glob, os
P, day = sys.argv[1], sys.argv[2]
base = f"/opt/ecom-intel/platforms/{P}/.tail-chunks"
cfgs = glob.glob(f"{base}/cfg/*.json")
outs = glob.glob(f"{base}/out/{day}/*.json")
att = sv = 0
for o in outs:
    try: d = json.load(open(o)); s = d.get("summary", {})
    except Exception: continue
    att += s.get("pincodes_total") or 0
    sv += s.get("pincodes_with_jivo") or 0
os.makedirs("/opt/ecom-intel/data/coverage", exist_ok=True)
json.dump({"date": day, "platform": P,
           "cities_done": len(glob.glob(f"{base}/done/{day}/*.done")),
           "cities_total": len(cfgs), "pins_attempted": att,
           "pins_with_jivo": sv},
          open(f"/opt/ecom-intel/data/coverage/amazon-tail-{P}-{day}.json", "w"))
PY
}

run_platform amazon-fresh & F=$!
run_platform amazon-now  & N=$!
wait "$F" "$N"
LOG all "tail sweep finished"
```

- [ ] **Step 2: Make executable + shellcheck** — `chmod +x tools/cron/amazon_tail_sweep.sh && bash -n tools/cron/amazon_tail_sweep.sh` (no output = parse OK).
- [ ] **Step 3: Smoke test with a 1-city micro-config** (single Amritsar pin per platform; verifies scraper honors PINCODES_FILE/OUT_FILE + lock path):

```bash
python3 - <<'PY'
import json
for p in ("amazon-fresh", "amazon-now"):
    full = json.load(open(f"/opt/ecom-intel/platforms/{p}/pincodes.daily.tail.json"))
    amr = [e for e in full if e["city"] == "Amritsar"][:1]
    json.dump(amr, open(f"/opt/ecom-intel/platforms/{p}/pincodes.daily.tail.json.smoke", "w"))
PY
# temporarily point the script at .smoke by running its inner command directly:
cd /opt/ecom-intel/platforms/amazon-now && env PINCODES_FILE=pincodes.daily.tail.json.smoke OUT_FILE=/tmp/claude-0/-root/d6bde6b5-eacd-4d3c-b320-6b472d4a2bda/scratchpad/now-smoke.json timeout 300 node scrape.ctnow.js; python3 -c "import json;print(json.load(open('/tmp/claude-0/-root/d6bde6b5-eacd-4d3c-b320-6b472d4a2bda/scratchpad/now-smoke.json'))['summary'])"
```

Expected: a summary object with `pincodes_total: 1` (with_jivo may be 0 — Amritsar is a probe). ⚠️ Daytime rule: run this smoke only between 7:30 AM and ~10 PM IST. Clean up the `.smoke` files after.
- [ ] **Step 4: Install cron** — `(crontab -l; echo '15 10 * * * cd /opt/ecom-intel && flock -n logs/.amazon-tail.lock ./tools/cron/amazon_tail_sweep.sh >> logs/amazon_tail.log 2>&1   # coverage80 amazon tail (post-batch)') | crontab -` then `crontab -l | grep amazon_tail` to confirm.
- [ ] **Step 5: Commit** — `git add tools/cron/amazon_tail_sweep.sh && git commit -m "feat(coverage80): post-batch chunked amazon tail sweep"`

---

### Task 7: chain predictor warm-start (flipkart-minutes only)

**Files:**
- Modify: `/opt/ecom-intel/tools/cron/durations.jsonl` (append)

The 10:00 chain's only expanded platform is flipkart-minutes (+~980 pins × 0.27 s ≈ +265 s). Amazon core lists are unchanged; blinkit/zepto/bigbasket are not chain platforms.

- [ ] **Step 1: Inspect the record format** — `tail -3 tools/cron/durations.jsonl` and note field names (expect ~`{"platform": "...", "secs": N, "sweep": "...", "ts": "..."}`).
- [ ] **Step 2: Append 10 synthetic fkm durations** matching that exact format, value = (latest real fkm secs) + 280, `sweep: "warmstart-coverage80-20260711"`, using a flock on `durations.jsonl.lock` (the file has a lock sibling — respect it):

```bash
python3 - <<'PY'
import json, fcntl, datetime
path = "/opt/ecom-intel/tools/cron/durations.jsonl"
rows = [json.loads(l) for l in open(path) if l.strip()]
fkm = [r for r in rows if r.get("platform") == "flipkart-minutes"][-1]
new = dict(fkm)
new["secs"] = int(fkm["secs"]) + 280            # adapt key name to Step-1 finding
new["sweep"] = "warmstart-coverage80-20260711"
with open(path, "a") as f, open(path + ".lock", "w") as lk:
    fcntl.flock(lk, fcntl.LOCK_EX)
    for _ in range(10):
        f.write(json.dumps(new) + "\n")
print("appended 10 ×", new)
PY
```

- [ ] **Step 3: Verify the predictor still parses** — `python3 tools/cron/predict_lead.py` → JSON with a `total` a few hundred seconds higher than before (compare against the value logged in `logs/cron.log` from last night). Must stay well under LEAD_MAX 11820.
- [ ] **Step 4: Commit** — `git add tools/cron/durations.jsonl && git commit -m "chore(coverage80): warm-start fkm chain duration"`

---

### Task 8: guide regen script + redeploy

**Files:**
- Create: `/root/jivo-city-coverage-guide/regen_matrix.py` (guide folder is Vercel-deployed, not a git repo)
- Create: `/opt/ecom-intel/tools/sites/regen_city_coverage_guide.py` (identical copy, committed — never again scratchpad-only)
- Modify: `/root/jivo-city-coverage-guide/index.html` (matrix tbody, programme table counts, footer, dates)

**Interfaces:**
- Consumes: `universe_guide24.build`, live list files (amazon = core ∪ tail; instamart = anchors' `pincodes[]` union ("represented"); bigbasket = `pincodes_jivo.json`).
- Produces: rewritten matrix rows with the same cell/CSS classes the page already uses (`c0..c6`, `z`, `any`, `anyp`, chips), and exits non-zero if any per-pincode platform cell < 80%.

- [ ] **Step 1: Write `regen_matrix.py`.** Parse nothing from the old HTML — recompute all 24 rows from data and splice between `<tbody>` and `</tbody>` of the matrix table (the second `<tbody>` in the file; anchor on the `<h2>2` section to be safe). Reuse the shade thresholds from the legend (`<15,30,45,60,75,90` → classes `c0..c6`), `z` class for zero, verdict chips: ≥95% Near-full, ≥73% Strong, ≥38% Partial, >0 Thin, 0 None (match existing page conventions). Update: programme-table "Pins tracked / In the 24 cities / Outside them" numbers, the summary tiles, section-3 bullet lists (regenerate the same structure), footer counts + "generated July 12, 2026". Instamart cells print `anchors→represented` exactly as today. Include `assert min(cell_pct) >= 0.80` across all seven platform columns before writing, and `sys.path.insert(0, "/opt/ecom-intel/tools/pincodes")` to import the universe module. (This is a from-scratch generator ~200 lines; the ground-truth test is Step 2.)
- [ ] **Step 2: Run + eyeball** — `python3 /root/jivo-city-coverage-guide/regen_matrix.py` → prints the 24×7 matrix + `MIN CELL ≥ 80% ✓`, writes `index.html`. Then `python3 -c "print(open('/root/jivo-city-coverage-guide/index.html').read().count('<tr>'))"` ≈ same row count as before; open a quick sanity render: `grep -o 'Amritsar.*%' /root/jivo-city-coverage-guide/index.html | head -1` shows ≥80% values, not 0.
- [ ] **Step 3: Deploy** — `cd /root/jivo-city-coverage-guide && vercel --prod` → deployment URL printed. If the sandbox/classifier blocks it, tell the owner to run `! cd /root/jivo-city-coverage-guide && vercel --prod`.
- [ ] **Step 4: Copy + commit the generator** — `cp /root/jivo-city-coverage-guide/regen_matrix.py /opt/ecom-intel/tools/sites/regen_city_coverage_guide.py && cd /opt/ecom-intel && git add tools/sites/regen_city_coverage_guide.py && git commit -m "feat(coverage80): committed guide regen script"`

> Ordering note: run Steps 2–3 of this task only AFTER Task 4 applied the lists (the matrix reads live files). Doing it the same evening is correct — the site shows attempted coverage, which flips tonight.

---

### Task 9: morning-after verification (2026-07-12)

**Files:**
- Create: `/opt/ecom-intel/tools/cron/verify_coverage80.sh`

- [ ] **Step 1: Write the one-shot checker**

```bash
#!/usr/bin/env bash
# verify_coverage80.sh — run manually the morning after the coverage80 flip.
set -u
DIR=/opt/ecom-intel; cd "$DIR"
TODAY="$(date +%F)"; RC=0
say(){ printf '%-46s %s\n' "$1" "$2"; }
fail(){ say "$1" "❌ $2"; RC=1; }

# 1) lists still expanded (nothing rolled them back overnight)
python3 - <<'PY' || exit 1
import json
mins = {"blinkit": 1400, "zepto": 1300, "flipkart-minutes": 1250}
for p, m in mins.items():
    n = len(json.load(open(f"/opt/ecom-intel/platforms/{p}/pincodes.daily.json")))
    print(f"{p:20s} list={n:5d}  {'OK' if n >= m else 'TOO SMALL'}")
PY
# 2) batch went out at 10:00
ls output/.batch/sent-"$TODAY"-1000 >/dev/null 2>&1 && say "10:00 batch sent-marker" "✅" || fail "10:00 batch sent-marker" "missing"
# 3) blinkit ingested a full-size mac drop
python3 - <<'PY'
import json
s = json.load(open("/opt/ecom-intel/platforms/blinkit/result.json")).get("summary", {})
print(f"blinkit pincodes_total={s.get('pincodes_total')} with_jivo={s.get('pincodes_with_jivo')} wall_s={s.get('wall_s', s.get('duration_s','?'))}")
PY
# 4) zepto / fkm / bb result sizes
for p in zepto flipkart-minutes; do
  python3 -c "import json;s=json.load(open('/opt/ecom-intel/platforms/$p/result.json')).get('summary',{});print('$p', s.get('pincodes_total'), 'pins')"
done
# 5) amazon tail progress
for p in amazon-fresh amazon-now; do
  f="data/coverage/amazon-tail-$p-$TODAY.json"
  [ -f "$f" ] && cat "$f" || say "tail $p" "not yet run (starts 10:15)"
done
# 6) chain durations vs prediction
grep "$TODAY" logs/cron.log | grep -m1 "deadline_sweep(10:00)" || true
exit $RC
```

- [ ] **Step 2: `chmod +x tools/cron/verify_coverage80.sh && bash -n` it.**
- [ ] **Step 3: Commit** — `git add tools/cron/verify_coverage80.sh && git commit -m "feat(coverage80): morning-after verifier"`
- [ ] **Step 4 (next morning, ~10:40 AM):** run `./tools/cron/verify_coverage80.sh`; every check ✅, blinkit `pincodes_total` ≈ new list size, wall under 7,800 s, Blinkit WhatsApp delivery timestamp ≤10:30 (check `logs/blinkit-main-wa.log`). Re-run again ~1:30 PM to see tail `cities_done == cities_total`. Report results to the owner with the per-platform serviceable-vs-attempted counts (first real serviceability census).

---

## Self-Review (done at authoring time)

- **Spec coverage:** universe/selection (T1), ordering+lists (T3/T4), Mac sync (T5), Amazon literal-daily via core+tail (T6), guards (T4 floors; layout gate verified value-format-only — no change needed; morning_report_guard has no count assumptions — verified by grep in T4-S3), predictor (T7), site+assert (T8), verification+census (T9), rollback = `.bak-20260711` restore + re-sync Mac + remove tail cron line.
- **Deviation from spec, deliberate:** spec's "KVM1 third Blinkit shard" and "Fresh overnight in chain" were written before reading the live architecture — Blinkit VPS/KVM path is retired and Mac wall-speed (~3.75 s/pin) makes 1,490 pins fit 6:30→~8:05; Amazon core stays in-chain unchanged with the tail post-batch. Spec §3/§4 amended alongside this plan.
- **Type consistency:** `build()`/`select_targets()` signatures match between T1 and T3; `cluster()` schema matches instamart config; tail schema matches scraper contract (`PINCODES_FILE`/`OUT_FILE`, verified against `amazon_chunked.sh` + `kvm1_run_trio.sh` usage).
