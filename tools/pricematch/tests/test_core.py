#!/usr/bin/env python3
"""VERIFY Phase 1 — golden tests for tools/pricematch/pricematch_core.py.

Adversarial gate: every expected value below is HAND-COMPUTED, independent of the
engine's own math. Runs bare: `python3 tools/pricematch/tests/test_core.py`.

Strategy: build a sandbox fake-repo (tools/pricematch/ + platforms/<p>/result.json)
with crafted fixtures, copy the engine in, and exercise BOTH the frozen Python
contract (regime_for / load_context / platform_comparison / all_comparisons /
summary) and the CLI (--json). Real repo files are never touched.

Exit code: 0 = all PASS, 1 = any FAIL, 2 = engine missing (not landed yet).
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PM_DIR = os.path.dirname(HERE)                      # tools/pricematch
ROOT = os.path.dirname(os.path.dirname(PM_DIR))     # repo root
CORE = os.path.join(PM_DIR, "pricematch_core.py")

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok), detail))
    print(("PASS  " if ok else "FAIL  ") + name + (("  -- " + str(detail)) if (detail and not ok) else ""))


# ---------------------------------------------------------------- fixtures
# Regime prices used everywhere below (SVD day 2026-06-06 => ref = svd).
# Hand math, SVD ref = 140, tolerance Rs1:
#   MATCH iff |live-140| <= 1  -> live in [139, 141]
#   BELOW iff live < 139
#   ABOVE iff live > 141
REG = {"mrp": 200, "bau": 150, "svd": 140, "art": 130}

def _sku(map_platforms, retired=False, regimes=None):
    e = {"regimes": dict(regimes if regimes is not None else REG), "platforms": map_platforms}
    if retired:
        e["retired"] = True
    return e

def _bk_map(prid, conf="exact", sale_modal=None, title=None):
    return {"id": prid, "url": "https://blinkit.com/prn/x/prid/" + prid,
            "title": title or ("Fixture title " + prid), "mrp": 200,
            "sale_modal": sale_modal, "sale_min": sale_modal, "sale_max": sale_modal,
            "in_stock": 1, "method": "ID-PRID", "confidence": conf}

def _bk_row(prid, sale, in_stock=1, pincode="110001", city="Delhi", canonical="fix"):
    return {"city": city, "pincode": pincode, "locality": "L", "store_id": 1,
            "store_name": "S", "sku_raw": "Fixture " + prid, "canonical": canonical,
            "pack": "1 l", "vol_ml": 1000, "sale": sale, "mrp": 200,
            "discount_pct": 0, "per_litre": sale, "eta_min": 8,
            "in_stock": in_stock, "prid": prid,
            "listing_url": "https://blinkit.com/prn/x/prid/" + prid}

MASTER_SKUS = {}
MAP_SKUS = {}
BK_ROWS = []

def add(name, prid, prices, conf="exact", retired=False, regimes=None,
        snapshot_modal=None, platforms_extra=None):
    """prices = list of (sale, in_stock, pincode, city) blinkit rows."""
    r = dict(regimes if regimes is not None else REG)
    MASTER_SKUS[name] = {"product": name, "asin": None, "url": None,
                         "mrp": r["mrp"], "asp": r["bau"], "svd": r["svd"],
                         "bau": r["bau"], "art": r["art"],
                         "url_price": None, "stock_status": None, "seller": None}
    plats = {}
    if prid is not None:
        plats["blinkit"] = _bk_map(prid, conf=conf, sale_modal=snapshot_modal)
    if platforms_extra:
        plats.update(platforms_extra)
    MAP_SKUS[name] = _sku(plats, retired=retired, regimes=r)
    for (sale, in_stock, pin, city) in prices:
        BK_ROWS.append(_bk_row(prid, sale, in_stock=in_stock, pincode=pin, city=city,
                               canonical=name.lower().replace(" ", "-")))

# 1. tolerance edges (ref svd=140)
add("EDGE MATCH LOW 1L",  "P1", [(139, 1, "110001", "Delhi")] * 3)            # diff -1 => MATCH
add("EDGE BELOW 1L",      "P2", [(138, 1, "110001", "Delhi"),
                                  (138, 1, "110002", "Delhi"),
                                  (138, 1, "560001", "Bengaluru")])           # diff -2 => BELOW
add("EDGE MATCH HIGH 1L", "P3", [(141, 1, "110001", "Delhi")] * 3)            # diff +1 => MATCH
add("EDGE ABOVE 1L",      "P4", [(142, 1, "110001", "Delhi")] * 3)            # diff +2 => ABOVE
add("EXACT MATCH 1L",     "P5", [(140, 1, "110001", "Delhi")] * 2)            # diff 0  => MATCH
# 2. OOS: rows exist, none in stock
add("OOS FIX 1L",         "P6", [(135, 0, "110001", "Delhi"), (135, 0, "110002", "Delhi")])
# 3a. pending review: review-list candidate, no ratified mapping (the real mechanism)
add("PENDING FIX 1L",     None, [])
BK_ROWS.append(_bk_row("P7", 100, canonical="pending-fix-1l"))
REVIEW_LIST = [{"platform": "blinkit", "id": "P7", "title": "pending fixture",
                "candidate": "PENDING FIX 1L", "reason": "verify fixture"}]
# 3b. safety: a mapping whose confidence is NOT exact/anchored must never be priced
add("LOWCONF FIX 1L",     "PC", [(100, 1, "110001", "Delhi")], conf="review")
# 4. retired => excluded entirely
add("RETIRED FIX 1L",     "P8", [(100, 1, "110001", "Delhi")], retired=True)
# 5. not listed on blinkit (only amazon mapping)
add("NOTLISTED FIX 1L",   None, [], platforms_extra={
    "amazon": {"id": "B0FIXTURE1", "url": "https://www.amazon.in/dp/B0FIXTURE1",
               "title": "amz fixture", "mrp": 200, "sale_modal": 140, "sale_min": 140,
               "sale_max": 140, "in_stock": True, "method": "ID-ASIN",
               "confidence": "exact"}})
# 6. stores_below with healthy modal: modal 150 (ABOVE) but one store at 130 < 139
add("STORESBELOW FIX 1L", "P9", [(150, 1, "110001", "Delhi"),
                                  (150, 1, "110002", "Delhi"),
                                  (150, 1, "400001", "Mumbai"),
                                  (130, 1, "560001", "Bengaluru")])
# 7. live-join: map snapshot says 999, result.json says 138 => engine must carry 138
add("LIVEJOIN FIX 1L",    "PA", [(138, 1, "110001", "Delhi")] * 2, snapshot_modal=999)
# 8. NO_REF: svd missing on an SVD day
add("NOREF FIX 1L",       "PB", [(140, 1, "110001", "Delhi")],
    regimes={"mrp": 200, "bau": 150, "svd": None, "art": 130})

REGIME_JSON = {
    "defaults": {"mon": "BAU", "tue": "BAU", "wed": "BAU", "thu": "BAU",
                 "fri": "SVD", "sat": "SVD", "sun": "SVD"},
    "overrides": [{"date": "2026-06-03", "regime": "ART", "note": "fixture override"}],
}

# expected regimes for the exhaustive week (hand-checked calendar):
# 2026-06-01 Mon BAU | 02 Tue BAU | 03 Wed ART(override; default BAU) | 04 Thu BAU
# 2026-06-05 Fri SVD | 06 Sat SVD | 07 Sun SVD | 08 Mon BAU
WEEK = {"2026-06-01": "BAU", "2026-06-02": "BAU", "2026-06-04": "BAU",
        "2026-06-05": "SVD", "2026-06-06": "SVD", "2026-06-07": "SVD",
        "2026-06-08": "BAU"}
OVERRIDE_DATE, OVERRIDE_REGIME = "2026-06-03", "ART"


def build_sandbox(base):
    pm = os.path.join(base, "tools", "pricematch")
    os.makedirs(pm)
    shutil.copy2(CORE, os.path.join(pm, "pricematch_core.py"))
    with open(os.path.join(pm, "master_v2.json"), "w") as f:
        json.dump({"version": "fixture", "source": "verify-fixture", "renames": {},
                   "dropped_from_sheet": [], "skus": MASTER_SKUS}, f, indent=1)
    with open(os.path.join(pm, "sku_map.json"), "w") as f:
        json.dump({"version": "fixture", "source": "verify-fixture",
                   "skus": MAP_SKUS, "unpriced": [], "junk": [],
                   "review": REVIEW_LIST}, f, indent=1)
    with open(os.path.join(pm, "regime.json"), "w") as f:
        json.dump(REGIME_JSON, f, indent=1)
    for p in ("blinkit", "zepto", "flipkart", "flipkart-minutes", "amazon",
              "amazon-fresh", "amazon-now", "bigbasket"):
        d = os.path.join(base, "platforms", p)
        os.makedirs(d)
        rows = BK_ROWS if p == "blinkit" else []
        if p == "amazon":
            rows = [{"city": "All India", "pincode": "110001", "locality": "", "store_id": "",
                     "store_name": "", "sku_raw": "amz fixture", "canonical": "notlisted-fix-1l",
                     "pack": "1 l", "vol_ml": 1000, "sale": 140, "mrp": 200, "discount_pct": 30,
                     "per_litre": 140, "eta_min": None, "in_stock": 1, "asin": "B0FIXTURE1"}]
        with open(os.path.join(d, "result.json"), "w") as f:
            json.dump({"allRows": rows, "perPin": {}, "summary": {"rows": len(rows)}}, f)
    return pm


DRIVER = r'''
import importlib.util, json, sys, datetime
spec = importlib.util.spec_from_file_location("pmc", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

def regime(d):
    try:
        return m.regime_for(d)
    except Exception:
        try:
            return m.regime_for(datetime.date.fromisoformat(d))
        except Exception as e:
            return "ERR:" + repr(e)

def ctx_for(d):
    try:
        return m.load_context(date=d)
    except Exception:
        return m.load_context(date=datetime.date.fromisoformat(d))

out = {"regimes": {}, "err": None}
for d in json.loads(sys.argv[2]):
    out["regimes"][d] = regime(d)
try:
    ctx = ctx_for(sys.argv[3])
    out["blinkit"] = m.platform_comparison(ctx, "blinkit")
    allc = m.all_comparisons(ctx)
    out["all_platforms"] = sorted(allc.keys())
    out["blinkit_via_all"] = allc.get("blinkit")
    out["summary"] = m.summary(ctx)
except Exception as e:
    import traceback
    out["err"] = traceback.format_exc()
print(json.dumps(out, default=str))
'''


def run_driver(base, dates, ctx_date):
    pm = os.path.join(base, "tools", "pricematch")
    p = subprocess.run([sys.executable, "-c", DRIVER,
                        os.path.join(pm, "pricematch_core.py"),
                        json.dumps(dates), ctx_date],
                       cwd=base, capture_output=True, text=True, timeout=120)
    if p.returncode != 0:
        return {"err": "driver rc=%d\n%s" % (p.returncode, p.stderr[-2000:])}
    try:
        return json.loads(p.stdout.strip().splitlines()[-1])
    except Exception as e:
        return {"err": "unparseable driver stdout: %r %r" % (e, p.stdout[-500:])}


def rec_by_sku(records, sku):
    for r in records or []:
        if r.get("sku") == sku:
            return r
    return None


def num(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def main():
    if not os.path.exists(CORE):
        print("ENGINE NOT LANDED: %s missing — nothing to test yet." % CORE)
        sys.exit(2)

    base = tempfile.mkdtemp(prefix="pmverify-")
    try:
        build_sandbox(base)
        out = run_driver(base, list(WEEK.keys()) + [OVERRIDE_DATE], "2026-06-06")

        # --- sandbox sanity: engine must read the SANDBOX files, not /opt/ecom-intel
        if out.get("err"):
            check("driver/load_context runs", False, out["err"])
            finish()
            return
        recs = out.get("blinkit") or []
        skus_seen = {r.get("sku") for r in recs}
        if skus_seen and not (skus_seen & set(MASTER_SKUS)):
            check("engine reads files relative to its location (sandboxable)", False,
                  "records show real-repo SKUs -> engine hardcodes absolute paths; got %s" %
                  sorted(skus_seen)[:3])
            finish()
            return
        check("engine reads files relative to its location (sandboxable)", True)

        # --- regime week (exhaustive)
        for d, want in sorted(WEEK.items()):
            check("regime_for(%s) == %s" % (d, want), out["regimes"].get(d) == want,
                  "got %r" % out["regimes"].get(d))
        check("regime_for override %s == %s" % (OVERRIDE_DATE, OVERRIDE_REGIME),
              out["regimes"].get(OVERRIDE_DATE) == OVERRIDE_REGIME,
              "got %r" % out["regimes"].get(OVERRIDE_DATE))

        # --- tolerance edges, hand-computed (ref = svd 140, tol Rs1)
        edge = [("EDGE MATCH LOW 1L", 139, -1, "MATCH"),
                ("EDGE BELOW 1L", 138, -2, "BELOW"),
                ("EDGE MATCH HIGH 1L", 141, 1, "MATCH"),
                ("EDGE ABOVE 1L", 142, 2, "ABOVE"),
                ("EXACT MATCH 1L", 140, 0, "MATCH")]
        for sku, live, diff, status in edge:
            r = rec_by_sku(recs, sku)
            if r is None:
                check("%s present" % sku, False, "record missing")
                continue
            check("%s status %s" % (sku, status), r.get("status") == status,
                  "got %r (live_modal=%r ref=%r diff=%r)" %
                  (r.get("status"), r.get("live_modal"), r.get("ref_price"), r.get("diff")))
            check("%s live_modal == %s" % (sku, live), num(r.get("live_modal")) == live,
                  "got %r" % r.get("live_modal"))
            check("%s ref_price == 140 (SVD)" % sku, num(r.get("ref_price")) == 140,
                  "got %r" % r.get("ref_price"))
            check("%s diff == %s" % (sku, diff), num(r.get("diff")) == diff,
                  "got %r" % r.get("diff"))

        # --- OOS
        r = rec_by_sku(recs, "OOS FIX 1L")
        check("OOS: status OOS when no in-stock rows", r is not None and r.get("status") == "OOS",
              "got %r" % (r and r.get("status")))

        # --- PENDING_REVIEW: review-list candidate counted, never priced
        r = rec_by_sku(recs, "PENDING FIX 1L")
        check("PENDING_REVIEW: review-list candidate => PENDING_REVIEW",
              r is not None and r.get("status") == "PENDING_REVIEW",
              "got %r" % (r and r.get("status")))
        if r is not None:
            check("PENDING_REVIEW: never priced (no live_modal/diff verdict)",
                  r.get("status") not in ("BELOW", "ABOVE", "MATCH"), "got %r" % r.get("status"))
        # --- safety: low-confidence mapping must NEVER participate in pricing
        r = rec_by_sku(recs, "LOWCONF FIX 1L")
        check("low-confidence mapping never priced",
              r is None or r.get("status") not in ("BELOW", "ABOVE", "MATCH"),
              "conf='review' mapping got priced: %r" % (r and r.get("status")))

        # --- retired excluded entirely
        check("retired SKU absent from records", rec_by_sku(recs, "RETIRED FIX 1L") is None,
              "retired SKU produced a record")

        # --- NOT_LISTED on blinkit (mapped only on amazon)
        r = rec_by_sku(recs, "NOTLISTED FIX 1L")
        check("NOT_LISTED: master SKU w/o blinkit mapping", r is not None and
              r.get("status") == "NOT_LISTED", "got %r" % (r and r.get("status")))

        # --- stores_below surfaces the one cheap dark store under a healthy modal
        r = rec_by_sku(recs, "STORESBELOW FIX 1L")
        if r is None:
            check("stores_below fixture present", False, "record missing")
        else:
            check("stores_below: modal 150 => status ABOVE", r.get("status") == "ABOVE",
                  "got %r modal=%r" % (r.get("status"), r.get("live_modal")))
            sb = r.get("stores_below") or []
            pins = {str(s.get("pincode")) for s in sb}
            check("stores_below: the 130@560001 store surfaces", "560001" in pins,
                  "stores_below=%r" % sb)
            check("stores_below: healthy stores NOT listed",
                  not ({"110001", "110002", "400001"} & pins), "stores_below=%r" % sb)
            prices = [num(s.get("price")) for s in sb if str(s.get("pincode")) == "560001"]
            check("stores_below: carries the store price 130", 130.0 in prices,
                  "prices=%r" % prices)

        # --- live-join: snapshot 999 vs result.json 138 => engine must carry 138
        r = rec_by_sku(recs, "LIVEJOIN FIX 1L")
        if r is None:
            check("live-join fixture present", False, "record missing")
        else:
            check("live-join: live_modal from result.json (138), not map snapshot (999)",
                  num(r.get("live_modal")) == 138, "got %r" % r.get("live_modal"))
            check("live-join: status BELOW", r.get("status") == "BELOW",
                  "got %r" % r.get("status"))

        # --- NO_REF
        r = rec_by_sku(recs, "NOREF FIX 1L")
        check("NO_REF: missing svd price on an SVD day",
              r is not None and r.get("status") == "NO_REF", "got %r" % (r and r.get("status")))

        # --- all_comparisons consistency + summary
        check("all_comparisons covers blinkit",
              out.get("blinkit_via_all") is not None and
              len(out["blinkit_via_all"]) == len(recs),
              "platform_comparison=%d via all=%r" %
              (len(recs), out.get("blinkit_via_all") and len(out["blinkit_via_all"])))
        summ = out.get("summary")
        check("summary() returns a dict", isinstance(summ, dict), "got %r" % type(summ))
        if isinstance(summ, dict):
            blob = json.dumps(summ)
            # hand count: BELOW on blinkit = EDGE BELOW (-2) + LIVEJOIN (-2) = 2 records
            check("summary mentions a below/violation count", any(
                k in blob.lower() for k in ("below", "violation")), "keys=%s" % list(summ)[:12])

        # --- regime on the override date flows into ref_price (ART=130)
        out2 = run_driver(base, [], OVERRIDE_DATE)
        if out2.get("err"):
            check("load_context on override date", False, out2["err"])
        else:
            r = rec_by_sku(out2.get("blinkit") or [], "EXACT MATCH 1L")
            check("override date: record regime == ART",
                  r is not None and r.get("regime") == "ART", "got %r" % (r and r.get("regime")))
            check("override date: ref_price == art 130",
                  r is not None and num(r.get("ref_price")) == 130,
                  "got %r" % (r and r.get("ref_price")))
            # live 140 vs ref 130 => diff +10 => ABOVE
            check("override date: 140 vs art 130 => ABOVE",
                  r is not None and r.get("status") == "ABOVE", "got %r" % (r and r.get("status")))

        # --- degraded regime.json: garbage then missing => weekday defaults, no crash
        rj = os.path.join(base, "tools", "pricematch", "regime.json")
        with open(rj, "w") as f:
            f.write("{this is not json")
        out3 = run_driver(base, ["2026-06-06", "2026-06-08"], "2026-06-06")
        check("bad regime.json: no crash",
              not out3.get("err") and "ERR:" not in str(out3.get("regimes")),
              str(out3.get("err") or out3.get("regimes"))[:300])
        check("bad regime.json: falls back to weekday defaults (Sat=SVD, Mon=BAU)",
              out3.get("regimes", {}).get("2026-06-06") == "SVD" and
              out3.get("regimes", {}).get("2026-06-08") == "BAU",
              "got %r" % out3.get("regimes"))
        os.remove(rj)
        out4 = run_driver(base, ["2026-06-06", "2026-06-08"], "2026-06-06")
        check("missing regime.json: no crash",
              not out4.get("err") and "ERR:" not in str(out4.get("regimes")),
              str(out4.get("err") or out4.get("regimes"))[:300])
        check("missing regime.json: weekday defaults hold",
              out4.get("regimes", {}).get("2026-06-06") == "SVD" and
              out4.get("regimes", {}).get("2026-06-08") == "BAU",
              "got %r" % out4.get("regimes"))
        # restore for CLI test
        with open(rj, "w") as f:
            json.dump(REGIME_JSON, f)

        # --- CLI smoke: --json dumps parseable JSON containing fixture records
        p = subprocess.run([sys.executable, os.path.join(base, "tools", "pricematch",
                                                         "pricematch_core.py"),
                            "--date", "2026-06-06", "--json"],
                           cwd=base, capture_output=True, text=True, timeout=120)
        ok_json, found = False, False
        if p.returncode == 0 and p.stdout.strip():
            try:
                blob = json.loads(p.stdout)
                ok_json = True
                found = "EDGE BELOW 1L" in p.stdout
            except ValueError:
                pass
        check("CLI --json: exit 0 + valid JSON", ok_json,
              "rc=%d stderr=%s" % (p.returncode, p.stderr[-300:]))
        check("CLI --json: contains fixture records", found, "fixture SKU absent from dump")
        p2 = subprocess.run([sys.executable, os.path.join(base, "tools", "pricematch",
                                                          "pricematch_core.py"),
                             "--date", "2026-06-06", "--json", "blinkit"],
                            cwd=base, capture_output=True, text=True, timeout=120)
        ok2 = p2.returncode == 0 and p2.stdout.strip().startswith(("[", "{"))
        check("CLI --json <platform>: exit 0 + JSON", ok2,
              "rc=%d stdout[:80]=%r" % (p2.returncode, p2.stdout[:80]))
    finally:
        shutil.rmtree(base, ignore_errors=True)

    finish()


def finish():
    fails = [r for r in RESULTS if not r[1]]
    print("\n== test_core: %d checks, %d FAIL ==" % (len(RESULTS), len(fails)))
    for name, _, detail in fails:
        print("  FAIL: %s  %s" % (name, detail))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
