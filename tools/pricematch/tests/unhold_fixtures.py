#!/usr/bin/env python3
"""
W3 adversarial fixtures — prove W1's recalibrated review.py still catches REAL
problems and clears only the genuine false positives. Pure in-memory, no I/O on
production data (staleness uses a throwaway temp ROOT for its history.csv).

Asserts:
  A. shared_price_dup STILL FIRES on one price bleed-assigned across genuinely
     UNRELATED non-combo products (fabrication).  [must FAIL the check]
  B. shared_price_dup PASSES on the real flipkart legit case (seller-duplicate
     listings of one product + combos sharing a bundle price).  [must PASS]
  C. staleness_alarm STILL FIRES on a truly-stuck scraper (every SKU frozen,
     snapshot path, NOTHING moved).  [must FAIL]
  D. staleness_alarm PASSES on genuinely-stable data where some SKU moved on the
     same path (the zepto real case).  [must PASS]
"""
import os
import sys
import tempfile
import csv

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import review  # noqa: E402

FAILS = []


def check(name, cond):
    print(f"  [{'PASS' if cond else 'FAIL'}] {name}")
    if not cond:
        FAILS.append(name)


# ---- A. fabrication MUST still fire -----------------------------------------
def test_fabrication_fires():
    print("A. fabrication across UNRELATED non-combo products -> must FIRE")
    # 5 genuinely-different oils, all stamped one fabricated discounted pair.
    pair = dict(sale=500, mrp=800)
    rows = [
        dict(item="MUSTARD 5L", sku_raw="MUSTARD 5L", canonical="c1", **pair),
        dict(item="SUNFLOWER 1L", sku_raw="SUNFLOWER 1L", canonical="c2", **pair),
        dict(item="GROUNDNUT 1L", sku_raw="GROUNDNUT 1L", canonical="c3", **pair),
        dict(item="POMACE OLIVE 1L", sku_raw="POMACE OLIVE 1L", canonical="c4", **pair),
        dict(item="EXTRA VIRGIN 250ML", sku_raw="EXTRA VIRGIN 250ML", canonical="c5", **pair),
    ]
    ok, detail, sev = review.shared_price_dup(rows)
    check("5 unrelated products at one price -> BROKEN", (not ok) and sev == "broken")
    # 3 unrelated, padded with clean distinct-priced rows so shared_frac stays low ->
    # isolates the CANON-COUNT trigger (max_canon=3 >= SUSPECT) without the fraction path.
    clean = [dict(item=f"CLEAN {i}", sku_raw=f"CLEAN {i}", canonical=f"k{i}",
                  sale=100 + i, mrp=200 + i) for i in range(40)]
    rows3 = rows[:3] + clean
    ok3, det3, sev3 = review.shared_price_dup(rows3)
    check("3 unrelated products at one price (frac low) -> fires (SUSPECT)",
          (not ok3) and sev3 == "suspect")
    print(f"      detail: {det3}")


# ---- B. real flipkart legit case MUST pass ----------------------------------
def test_flipkart_legit_passes():
    print("B. real flipkart legit case (seller-dup + combos) -> must PASS")
    rows = [
        # pair (1285,1650): 2 seller-dup 'CANOLA 5L' + a 4+1L combo
        dict(item="CANOLA 5L", sku_raw="CANOLA 5L", canonical="EDOHHX9RDSSJGYGG", sale=1285, mrp=1650),
        dict(item="CANOLA 5L", sku_raw="CANOLA 5L", canonical="EDOHYRG4UMJFF2YE", sale=1285, mrp=1650),
        dict(item="CANOLA 4+1L", sku_raw="CANOLA 4+1L", canonical="EDOHHXANUW9SHPPJ", sale=1285, mrp=1650),
        # pair (1496,3247): two 3-oil combos, oils in different order
        dict(item="EXTRA LIGHT 1L+POMACE 1L+EXTRA VIRGIN 1L", sku_raw="EXTRA LIGHT 1L+POMACE 1L+EXTRA VIRGIN 1L", canonical="EDOGNZ74XZGU6ZHR", sale=1496, mrp=3247),
        dict(item="EXTRA LIGHT 1L+EXTRA VIRGIN 1L+POMACE 1L", sku_raw="EXTRA LIGHT 1L+EXTRA VIRGIN 1L+POMACE 1L", canonical="QWRGGDFMZKGBZZYG", sale=1496, mrp=3247),
        # pair (1404,2025): two 'CANOLA 5+1L' combos
        dict(item="CANOLA 5+1L", sku_raw="CANOLA 5+1L", canonical="EDOHHXABMQ3JVFSR", sale=1404, mrp=2025),
        dict(item="CANOLA 5+1L", sku_raw="CANOLA 5+1L", canonical="EDOHHZBQB9P4Z6WM", sale=1404, mrp=2025),
        # a few normal distinct rows
        dict(item="MUSTARD 5L", sku_raw="MUSTARD 5L", canonical="m1", sale=1133, mrp=1250),
        dict(item="SO OLIVE 1L", sku_raw="SO OLIVE 1L", canonical="m2", sale=237, mrp=325),
    ]
    ok, detail, sev = review.shared_price_dup(rows)
    check("flipkart legit (seller-dup+combos) -> PASS", ok)
    print(f"      detail: {detail}")


# ---- staleness helpers -------------------------------------------------------
def _write_history(root, platform, runs):
    """runs: list of (run_id, {canonical: price}). Writes data/<p>/history.csv."""
    d = os.path.join(root, "data", platform)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "history.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["run_id", "date_ist", "platform", "canonical_sku",
                    "city", "pincode", "price", "mrp", "discount_pct", "in_stock"])
        for rid, prices in runs:
            for c, p in prices.items():
                w.writerow([rid, rid[:10], platform, c, "X", "0", p, p, 0, 1])


def _staleness(root, platform, this_rows, pct_nonrt):
    data = {"summary": {"freshness": {"pct_non_realtime": pct_nonrt}}}
    return review.staleness_alarm(data, this_rows, platform, "2099-01-01-0000")


# ---- C. truly-stuck scraper MUST still fire ---------------------------------
def test_stuck_scraper_fires():
    print("C. truly-stuck scraper (every SKU frozen, snapshot, nothing moved) -> must FIRE")
    tmp = tempfile.mkdtemp(prefix="w3stuck_")
    orig = review.ROOT
    try:
        review.ROOT = tmp
        frozen = {"a": 100.0, "b": 200.0, "c": 300.0}
        runs = [(f"2026-05-{d:02d}-1200", dict(frozen)) for d in range(1, 11)]  # 10 runs, all identical
        _write_history(tmp, "stuckplat", runs)
        this_rows = [dict(canonical=c, sale=p) for c, p in frozen.items()]
        ok, detail, sev = _staleness(tmp, "stuckplat", this_rows, 100.0)
        check("all-frozen + snapshot + no movers -> FIRES (SUSPECT)", (not ok) and sev == "suspect")
        print(f"      detail: {detail}")
    finally:
        review.ROOT = orig


# ---- D. genuinely-stable (some SKU moved) MUST pass --------------------------
def test_stable_with_mover_passes():
    print("D. genuinely-stable, one SKU moved on same path (zepto real case) -> must PASS")
    tmp = tempfile.mkdtemp(prefix="w3stable_")
    orig = review.ROOT
    try:
        review.ROOT = tmp
        # a,b,c frozen across all runs; 'mover' changes price mid-window
        runs = []
        for i, d in enumerate(range(1, 11)):
            prices = {"a": 100.0, "b": 200.0, "c": 300.0,
                      "mover": 500.0 if i < 5 else 560.0}
            runs.append((f"2026-05-{d:02d}-1200", prices))
        _write_history(tmp, "liveplat", runs)
        this_rows = [dict(canonical=c, sale=p) for c, p in
                     {"a": 100.0, "b": 200.0, "c": 300.0, "mover": 560.0}.items()]
        ok, detail, sev = _staleness(tmp, "liveplat", this_rows, 100.0)
        check("frozen SKUs but path proven live by a mover -> PASS", ok)
        print(f"      detail: {detail}")
    finally:
        review.ROOT = orig


if __name__ == "__main__":
    test_fabrication_fires()
    test_flipkart_legit_passes()
    test_stuck_scraper_fires()
    test_stable_with_mover_passes()
    print()
    if FAILS:
        print(f"RESULT: {len(FAILS)} FIXTURE(S) FAILED: {FAILS}")
        sys.exit(1)
    print("RESULT: ALL FIXTURES PASS")
