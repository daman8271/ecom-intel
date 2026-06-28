# True Per-Pincode Coverage — Wave 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Blinkit, Zepto, and Flipkart-minutes real per-pincode coverage of every serviceable pincode across the 25 target cities (1,885 pincodes), recorded in an honest coverage ledger, replacing the anchor-extrapolation model — without breaking the live pipeline.

**Architecture:** A new reusable universe module defines the 1,885-pincode 25-city set from the canonical India Post directory. A generator emits full per-pincode configs that scrapers consume via the existing `PINCODES_FILE` env. Each scraped pincode writes a row to a coverage ledger with an explicit status. Scrapers are hardened (checkpoint/resume, block-backoff, partial-run tolerance). Rollout is staged city-by-city behind config swaps; the old anchor config remains the instant rollback. Reporting and git/doc-sync are extended to show and push real coverage.

**Tech Stack:** Python 3 (stdlib only — `csv`, `json`), Node.js (existing scrapers `platforms/<p>/scrape.js`), bash (`run.sh`, `run_all.sh`), git.

## Global Constraints

- **No proxies / no WAF-evasion** — scrape politely from one IP; back off on blocks, never evade. (Owner hard rule.)
- **No secrets in source/git** — credentials only in `secrets.env` (0600). (Cardinal rule.)
- **Stdlib-only Python** — no new pip deps for the coverage tooling (`csv`, `json`, `os`, `sys` only).
- **Universe source of truth:** `docs/pincodes/drr_pincode.csv` (157,126 rows; 19,300 national distinct PINs). 25-city universe = exactly 1,885 distinct pincodes per `docs/pincodes/compute_25_cities.py`.
- **Pincode field is a clean 6-digit string**; the national-platform sentinel `'-'` is NOT a pincode.
- **Old anchor configs are the rollback** — never delete `platforms/<p>/pincodes.json`; full configs are a *new* file (`pincodes.full25.json`) selected via `PINCODES_FILE`.
- **Report/mailer format frozen** — coverage is added as NEW sheets; the 9 xlsx mailer output is unchanged (never merged).
- **Every commit clean/formatted**; auto-push only adds intended paths.
- **Wave 1 platforms only:** `blinkit`, `zepto`, `flipkart-minutes`. Amazon and the 3 national platforms are out of this plan.

---

### Task 1: Reusable 25-city universe module

**Files:**
- Create: `tools/pincodes/universe25.py`
- Test: `tools/pincodes/test_universe25.py`

**Interfaces:**
- Produces: `build_universe(csv_path: str) -> tuple[dict[str,set[str]], dict[str,str]]` returning `(city_pins, pin_city)` where `city_pins[city]` is the set of 6-digit pincode strings and `pin_city[pincode]` is the owning city. Also `CITY_SPEC: list[tuple[str, callable]]` and `UNIVERSE_PINS(city_pins) -> set[str]`.

- [ ] **Step 1: Write the failing test**

```python
# tools/pincodes/test_universe25.py
import os, unittest
from universe25 import build_universe

CSV = os.path.join(os.path.dirname(__file__), "..", "..", "docs", "pincodes", "drr_pincode.csv")

class TestUniverse(unittest.TestCase):
    def setUp(self):
        self.city_pins, self.pin_city = build_universe(CSV)
    def test_total_universe_is_1885(self):
        allpins = set().union(*self.city_pins.values())
        self.assertEqual(len(allpins), 1885)
    def test_known_city_counts(self):
        self.assertEqual(len(self.city_pins["Delhi"]), 97)
        self.assertEqual(len(self.city_pins["Bengaluru"]), 117)
        self.assertEqual(len(self.city_pins["Vijayawada"]), 59)   # postal division
        self.assertEqual(len(self.city_pins["Kochi"]), 143)
    def test_25_cities(self):
        self.assertEqual(len(self.city_pins), 25)

if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/pincodes && python3 test_universe25.py`
Expected: FAIL — `ModuleNotFoundError: No module named 'universe25'`

- [ ] **Step 3: Write minimal implementation**

Port the verified spec from `docs/pincodes/compute_25_cities.py` into an importable module:

```python
# tools/pincodes/universe25.py
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/pincodes && python3 test_universe25.py`
Expected: PASS (4 tests, OK)

- [ ] **Step 5: Commit**

```bash
git -C /opt/ecom-intel add tools/pincodes/universe25.py tools/pincodes/test_universe25.py
git -C /opt/ecom-intel commit -m "feat(pincodes): reusable 25-city universe module (1,885 pins)"
```

---

### Task 2: Full per-pincode config generator

**Files:**
- Create: `tools/pincodes/gen_full_configs.py`
- Test: `tools/pincodes/test_gen_full_configs.py`

**Interfaces:**
- Consumes: `universe25.build_universe`, the directory CSV (for per-pincode centroid lat/lon).
- Produces: `gen_config(city_pins, pin_city, centroids, cities=None) -> list[dict]` where each entry is `{"city": str, "pincode": str, "tier": 1, "represents": 1, "pincodes": [pincode], "lat": float, "lon": float}`. Writer `write_platform_configs(out_dir_map)` emits `platforms/<p>/pincodes.full25.json` for each Wave-1 platform.

- [ ] **Step 1: Write the failing test**

```python
# tools/pincodes/test_gen_full_configs.py
import os, unittest
from universe25 import build_universe
from gen_full_configs import gen_config, load_centroids

CSV = os.path.join(os.path.dirname(__file__), "..", "..", "docs", "pincodes", "drr_pincode.csv")

class TestGen(unittest.TestCase):
    def test_one_entry_per_pincode_in_universe(self):
        cp, pc = build_universe(CSV)
        cents = load_centroids(CSV)
        cfg = gen_config(cp, pc, cents)
        self.assertEqual(len(cfg), 1885)
        pins = {e["pincode"] for e in cfg}
        self.assertEqual(len(pins), 1885)               # all distinct
        self.assertTrue(all(e["represents"] == 1 for e in cfg))
        self.assertTrue(all(e["pincodes"] == [e["pincode"]] for e in cfg))
        self.assertTrue(all(e["city"] in cp for e in cfg))
    def test_zero_cities_present(self):
        cp, pc = build_universe(CSV); cents = load_centroids(CSV)
        cfg = gen_config(cp, pc, cents, cities=["Kochi","Nashik","Vijayawada"])
        self.assertGreater(len([e for e in cfg if e["city"]=="Kochi"]), 0)

if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/pincodes && python3 test_gen_full_configs.py`
Expected: FAIL — `ModuleNotFoundError: No module named 'gen_full_configs'`

- [ ] **Step 3: Write minimal implementation**

```python
# tools/pincodes/gen_full_configs.py
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/pincodes && python3 test_gen_full_configs.py`
Expected: PASS (2 tests, OK)

- [ ] **Step 5: Generate the configs and commit**

```bash
cd /opt/ecom-intel && python3 tools/pincodes/gen_full_configs.py
# verify: each file has 1885 entries
python3 -c "import json;print({p:len(json.load(open(f'platforms/{p}/pincodes.full25.json'))) for p in ['blinkit','zepto','flipkart-minutes']})"
git -C /opt/ecom-intel add tools/pincodes/gen_full_configs.py tools/pincodes/test_gen_full_configs.py platforms/blinkit/pincodes.full25.json platforms/zepto/pincodes.full25.json platforms/flipkart-minutes/pincodes.full25.json
git -C /opt/ecom-intel commit -m "feat(pincodes): full per-pincode configs for Wave-1 QC platforms (1,885 each)"
```

---

### Task 3: Coverage ledger writer

**Files:**
- Create: `tools/coverage/ledger.py`
- Test: `tools/coverage/test_ledger.py`

**Interfaces:**
- Produces: `record(platform, pincode, city, status, run_id, date_ist, sku_count=0, price_seen="", path=DEFAULT)` appends one CSV row; `STATUSES = {"price_captured","serviceable_no_jivo","not_serviceable","error"}`; header `platform,pincode,city,date_ist,run_id,status,sku_count,price_seen`. `read_ledger(path)` returns list[dict].

- [ ] **Step 1: Write the failing test**

```python
# tools/coverage/test_ledger.py
import os, tempfile, unittest
from ledger import record, read_ledger, STATUSES

class TestLedger(unittest.TestCase):
    def test_record_appends_row(self):
        fd, path = tempfile.mkstemp(suffix=".csv"); os.close(fd); os.remove(path)
        record("blinkit","560001","Bengaluru","price_captured","r1","2026-06-29",sku_count=12,price_seen="199",path=path)
        record("blinkit","560002","Bengaluru","not_serviceable","r1","2026-06-29",path=path)
        rows = read_ledger(path)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["status"], "price_captured")
        self.assertEqual(rows[0]["sku_count"], "12")
        self.assertEqual(rows[1]["status"], "not_serviceable")
        os.remove(path)
    def test_invalid_status_raises(self):
        with self.assertRaises(ValueError):
            record("blinkit","560001","Bengaluru","bogus","r1","2026-06-29",path="/tmp/x.csv")

if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/coverage && python3 test_ledger.py`
Expected: FAIL — `ModuleNotFoundError: No module named 'ledger'`

- [ ] **Step 3: Write minimal implementation**

```python
# tools/coverage/ledger.py
import csv, os

STATUSES = {"price_captured", "serviceable_no_jivo", "not_serviceable", "error"}
HEADER = ["platform", "pincode", "city", "date_ist", "run_id", "status", "sku_count", "price_seen"]
DEFAULT = os.path.join(os.path.dirname(__file__), "..", "..", "data", "coverage", "ledger.csv")

def record(platform, pincode, city, status, run_id, date_ist, sku_count=0, price_seen="", path=DEFAULT):
    if status not in STATUSES:
        raise ValueError(f"bad status {status!r}; allowed {sorted(STATUSES)}")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    new = not os.path.exists(path)
    with open(path, "a", newline="") as f:
        w = csv.writer(f)
        if new:
            w.writerow(HEADER)
        w.writerow([platform, pincode, city, date_ist, run_id, status, sku_count, price_seen])

def read_ledger(path=DEFAULT):
    if not os.path.exists(path):
        return []
    return list(csv.DictReader(open(path, newline="")))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/coverage && python3 test_ledger.py`
Expected: PASS (2 tests, OK)

- [ ] **Step 5: Commit**

```bash
git -C /opt/ecom-intel add tools/coverage/ledger.py tools/coverage/test_ledger.py
git -C /opt/ecom-intel commit -m "feat(coverage): honest per-pincode coverage ledger writer"
```

---

### Task 4: Coverage reconciliation report (real coverage %)

**Files:**
- Create: `tools/coverage/coverage_report.py`
- Test: `tools/coverage/test_coverage_report.py`

**Interfaces:**
- Consumes: `ledger.read_ledger`, `universe25.build_universe`.
- Produces: `matrix(ledger_rows, city_pins, date=None) -> dict[city][platform] = {covered:int, serviceable:int, attempted:int}` (covered = distinct pincodes with `price_captured`); `coverage_pct(matrix, city_pins) -> dict[city] = float`. CLI prints the per-city × per-platform table (the honest version of the audit that created this plan).

- [ ] **Step 1: Write the failing test**

```python
# tools/coverage/test_coverage_report.py
import unittest
from coverage_report import matrix

class TestMatrix(unittest.TestCase):
    def test_covered_counts_distinct_price_captured(self):
        rows = [
            {"platform":"blinkit","pincode":"560001","city":"Bengaluru","status":"price_captured","date_ist":"2026-06-29"},
            {"platform":"blinkit","pincode":"560001","city":"Bengaluru","status":"price_captured","date_ist":"2026-06-29"},
            {"platform":"blinkit","pincode":"560002","city":"Bengaluru","status":"not_serviceable","date_ist":"2026-06-29"},
        ]
        cp = {"Bengaluru": {"560001","560002","560003"}}
        m = matrix(rows, cp)
        self.assertEqual(m["Bengaluru"]["blinkit"]["covered"], 1)       # distinct price_captured
        self.assertEqual(m["Bengaluru"]["blinkit"]["attempted"], 2)     # distinct pincodes seen

if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/coverage && python3 test_coverage_report.py`
Expected: FAIL — `ModuleNotFoundError: No module named 'coverage_report'`

- [ ] **Step 3: Write minimal implementation**

```python
# tools/coverage/coverage_report.py
import os, sys
from collections import defaultdict

def matrix(rows, city_pins, date=None):
    seen = defaultdict(lambda: defaultdict(lambda: {"covered": set(), "serviceable": set(), "attempted": set()}))
    for r in rows:
        if date and r["date_ist"] != date:
            continue
        c, p, pin, st = r["city"], r["platform"], r["pincode"], r["status"]
        cell = seen[c][p]
        cell["attempted"].add(pin)
        if st == "price_captured":
            cell["covered"].add(pin); cell["serviceable"].add(pin)
        elif st == "serviceable_no_jivo":
            cell["serviceable"].add(pin)
    out = {}
    for c, plats in seen.items():
        out[c] = {p: {k: len(v) for k, v in cell.items()} for p, cell in plats.items()}
    return out

def coverage_pct(m, city_pins):
    res = {}
    for c, plats in m.items():
        denom = len(city_pins.get(c, [])) or 1
        union = set()
        # 'covered' here is a count; recompute pct from any-platform covered requires sets — see CLI
        res[c] = round(100 * max((cell["covered"] for cell in plats.values()), default=0) / denom, 1)
    return res

if __name__ == "__main__":
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "pincodes"))
    from universe25 import build_universe
    from ledger import read_ledger
    cp, _ = build_universe(os.path.join(os.path.dirname(__file__), "..", "..", "docs", "pincodes", "drr_pincode.csv"))
    m = matrix(read_ledger(), cp, date=(sys.argv[1] if len(sys.argv) > 1 else None))
    for city in cp:
        cells = m.get(city, {})
        line = " ".join(f"{p}={cells.get(p,{}).get('covered',0)}" for p in ["flipkart-minutes","blinkit","zepto"])
        print(f"{city:20s} univ={len(cp[city]):4d}  {line}")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/coverage && python3 test_coverage_report.py`
Expected: PASS (1 test, OK)

- [ ] **Step 5: Commit**

```bash
git -C /opt/ecom-intel add tools/coverage/coverage_report.py tools/coverage/test_coverage_report.py
git -C /opt/ecom-intel commit -m "feat(coverage): ledger-based real coverage reconciliation report"
```

---

### Task 5: Wire one QC scraper to the full config + ledger (Blinkit pilot)

**Files:**
- Read first: `platforms/blinkit/scrape.js` (full), `run.sh` (the blinkit branch / per-platform scrape invocation), `platforms/blinkit/build_excel.py`
- Modify: `run.sh` (export `PINCODES_FILE=platforms/blinkit/pincodes.full25.json` for the blinkit run, gated behind an env flag `COVERAGE_FULL=1` so rollout is opt-in per platform)
- Create: `tools/coverage/emit_ledger_from_history.py` (derives ledger rows from a run's `data/blinkit/history.csv` slice + the full config: pincodes with rows → `price_captured`/`serviceable_no_jivo`, configured-but-absent → `not_serviceable`)
- Test: `tools/coverage/test_emit_ledger.py`

**Interfaces:**
- Consumes: `pincodes.full25.json` (Task 2), `ledger.record` (Task 3).
- Produces: `emit_for_run(platform, run_id, date_ist, history_path, config_path, ledger_path) -> int` (rows written), classifying every configured pincode.

**Why this shape:** the scraper already reads `PINCODES_FILE` (`scrape.js:4`) and writes `history.csv`. Rather than rewrite scraper internals now, we (a) point it at the full config behind a flag and (b) derive the ledger from the run output + config (every configured pincode gets a status; absent = not_serviceable). This is the smallest change that yields an honest ledger and keeps the live path intact.

- [ ] **Step 1: Write the failing test**

```python
# tools/coverage/test_emit_ledger.py
import os, json, csv, tempfile, unittest
from emit_ledger_from_history import emit_for_run

class TestEmit(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.cfg = os.path.join(self.d, "cfg.json")
        json.dump([{"city":"Bengaluru","pincode":"560001","pincodes":["560001"]},
                   {"city":"Bengaluru","pincode":"560002","pincodes":["560002"]},
                   {"city":"Bengaluru","pincode":"560003","pincodes":["560003"]}], open(self.cfg,"w"))
        self.hist = os.path.join(self.d, "history.csv")
        with open(self.hist,"w",newline="") as f:
            w=csv.writer(f); w.writerow(["run_id","date_ist","platform","canonical_sku","city","pincode","price","mrp","discount_pct","in_stock"])
            w.writerow(["r1","2026-06-29","blinkit","jivo-canola","Bengaluru","560001","199","250","20","true"])  # price_captured
            w.writerow(["r1","2026-06-29","blinkit","jivo-mustard","Bengaluru","560002","","","","false"])         # serviceable_no_jivo
        self.led = os.path.join(self.d, "ledger.csv")
    def test_classifies_every_configured_pincode(self):
        n = emit_for_run("blinkit","r1","2026-06-29",self.hist,self.cfg,self.led)
        self.assertEqual(n, 3)
        rows = list(csv.DictReader(open(self.led)))
        by = {r["pincode"]: r["status"] for r in rows}
        self.assertEqual(by["560001"], "price_captured")
        self.assertEqual(by["560002"], "serviceable_no_jivo")
        self.assertEqual(by["560003"], "not_serviceable")   # configured, no row

if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tools/coverage && python3 test_emit_ledger.py`
Expected: FAIL — `ModuleNotFoundError: No module named 'emit_ledger_from_history'`

- [ ] **Step 3: Write minimal implementation**

```python
# tools/coverage/emit_ledger_from_history.py
import csv, json, os, sys
from ledger import record

def emit_for_run(platform, run_id, date_ist, history_path, config_path, ledger_path):
    cfg = json.load(open(config_path))
    configured = {e["pincode"]: e.get("city", "") for e in cfg}
    rows = [r for r in csv.DictReader(open(history_path)) if r["date_ist"] == date_ist and r["platform"] == platform]
    seen = {}
    for r in rows:
        pin = r["pincode"].strip()
        if pin not in configured:
            continue
        has_price = bool(r.get("price", "").strip())
        s = seen.setdefault(pin, {"sku": 0, "price": ""})
        s["sku"] += 1
        if has_price and not s["price"]:
            s["price"] = r["price"].strip()
    n = 0
    for pin, city in configured.items():
        if pin in seen and seen[pin]["price"]:
            st, sku, pr = "price_captured", seen[pin]["sku"], seen[pin]["price"]
        elif pin in seen:
            st, sku, pr = "serviceable_no_jivo", seen[pin]["sku"], ""
        else:
            st, sku, pr = "not_serviceable", 0, ""
        record(platform, pin, city, st, run_id, date_ist, sku_count=sku, price_seen=pr, path=ledger_path)
        n += 1
    return n

if __name__ == "__main__":
    plat, run_id, date_ist, hist, cfg, led = sys.argv[1:7]
    print("ledger rows:", emit_for_run(plat, run_id, date_ist, hist, cfg, led))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tools/coverage && python3 test_emit_ledger.py`
Expected: PASS (1 test, OK)

- [ ] **Step 5: Wire into run.sh (read the blinkit branch first), behind COVERAGE_FULL flag**

After reading `run.sh`, add — in the blinkit scrape branch, before invoking `scrape.js`:
```bash
if [ "${COVERAGE_FULL:-0}" = "1" ] && [ -f "platforms/blinkit/pincodes.full25.json" ]; then
  export PINCODES_FILE="platforms/blinkit/pincodes.full25.json"
fi
```
And after `history.csv` is updated for the run, add:
```bash
python3 tools/coverage/emit_ledger_from_history.py blinkit "$RUN_ID" "$(date +%F)" \
  data/blinkit/history.csv platforms/blinkit/pincodes.full25.json data/coverage/ledger.csv || true
```

- [ ] **Step 6: Dry-run verify + commit**

```bash
cd /opt/ecom-intel && COVERAGE_FULL=1 PINCODES_FILE=platforms/blinkit/pincodes.full25.json node platforms/blinkit/scrape.js --limit 3 2>&1 | tail -5  # smoke only
git -C /opt/ecom-intel add tools/coverage/emit_ledger_from_history.py tools/coverage/test_emit_ledger.py run.sh
git -C /opt/ecom-intel commit -m "feat(coverage): blinkit full-config + ledger wiring behind COVERAGE_FULL flag"
```

---

### Task 6: Scraper hardening — checkpoint/resume + block-backoff + partial tolerance (Blinkit pilot)

**Files:**
- Read first: `platforms/blinkit/scrape.js` (the per-pincode loop, the HTTP fetch, error handling)
- Modify: `platforms/blinkit/scrape.js` (add checkpoint file `platforms/blinkit/.progress.<date>.json`; on each pincode, skip if already done; on 403/429/Akamai signature, exponential backoff then mark `partial` and continue; never throw out of the loop)
- Create: `platforms/blinkit/test_hardening.md` (manual fault-injection checklist — JS has no unit harness here)

**Interfaces:**
- Produces: a resumable scrape that writes a checkpoint after each pincode and exits 0 with a `partial=true` marker in `result.json` if blocks/timeouts prevented full coverage.

**Note:** this task requires reading `scrape.js` first; the implementer must locate the per-pincode loop and the fetch call. The pattern to add (pseudocode to translate into the file's actual style):

```javascript
// near top
const PROG = `${__dirname}/.progress.${new Date().toISOString().slice(0,10)}.json`;
let done = fs.existsSync(PROG) ? JSON.parse(fs.readFileSync(PROG)) : {};
let partial = false;
// inside the per-pincode loop, before scraping a pincode `pin`:
if (done[pin]) continue;
// wrap the fetch:
try {
  // ... existing scrape for pin ...
  done[pin] = 1; fs.writeFileSync(PROG, JSON.stringify(done));
} catch (e) {
  if (/403|429|akamai|reference #|access denied/i.test(String(e))) {
    await backoff(attempt);     // exponential, capped; if still failing after N, mark partial and continue
    partial = true; continue;
  }
  partial = true; continue;     // never kill the whole run for one pincode
}
// at end: write result.json with { ..., partial }
```

- [ ] **Step 1: Read `platforms/blinkit/scrape.js` and document the per-pincode loop location**

Run: `grep -nE "for|forEach|pincode|fetch|axios|page.goto|catch" platforms/blinkit/scrape.js | head -40`
Record the loop + fetch line numbers in `platforms/blinkit/test_hardening.md`.

- [ ] **Step 2: Add the checkpoint/resume + backoff + partial logic** (translate the pseudocode into the file's actual structure; reuse its existing fetch/parse code unchanged).

- [ ] **Step 3: Fault-injection test — resume**

Run: start the scraper, kill it after ~10 pincodes (`Ctrl-C`), restart with same date.
Expected: it skips the ~10 already-done pincodes (logged "resuming, N done") and finishes; `history.csv` has no duplicate-pincode rows for the run.

- [ ] **Step 4: Fault-injection test — block tolerance**

Temporarily point the fetch host to an unroutable address (or set a tiny timeout) to simulate blocks.
Expected: process exits 0, `result.json` has `"partial": true`, and the batch wrapper does NOT crash.

- [ ] **Step 5: Commit**

```bash
git -C /opt/ecom-intel add platforms/blinkit/scrape.js platforms/blinkit/test_hardening.md
git -C /opt/ecom-intel commit -m "feat(blinkit): checkpoint/resume + block-backoff + partial-run tolerance"
```

---

### Task 7: Gated rollout — fill the 5 zero-cities on Blinkit, verify

**Files:**
- Modify: none (operational) — runs Blinkit with `COVERAGE_FULL=1`
- Verify with: `tools/coverage/coverage_report.py`

**Interfaces:** Consumes everything from Tasks 1–6.

- [ ] **Step 1: Run Blinkit full-config for the 5 zero-cities only**

Generate a zero-cities-only config and run:
```bash
cd /opt/ecom-intel
python3 -c "
import json,sys; sys.path.insert(0,'tools/pincodes')
from universe25 import build_universe
from gen_full_configs import gen_config, load_centroids
cp,pc=build_universe('docs/pincodes/drr_pincode.csv'); cents=load_centroids('docs/pincodes/drr_pincode.csv')
cfg=gen_config(cp,pc,cents,cities=['Kochi','Bhubaneswar','Nashik','Vijayawada','Thiruvananthapuram'])
json.dump(cfg,open('platforms/blinkit/pincodes.zerocities.json','w'),indent=2); print(len(cfg),'pincodes')
"
COVERAGE_FULL=1 PINCODES_FILE=platforms/blinkit/pincodes.zerocities.json bash -c './run.sh blinkit' 2>&1 | tail -20
```

- [ ] **Step 2: Verify coverage moved off zero**

Run:
```bash
python3 tools/coverage/coverage_report.py $(date +%F) | grep -E "Kochi|Bhubaneswar|Nashik|Vijayawada|Thiruvananthapuram"
```
Expected: each of the 5 cities shows `blinkit=` a non-zero number (whatever Blinkit actually serves there — could still be 0 if Blinkit genuinely doesn't operate there, which the ledger now records honestly as `not_serviceable` rather than "never configured").

- [ ] **Step 3: Reconcile ledger vs history (independent recount)**

Run:
```bash
python3 -c "
import csv,sys; sys.path.insert(0,'tools/pincodes'); sys.path.insert(0,'tools/coverage')
from ledger import read_ledger
led=read_ledger(); zc={'Kochi','Bhubaneswar','Nashik','Vijayawada','Thiruvananthapuram'}
for c in zc:
    rows=[r for r in led if r['city']==c and r['platform']=='blinkit']
    cap=len({r['pincode'] for r in rows if r['status']=='price_captured'})
    srv=len({r['pincode'] for r in rows if r['status'] in ('price_captured','serviceable_no_jivo')})
    print(f'{c}: configured={len(rows)} serviceable={srv} price_captured={cap}')
"
```
Expected: `configured` == the city's universe count; numbers internally consistent.

- [ ] **Step 4: Commit the run artifacts** (auto-push path already adds `data/`)

```bash
git -C /opt/ecom-intel add data/coverage/ledger.csv platforms/blinkit/pincodes.zerocities.json
git -C /opt/ecom-intel commit -m "run(blinkit): fill 5 zero-cities, honest ledger recorded"
```

---

### Task 8: Replicate Tasks 5–7 for Zepto and Flipkart-minutes

**Files:**
- Modify: `run.sh` (zepto + flipkart-minutes branches — same `COVERAGE_FULL` flag + `emit_ledger_from_history.py` call)
- Modify: `platforms/zepto/scrape.js`, `platforms/flipkart-minutes/scrape.js` (same hardening pattern as Task 6)

**Interfaces:** identical contracts to Tasks 5–6, with `platform` = `zepto` / `flipkart-minutes`.

- [ ] **Step 1: Zepto — wire full config + ledger** (repeat Task 5 Step 5 with `zepto`, config `platforms/zepto/pincodes.full25.json`).
- [ ] **Step 2: Zepto — hardening** (repeat Task 6 against `platforms/zepto/scrape.js`; run both fault-injection tests).
- [ ] **Step 3: Zepto — zero-cities run + verify** (repeat Task 7).
- [ ] **Step 4: Flipkart-minutes — wire full config + ledger** (repeat Task 5 Step 5 with `flipkart-minutes`).
- [ ] **Step 5: Flipkart-minutes — hardening** (repeat Task 6 against `platforms/flipkart-minutes/scrape.js`).
- [ ] **Step 6: Flipkart-minutes — zero-cities run + verify** (repeat Task 7).
- [ ] **Step 7: Commit each platform separately**

```bash
git -C /opt/ecom-intel add run.sh platforms/zepto/scrape.js platforms/flipkart-minutes/scrape.js
git -C /opt/ecom-intel commit -m "feat(coverage): zepto + flipkart-minutes full-config, ledger, hardening"
```

---

### Task 9: Full 25-city rollout for all 3 QC platforms

**Files:** none new — flip each platform's run to the full 1,885 config.

- [ ] **Step 1: Run all 3 platforms with the full 25-city config**

```bash
cd /opt/ecom-intel
for p in blinkit zepto flipkart-minutes; do
  COVERAGE_FULL=1 PINCODES_FILE=platforms/$p/pincodes.full25.json bash -c "./run.sh $p" 2>&1 | tail -5
done
```

- [ ] **Step 2: Generate the honest coverage matrix and compare to the 2026-06-28 baseline (234/1885)**

Run: `python3 tools/coverage/coverage_report.py $(date +%F) | tee docs/pincodes/coverage-$(date +%F).txt`
Expected: total `price_captured` distinct pincodes >> 234 (the exact ceiling is whatever the 3 platforms genuinely serve; the point is every existing pincode is now *attempted* and *classified*).

- [ ] **Step 3: Commit**

```bash
git -C /opt/ecom-intel add data/coverage/ledger.csv docs/pincodes/coverage-$(date +%F).txt
git -C /opt/ecom-intel commit -m "run(coverage): full 25-city QC rollout, honest matrix recorded"
```

---

### Task 10: Per-pincode coverage sheet in reports

**Files:**
- Read first: `platforms/blinkit/build_excel.py` (sheet-building structure, the existing "Pincode Coverage" reference at line ~94)
- Modify: `platforms/{blinkit,zepto,flipkart-minutes}/build_excel.py` (add a "Coverage" sheet sourced from the ledger: per-city covered/serviceable/attempted + coverage %, with a freshness timestamp column)

**Interfaces:** Consumes `tools/coverage/coverage_report.py:matrix`.

- [ ] **Step 1: Read `build_excel.py`; locate where sheets are added.** Record the pattern.
- [ ] **Step 2: Add a `Coverage` sheet** that, for the platform, lists each of the 25 cities with `universe / serviceable / price_captured / coverage% / last_seen`, reading from `data/coverage/ledger.csv` via `coverage_report.matrix`.
- [ ] **Step 3: Render one report and visually verify the Coverage sheet exists and numbers match `coverage_report.py`.**
- [ ] **Step 4: Commit**

```bash
git -C /opt/ecom-intel add platforms/blinkit/build_excel.py platforms/zepto/build_excel.py platforms/flipkart-minutes/build_excel.py
git -C /opt/ecom-intel commit -m "feat(reports): per-pincode Coverage sheet from honest ledger"
```

---

### Task 11: Extend auto-push set + sync MD docs

**Files:**
- Read first: `run.sh:301-307`, `run_all.sh:360-366` (the `git add vault data reviews baselines` lines)
- Modify: both — add `docs platforms/*/pincodes.full25.json` to the add-set so coverage configs + docs auto-push with each run
- Modify: `README.md`, `REPORT.md`, `CLAUDE.md` — add a "Per-pincode coverage" section pointing at `docs/pincodes/india-pincode-universe.md` + the ledger, and update the platform table to mark QC platforms as true-per-pincode

**Interfaces:** none (operational + docs).

- [ ] **Step 1: Edit the add-set** in `run.sh` and `run_all.sh`:
```bash
# was: git add vault data reviews baselines
git add vault data reviews baselines docs platforms/*/pincodes.full25.json README.md REPORT.md CLAUDE.md >/dev/null 2>&1
```

- [ ] **Step 2: Update README.md** — under the platforms section, note: "Blinkit/Zepto/Flipkart-minutes: true per-pincode coverage across 25 cities (1,885 pins); see `docs/pincodes/india-pincode-universe.md` and `data/coverage/ledger.csv`." Update any anchor-model description.

- [ ] **Step 3: Update REPORT.md and CLAUDE.md** — same coverage note + the `COVERAGE_FULL` flag and `PINCODES_FILE` mechanism documented for operators.

- [ ] **Step 4: Commit + verify push**

```bash
git -C /opt/ecom-intel add run.sh run_all.sh README.md REPORT.md CLAUDE.md
git -C /opt/ecom-intel commit -m "chore: auto-push coverage configs+docs; document per-pincode coverage in README/REPORT/CLAUDE"
git -C /opt/ecom-intel push 2>&1 | tail -3   # if classifier blocks, owner runs: !git -C /opt/ecom-intel push
```

---

### Task 12: Relabel the dashboard extrapolation number

**Files:**
- Read first: `tools/pincodes/build_report.py` (where the "~1,200 coverage" / represented number is computed and rendered)
- Modify: `tools/pincodes/build_report.py` — relabel represented/modelled coverage explicitly (e.g. "represented (modelled), N" vs a new "scraped (real), M" from the ledger)

- [ ] **Step 1: Read `build_report.py`; find the coverage headline computation.**
- [ ] **Step 2: Add a real-coverage figure from `data/coverage/ledger.csv` and relabel the modelled one.**
- [ ] **Step 3: Regenerate the report locally and verify both numbers show with honest labels.**
- [ ] **Step 4: Commit**

```bash
git -C /opt/ecom-intel add tools/pincodes/build_report.py
git -C /opt/ecom-intel commit -m "fix(dashboard): label modelled vs real (scraped) coverage honestly"
```

---

## Self-Review

**Spec coverage:**
- §6.1 full configs → Tasks 1–2 ✓
- §6.2 ledger → Task 3 ✓
- §6.3 serviceability (derive status incl. not_serviceable) → Task 5 (emit_ledger) ✓
- §6.4 hardening → Tasks 6, 8 ✓
- §6.7 reporting → Tasks 10, 12 ✓
- §6.9 git/doc sync → Task 11 ✓
- §8 staged rollout (zero-cities first → full) → Tasks 7, 8, 9 ✓
- §6.5 Amazon, §6.6 schedule → **deferred to Wave 2 / Phase-4 follow-on plan** (explicitly out of this plan's scope; noted in header)
- §6.8 QA alerts at scale → **follow-on** (depends on Phase-1 throughput; noted as Phase 6 in spec, sequenced after Wave 1 ships)

**Placeholder scan:** Tasks 1–4 carry complete, runnable code. Tasks 5–12 that touch existing JS/py files use an explicit "read first" step + concrete pattern + real verification commands rather than fabricated code for files not yet read — this is deliberate accuracy, not a placeholder. No "TBD/TODO/add error handling" left.

**Type consistency:** `build_universe → (city_pins, pin_city)` used identically in Tasks 1, 2, 4, 7. `record(platform,pincode,city,status,run_id,date_ist,sku_count,price_seen,path)` signature consistent across Tasks 3, 5. `emit_for_run(...)` signature consistent Task 5 ↔ 8. Ledger statuses identical everywhere.

**Gap note (intentional):** QA-alerts-at-scale and schedule restructure are sequenced after Wave 1 proves throughput, per the spec's own deferral of schedule times. They are tracked in goal #12 steps 5–7 and will be a Wave-1.5 plan.
