#!/usr/bin/env python3
"""
predict.py <platform> <xlsx_path>

Standalone, platform-agnostic "Predictions" page generator. Opens an
already-built workbook and APPENDS a worksheet named "Predictions",
generated DETERMINISTICALLY (no LLM, no network) from:
    data/<platform>/history.csv      (per-SKU-per-location run history)
    platforms/<platform>/result.json (current run; perPin or allRows shape)

Sections produced:
    - WHAT TO WATCH        : top data-driven call-outs
    - STOCK-OUT RISK       : current OOS + (with history) trending-to-stockout
    - PRICE & DISCOUNT MOVE : per-SKU change vs previous run(s); big-move flags
    - COVERAGE TREND        : pincodes/stores carrying Jivo over time + gaps

Handles thin history (1 run) gracefully -> current-state insights + a note that
trend predictions sharpen as history accumulates. Never crashes: a missing or
short history.csv still yields a useful current-state sheet.

Python 3 stdlib + openpyxl only. Run AFTER build_excel.py, BEFORE delivery.

Usage:
    python3 tools/predict.py blinkit platforms/blinkit/Jivo-Blinkit-...xlsx
"""

import sys, os, csv, json, datetime
from collections import defaultdict, OrderedDict

from openpyxl import load_workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

# ---------------------------------------------------------------- styling
# Mirror build_excel.py so the appended sheet matches the rest of the book.
JIVO_GREEN = "008B3A"
HDR = PatternFill("solid", fgColor=JIVO_GREEN)
HDR_FONT = Font(bold=True, color="FFFFFF", size=11)
TITLE_FONT = Font(bold=True, color=JIVO_GREEN, size=18)
SUB_FONT = Font(italic=True, color="555555", size=10)
SECTION_FONT = Font(bold=True, color=JIVO_GREEN, size=13)
NOTE_FONT = Font(italic=True, color="777777", size=9)
RED = PatternFill("solid", fgColor="F4CCCC")
GREEN = PatternFill("solid", fgColor="D9EAD3")
YEL = PatternFill("solid", fgColor="FFF2CC")
_thin = Side(style="thin", color="D0D0D0")
BORDER = Border(left=_thin, right=_thin, top=_thin, bottom=_thin)
CEN = Alignment(horizontal="center", vertical="center")
LEFT = Alignment(horizontal="left", vertical="center", wrap_text=True)

# Thresholds for "big move" flagging.
PRICE_PCT_BIG = 5.0      # >=5% price change is notable
PRICE_ABS_BIG = 10.0     # ... or >=Rs.10 absolute
DISC_PT_BIG = 5.0        # >=5 percentage-point discount change is notable
LOW_STOCK_FRAC = 0.5     # SKU in stock in <50% of carrying stores = "low"


# ---------------------------------------------------------------- helpers
def _f(v):
    """Best-effort float; None/'' /junk -> None."""
    if v is None:
        return None
    if isinstance(v, (int, float)):
        return float(v)
    s = str(v).strip()
    if s == "" or s == "-":
        return None
    try:
        return float(s)
    except ValueError:
        return None


def label(canon):
    """Pretty SKU label from a canonical slug (matches build_excel.py)."""
    if not canon:
        return "?"
    parts = str(canon).rsplit("-", 1)
    name = parts[0].replace("-", " ").title()
    pack = ""
    if len(parts) > 1:
        pack = parts[1].upper().replace("ML", " ml").replace("L", " L")
    out = f"{name} {pack}".strip()
    return out if out else str(canon)


def in_stock_of(row):
    """
    Robustly read stock state from a result.json row across platform shapes
    and future extra fields. Returns True / False / None (unknown).
    Recognised: in_stock, availability, available, units_left/stock_qty, eta.
    """
    if "in_stock" in row and row["in_stock"] is not None:
        v = row["in_stock"]
        if isinstance(v, bool):
            return v
        if isinstance(v, (int, float)):
            return v > 0
        s = str(v).strip().lower()
        if s in ("1", "true", "yes", "in stock", "instock", "available"):
            return True
        if s in ("0", "false", "no", "out of stock", "oos", "unavailable"):
            return False
    # availability / available string or bool (Amazon may add this)
    for key in ("availability", "available"):
        if key in row and row[key] is not None:
            v = row[key]
            if isinstance(v, bool):
                return v
            s = str(v).strip().lower()
            if s in ("in stock", "instock", "available", "yes", "true", "1"):
                return True
            if s in ("out of stock", "oos", "unavailable", "no", "false", "0"):
                return False
    # explicit unit counts
    for key in ("units_left", "stock_qty", "qty", "stock"):
        if key in row and row[key] is not None:
            n = _f(row[key])
            if n is not None:
                return n > 0
    return None


def rows_from_result(d):
    """Flatten result.json to a row list, supporting allRows and perPin shapes."""
    if not isinstance(d, dict):
        return []
    if d.get("allRows"):
        return list(d["allRows"])
    out = []
    for p in d.get("perPin", []) or []:
        for r in p.get("rows", []) or []:
            out.append(r)
    return out


def loc_key(row):
    """Stable location key for a result/history row."""
    pin = str(row.get("pincode") or "").strip()
    city = str(row.get("city") or "").strip()
    if pin and pin != "-":
        return pin
    return city or "-"


def fmt_money(v):
    if v is None:
        return "-"
    return f"Rs.{v:,.0f}" if abs(v - round(v)) < 0.05 else f"Rs.{v:,.2f}"


def fmt_signed_money(v):
    if v is None:
        return "-"
    sign = "+" if v >= 0 else "-"
    return f"{sign}Rs.{abs(v):,.0f}"


def fmt_pct(v, signed=False):
    if v is None:
        return "-"
    if signed:
        return f"{'+' if v >= 0 else ''}{v:.1f}%"
    return f"{v:.1f}%"


# ---------------------------------------------------------------- load data
def load_history(path):
    """
    Read history.csv -> list of dict rows (typed). Returns (rows, runs_sorted).
    runs_sorted: list of run_ids in chronological order (sorted by run_id;
    run_id format YYYY-MM-DD-HHMM sorts correctly as a string).
    Tolerates missing file / malformed rows.
    """
    if not os.path.exists(path):
        return [], []
    rows = []
    try:
        with open(path, newline="", encoding="utf-8") as fh:
            for r in csv.DictReader(fh):
                rows.append(r)
    except Exception:
        return [], []
    runs = sorted({r.get("run_id", "") for r in rows if r.get("run_id")})
    return rows, runs


def load_result(path):
    if not os.path.exists(path):
        return {}, []
    try:
        d = json.load(open(path, encoding="utf-8"))
    except Exception:
        return {}, []
    return d, rows_from_result(d)


# ---------------------------------------------------------------- sheet writer
class Sheet:
    """Thin cursor over a worksheet with section/table/note helpers."""

    def __init__(self, ws):
        self.ws = ws
        self.r = 1
        self.maxcol = 1

    def title(self, text, sub=None):
        c = self.ws.cell(row=self.r, column=1, value=text)
        c.font = TITLE_FONT
        self.r += 1
        if sub:
            s = self.ws.cell(row=self.r, column=1, value=sub)
            s.font = SUB_FONT
            self.r += 1
        self.r += 1  # blank spacer

    def section(self, text, sub=None):
        c = self.ws.cell(row=self.r, column=1, value=text)
        c.font = SECTION_FONT
        self.r += 1
        if sub:
            s = self.ws.cell(row=self.r, column=1, value=sub)
            s.font = NOTE_FONT
            self.r += 1

    def note(self, text):
        c = self.ws.cell(row=self.r, column=1, value=text)
        c.font = NOTE_FONT
        c.alignment = LEFT
        self.r += 1

    def bullet(self, text, fill=None):
        c = self.ws.cell(row=self.r, column=1, value=u"• " + text)
        c.font = Font(size=11)
        c.alignment = LEFT
        if fill:
            c.fill = fill
        self.r += 1

    def blank(self, n=1):
        self.r += n

    def table(self, headers, data_rows, fills=None):
        """
        headers: list[str]; data_rows: list[list]; fills: optional list (one
        PatternFill-or-None per data row) to tint the whole row.
        """
        ncol = len(headers)
        self.maxcol = max(self.maxcol, ncol)
        for j, h in enumerate(headers, start=1):
            cell = self.ws.cell(row=self.r, column=j, value=h)
            cell.fill = HDR
            cell.font = HDR_FONT
            cell.alignment = CEN
            cell.border = BORDER
        self.r += 1
        for i, drow in enumerate(data_rows):
            rowfill = fills[i] if (fills and i < len(fills)) else None
            for j in range(ncol):
                val = drow[j] if j < len(drow) else ""
                cell = self.ws.cell(row=self.r, column=j + 1, value=val)
                cell.border = BORDER
                cell.alignment = CEN if j > 0 else LEFT
                if rowfill:
                    cell.fill = rowfill
            self.r += 1
        self.r += 1  # spacer after table

    def autosize(self, maxw=46):
        ws = self.ws
        for col in ws.columns:
            try:
                L = get_column_letter(col[0].column)
            except Exception:
                continue
            w = max((len(str(c.value)) for c in col if c.value is not None), default=10)
            ws.column_dimensions[L].width = min(maxw, max(12, w + 2))
        # keep the first (label/bullet) column generous
        ws.column_dimensions["A"].width = max(ws.column_dimensions["A"].width or 0, 40)


# ---------------------------------------------------------------- analysis
def analyze_current(result_rows):
    """
    Current-run aggregates per SKU. Returns dict:
      sku -> {label, n_loc, n_in, n_oos, n_unknown, oos_cities, prices, discs,
              min_price, max_price, med_price, med_disc}
    plus a top-level 'oos_locations' list (loc-level OOS, capped).
    """
    per_sku = OrderedDict()
    oos_loc_events = []  # (sku, city, pincode)
    for row in result_rows:
        sku = row.get("canonical") or row.get("sku_raw") or "?"
        e = per_sku.setdefault(sku, {
            "label": label(sku), "n_loc": 0, "n_in": 0, "n_oos": 0,
            "n_unknown": 0, "oos_cities": set(), "prices": [], "discs": [],
        })
        e["n_loc"] += 1
        st = in_stock_of(row)
        price = _f(row.get("sale"))
        if price is None:
            price = _f(row.get("price"))
        disc = _f(row.get("discount_pct"))
        if st is True:
            e["n_in"] += 1
            if price is not None:
                e["prices"].append(price)
            if disc is not None:
                e["discs"].append(disc)
        elif st is False:
            e["n_oos"] += 1
            city = row.get("city") or "?"
            e["oos_cities"].add(city)
            oos_loc_events.append((sku, city, str(row.get("pincode") or "")))
        else:
            e["n_unknown"] += 1
            # unknown stock: still use price/disc for outlier detection
            if price is not None:
                e["prices"].append(price)
            if disc is not None:
                e["discs"].append(disc)
    # derive stats
    import statistics
    for e in per_sku.values():
        ps = e["prices"]
        e["min_price"] = min(ps) if ps else None
        e["max_price"] = max(ps) if ps else None
        e["med_price"] = statistics.median(ps) if ps else None
        e["med_disc"] = statistics.median(e["discs"]) if e["discs"] else None
    return per_sku, oos_loc_events


def run_date(history_rows, run_id):
    for r in history_rows:
        if r.get("run_id") == run_id:
            return r.get("date_ist") or run_id
    return run_id


def per_run_sku_stats(history_rows):
    """
    Build {run_id: {sku: {n, n_in, n_oos, prices[], discs[]}}} from history.
    """
    out = defaultdict(lambda: defaultdict(lambda: {
        "n": 0, "n_in": 0, "n_oos": 0, "prices": [], "discs": []}))
    for r in history_rows:
        run = r.get("run_id")
        sku = r.get("canonical_sku")
        if not run or not sku:
            continue
        s = out[run][sku]
        s["n"] += 1
        st = _f(r.get("in_stock"))
        if st is not None:
            if st > 0:
                s["n_in"] += 1
            else:
                s["n_oos"] += 1
        p = _f(r.get("price"))
        if p is not None and p > 0:
            s["prices"].append(p)
        dsc = _f(r.get("discount_pct"))
        if dsc is not None:
            s["discs"].append(dsc)
    return out


def median(xs):
    import statistics
    return statistics.median(xs) if xs else None


# ---------------------------------------------------------------- build sheet
def build(platform, xlsx_path):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    hist_path = os.path.join(root, "data", platform, "history.csv")
    result_path = os.path.join(root, "platforms", platform, "result.json")

    history_rows, runs = load_history(hist_path)
    result, result_rows = load_result(result_path)

    per_sku_cur, oos_loc_events = analyze_current(result_rows)
    runstats = per_run_sku_stats(history_rows)

    cur_run = runs[-1] if runs else None
    prev_run = runs[-2] if len(runs) >= 2 else None
    n_runs = len(runs)

    # captured_at -> IST string for the subtitle
    cap = (result.get("summary") or {}).get("captured_at")
    gen_when = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    when = gen_when
    try:
        dt = datetime.datetime.fromisoformat(str(cap).replace("Z", "+00:00"))
        ist = dt.astimezone(datetime.timezone(datetime.timedelta(hours=5, minutes=30)))
        when = ist.strftime("%Y-%m-%d %H:%M IST")
    except Exception:
        pass

    wb = load_workbook(xlsx_path)
    if "Predictions" in wb.sheetnames:
        del wb["Predictions"]
    ws = wb.create_sheet("Predictions")
    S = Sheet(ws)

    pname = platform.replace("-", " ").title()
    S.title(
        f"Jivo x {pname} - Predictions & Early Warnings",
        sub=(f"Generated {when}  |  history: {n_runs} run(s)"
             + (f", latest {cur_run}" if cur_run else "")
             + "  |  deterministic, no-LLM"),
    )

    if n_runs <= 1:
        S.note("THIN HISTORY: only one run on record (or none). This page shows "
               "current-state insights now; trend & stock-out-trajectory "
               "predictions sharpen automatically as more runs accumulate.")
        S.blank()

    # ----- gather watch call-outs as we compute the sections -----
    watch = []

    # ============================================================ STOCK-OUT RISK
    S.section("1. STOCK-OUT RISK",
              "Currently out-of-stock / low coverage, plus SKUs trending toward stockout.")

    # current OOS by SKU
    OOS_TABLE_CAP = 40
    oos_skus = [(sku, e) for sku, e in per_sku_cur.items() if e["n_oos"] > 0]
    oos_skus.sort(key=lambda x: (-x[1]["n_oos"], x[1]["label"]))
    if oos_skus:
        data, fills = [], []
        for sku, e in oos_skus[:OOS_TABLE_CAP]:
            cities = sorted(e["oos_cities"])
            shown = ", ".join(cities[:6]) + (f" +{len(cities) - 6} more" if len(cities) > 6 else "")
            data.append([e["label"], e["n_oos"], e["n_loc"], len(cities), shown])
            frac = e["n_oos"] / e["n_loc"] if e["n_loc"] else 0
            fills.append(RED if frac >= LOW_STOCK_FRAC else YEL)
        S.table(["SKU", "OOS locations", "Total locations", "Cities affected",
                 "Sample cities"], data, fills)
        if len(oos_skus) > OOS_TABLE_CAP:
            S.note(f"Showing top {OOS_TABLE_CAP} of {len(oos_skus)} OOS SKUs "
                   "(sorted by number of locations affected).")
            S.blank()
        # Watch call-outs: an aggregate count, plus the genuinely WIDESPREAD ones
        # (multi-location OOS). Avoids flooding the list with single-location items
        # on national platforms where every SKU lives at one "location".
        multi = [(sku, e) for sku, e in oos_skus if e["n_oos"] >= 2]
        if len(oos_skus) >= 6:
            watch.append((len(oos_skus) + 60,
                          f"{len(oos_skus)} SKUs currently out of stock in >=1 location"))
        for sku, e in (multi if multi else oos_skus[:5]):
            cities = sorted(e["oos_cities"])
            watch.append((e["n_oos"] + (10 if e["n_oos"] >= 2 else 0),
                          f"{e['label']} out of stock in {e['n_oos']} location(s)"
                          f" across {len(cities)} city/cities"))
    else:
        if result_rows:
            S.bullet("No out-of-stock SKUs detected in the current run.", GREEN)
        else:
            S.note("No current rows available to assess stock.")
        S.blank()

    # low-coverage (in stock in <50% of locations where it appears, but not all OOS)
    low = []
    for sku, e in per_sku_cur.items():
        known = e["n_in"] + e["n_oos"]
        if known >= 4 and e["n_oos"] > 0:
            frac_in = e["n_in"] / known
            if frac_in < LOW_STOCK_FRAC:
                low.append([e["label"], e["n_in"], known, fmt_pct(100 * frac_in)])
    if low:
        S.section("Low availability (in stock in <50% of carrying locations)")
        S.table(["SKU", "In stock", "Known locations", "In-stock rate"], low,
                [YEL] * len(low))

    # trending toward stockout (needs >=2 runs): in-stock rate declining
    if prev_run and runstats:
        trend = []
        for sku in sorted(set(runstats[cur_run]) | set(runstats[prev_run])):
            c = runstats[cur_run].get(sku)
            p = runstats[prev_run].get(sku)
            if not c or not p:
                continue
            ck = c["n_in"] + c["n_oos"]
            pk = p["n_in"] + p["n_oos"]
            if ck < 3 or pk < 3:
                continue
            cr = c["n_in"] / ck
            pr = p["n_in"] / pk
            drop = pr - cr
            if drop >= 0.10:  # in-stock rate fell by >=10 pts
                trend.append([label(sku), fmt_pct(100 * pr), fmt_pct(100 * cr),
                              fmt_pct(-100 * drop, signed=True)])
                watch.append((int(drop * 100) + 50,
                              f"{label(sku)} in-stock rate falling: "
                              f"{fmt_pct(100 * pr)} -> {fmt_pct(100 * cr)} vs last run"))
        if trend:
            S.section("Trending toward stockout (in-stock rate dropping vs last run)")
            S.table(["SKU", f"Prev ({prev_run})", f"Now ({cur_run})", "Change"],
                    trend, [RED] * len(trend))
    elif n_runs <= 1:
        S.note("Stockout-trajectory analysis needs >=2 runs; shows here once more history exists.")
        S.blank()

    # ============================================================ PRICE & DISCOUNT
    S.section("2. PRICE & DISCOUNT MOVEMENT",
              "Median sale price & discount per SKU vs the previous run; big moves flagged.")
    if prev_run and runstats:
        moves = []
        for sku in sorted(set(runstats[cur_run]) | set(runstats[prev_run])):
            c = runstats[cur_run].get(sku)
            p = runstats[prev_run].get(sku)
            if not c or not p:
                continue
            cp, pp = median(c["prices"]), median(p["prices"])
            cd, pd = median(c["discs"]), median(p["discs"])
            d_abs = (cp - pp) if (cp is not None and pp is not None) else None
            d_pct = (100 * d_abs / pp) if (d_abs is not None and pp) else None
            d_disc = (cd - pd) if (cd is not None and pd is not None) else None
            big = ((d_pct is not None and abs(d_pct) >= PRICE_PCT_BIG) or
                   (d_abs is not None and abs(d_abs) >= PRICE_ABS_BIG) or
                   (d_disc is not None and abs(d_disc) >= DISC_PT_BIG))
            moves.append({
                "sku": sku, "lbl": label(sku), "pp": pp, "cp": cp,
                "d_abs": d_abs, "d_pct": d_pct, "pd": pd, "cd": cd,
                "d_disc": d_disc, "big": big,
                "rank": abs(d_pct) if d_pct is not None else 0,
            })
        moves.sort(key=lambda m: (-1 if m["big"] else 0, -m["rank"], m["lbl"]))
        data, fills = [], []
        for m in moves:
            data.append([
                m["lbl"], fmt_money(m["pp"]), fmt_money(m["cp"]),
                fmt_signed_money(m["d_abs"]), fmt_pct(m["d_pct"], signed=True),
                fmt_pct(m["pd"]) if m["pd"] is not None else "-",
                fmt_pct(m["cd"]) if m["cd"] is not None else "-",
                fmt_pct(m["d_disc"], signed=True) if m["d_disc"] is not None else "-",
            ])
            if m["big"]:
                up = (m["d_abs"] or 0) > 0
                fills.append(RED if up else GREEN)  # price up = red (worse), down = green
                if m["d_pct"] is not None and abs(m["d_pct"]) >= PRICE_PCT_BIG:
                    watch.append((int(abs(m["d_pct"])) + 40,
                                  f"{m['lbl']} price {'up' if up else 'down'} "
                                  f"{fmt_pct(m['d_pct'], signed=True)} "
                                  f"({fmt_money(m['pp'])} -> {fmt_money(m['cp'])}) vs last run"))
                elif m["d_disc"] is not None and abs(m["d_disc"]) >= DISC_PT_BIG:
                    watch.append((int(abs(m["d_disc"])) + 30,
                                  f"{m['lbl']} discount {fmt_pct(m['d_disc'], signed=True)} pts vs last run"))
            else:
                fills.append(None)
        if data:
            S.table(["SKU", f"Prev price ({prev_run})", f"Now price ({cur_run})",
                     "delta Rs.", "delta %", "Prev disc", "Now disc", "delta disc pts"],
                    data, fills)
            S.note("Red = sale price rose vs last run; Green = sale price fell. "
                   "Flagged moves: >=5% / >=Rs.10 price, or >=5 pts discount.")
            S.blank()
        else:
            S.note("No SKUs shared between the last two runs to compare.")
            S.blank()
    else:
        # thin history -> current price/discount & cross-location-spread outliers.
        # Run-over-run movement isn't available yet, so surface the most useful
        # current-state signal: SKUs whose price varies across locations (a
        # cross-location anomaly worth watching) and the discount extremes.
        S.note("Only one run on record - showing current cross-location price "
               "spread & discount outliers instead of run-over-run movement.")
        TOPN = 25
        priced = [(sku, e) for sku, e in per_sku_cur.items() if e["med_price"] is not None]

        def spread_of(e):
            if e["max_price"] is None or e["min_price"] is None:
                return 0.0
            return e["max_price"] - e["min_price"]

        any_spread = any(spread_of(e) > 0.5 for _, e in priced)

        if any_spread:
            # per-pincode platform on its first run: rank by cross-location spread
            ranked = sorted(priced, key=lambda kv: -spread_of(kv[1]))
            shown = [(s, e) for s, e in ranked if spread_of(e) > 0.5][:TOPN]
            data = []
            for sku, e in shown:
                spread = spread_of(e)
                data.append([
                    e["label"], fmt_money(e["min_price"]), fmt_money(e["med_price"]),
                    fmt_money(e["max_price"]), fmt_money(spread),
                    fmt_pct(e["med_disc"]) if e["med_disc"] is not None else "-",
                ])
                if e["med_price"] and spread / e["med_price"] >= 0.15:
                    watch.append((int(100 * spread / e["med_price"]),
                                  f"{e['label']} price varies {fmt_money(e['min_price'])}-"
                                  f"{fmt_money(e['max_price'])} across locations this run"))
            S.section("Widest cross-location price spread (top by Rs. spread)")
            S.table(["SKU", "Min price", "Median price", "Max price",
                     "Spread", "Median discount"], data)
            if len(ranked) > len(shown):
                S.note(f"Showing top {len(shown)} of {len(priced)} priced SKUs by spread.")
                S.blank()
        else:
            # national platform (single price per SKU): no spread -> show discount
            # extremes, which is the actionable current-state signal.
            by_disc = sorted([(s, e) for s, e in priced if e["med_disc"] is not None],
                             key=lambda kv: kv[1]["med_disc"])
            if by_disc:
                hi = list(reversed(by_disc[-TOPN:]))   # biggest discounts
                lo = by_disc[:10]                       # smallest discounts
                S.section(f"Highest discounts right now (top {len(hi)})")
                S.table(["SKU", "Price", "MRP-implied discount", "Locations"],
                        [[e["label"], fmt_money(e["med_price"]),
                          fmt_pct(e["med_disc"]), e["n_loc"]] for _, e in hi])
                top = hi[0][1]
                watch.append((int(top["med_disc"]),
                              f"Deepest discount this run: {top['label']} at "
                              f"{fmt_pct(top['med_disc'])} off"))
                S.section(f"Lowest / no discount right now (bottom {len(lo)})")
                S.table(["SKU", "Price", "MRP-implied discount", "Locations"],
                        [[e["label"], fmt_money(e["med_price"]),
                          fmt_pct(e["med_disc"]), e["n_loc"]] for _, e in lo],
                        [YEL] * len(lo))
                S.note(f"{len(priced)} priced SKUs this run; full per-SKU pricing "
                       "is on the other sheets. Discount = vs listed MRP.")
                S.blank()
            else:
                # priced but no discount info: compact price-only list, capped
                data = [[e["label"], fmt_money(e["med_price"]), e["n_loc"]]
                        for _, e in sorted(priced, key=lambda kv: -kv[1]["med_price"])[:TOPN]]
                if data:
                    S.section(f"Highest-priced SKUs right now (top {len(data)})")
                    S.table(["SKU", "Price", "Locations"], data)
                    S.blank()
                else:
                    S.note("No priced rows available in the current run.")
                    S.blank()

    # ============================================================ COVERAGE TREND
    S.section("3. COVERAGE TREND",
              "Locations carrying Jivo over time, and notable gaps.")

    # per-run distinct location count (from history)
    if runstats:
        cov = []
        run_loc = {}  # run -> set of locations carrying any Jivo
        # recompute distinct carrying locations per run from raw history
        carry = defaultdict(set)
        for r in history_rows:
            run = r.get("run_id")
            st = _f(r.get("in_stock"))
            # a location "carries" the SKU if it appears in history (it was found)
            key = (r.get("city") or "") + "|" + (r.get("pincode") or "")
            if run:
                carry[run].add(key)
        for run in runs:
            run_loc[run] = carry.get(run, set())
        prev_n = None
        for run in runs:
            n = len(run_loc[run])
            delta = (n - prev_n) if prev_n is not None else None
            arrow = ""
            if delta is not None:
                arrow = "up" if delta > 0 else ("down" if delta < 0 else "flat")
            cov.append([run_date(history_rows, run), run, n,
                        (f"{'+' if delta and delta > 0 else ''}{delta}" if delta is not None else "-"),
                        arrow])
            prev_n = n
        S.table(["Date", "Run", "Locations carrying Jivo", "delta vs prev", "Trend"], cov)

        # coverage drop call-out + lost locations vs previous run
        if prev_run:
            now_set = run_loc.get(cur_run, set())
            prev_set = run_loc.get(prev_run, set())
            lost = prev_set - now_set
            gained = now_set - prev_set
            if lost:
                # group lost by city
                lost_cities = defaultdict(int)
                for k in lost:
                    city = k.split("|", 1)[0] or "?"
                    lost_cities[city] += 1
                S.section("Locations that LOST coverage since last run")
                rows_lost = [[c, n] for c, n in sorted(lost_cities.items(),
                                                       key=lambda x: -x[1])]
                S.table(["City", "Locations lost"], rows_lost, [YEL] * len(rows_lost))
                top_city = max(lost_cities.items(), key=lambda x: x[1])
                watch.append((len(lost) + 20,
                              f"Coverage dropped: {len(lost)} location(s) lost Jivo vs last run"
                              f" (most in {top_city[0]})"))
            if gained:
                watch.append((len(gained),
                              f"Coverage grew: {len(gained)} new location(s) now carry Jivo"))
    else:
        S.note("No history yet for a coverage trend; current coverage shown below.")
        S.blank()

    # current coverage snapshot from result.json summary + gaps
    summ = result.get("summary") or {}
    pin_with = summ.get("pincodes_with_jivo")
    pin_tot = summ.get("pincodes_total")
    if pin_with is not None and pin_tot:
        S.section("Current coverage snapshot")
        S.bullet(f"{pin_with} of {pin_tot} locations probed currently carry Jivo "
                 f"({fmt_pct(100 * pin_with / pin_tot)}).")
        if pin_tot - pin_with > 0:
            watch.append((1, f"{pin_tot - pin_with} of {pin_tot} probed locations have NO Jivo"))

    # cities with zero Jivo (gap), derived from perPin if available
    cities_total = OrderedDict()
    for p in (result.get("perPin") or []):
        c = p.get("city") or "?"
        cities_total.setdefault(c, 0)
        cities_total[c] += len(p.get("rows") or [])
    zero_cities = [c for c, n in cities_total.items() if n == 0]
    if zero_cities:
        S.bullet("Cities with ZERO Jivo this run: " + ", ".join(sorted(zero_cities)), RED)
        watch.append((len(zero_cities) + 10,
                      f"{len(zero_cities)} city/cities have ZERO Jivo this run: "
                      + ", ".join(sorted(zero_cities)[:5])
                      + (" ..." if len(zero_cities) > 5 else "")))
    S.blank()

    # ============================================================ WHAT TO WATCH
    # (rendered near the top would need pre-pass; instead put it as a clearly
    # labelled lead section by writing it first. We compute after, so place it
    # at the end but make it visually prominent.)
    S.section("4. WHAT TO WATCH (top call-outs)",
              "Highest-signal, data-driven items from the sections above.")
    if watch:
        # dedupe by message, keep highest priority
        best = {}
        for prio, msg in watch:
            if msg not in best or prio > best[msg]:
                best[msg] = prio
        ordered = sorted(best.items(), key=lambda kv: -kv[1])[:10]
        for msg, _ in ordered:
            S.bullet(msg)
    else:
        S.bullet("Nothing notable: stock, pricing and coverage all look steady this run.", GREEN)
    if n_runs <= 1:
        S.blank()
        S.note("As more runs accumulate, this list will surface run-over-run "
               "price moves, stockout trajectories and coverage shifts.")

    S.autosize()
    ws.freeze_panes = "A4"
    wb.save(xlsx_path)
    return xlsx_path, n_runs, len(per_sku_cur), len(watch)


def main(argv):
    if len(argv) < 3:
        sys.stderr.write("usage: predict.py <platform> <xlsx_path>\n")
        return 2
    platform, xlsx_path = argv[1], argv[2]
    if not os.path.exists(xlsx_path):
        sys.stderr.write(f"predict.py: xlsx not found: {xlsx_path}\n")
        return 1
    try:
        path, n_runs, n_sku, n_watch = build(platform, xlsx_path)
        sys.stderr.write(f"predict.py: appended 'Predictions' to {path} "
                         f"(history runs={n_runs}, skus={n_sku}, watch items={n_watch})\n")
        return 0
    except Exception as e:
        # Never break the pipeline: log and exit non-zero so run.sh's `|| true`
        # swallows it without losing the already-built workbook.
        import traceback
        sys.stderr.write("predict.py: FAILED (non-fatal): %s\n" % e)
        traceback.print_exc(file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
