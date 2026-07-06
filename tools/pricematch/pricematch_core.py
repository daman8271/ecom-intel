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
          stores_below: [{pincode, city, price}],
          pin_groups: [{price, pincodes, is_mode}]}   # per-pincode platforms only;
                                                      # pan-India, mode group first

Rules (owner-ratified):
  - Reference = the regime price for the given date (Fri/Sat/Sun -> SVD, else BAU;
    regime.json overrides win on exact date match).
  - Tolerance Rs 1: |live_modal - ref| <= 1 => MATCH.
  - BELOW = live_modal < ref-1 (red). ABOVE = live_modal > ref+1 (green).
  - stores_below lists EVERY in-stock store/pincode row priced < ref-1, even when the
    modal itself is fine.
  - Live price basis = modal of in-stock rows; min/max recorded. No in-stock rows => OOS.
  - load_context(basis_pincode=...) narrows the verdict basis to in-stock rows AT that
    pincode (national platforms keep their one all-India price; stores_below stays
    pan-India). Default None = the legacy modal across all stores.
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

# SVD applies on the first N calendar days of any month (any weekday), in addition
# to the weekday defaults (Fri/Sat/Sun). Owner-confirmed 2026-06-09.
SVD_FIRST_N_DAYS = 7

# ---- Competitor price-match (JOB B) — owner-confirmed 2026-06-09 -------------
# Reference pincodes the compete sheets evaluate at (NOT modal/average — exact
# rows at these pincodes). Owner order 2026-06-11 night: 110092 (East Delhi,
# the richest-coverage pin) replaces 110095, and 560006 (J.C. Nagar Bengaluru,
# owner probe newly added to all 5 QC sweeps) replaces 560005. These are also
# the Matrix pins (build_pricematch.PM_MATRIX_PINS).
PM_REF_PINCODES = ["110092", "560006"]
# Platforms whose ONE national price applies at every pincode (marketplace /
# all-India). For these we ignore the pincode arg and tag the cell national=True.
NATIONAL_PLATFORMS = {"amazon", "flipkart"}  # bigbasket moved to per-pincode (licensed QC pincode feed) 2026-06-15 -> gets basis pricing + pin_groups (Pin Spread) like the other QC platforms


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


def _pin_groups(in_rows, prices):
    """Group in-stock rows by sale price -> the distinct pincodes at that price.
    Returns [{price, pincodes, is_mode}] with the mode group first, then by pin
    count (desc), then price. A pincode selling at two prices (two stores)
    appears in both groups — that is the real spread, not a dedupe bug. Rows
    without a usable pincode ('-'/'') are skipped; [] if none has one."""
    by_price = {}
    for r, p in zip(in_rows, prices):
        pc = str(r.get("pincode", "") or "")
        if not pc or pc == "-":
            continue
        by_price.setdefault(p, set()).add(pc)
    if not by_price:
        return []
    mode = _modal(prices)
    groups = [{"price": p, "pincodes": sorted(pins), "is_mode": p == mode}
              for p, pins in by_price.items()]
    groups.sort(key=lambda g: (not g["is_mode"], -len(g["pincodes"]), g["price"]))
    return groups


# ---------------------------------------------------------------- regime

_BUILTIN_DEFAULTS = {"mon": "BAU", "tue": "BAU", "wed": "BAU", "thu": "BAU",
                     "fri": "SVD", "sat": "SVD", "sun": "SVD"}


def regime_for(date=None, cfg=None):
    """'BAU'|'SVD'|'ART' for the given date. cfg (dict) is an optional injected
    regime config for testing; default reads tools/pricematch/regime.json.
    A missing/corrupt regime.json degrades to the built-in Fri-Sun=SVD defaults.

    Resolution order (first match wins):
      1. An exact-date override in regime.json (ART or explicit BAU/SVD) ALWAYS wins.
      2. The weekday default (Fri/Sat/Sun -> SVD, else BAU).
      3. FIRST-WEEK rule (owner-confirmed 2026-06-09): if steps 1-2 resolved to BAU
         and the date is within the first SVD_FIRST_N_DAYS (=7) days of its month,
         upgrade to SVD. So days 1-7 of any month are SVD on ANY weekday, while an
         explicit ART/override on such a date still wins (step 1 precedence)."""
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
                return r  # override (incl. ART) wins outright
    dow = DOW_KEYS[d.weekday()]
    r = str((cfg.get("defaults") or {}).get(dow, _BUILTIN_DEFAULTS[dow])).upper()
    if r not in REGIMES:
        r = _BUILTIN_DEFAULTS[dow]
    # First-week-of-month rule: only upgrades a plain BAU weekday to SVD; never
    # downgrades SVD and never overrides an explicit override above.
    if r == "BAU" and d.day <= SVD_FIRST_N_DAYS:
        return "SVD"
    return r


# ---------------------------------------------------------------- context

def _index_live(platform):
    """Read platforms/<p>/result.json fresh and index allRows by listing id.
    BigBasket is fed by the licensed QuickCommerce per-pincode pull
    (result_pincode.json, per-pincode rows for the Pin Spread); falls back to
    result.json (national scrape) if that pull hasn't run today."""
    path = os.path.join(PLATFORMS_DIR, platform, "result.json")
    if platform == "bigbasket":
        _pin = os.path.join(PLATFORMS_DIR, platform, "result_pincode.json")
        if os.path.exists(_pin):
            path = _pin
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


def load_context(date=None, basis_pincode=None):
    """Load master + map + regime + fresh live rows for every platform.

    basis_pincode: when set, platform_comparison prices per-pincode platforms
    from in-stock rows AT this pincode only (owner order 2026-06-11)."""
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
        "basis_pincode": str(basis_pincode) if basis_pincode else None,
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
        if not rows:
            rec["status"] = "NOT_LISTED"
            records.append(rec)
            continue

        in_rows = [r for r in rows if r.get("in_stock") and _num(r.get("sale")) is not None]
        # verdict basis: rows at the basis pincode when one is set (national
        # platforms carry one all-India price, so they are never narrowed)
        basis_pin = ctx.get("basis_pincode")
        if basis_pin and platform not in NATIONAL_PLATFORMS:
            basis_rows = [r for r in in_rows if str(r.get("pincode", "")) == basis_pin]
        else:
            basis_rows = in_rows
        prices = [_round2(_num(r.get("sale"))) for r in basis_rows]
        all_prices = [_round2(_num(r.get("sale"))) for r in in_rows]
        mrps = [_num(r.get("mrp")) for r in (in_rows or rows) if _num(r.get("mrp")) is not None]
        if mrps:
            rec["mrp_live"] = _round2(_modal(mrps))

        # EVERY in-stock store under ref-1 — pan-India regardless of the basis,
        # so the Violations safety net never shrinks when the basis narrows
        if ref is not None and in_rows:
            below = [
                {"pincode": str(r.get("pincode", "")), "city": r.get("city", ""), "price": p}
                for r, p in zip(in_rows, all_prices) if p < ref - TOLERANCE
            ]
            rec["stores_below"] = sorted(below, key=lambda s: (s["price"], s["pincode"]))

        # pan-India pin price groups (additive, 2026-06-11) — feeds the Matrix
        # PINCODE SPREAD section. Per-pincode platforms only: national carry
        # one all-India price, so a spread is meaningless there.
        if platform not in NATIONAL_PLATFORMS and in_rows:
            pg = _pin_groups(in_rows, all_prices)
            if pg:
                rec["pin_groups"] = pg

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
            rec["status"] = "OOS"  # no in-stock rows at the basis -> no verdict
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


# ------------------------------------------------- competitor compare (JOB B)
#
# COLOR POLARITY (OWNER — OPPOSITE to the agreed-price sheets, flag it loudly):
#   a COMPETITOR priced BELOW the reference (undercutting our Amazon) = RED;
#   ABOVE the reference = GREEN; within +/- TOLERANCE of it = MATCH.
#   diff = competitor_price - ref_price  (NEGATIVE diff = undercut = RED).
# This is the inverse of platform_comparison's BELOW=red-against-our-own-floor.

def price_at(platform, sku, pincode, live=None, skumap=None):
    """Live price for a master SKU on a platform at a SPECIFIC pincode.

    Returns {sale, mrp, in_stock, seller} or None. Read FRESH from
    platforms/<p>/result.json (never the sku_map snapshot prices).
      - None            -> not serviceable here: unknown/no-data platform
                           (e.g. /), no ratified mapping, or no
                           row at this pincode at all.
      - in_stock False  -> a row exists at the pincode but is OOS / unpriced.
      - in_stock True   -> sale is the modal in-stock price at the pincode.
    NATIONAL_PLATFORMS ignore the pincode (one national price for every pincode).
    `live`/`skumap` are optional injected caches (competitor_compare passes them
    so the inner loop reads each result.json once)."""
    if platform not in ID_FIELD:
        return None  # caller-passed but we have no data (, removed )
    if skumap is None:
        skumap = _load_json(MAP_PATH)
    if live is None:
        live = _index_live(platform)
    national = platform in NATIONAL_PLATFORMS

    entry = (skumap.get("skus") or {}).get(sku) or {}
    plat = (entry.get("platforms") or {}).get(platform)
    listings = _candidate_listings(plat) if plat else []
    if not listings:
        return None  # no ratified mapping for this SKU on this platform

    listing, rows = listings[0], _rows_for(live, listings[0])
    for alt in listings[1:]:
        if rows:
            break
        arows = _rows_for(live, alt)
        if arows:
            listing, rows = alt, arows

    if not national:
        rows = [r for r in rows if str(r.get("pincode", "")) == str(pincode)]
    if not rows:
        return None  # not serviceable at this pincode

    in_rows = [r for r in rows if r.get("in_stock") and _num(r.get("sale")) is not None]
    if not in_rows:
        mrps = [_num(r.get("mrp")) for r in rows if _num(r.get("mrp")) is not None]
        return {"sale": None, "mrp": _round2(_modal(mrps)) if mrps else None,
                "in_stock": False, "seller": rows[0].get("seller")}

    prices = [_round2(_num(r.get("sale"))) for r in in_rows]
    sale = _modal(prices)
    mrps = [_num(r.get("mrp")) for r in in_rows if _num(r.get("mrp")) is not None]
    seller = next((r.get("seller") for r in in_rows
                   if _round2(_num(r.get("sale"))) == sale), in_rows[0].get("seller"))
    return {"sale": sale, "mrp": _round2(_modal(mrps)) if mrps else None,
            "in_stock": True, "seller": seller}


def buybox_seller(sku, live=None, skumap=None):
    """Amazon-core current buybox seller + price for a master SKU, or None.
    seller is the raw amazon `seller` field: 'RK World Infocom Pvt Ltd',
    'Jivo Mart', or '' (blank = Amazon-fulfilled). Used for the compete sheet's
    'Amazon Jivo Mart' (RK/JM/blank) column when amazon-core is the reference."""
    p = price_at("amazon", sku, "-", live=live, skumap=skumap)
    if p is None or not p.get("in_stock"):
        return None
    return {"seller": p.get("seller"), "sale": p.get("sale")}


def competitor_compare(ref_platform, competitor_platforms, skus, pincodes=PM_REF_PINCODES):
    """Compare each competitor platform's per-pincode price against a REFERENCE
    platform's price, for every (sku, pincode). Returns one record per
    (sku, pincode):
        {sku, pincode, ref_price, ref_seller?, cells: [
            {platform, price, in_stock, national, diff, status}, ... ]}
    ref_price is the reference's in-stock price at that pincode (for amazon-core
    ref this is the national buybox price; for amazon-now ref it is the
    per-pincode price). ref_seller is present only for amazon-core ref (buybox).

    cell.status, in precedence order:
      NOT_SERVICEABLE  competitor has no row here (or no data at all) -> blank
      OOS              a row exists but is out of stock / unpriced
      NO_REF           competitor IS priced but the reference has no price
      BELOW  (RED)     competitor priced < ref - TOLERANCE  (undercut)
      ABOVE  (GREEN)   competitor priced > ref + TOLERANCE
      MATCH            within +/- TOLERANCE of the reference
    """
    skumap = _load_json(MAP_PATH)
    needed = {ref_platform, *competitor_platforms}
    live = {p: _index_live(p) for p in needed if p in ID_FIELD}
    ref_is_core = (ref_platform == "amazon")

    out = []
    for sku in skus:
        for pincode in pincodes:
            ref = (price_at(ref_platform, sku, pincode, live=live.get(ref_platform), skumap=skumap)
                   if ref_platform in ID_FIELD else None)
            ref_price = ref["sale"] if (ref and ref.get("in_stock")) else None
            if ref_is_core:
                bb = buybox_seller(sku, live=live.get("amazon"), skumap=skumap)
                ref_seller = bb["seller"] if bb else None
            else:
                ref_seller = ref.get("seller") if ref else None

            cells = []
            for plat in competitor_platforms:
                national = plat in NATIONAL_PLATFORMS
                p = (price_at(plat, sku, pincode, live=live.get(plat), skumap=skumap)
                     if plat in ID_FIELD else None)
                cell = {"platform": plat, "price": None, "in_stock": False,
                        "national": national, "diff": None, "status": None}
                if p is None:
                    cell["status"] = "NOT_SERVICEABLE"
                elif not p.get("in_stock"):
                    cell["status"] = "OOS"
                elif ref_price is None:
                    cell["price"] = p["sale"]
                    cell["in_stock"] = True
                    cell["status"] = "NO_REF"
                else:
                    cell["price"] = p["sale"]
                    cell["in_stock"] = True
                    diff = round(p["sale"] - ref_price, 2)
                    cell["diff"] = diff
                    if diff < -TOLERANCE:
                        cell["status"] = "BELOW"   # RED: competitor undercuts our Amazon
                    elif diff > TOLERANCE:
                        cell["status"] = "ABOVE"   # GREEN: competitor dearer than our Amazon
                    else:
                        cell["status"] = "MATCH"
                cells.append(cell)

            rec = {"sku": sku, "pincode": pincode, "ref_price": _round2(ref_price),
                   "cells": cells}
            if ref_seller is not None:
                rec["ref_seller"] = ref_seller
            out.append(rec)
    return out


# ------------------------------------------- EXACT price-match (cross-platform)
#
# DISTINCT from the Matrix +/-5 cluster: this detects 2+ platforms sitting at the
# IDENTICAL price for one SKU (genuine price-matching between platforms). "Same
# price" = the prices round to the same whole rupee (|a-b| < 0.5). This is a
# neutral *signal* — NOT a compliance verdict, NOT red/green.

EXACT_MATCH_TOL = 0.5  # "same price" = prices round to the same whole rupee


def exact_price_match(price_by_platform):
    """Given {platform: price} (None / non-numeric = not priced), return the
    groups of >=2 platforms sharing the SAME price (within EXACT_MATCH_TOL, i.e.
    rounding to the same whole rupee). Each group:
        {"price": <rounded Rs>, "platforms": [<platform keys sorted>]}
    Groups sorted by size desc then price asc. Empty list if no 2 platforms share
    a price. None / non-numeric prices are ignored. A platform appears in at most
    one group (it lands in exactly one whole-rupee bucket)."""
    buckets = {}  # rounded-rupee -> [platform, ...]
    for plat, price in (price_by_platform or {}).items():
        v = _num(price)
        if v is None:
            continue
        key = int(round(v))  # whole-rupee bucket; |a-b| < 0.5 => same bucket
        buckets.setdefault(key, []).append(plat)
    groups = [
        {"price": key, "platforms": sorted(plats)}
        for key, plats in buckets.items() if len(plats) >= 2
    ]
    groups.sort(key=lambda g: (-len(g["platforms"]), g["price"]))
    return groups


def _board_price(platform, sku, pincodes, live, skumap):
    """A single board-wide live price for (platform, sku), or None. National
    platforms use their one price; per-pincode platforms use the modal of the
    in-stock prices observed across the reference pincodes."""
    if platform not in ID_FIELD:
        return None
    if platform in NATIONAL_PLATFORMS:
        p = price_at(platform, sku, "-", live=live.get(platform), skumap=skumap)
        return p["sale"] if (p and p.get("in_stock")) else None
    sales = []
    for pc in pincodes:
        p = price_at(platform, sku, pc, live=live.get(platform), skumap=skumap)
        if p and p.get("in_stock") and p.get("sale") is not None:
            sales.append(p["sale"])
    return _modal(sales) if sales else None


def board_price_matches(skus, platforms=PLATFORM_ORDER, pincodes=PM_REF_PINCODES,
                        live=None, skumap=None):
    """Board-wide convenience: per SKU, build {platform: live_price} from the FRESH
    live records and run exact_price_match. Returns the SKUs that have at least one
    exact-match group:
        [{"sku": <name>, "groups": [<exact_price_match group>, ...]}, ...]
    `live`/`skumap` are optional injected caches (read once each if omitted).
    W2 may call this for the Ecom Head summary, or build the {platform: price} dict
    itself and call exact_price_match directly — both are supported."""
    if skumap is None:
        skumap = _load_json(MAP_PATH)
    if live is None:
        live = {p: _index_live(p) for p in platforms if p in ID_FIELD}
    out = []
    for sku in skus:
        pbp = {p: _board_price(p, sku, pincodes, live, skumap) for p in platforms}
        groups = exact_price_match(pbp)
        if groups:
            out.append({"sku": sku, "groups": groups})
    return out


# ---------------------------------------------------------------- CLI

def main(argv=None):
    ap = argparse.ArgumentParser(description="Jivo price-match violations engine (deterministic)")
    ap.add_argument("--date", default=None, help="YYYY-MM-DD (default: today)")
    ap.add_argument("--json", nargs="?", const="__ALL__", default=None, metavar="PLATFORM",
                    help="dump JSON: all platforms + summary, or one platform's records")
    ap.add_argument("--compete", default=None, metavar="REF_PLATFORM",
                    help="dump competitor_compare JSON with this reference platform "
                         "(e.g. amazon-now or amazon); competitors = the other live platforms")
    ap.add_argument("--exact-demo", action="store_true",
                    help="list SKUs where 2+ platforms sit at the EXACT same Rs "
                         "(exact_price_match / board_price_matches smoke test)")
    args = ap.parse_args(argv)

    if args.exact_demo:
        ctx = load_context(args.date)
        matches = board_price_matches(ctx["sku_names"])
        print("exact price-matches (2+ platforms at identical Rs)  %s  regime=%s"
              % (ctx["date"], ctx["regime"]))
        if not matches:
            print("  (no SKU has 2+ platforms at an identical price today)")
        for m in matches:
            for g in m["groups"]:
                print("  Rs%-7s x%d  %-34s %s" % (
                    g["price"], len(g["platforms"]), m["sku"][:34],
                    ", ".join(g["platforms"])))
        return 0

    if args.compete is not None:
        ref = args.compete
        ctx = load_context(args.date)
        competitors = [p for p in PLATFORM_ORDER if p != ref]
        recs = competitor_compare(ref, competitors, ctx["sku_names"])
        json.dump({"date": ctx["date"], "ref_platform": ref,
                   "ref_pincodes": PM_REF_PINCODES, "competitors": competitors,
                   "records": recs}, sys.stdout, indent=1)
        sys.stdout.write("\n")
        return 0

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
