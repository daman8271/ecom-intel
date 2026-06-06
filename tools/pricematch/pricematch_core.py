#!/usr/bin/env python3
"""pricematch_core — deterministic price-match violations engine (NO LLM, NO network).

Loads the SKU map (tools/pricematch/sku_map.json) + master prices (master_v2.json) +
today's pricing regime (regime.json), joins each mapped listing to FRESH live per-store
prices from platforms/<p>/result.json, and emits structured comparison records that the
Excel sheet builders consume.

FROZEN CONTRACT (sheet builders code against these names — do not change):
    regime_for(date) -> 'BAU'|'SVD'|'ART'
    load_context(date=None) -> ctx
    platform_comparison(ctx, platform) -> list[record]
    all_comparisons(ctx) -> dict[platform, list[record]]
    summary(ctx) -> dict

record = {sku, platform, listing_id, url, title, regime, ref_price, live_modal,
          live_min, live_max, in_stock, mrp_live, mrp_official, diff, diff_pct,
          status: 'BELOW'|'ABOVE'|'MATCH'|'OOS'|'NO_REF'|'PENDING_REVIEW'|'NOT_LISTED',
          stores_below: [{pincode, city, price}]}

Rules (owner-ratified):
  - Reference = the regime price for the given date (Fri/Sat/Sun -> SVD, else BAU;
    regime.json overrides win on exact date match).
  - Tolerance Rs 1: |live_modal - ref| <= 1 => MATCH.
  - BELOW = live_modal < ref-1 (red). ABOVE = live_modal > ref+1 (green).
  - stores_below lists EVERY in-stock store/pincode row priced < ref-1, even when the
    modal itself is fine.
  - Live price basis = modal of in-stock rows; min/max recorded. No in-stock rows => OOS.
  - Zepto rows are already SUPER_SAVER prices (no adjustment).
  - Only confidence exact/anchored mappings participate; a review-pending candidate
    (sku_map.json "review" list) with no ratified mapping => PENDING_REVIEW (counted,
    never priced). retired SKUs excluded entirely. In master but no mapping => NOT_LISTED.

CLI:  python3 pricematch_core.py [--date YYYY-MM-DD] [--json [platform]]
"""

import argparse
import datetime
import json
import os
import sys
from collections import Counter

# All paths resolve relative to this file (sandbox/relocation-safe), with env
# overrides: PM_ROOT (repo root holding platforms/), PM_DIR (dir holding the
# three json inputs), and per-file PM_MASTER / PM_MAP / PM_REGIME / PM_PLATFORMS.
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.environ.get("PM_ROOT") or os.path.join(HERE, "..", ".."))
PM_DIR = os.path.abspath(os.environ.get("PM_DIR") or HERE)

MASTER_PATH = os.environ.get("PM_MASTER") or os.path.join(PM_DIR, "master_v2.json")
MAP_PATH = os.environ.get("PM_MAP") or os.path.join(PM_DIR, "sku_map.json")
REGIME_PATH = os.environ.get("PM_REGIME") or os.path.join(PM_DIR, "regime.json")
PLATFORMS_DIR = os.environ.get("PM_PLATFORMS") or os.path.join(ROOT, "platforms")

TOLERANCE = 1.0  # Rs; |diff| <= 1 => MATCH

# Canonical platform order (mirrors the live sweep) and the result.json row field
# that carries each platform's listing id (the join key to sku_map entries).
ID_FIELD = {
    "amazon": "asin",
    "flipkart": "fsn",
    "amazon-fresh": "asin",
    "amazon-now": "asin",
    "flipkart-minutes": "fk_pid",
    "zepto": "variant_id",
    "blinkit": "prid",
    "bigbasket": "sku_id",
}
PLATFORM_ORDER = [
    "amazon", "flipkart", "amazon-fresh", "amazon-now",
    "flipkart-minutes", "zepto", "blinkit", "bigbasket",
]

REGIMES = ("BAU", "SVD", "ART")
REGIME_PRICE_KEY = {"BAU": "bau", "SVD": "svd", "ART": "art"}
DOW_KEYS = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")  # date.weekday() 0=mon
ALLOWED_CONFIDENCE = ("exact", "anchored")


# ---------------------------------------------------------------- helpers

def _as_date(date=None):
    """Accept None / 'YYYY-MM-DD' / datetime.date|datetime -> datetime.date."""
    if date is None:
        return datetime.date.today()
    if isinstance(date, datetime.datetime):
        return date.date()
    if isinstance(date, datetime.date):
        return date
    return datetime.datetime.strptime(str(date).strip(), "%Y-%m-%d").date()


def _load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _num(v):
    """Coerce to float if it is a usable price, else None."""
    if v is None or isinstance(v, bool):
        return None
    try:
        f = float(v)
    except (TypeError, ValueError):
        return None
    return f if f > 0 else None


def _round2(v):
    return None if v is None else round(v + 0.0, 2)


def _modal(prices):
    """Most common price; ties broken by the LOWEST price (conservative for
    a below-reference check). prices must be a non-empty list of floats."""
    counts = Counter(prices)
    top = max(counts.values())
    return min(p for p, c in counts.items() if c == top)


# ---------------------------------------------------------------- regime

_BUILTIN_DEFAULTS = {"mon": "BAU", "tue": "BAU", "wed": "BAU", "thu": "BAU",
                     "fri": "SVD", "sat": "SVD", "sun": "SVD"}


def regime_for(date=None, cfg=None):
    """'BAU'|'SVD'|'ART' for the given date. cfg (dict) is an optional injected
    regime config for testing; default reads tools/pricematch/regime.json.
    A missing/corrupt regime.json degrades to the built-in Fri-Sun=SVD defaults."""
    d = _as_date(date)
    if cfg is None:
        try:
            cfg = _load_json(REGIME_PATH)
        except (OSError, ValueError):
            cfg = {"defaults": _BUILTIN_DEFAULTS, "overrides": []}
    if not isinstance(cfg, dict):
        cfg = {"defaults": _BUILTIN_DEFAULTS, "overrides": []}
    iso = d.isoformat()
    for ov in cfg.get("overrides") or []:
        if str(ov.get("date")) == iso:
            r = str(ov.get("regime", "")).upper()
            if r in REGIMES:
                return r
    dow = DOW_KEYS[d.weekday()]
    r = str((cfg.get("defaults") or {}).get(dow, _BUILTIN_DEFAULTS[dow])).upper()
    return r if r in REGIMES else _BUILTIN_DEFAULTS[dow]


# ---------------------------------------------------------------- context

def _index_live(platform):
    """Read platforms/<p>/result.json fresh and index allRows by listing id."""
    path = os.path.join(PLATFORMS_DIR, platform, "result.json")
    out = {"by_id": {}, "by_canonical": {}, "rows": 0, "mtime": None, "path": path}
    if not os.path.exists(path):
        return out
    try:
        data = _load_json(path)
    except (ValueError, OSError):
        return out
    rows = data.get("allRows") or []
    out["rows"] = len(rows)
    out["mtime"] = datetime.datetime.fromtimestamp(os.path.getmtime(path)).isoformat(timespec="seconds")
    idf = ID_FIELD[platform]
    for r in rows:
        rid = r.get(idf)
        if rid not in (None, ""):
            out["by_id"].setdefault(str(rid), []).append(r)
        elif r.get("canonical"):
            # fallback bucket for rows that arrived without the id field
            out["by_canonical"].setdefault(str(r["canonical"]), []).append(r)
    return out


def load_context(date=None):
    """Load master + map + regime + fresh live rows for every platform."""
    d = _as_date(date)
    master = _load_json(MASTER_PATH)
    skumap = _load_json(MAP_PATH)
    map_skus = skumap.get("skus") or {}

    # review-pending candidates: (sku, platform) -> review entry (first wins)
    pending = {}
    for rv in skumap.get("review") or []:
        if isinstance(rv, dict) and rv.get("candidate") and rv.get("platform"):
            pending.setdefault((rv["candidate"], rv["platform"]), rv)

    # master SKU list, retired excluded entirely (master order preserved)
    sku_names = [
        name for name, _ in (master.get("skus") or {}).items()
        if not (map_skus.get(name) or {}).get("retired")
    ]

    return {
        "date": d.isoformat(),
        "regime": regime_for(d),
        "master": master.get("skus") or {},
        "map": map_skus,
        "pending": pending,
        "sku_names": sku_names,
        "live": {p: _index_live(p) for p in PLATFORM_ORDER},
        "_comparisons": {},  # per-platform cache
    }


# ---------------------------------------------------------------- comparison

def _candidate_listings(entry):
    """Primary mapping first, then alt listings — allowed confidence only."""
    out = []
    if entry.get("confidence") in ALLOWED_CONFIDENCE:
        out.append(entry)
    for alt in entry.get("alt") or []:
        if isinstance(alt, dict) and alt.get("confidence") in ALLOWED_CONFIDENCE:
            out.append(alt)
    return out


def _rows_for(live, listing):
    """Join a map listing to fresh live rows: by id, else by canonical slug."""
    rows = live["by_id"].get(str(listing.get("id")), [])
    if rows:
        return rows
    # rare fallback: rows that came in without the id field, joined on the
    # canonical slug embedded in the listing url's last path segments
    url = listing.get("url") or ""
    for canon, crows in live["by_canonical"].items():
        if canon and canon in url:
            return crows
    return []


def _base_record(sku, platform, regime, ref, mrp_official, listing=None):
    return {
        "sku": sku,
        "platform": platform,
        "listing_id": (listing or {}).get("id"),
        "url": (listing or {}).get("url"),
        "title": (listing or {}).get("title"),
        "regime": regime,
        "ref_price": _round2(ref),
        "live_modal": None,
        "live_min": None,
        "live_max": None,
        "in_stock": False,
        "mrp_live": None,
        "mrp_official": mrp_official,
        "diff": None,
        "diff_pct": None,
        "status": None,
        "stores_below": [],
    }


def platform_comparison(ctx, platform):
    """One record per (non-retired) master SKU for this platform."""
    if platform in ctx["_comparisons"]:
        return ctx["_comparisons"][platform]
    if platform not in ID_FIELD:
        raise ValueError("unknown platform: %r (expected one of %s)" % (platform, PLATFORM_ORDER))

    regime = ctx["regime"]
    price_key = REGIME_PRICE_KEY[regime]
    live = ctx["live"][platform]
    records = []

    for sku in ctx["sku_names"]:
        m = ctx["master"][sku]
        ref = _num(m.get(price_key))
        mrp_official = _num(m.get("mrp"))
        entry = (ctx["map"].get(sku) or {}).get("platforms", {}).get(platform)
        listings = _candidate_listings(entry) if entry else []

        if not listings:
            # no ratified mapping: review-pending candidate, else NOT_LISTED
            rv = ctx["pending"].get((sku, platform))
            rec = _base_record(sku, platform, regime, ref, mrp_official)
            if rv is not None:
                rec["listing_id"] = rv.get("id")
                rec["title"] = rv.get("title")
                rec["status"] = "PENDING_REVIEW"  # counted, never priced
            else:
                rec["status"] = "NOT_LISTED"
            records.append(rec)
            continue

        # join FRESH live rows: primary listing first, alts only if primary has none
        listing, rows = listings[0], _rows_for(live, listings[0])
        for alt in listings[1:]:
            if rows:
                break
            arows = _rows_for(live, alt)
            if arows:
                listing, rows = alt, arows

        rec = _base_record(sku, platform, regime, ref, mrp_official, listing)
        in_rows = [r for r in rows if r.get("in_stock") and _num(r.get("sale")) is not None]
        prices = [_round2(_num(r.get("sale"))) for r in in_rows]
        mrps = [_num(r.get("mrp")) for r in (in_rows or rows) if _num(r.get("mrp")) is not None]
        if mrps:
            rec["mrp_live"] = _round2(_modal(mrps))

        if ref is None:
            rec["status"] = "NO_REF"  # no regime price -> no compliance verdict
            if prices:
                rec["in_stock"] = True
                rec["live_modal"] = _modal(prices)
                rec["live_min"] = min(prices)
                rec["live_max"] = max(prices)
            records.append(rec)
            continue

        if not prices:
            rec["status"] = "OOS"  # no in-stock rows -> no compliance verdict
            records.append(rec)
            continue

        modal = _modal(prices)
        rec["in_stock"] = True
        rec["live_modal"] = modal
        rec["live_min"] = min(prices)
        rec["live_max"] = max(prices)
        diff = round(modal - ref, 2)
        rec["diff"] = diff
        rec["diff_pct"] = round(diff / ref * 100.0, 2)
        if abs(diff) <= TOLERANCE:
            rec["status"] = "MATCH"
        elif diff < -TOLERANCE:
            rec["status"] = "BELOW"   # red: selling under the agreed reference
        else:
            rec["status"] = "ABOVE"   # green
        # EVERY in-stock store under ref-1, even when the modal is fine
        below = [
            {"pincode": str(r.get("pincode", "")), "city": r.get("city", ""), "price": p}
            for r, p in zip(in_rows, prices) if p < ref - TOLERANCE
        ]
        rec["stores_below"] = sorted(below, key=lambda s: (s["price"], s["pincode"]))
        records.append(rec)

    ctx["_comparisons"][platform] = records
    return records


def all_comparisons(ctx):
    return {p: platform_comparison(ctx, p) for p in PLATFORM_ORDER}


# ---------------------------------------------------------------- summary

def summary(ctx):
    """KPIs: per-platform + global status counts, total below-ref exposure Rs."""
    comps = all_comparisons(ctx)
    statuses = ("BELOW", "ABOVE", "MATCH", "OOS", "NO_REF", "PENDING_REVIEW", "NOT_LISTED")
    out = {
        "date": ctx["date"],
        "regime": ctx["regime"],
        "sku_count": len(ctx["sku_names"]),
        "platforms": {},
        "global": {s: 0 for s in statuses},
    }
    g_exposure = 0.0
    g_stores = 0
    for p, recs in comps.items():
        counts = {s: 0 for s in statuses}
        exposure = 0.0
        stores = 0
        for r in recs:
            counts[r["status"]] += 1
            if r["status"] == "BELOW":
                exposure += (r["ref_price"] - r["live_modal"])
            stores += len(r["stores_below"])
        out["platforms"][p] = dict(
            counts,
            records=len(recs),
            below_exposure_inr=round(exposure, 2),
            stores_below_total=stores,
            live_rows=ctx["live"][p]["rows"],
            live_mtime=ctx["live"][p]["mtime"],
        )
        for s in statuses:
            out["global"][s] += counts[s]
        g_exposure += exposure
        g_stores += stores
    out["global"]["records"] = sum(len(r) for r in comps.values())
    out["global"]["below_exposure_inr"] = round(g_exposure, 2)
    out["global"]["stores_below_total"] = g_stores
    return out


# ---------------------------------------------------------------- CLI

def main(argv=None):
    ap = argparse.ArgumentParser(description="Jivo price-match violations engine (deterministic)")
    ap.add_argument("--date", default=None, help="YYYY-MM-DD (default: today)")
    ap.add_argument("--json", nargs="?", const="__ALL__", default=None, metavar="PLATFORM",
                    help="dump JSON: all platforms + summary, or one platform's records")
    args = ap.parse_args(argv)

    ctx = load_context(args.date)
    if args.json == "__ALL__":
        json.dump({"date": ctx["date"], "regime": ctx["regime"],
                   "records": all_comparisons(ctx), "summary": summary(ctx)},
                  sys.stdout, indent=1)
        sys.stdout.write("\n")
        return 0
    if args.json is not None:
        json.dump(platform_comparison(ctx, args.json), sys.stdout, indent=1)
        sys.stdout.write("\n")
        return 0

    s = summary(ctx)
    print("pricematch %s  regime=%s  skus=%d" % (s["date"], s["regime"], s["sku_count"]))
    hdr = ("platform", "BELOW", "ABOVE", "MATCH", "OOS", "NO_REF", "PEND", "NOT_L", "expo Rs", "rows")
    print("%-17s %6s %6s %6s %5s %7s %5s %6s %10s %6s" % hdr)
    for p in PLATFORM_ORDER:
        c = s["platforms"][p]
        print("%-17s %6d %6d %6d %5d %7d %5d %6d %10.2f %6d" % (
            p, c["BELOW"], c["ABOVE"], c["MATCH"], c["OOS"], c["NO_REF"],
            c["PENDING_REVIEW"], c["NOT_LISTED"], c["below_exposure_inr"], c["live_rows"]))
    g = s["global"]
    print("%-17s %6d %6d %6d %5d %7d %5d %6d %10.2f" % (
        "TOTAL", g["BELOW"], g["ABOVE"], g["MATCH"], g["OOS"], g["NO_REF"],
        g["PENDING_REVIEW"], g["NOT_LISTED"], g["below_exposure_inr"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
