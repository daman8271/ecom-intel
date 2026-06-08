#!/usr/bin/env python3
"""W2 independent recompute of the 'Price-Match active (±₹5)' cluster column.

Reads ONLY the engine (pricematch_core --json). Has NO knowledge of how W1
implemented sheet_matrix. Produces, per SKU, the set of price-match clusters:
a cluster = a maximal run of platforms (sorted by live price) whose group
spread max-min <= BAND (=5). Groups of size >=2 only. Priced statuses only
(OOS / NOT_LISTED / PENDING_REVIEW / retired excluded).

Usage: cluster_recompute.py [--date YYYY-MM-DD] [--platforms csv] [--json]
"""
import argparse, json, subprocess, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
CORE = os.path.join(HERE, "..", "pricematch_core.py")
BAND = 5.0
PRICED = {"BELOW", "ABOVE", "MATCH", "NO_REF"}
# canonical platform order (mirrors build_pricematch.CANONICAL)
CANONICAL = ["flipkart-minutes", "flipkart", "zepto", "bigbasket",
             "amazon", "amazon-fresh", "amazon-now", "blinkit"]


def engine(date):
    out = subprocess.run([sys.executable, CORE, "--date", date, "--json"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit("engine failed: " + out.stderr[-500:])
    return json.loads(out.stdout)


def clusters_for(prices):
    """prices: list of (platform, price). Returns list of clusters; each cluster
    is a list of (platform, price) with group spread <= BAND and size >= 2.
    Greedy sorted-window: sort by price; extend the window while
    (current_price - window_min) <= BAND; otherwise close the window and start
    a new one at the current item. This is the natural complete-linkage-on-a-
    line grouping (since the window is sorted, window max-min = last-first)."""
    if not prices:
        return []
    sp = sorted(prices, key=lambda x: x[1])
    out, cur = [], [sp[0]]
    for plat, pr in sp[1:]:
        if pr - cur[0][1] <= BAND:
            cur.append((plat, pr))
        else:
            if len(cur) >= 2:
                out.append(cur)
            cur = [(plat, pr)]
    if len(cur) >= 2:
        out.append(cur)
    return out


def recompute(date, platforms=None):
    d = engine(date)
    recs = d["records"]
    plats = platforms or CANONICAL
    # gather priced live prices per sku
    per_sku = {}
    for p in plats:
        for r in recs.get(p, []):
            if r.get("status") in PRICED:
                lm = r.get("live_modal")
                if lm is None:
                    continue
                per_sku.setdefault(r["sku"], []).append((p, float(lm)))
    result = {}
    for sku, prices in per_sku.items():
        cl = clusters_for(prices)
        if cl:
            result[sku] = cl
    return d, result


def fmt_cluster(cl):
    parts = []
    for cluster in cl:
        plist = ", ".join(p for p, _ in cluster)
        lo = min(pr for _, pr in cluster)
        hi = max(pr for _, pr in cluster)
        band = f"₹{lo:,.0f}" if lo == hi else f"₹{lo:,.0f}–₹{hi:,.0f}"
        parts.append(f"{plist} [{band}]")
    return " | ".join(parts)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", default="2026-06-08")
    ap.add_argument("--platforms")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    plats = [s.strip() for s in a.platforms.split(",")] if a.platforms else None
    d, result = recompute(a.date, plats)
    if a.json:
        # serialize clusters as platform->price maps
        ser = {sku: [[{"platform": p, "price": pr} for p, pr in cl]
                     for cl in cls] for sku, cls in result.items()}
        print(json.dumps({"date": a.date, "clusters": ser}, indent=1))
        return
    print(f"# cluster recompute · {a.date} · BAND=±₹{BAND:.0f}")
    print(f"# SKUs with >=1 price-match cluster: {len(result)}")
    for sku in sorted(result):
        print(f"{sku:28s} {fmt_cluster(result[sku])}")


if __name__ == "__main__":
    main()
