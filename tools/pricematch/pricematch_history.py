#!/usr/bin/env python3
"""pricematch_history.py — persist the daily price-match compliance numbers as
machine history so the Obsidian vault (W2) and any trend tooling can read them.

Deterministic, stdlib-only (no openpyxl, no network, NO LLM). Idempotent: re-running
for a date REPLACES that date's rows (keyed on date) — never duplicates — and produces
a byte-identical file given the same inputs.

Two stores under data/pricematch/ (created on first write):

  history.csv  — one row per (date, sku, platform). FROZEN columns (W2 binds to these):
    date, regime, sku, platform, listing_id, ref_price, live_modal, live_min, live_max,
    in_stock, status, diff, diff_pct, stores_below_count, mrp_official, mrp_live

  daily.csv    — one compact rollup row per date. FROZEN columns:
    date, regime, skus_tracked, listings, below, above, match, oos, pending, not_listed,
    exposure, store_violations, top_offender_sku, top_offender_platform, top_offender_diff

Sources of truth:
  - "Full" dates (today, or any day re-run): rows are computed straight from the engine's
    all_comparisons(ctx) records — the SAME objects build_pricematch.py already holds, so
    the capture hook appends from those, it does NOT recompute.
  - "KPI-only" dates (backfilled past days the engine can't reproduce — live result.json
    is overwritten each sweep): only daily.csv is filled, from the *.summary.json sidecar
    (top offender parsed from summary_md). The ABSENCE of per-SKU history.csv rows for a
    date is itself the "this date is KPI-only" marker (history.csv stays honest).

CLI:
  python3 pricematch_history.py                 # capture today from the live engine
  python3 pricematch_history.py --date D        # capture date D from the live engine
  python3 pricematch_history.py --backfill      # today (full, engine) + past sidecars (KPI-only)
"""

import argparse
import csv
import datetime
import glob
import io
import json
import os
import re
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import pricematch_core as core  # frozen contract: load_context / all_comparisons / regime_for

DATA_DIR = os.path.abspath(os.environ.get("PM_HISTORY_DIR")
                           or os.path.join(HERE, "..", "..", "data", "pricematch"))
HISTORY_PATH = os.path.join(DATA_DIR, "history.csv")
DAILY_PATH = os.path.join(DATA_DIR, "daily.csv")

HISTORY_COLS = [
    "date", "regime", "sku", "canonical_sku", "platform", "listing_id", "ref_price",
    "live_modal", "live_min", "live_max", "in_stock", "status", "diff", "diff_pct",
    "stores_below_count", "mrp_official", "mrp_live",
]
DAILY_COLS = [
    "date", "regime", "skus_tracked", "listings", "below", "above", "match", "oos",
    "pending", "not_listed", "exposure", "store_violations",
    "top_offender_sku", "top_offender_platform", "top_offender_diff",
]

_PLATFORM_INDEX = {p: i for i, p in enumerate(core.PLATFORM_ORDER)}


# ---------------------------------------------------------------- formatting

def _numstr(v):
    """Stable string for a CSV cell. None/bool-as-None -> ''; ints lose the '.0';
    floats keep up to 2 decimals with no trailing zeros."""
    if v is None:
        return ""
    if isinstance(v, bool):  # never expected for a number; guard anyway
        return ""
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        if v != v:  # NaN
            return ""
        if v == int(v):
            return str(int(v))
        return ("%.2f" % v).rstrip("0").rstrip(".")
    return str(v)


def _boolstr(v):
    return "true" if v else "false"


def _store_violation_count(comps):
    """Mirror build_pricematch.store_violations() row count so daily.csv reconciles
    with the *.summary.json sidecar: every in-stock store under ref, PLUS one
    national-level row per BELOW record that carries no per-store granularity."""
    n = 0
    for recs in comps.values():
        for r in recs:
            ref = r.get("ref_price")
            stores = r.get("stores_below") or []
            for s in stores:
                if s.get("price") is not None and ref is not None:
                    n += 1
            if (not stores and r.get("status") == "BELOW"
                    and ref is not None and r.get("live_modal") is not None):
                n += 1
    return n


# ---------------------------------------------------------------- canonical join

def _canonical_for(ctx, platform, listing_id, url):
    """The result.json 'canonical' slug for a record's joined listing — the SAME key
    data/<p>/history.csv uses, so W2 can cross-link the real vault SKU hubs. Mirrors
    pricematch_core._rows_for (by_id first, then the url->canonical fallback). Returns
    the modal canonical (tie-break alpha) of the joined rows, or None."""
    if not ctx:
        return None
    live = (ctx.get("live") or {}).get(platform)
    if not live:
        return None
    rows = []
    if listing_id not in (None, ""):
        rows = live["by_id"].get(str(listing_id)) or []
    if not rows and url:
        for canon, crows in live["by_canonical"].items():
            if canon and canon in url:
                rows = crows
                break
    canons = [r.get("canonical") for r in rows if r.get("canonical")]
    if not canons:
        return None
    counts = Counter(canons)
    top = max(counts.values())
    return min(c for c, n in counts.items() if n == top)


# ---------------------------------------------------------------- row builders

def history_rows_from_comps(date, regime, comps, ctx=None):
    """One dict per (sku, platform) record, ready for HISTORY_COLS."""
    rows = []
    for platform, recs in comps.items():
        for r in recs:
            rows.append({
                "date": date,
                "regime": regime,
                "sku": r.get("sku"),
                "canonical_sku": _canonical_for(ctx, platform, r.get("listing_id"), r.get("url")),
                "platform": platform,
                "listing_id": r.get("listing_id"),
                "ref_price": r.get("ref_price"),
                "live_modal": r.get("live_modal"),
                "live_min": r.get("live_min"),
                "live_max": r.get("live_max"),
                "in_stock": r.get("in_stock"),
                "status": r.get("status"),
                "diff": r.get("diff"),
                "diff_pct": r.get("diff_pct"),
                "stores_below_count": len(r.get("stores_below") or []),
                "mrp_official": r.get("mrp_official"),
                "mrp_live": r.get("mrp_live"),
            })
    return rows


def daily_row_from_comps(date, regime, comps, store_violation_count=None):
    """Compute the daily rollup straight from the engine records (full date)."""
    counts = {"BELOW": 0, "ABOVE": 0, "MATCH": 0, "OOS": 0,
              "PENDING_REVIEW": 0, "NOT_LISTED": 0, "NO_REF": 0}
    skus = set()
    listings = 0
    exposure = 0.0
    top = None  # (diff, sku, platform)
    for platform, recs in comps.items():
        for r in recs:
            listings += 1
            skus.add(r.get("sku"))
            st = r.get("status")
            if st in counts:
                counts[st] += 1
            if st == "BELOW":
                ref, modal = r.get("ref_price"), r.get("live_modal")
                if ref is not None and modal is not None:
                    exposure += (ref - modal)
                d = r.get("diff")
                if d is not None:
                    cand = (d, r.get("sku") or "", platform)
                    if top is None or cand < top:  # most-negative diff wins (deterministic)
                        top = cand
    if store_violation_count is None:
        store_violation_count = _store_violation_count(comps)
    return {
        "date": date,
        "regime": regime,
        "skus_tracked": len(skus),
        "listings": listings,
        "below": counts["BELOW"],
        "above": counts["ABOVE"],
        "match": counts["MATCH"],
        "oos": counts["OOS"],
        "pending": counts["PENDING_REVIEW"],
        "not_listed": counts["NOT_LISTED"],
        "exposure": round(exposure),
        "store_violations": store_violation_count,
        "top_offender_sku": (top[1] if top else None),
        "top_offender_platform": (top[2] if top else None),
        "top_offender_diff": (top[0] if top else None),
    }


# ---------------------------------------------------------------- csv io

def _read_csv(path, cols):
    if not os.path.exists(path):
        return []
    with open(path, "r", encoding="utf-8", newline="") as fh:
        rdr = csv.DictReader(fh)
        return [dict(row) for row in rdr]


def _render_csv(cols, rows):
    """Deterministic CSV text: fixed header, '\\n' terminators, minimal quoting."""
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    w.writerow(cols)
    for row in rows:
        w.writerow([row.get(c, "") for c in cols])
    return buf.getvalue()


def _atomic_write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)
    os.replace(tmp, path)


def _history_rows_to_cells(rows):
    """dict rows (typed) -> string-cell dicts in HISTORY_COLS order."""
    out = []
    for r in rows:
        out.append({
            "date": r["date"], "regime": r["regime"], "sku": r["sku"],
            "canonical_sku": (r.get("canonical_sku") or ""),
            "platform": r["platform"], "listing_id": _numstr(r["listing_id"]),
            "ref_price": _numstr(r["ref_price"]), "live_modal": _numstr(r["live_modal"]),
            "live_min": _numstr(r["live_min"]), "live_max": _numstr(r["live_max"]),
            "in_stock": _boolstr(r["in_stock"]), "status": r["status"],
            "diff": _numstr(r["diff"]), "diff_pct": _numstr(r["diff_pct"]),
            "stores_below_count": _numstr(r["stores_below_count"]),
            "mrp_official": _numstr(r["mrp_official"]), "mrp_live": _numstr(r["mrp_live"]),
        })
    return out


def _daily_row_to_cells(r):
    return {
        "date": r["date"], "regime": r["regime"],
        "skus_tracked": _numstr(r["skus_tracked"]), "listings": _numstr(r["listings"]),
        "below": _numstr(r["below"]), "above": _numstr(r["above"]),
        "match": _numstr(r["match"]), "oos": _numstr(r["oos"]),
        "pending": _numstr(r["pending"]), "not_listed": _numstr(r["not_listed"]),
        "exposure": _numstr(r["exposure"]), "store_violations": _numstr(r["store_violations"]),
        "top_offender_sku": (r["top_offender_sku"] or ""),
        "top_offender_platform": (r["top_offender_platform"] or ""),
        "top_offender_diff": _numstr(r["top_offender_diff"]),
    }


def _hist_sort_key(cell):
    return (cell.get("date", ""), _PLATFORM_INDEX.get(cell.get("platform"), 99),
            cell.get("sku", ""))


def write_history(date, history_cells, daily_cell):
    """Idempotent replace-by-date for both stores. history_cells may be None to
    leave history.csv untouched (KPI-only backfill of a past date)."""
    # ---- history.csv (only when we have full per-SKU rows) ----
    if history_cells is not None:
        existing = [r for r in _read_csv(HISTORY_PATH, HISTORY_COLS) if r.get("date") != date]
        merged = existing + history_cells
        merged.sort(key=_hist_sort_key)
        _atomic_write(HISTORY_PATH, _render_csv(HISTORY_COLS, merged))
    # ---- daily.csv (always) ----
    existing_d = [r for r in _read_csv(DAILY_PATH, DAILY_COLS) if r.get("date") != date]
    merged_d = existing_d + [daily_cell]
    merged_d.sort(key=lambda r: r.get("date", ""))
    _atomic_write(DAILY_PATH, _render_csv(DAILY_COLS, merged_d))


# ---------------------------------------------------------------- public capture

def record_run(date, regime, comps, store_violation_count=None, ctx=None):
    """FULL capture from live engine records. Used by the CLI and by the best-effort
    hook at the end of build_pricematch.py main(). `ctx` (from core.load_context) lets
    us resolve each record's canonical_sku from the live join; if the caller (e.g. the
    build hook) doesn't have it, we lazily reload it for `date` — the live result.json
    is unchanged within a sweep, so the join is identical."""
    if ctx is None:
        try:
            ctx = core.load_context(date)
        except Exception:
            ctx = None  # canonical_sku degrades to empty; history still written
    hist = history_rows_from_comps(date, regime, comps, ctx=ctx)
    daily = daily_row_from_comps(date, regime, comps, store_violation_count)
    write_history(date, _history_rows_to_cells(hist), _daily_row_to_cells(daily))
    return len(hist), daily


def capture_today(date=None):
    """Build the engine context for `date` (default today) and persist full history."""
    ctx = core.load_context(date)
    comps = core.all_comparisons(ctx)
    return record_run(ctx["date"], ctx["regime"], comps, ctx=ctx)


# ---------------------------------------------------------------- backfill (KPI-only)

_OFFENDER_RE = re.compile(
    r"^(?P<sku>.+?)\s*\((?P<platform>[^)]+?)\s+[-−–]₹?(?P<amt>[\d,]+)\)")
_PLATFORM_DISPLAY = {
    "amazon": "amazon", "flipkart": "flipkart", "amazon fresh": "amazon-fresh",
    "amazon now": "amazon-now", "flipkart minutes": "flipkart-minutes",
    "zepto": "zepto", "blinkit": "blinkit", "bigbasket": "bigbasket",
}


def _platform_key(display):
    d = (display or "").strip().lower()
    return _PLATFORM_DISPLAY.get(d, d.replace(" ", "-"))


def _parse_top_offender(summary_md):
    """Pull the first 'Top offenders: NAME (Platform −₹NNN) · ...' entry."""
    if not summary_md:
        return None, None, None
    for line in summary_md.splitlines():
        line = line.strip()
        if not line.lower().startswith("top offenders:"):
            continue
        body = line.split(":", 1)[1].strip()
        first = body.split(" · ")[0].strip()
        m = _OFFENDER_RE.match(first)
        if m:
            amt = float(m.group("amt").replace(",", ""))
            return (m.group("sku").strip(),
                    _platform_key(m.group("platform")),
                    -round(amt))
        return None, None, None
    return None, None, None


def daily_row_from_sidecar(sidecar):
    """KPI-only daily row reconstructed from a *.summary.json sidecar."""
    k = sidecar.get("kpis") or {}
    sku, plat, diff = _parse_top_offender(sidecar.get("summary_md"))
    return {
        "date": sidecar.get("date"),
        "regime": sidecar.get("regime"),
        "skus_tracked": k.get("skus_tracked"),
        "listings": k.get("listings"),
        "below": k.get("below"),
        "above": k.get("above"),
        "match": k.get("compliant"),
        "oos": k.get("oos"),
        "pending": k.get("pending"),
        "not_listed": k.get("not_listed"),
        "exposure": k.get("exposure"),
        "store_violations": sidecar.get("store_violations"),
        "top_offender_sku": sku,
        "top_offender_platform": plat,
        "top_offender_diff": diff,
    }


def _find_sidecars():
    out = {}
    for path in sorted(glob.glob(os.path.join(HERE, "Jivo-Price-Match-*.xlsx.summary.json"))):
        # skip scoped editions (e.g. Jivo-Price-Match-Amazon-2026-...); date-only files only
        base = os.path.basename(path)
        m = re.match(r"^Jivo-Price-Match-(\d{4}-\d{2}-\d{2})\.xlsx\.summary\.json$", base)
        if not m:
            continue
        try:
            with open(path, encoding="utf-8") as fh:
                out[m.group(1)] = json.load(fh)
        except (OSError, ValueError):
            continue
    return out


def backfill(today=None):
    """Today (FULL via engine) + every past sidecar date (KPI-only daily row)."""
    today = core._as_date(today).isoformat()
    sidecars = _find_sidecars()
    results = []  # (date, mode, detail)

    # today first — full per-SKU history from the live engine
    n, daily = capture_today(today)
    results.append((today, "FULL", "%d history rows · below=%d exposure=%s sv=%s"
                    % (n, daily["below"], daily["exposure"], daily["store_violations"])))

    # past dates — KPI-only from sidecar (engine cannot reproduce overwritten live prices)
    for date in sorted(sidecars):
        if date == today:
            continue
        daily = daily_row_from_sidecar(sidecars[date])
        write_history(date, None, _daily_row_to_cells(daily))
        results.append((date, "KPI-only", "below=%s exposure=%s sv=%s (sidecar)"
                        % (daily["below"], daily["exposure"], daily["store_violations"])))
    return results


# ---------------------------------------------------------------- CLI

def main(argv=None):
    ap = argparse.ArgumentParser(description="Persist price-match compliance history")
    ap.add_argument("--date", default=None, help="YYYY-MM-DD (default: today)")
    ap.add_argument("--backfill", action="store_true",
                    help="today (full, engine) + past sidecars (KPI-only daily rows)")
    args = ap.parse_args(argv)

    if args.backfill:
        for date, mode, detail in backfill(args.date):
            print("backfill %s [%s] %s" % (date, mode, detail))
    else:
        n, daily = capture_today(args.date)
        print("captured %s [FULL] %d history rows · below=%d exposure=%s sv=%s"
              % (daily["date"], n, daily["below"], daily["exposure"], daily["store_violations"]))
    print("history -> %s" % HISTORY_PATH)
    print("daily   -> %s" % DAILY_PATH)
    return 0


if __name__ == "__main__":
    sys.exit(main())
