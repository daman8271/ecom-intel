#!/usr/bin/env python3
"""build_pricematch.py [--date YYYY-MM-DD] [--out DIR] — the master Price Match workbook.

Builds `Jivo-Price-Match-<date>.xlsx` — every platform x every SKU vs the day's
reference price (regime from tools/pricematch/regime.json via pricematch_core) — with
the **Ecom Head** executive view as the FIRST sheet. Color direction is sacred:
RED = live BELOW reference (the violation), GREEN = live ABOVE reference.

Sheets:
  1. Ecom Head          — date + regime badge, KPI cards, top-10 violations,
                          platform scoreboard, MRP-integrity flags, source footer.
  2. Matrix             — all SKUs x (MRP|BAU|SVD|ART + one col per platform);
                          live modal price, RED below / GREEN above, hyperlink to
                          the listing, cell comment carries the (±₹x) detail.
  3. Violations         — one row per (SKU, platform, store) below ref, by loss.
  4. Above reference    — the green list (platform-level).
  5. Coverage & pending — NOT_LISTED gaps, PENDING_REVIEW items, OOS list.

Also writes `<xlsx>.summary.json` (regime, KPI counts, a deterministic 6-line
Telegram markdown summary + caption) for the run_all.sh batch wiring, and prints
the absolute xlsx path as the LAST stdout line (run_all.sh reads it).

Consumes the FROZEN pricematch_core contract (load_context / all_comparisons /
summary / regime_for) — stdlib + openpyxl only, NO LLM, NO network.
"""
import argparse
import datetime
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))              # /opt/ecom-intel/tools

from openpyxl import Workbook
from openpyxl.comments import Comment
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

import xlsx_dash as xd                                 # v2 house style (fresh-eyes)

# ---------------------------------------------------------------- palette
# Single house palette from tools/xlsx_dash (fresh-eyes 2026-06-06: one brand
# green, ONE red/green compliance pair across every deliverable).
JIVO_GREEN = xd.JIVO_GREEN
BRAND      = xd.BRAND
BRAND_SOFT = xd.BRAND_SOFT
INK        = xd.INK
MUTED      = xd.MUTED
RULE       = xd.RULE
CANVAS     = xd.CANVAS
POS        = xd.POS      # green text — ABOVE ref
NEG        = xd.NEG      # red text — BELOW ref (the violation)
WARN       = xd.WARN
RED_FILL   = PatternFill("solid", fgColor=xd.RED_FILL_HEX)
GREEN_FILL = PatternFill("solid", fgColor=xd.GREEN_FILL_HEX)
AMBER_FILL = PatternFill("solid", fgColor=xd.AMBER_FILL_HEX)
GREY_FILL  = PatternFill("solid", fgColor=CANVAS)
HDR_FILL   = PatternFill("solid", fgColor=JIVO_GREEN)
SOFT_FILL  = PatternFill("solid", fgColor=BRAND_SOFT)
RULE_FILL  = PatternFill("solid", fgColor=RULE)

F = xd.F

CANONICAL = ["flipkart-minutes", "flipkart", "zepto", "bigbasket",
             "amazon", "amazon-fresh", "amazon-now", "blinkit"]
PDISP = dict(xd.PLATFORM_DISPLAY)        # canonical full display names

REGIME_BADGE = {"BAU": ("475569", "BAU day"),        # slate
                "SVD": (JIVO_GREEN, "SVD day"),      # Jivo green
                "ART": ("B45309", "ART day")}        # amber — announcement regime

def regime_long(regime):
    """'SVD' -> 'SVD — Special Value Days (…)' via the shared glossary."""
    full = xd.GLOSSARY.get(regime)
    return f"{regime} — {full}" if full else f"{regime} day"


def _f(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def esc_md(t):
    t = str(t)
    for ch in ("_", "*", "`", "["):
        t = t.replace(ch, "\\" + ch)
    return t


# ---------------------------------------------------------------- data
def gather(date_str):
    """Load everything through the frozen pricematch_core contract."""
    import pricematch_core as core

    ctx = core.load_context(date_str) if date_str else core.load_context()
    comps = core.all_comparisons(ctx)          # dict[platform, list[record]]
    try:
        summ = core.summary(ctx) or {}
    except Exception as e:                     # summary shape is the loosest part
        print(f"build_pricematch: core.summary failed (non-fatal): {e}", file=sys.stderr)
        summ = {}

    date = date_str or datetime.date.today().isoformat()
    regime = None
    for recs in comps.values():
        for r in recs:
            if r.get("regime"):
                regime = r["regime"]
                break
        if regime:
            break
    if not regime:
        try:
            regime = core.regime_for(date)
        except Exception:
            regime = core.regime_for(datetime.date.fromisoformat(date))

    with open(os.path.join(HERE, "sku_map.json"), encoding="utf-8") as fh:
        sku_map = json.load(fh)
    return date, regime, comps, summ, sku_map


def flatten(comps):
    """records flat + indexed by (sku, platform); first record wins on dupes."""
    flat, by_key = [], {}
    for p in CANONICAL:
        for r in comps.get(p, []):
            flat.append(r)
            by_key.setdefault((r.get("sku"), p), r)
    # any platform the canonical list doesn't know about (defensive)
    for p, recs in comps.items():
        if p in CANONICAL:
            continue
        for r in recs:
            flat.append(r)
            by_key.setdefault((r.get("sku"), p), r)
    return flat, by_key


def kpis_of(flat, summ, sku_map):
    skus = sku_map.get("skus", {})
    live_skus = [s for s, v in skus.items() if not v.get("retired")]
    counts = {}
    for r in flat:
        counts[r.get("status")] = counts.get(r.get("status"), 0) + 1

    # total below-ref exposure ₹: prefer the engine's global number if findable,
    # else Σ(ref − live_modal) over BELOW records (deterministic fallback).
    exposure = None
    candidates = []

    def walk(o, depth=0):
        if depth > 4:
            return
        if isinstance(o, dict):
            for k, v in o.items():
                if isinstance(v, (int, float)) and "exposure" in str(k).lower():
                    candidates.append((depth, float(v)))
                else:
                    walk(v, depth + 1)

    walk(summ)
    if candidates:
        candidates.sort()                      # shallowest key = the global one
        exposure = candidates[0][1]
    if exposure is None:
        exposure = sum((_f(r.get("ref_price")) or 0) - (_f(r.get("live_modal")) or 0)
                       for r in flat if r.get("status") == "BELOW"
                       and _f(r.get("ref_price")) and _f(r.get("live_modal")))
    # listing-unit counts (fresh-eyes: the cards must say which unit they count)
    listed_skus = {r.get("sku") for r in flat if r.get("status") != "NOT_LISTED"}
    return {
        "skus_tracked": len(live_skus),
        "platforms": len([p for p in CANONICAL]),
        "compliant": counts.get("MATCH", 0),
        "below": counts.get("BELOW", 0),
        "above": counts.get("ABOVE", 0),
        "oos": counts.get("OOS", 0),
        "pending": counts.get("PENDING_REVIEW", 0),
        "not_listed": counts.get("NOT_LISTED", 0),
        "exposure": round(exposure),
        "listings": len(flat),
        "mapped": sum(1 for r in flat if r.get("status") != "NOT_LISTED"),
        "listed_skus": len(listed_skus),
    }


def store_violations(flat):
    """Every (SKU, platform, store) below ref — the dark-store-level check."""
    rows = []
    for r in flat:
        ref = _f(r.get("ref_price"))
        stores = r.get("stores_below") or []
        for s in stores:
            price = _f(s.get("price"))
            if price is None or ref is None:
                continue
            rows.append({"sku": r.get("sku"), "platform": r.get("platform"),
                         "city": s.get("city") or "—", "pincode": s.get("pincode") or "—",
                         "price": price, "ref": ref, "loss": round(ref - price, 2),
                         "url": r.get("url")})
        if not stores and r.get("status") == "BELOW" and ref is not None \
                and _f(r.get("live_modal")) is not None:
            # platform-level BELOW with no store granularity (national platforms)
            rows.append({"sku": r.get("sku"), "platform": r.get("platform"),
                         "city": "(national)", "pincode": "—",
                         "price": _f(r.get("live_modal")), "ref": ref,
                         "loss": round(ref - _f(r.get("live_modal")), 2),
                         "url": r.get("url")})
    rows.sort(key=lambda x: -x["loss"])
    return rows


def mrp_flags_of(sku_map):
    """master_mrp_stale entries + the EL 1+1L 2798-vs-2998 drift case (owner brief)."""
    stale = sku_map.get("master_mrp_stale") or {}
    el = [d for d in (sku_map.get("mrp_drift") or [])
          if str(d.get("product", "")).upper().replace(" ", "") == "EXTRALIGHT1+1L"]
    return stale, el


# ---------------------------------------------------------------- sheet helpers
def title_cell(ws, row, text, size=20, color=INK, span=10):
    c = ws.cell(row, 1, text)
    c.font = Font(name=F, size=size, bold=True, color=color)
    c.alignment = Alignment(horizontal="left", vertical="center", indent=1)
    ws.merge_cells(start_row=row, start_column=1, end_row=row, end_column=span)
    ws.row_dimensions[row].height = max(22, size + 16)
    return c


def divider(ws, row, span=10):
    for c in range(1, span + 1):
        ws.cell(row, c).fill = RULE_FILL
    ws.row_dimensions[row].height = 3


def table_header(ws, row, cols, start_col=1):
    for i, h in enumerate(cols):
        c = ws.cell(row, start_col + i, h)
        c.font = Font(name=F, size=10, bold=True, color="FFFFFF")
        c.fill = HDR_FILL
        c.alignment = Alignment(horizontal="left", vertical="center", indent=1)
    ws.row_dimensions[row].height = 18


def money(c, red=False, green=False, bold=False):
    c.number_format = "₹#,##0"
    color = NEG if red else (POS if green else INK)
    c.font = Font(name=F, size=10, bold=bold or red or green, color=color)


# ---------------------------------------------------------------- sheets
def sheet_ecom_head(wb, date, regime, flat, comps, kpi, sku_map, label=None):
    ws = wb.create_sheet("Ecom Head", 0)
    ws.sheet_view.showGridLines = False
    ws.sheet_view.zoomScale = 110
    for L in "ABCDEFGHIJ":
        ws.column_dimensions[L].width = 16

    # edition cover identity (fresh-eyes ed-MUST-1: a scoped edition must
    # never be mistakable for the cross-platform master)
    title = (f"Jivo — Price Match · {label} channels" if label
             else "Jivo — Price Match · Ecom Head")
    title_cell(ws, 1, title, span=8)
    # regime badge, top-right
    badge_color, badge_text = REGIME_BADGE.get(regime, (MUTED, f"{regime} day"))
    b = ws.cell(1, 9, f"{date}  ·  {badge_text}".upper())
    b.font = Font(name=F, size=11, bold=True, color="FFFFFF")
    b.fill = PatternFill("solid", fgColor=badge_color)
    b.alignment = Alignment(horizontal="center", vertical="center")
    ws.merge_cells(start_row=1, start_column=9, end_row=1, end_column=10)
    if label:
        xd.edition_badge(ws, 2, 9, f"{label} edition", span=2)

    # ONE reconciling caption: the cards below count LISTINGS (SKU×platform),
    # not SKUs — say so up front (fresh-eyes MUST-2).
    scope = (f"{', '.join(PDISP.get(p, p) for p in CANONICAL)} — the cross-"
             f"platform master covers all 8 platforms · " if label else "")
    h = ws.cell(2, 1, f"{kpi['skus_tracked']} master SKUs, {kpi['listed_skus']} listed here · "
                      f"{scope}of {kpi['listings']} SKU×platform listings: "
                      f"{kpi['compliant']} at agreed price · {kpi['below']} below · "
                      f"{kpi['above']} above · {kpi['oos']} OOS · "
                      f"{kpi['not_listed']} not listed · {kpi['pending']} pending · "
                      f"₹{kpi['exposure']:,} below-ref gap")
    h.font = Font(name=F, size=10, color=MUTED)
    h.alignment = Alignment(horizontal="left", vertical="center", indent=1)
    ws.merge_cells(start_row=2, start_column=1, end_row=2, end_column=8 if label else 10)
    ws.row_dimensions[2].height = 22
    divider(ws, 3)

    # ---- KPI cards: 8 cards, 2 rows x 4, each spanning 2 cols x 3 rows ----
    cards = [
        ("MASTER SKUS", f"{kpi['skus_tracked']}", "tracked (retired excluded)", INK),
        ("PLATFORMS", f"{kpi['platforms']}", "in this report", INK),
        ("AT AGREED PRICE", f"{kpi['compliant']}", "listings matching reference (±₹1)", BRAND),
        ("BELOW REF", f"{kpi['below']}", "listing-level violations — under agreed price", NEG),
        ("ABOVE REF", f"{kpi['above']}", "listings priced over reference", POS),
        ("OOS LISTINGS", f"{kpi['oos']}", f"of {kpi['mapped']} mapped listings — no price verdict", MUTED),
        ("PENDING REVIEW", f"{kpi['pending']}", "mappings awaiting confirmation", WARN),
        ("BELOW-REF GAP ₹", f"₹{kpi['exposure']:,}", "Σ(agreed − live) over below-ref listings", NEG),
    ]
    r0 = 5
    for i, (label, value, sub, color) in enumerate(cards):
        rr = r0 + (i // 4) * 4
        cc = [1, 3, 6, 8][i % 4]                      # cols 1,3,6,8 (gutter mid-sheet)
        for dr in range(3):
            for dc in range(2):
                ws.cell(rr + dr, cc + dc).fill = GREY_FILL
        lc = ws.cell(rr, cc, label)
        lc.font = Font(name=F, size=8, bold=True, color=MUTED)
        lc.alignment = Alignment(horizontal="left", vertical="bottom", indent=1)
        vc = ws.cell(rr + 1, cc, value)
        vc.font = Font(name=F, size=20, bold=True, color=color)
        vc.alignment = Alignment(horizontal="left", vertical="center", indent=1)
        sc = ws.cell(rr + 2, cc, sub)
        sc.font = Font(name=F, size=8, color=MUTED)
        sc.alignment = Alignment(horizontal="left", vertical="top", indent=1)
    row = r0 + 8

    # ---- TOP-10 violations ----
    below = sorted([r for r in flat if r.get("status") == "BELOW"],
                   key=lambda r: _f(r.get("diff")) or 0)
    t = ws.cell(row, 1, "TOP VIOLATIONS — live BELOW the reference price")
    t.font = Font(name=F, size=12, bold=True, color=NEG)
    row += 1
    table_header(ws, row, ["SKU", "Platform", "Ref ₹", "Live ₹", "Diff ₹",
                           "Worst store (city @ ₹)"])
    ws.merge_cells(start_row=row, start_column=6, end_row=row, end_column=8)
    row += 1
    if not below:
        c = ws.cell(row, 1, "None — every priced listing is at or above reference today.")
        c.font = Font(name=F, size=10, italic=True, color=POS)
        row += 1
    for r in below[:10]:
        ws.cell(row, 1, r.get("sku")).font = Font(name=F, size=10, color=INK)
        ws.cell(row, 2, PDISP.get(r.get("platform"), r.get("platform"))).font = \
            Font(name=F, size=10, color=MUTED)
        money(ws.cell(row, 3, _f(r.get("ref_price"))))
        money(ws.cell(row, 4, _f(r.get("live_modal"))), red=True)
        d = ws.cell(row, 5, _f(r.get("diff")))
        d.number_format = "₹#,##0;-₹#,##0"
        d.font = Font(name=F, size=10, bold=True, color=NEG)
        worst = "—"
        stores = [s for s in (r.get("stores_below") or []) if _f(s.get("price")) is not None]
        if stores:
            w = min(stores, key=lambda s: _f(s.get("price")))
            worst = f"{w.get('city') or '?'} @ ₹{_f(w.get('price')):,.0f}"
        wc = ws.cell(row, 6, worst)
        wc.font = Font(name=F, size=10, color=INK)
        ws.merge_cells(start_row=row, start_column=6, end_row=row, end_column=8)
        row += 1
    row += 1

    # ---- platform scoreboard ----
    t = ws.cell(row, 1, "PLATFORM SCOREBOARD")
    t.font = Font(name=F, size=12, bold=True, color=INK)
    row += 1
    table_header(ws, row, ["Platform", "Mapped SKUs", "% ≥ ref", "Violations",
                           "Biggest offender"])
    ws.merge_cells(start_row=row, start_column=5, end_row=row, end_column=7)
    row += 1
    for p in CANONICAL:
        recs = comps.get(p, [])
        mapped = sum(1 for r in recs if r.get("status") != "NOT_LISTED")
        priced = [r for r in recs if r.get("status") in ("BELOW", "ABOVE", "MATCH")]
        ok = sum(1 for r in priced if r.get("status") in ("ABOVE", "MATCH"))
        pct = (100.0 * ok / len(priced)) if priced else None
        viols = [r for r in recs if r.get("status") == "BELOW"]
        offender = "—"
        if viols:
            w = min(viols, key=lambda r: _f(r.get("diff")) or 0)
            offender = f"{w.get('sku')} (−₹{abs(_f(w.get('diff')) or 0):,.0f})"
        ws.cell(row, 1, PDISP.get(p, p)).font = Font(name=F, size=10, bold=True, color=INK)
        ws.cell(row, 2, mapped).font = Font(name=F, size=10, color=INK)
        pc = ws.cell(row, 3, f"{pct:.0f}%" if pct is not None else "—")
        # fresh-eyes S9: threshold the colour or it stops meaning anything
        pc.font = Font(name=F, size=10, bold=True,
                       color=(POS if (pct or 0) >= 90 else
                              (WARN if (pct or 0) >= 70 else NEG)) if pct is not None else MUTED)
        vc = ws.cell(row, 4, len(viols))
        vc.font = Font(name=F, size=10, bold=True, color=NEG if viols else POS)
        oc = ws.cell(row, 5, offender)
        oc.font = Font(name=F, size=10, color=NEG if viols else MUTED)
        ws.merge_cells(start_row=row, start_column=5, end_row=row, end_column=7)
        row += 1
    row += 1

    # ---- MRP-integrity flags ----
    stale, el = mrp_flags_of(sku_map)
    n_flags = len(stale) + len(el)
    t = ws.cell(row, 1, f"MRP-INTEGRITY FLAGS: {n_flags}")
    t.font = Font(name=F, size=12, bold=True, color=WARN if n_flags else POS)
    row += 1
    # plain language (fresh-eyes S10: no insider shorthand, state the action)
    detail = []
    if stale:
        detail.append(f"{len(stale)} master MRPs look stale vs live listings "
                      f"({', '.join(sorted(stale))}) — confirm with brand team")
    for d in el:
        detail.append(f"EXTRA LIGHT 1+1L: master MRP ₹{d.get('official_mrp')} vs "
                      f"{PDISP.get(d.get('platform'), d.get('platform'))} live "
                      f"₹{d.get('platform_mrp')} — confirm which is current")
    dc = ws.cell(row, 1, "; ".join(detail) if detail else "none on file")
    dc.font = Font(name=F, size=9, color=MUTED)
    dc.alignment = Alignment(horizontal="left", vertical="top", wrap_text=True, indent=1)
    ws.merge_cells(start_row=row, start_column=1, end_row=row, end_column=10)
    ws.row_dimensions[row].height = 28
    row += 2

    # ---- footer ----
    divider(ws, row)
    row += 1
    # plain words, no internal file names (fresh-eyes MUST-4)
    fc = ws.cell(row, 1, f"Today is {regime_long(regime)}. Every reference price on "
                         f"this report is today's agreed {regime} price list.")
    fc.font = Font(name=F, size=9, italic=True, color=MUTED)
    fc.alignment = Alignment(horizontal="left", vertical="center", indent=1)
    ws.merge_cells(start_row=row, start_column=1, end_row=row, end_column=10)
    return ws


def sheet_matrix(wb, date, regime, by_key, sku_map, listed_only=False):
    # Owner order 2026-06-06: show ONLY today's regime — MRP + ONE named
    # "Agreed price (<regime>)" column. The BAU/SVD/ART trio lives in the
    # team's own master sheet; our report shows the day's truth.
    # listed_only (scoped editions): keep only SKUs with >=1 listing on the
    # edition's platforms — the never-listed tail lives in Coverage & pending.
    ws = wb.create_sheet("Matrix")
    ws.sheet_view.showGridLines = False
    ws.freeze_panes = "B3"
    ws.column_dimensions["A"].width = 26
    regime_cols = ["MRP", f"Agreed price ({regime})"]
    ws.column_dimensions["B"].width = 11
    ws.column_dimensions["C"].width = 18
    for i in range(len(CANONICAL)):
        ws.column_dimensions[get_column_letter(2 + len(regime_cols) + i)].width = 14

    headers = ["SKU"] + regime_cols + [PDISP.get(p, p) for p in CANONICAL]
    table_header(ws, 1, headers)
    agreed_col = 3
    ws.cell(1, agreed_col).fill = PatternFill("solid", fgColor=INK)

    # legend at the TOP, inside the frozen pane, all states covered
    # (fresh-eyes MUST-5: it was the last row, below 115 data rows)
    xd.legend(ws, 2, [
        ("RED = live below agreed price (±₹1)", xd.RED_FILL_HEX, xd.RED_TEXT),
        ("GREEN = live above", xd.GREEN_FILL_HEX, xd.GREEN_TEXT),
        ("blue link = live listing · plain = at agreed price", None, "0563C1"),
        ("OOS = out of stock · ? = mapping under review · — = not listed", None, None),
    ], span=2)

    skus = sku_map.get("skus", {})
    if listed_only:
        skus = {sku: e for sku, e in skus.items()
                if not e.get("retired") and any(
                    (by_key.get((sku, p)) or {}).get("status",
                     "NOT_LISTED") != "NOT_LISTED" for p in CANONICAL)}
    row = 3
    for sku, entry in skus.items():
        retired = bool(entry.get("retired"))
        name = ws.cell(row, 1, sku + ("  (retired)" if retired else ""))
        name.font = Font(name=F, size=10, bold=not retired,
                         color=MUTED if retired else INK)
        if retired:
            for c in range(1, len(headers) + 1):
                ws.cell(row, c).fill = GREY_FILL
        regs = entry.get("regimes") or {}
        for i, key in enumerate(("mrp", regime.lower())):
            c = ws.cell(row, 2 + i, _f(regs.get(key)))
            money(c)
            if retired:
                c.font = Font(name=F, size=10, color=MUTED)
                c.fill = GREY_FILL
            elif agreed_col == 2 + i:
                c.fill = SOFT_FILL
                c.font = Font(name=F, size=10, bold=True, color=BRAND)
        for j, p in enumerate(CANONICAL):
            cc = 2 + len(regime_cols) + j
            c = ws.cell(row, cc)
            if retired:
                c.value = "retired"
                c.font = Font(name=F, size=9, italic=True, color=MUTED)
                c.fill = GREY_FILL
                continue
            r = by_key.get((sku, p))
            status = (r or {}).get("status")
            if r is None or status == "NOT_LISTED":
                c.value = "—"
                c.font = Font(name=F, size=10, color=MUTED)
                c.fill = GREY_FILL
                c.alignment = Alignment(horizontal="center")
                continue
            if status == "OOS":
                c.value = "OOS"
                c.font = Font(name=F, size=9, bold=True, color=MUTED)
                c.alignment = Alignment(horizontal="center")
                if r.get("url"):
                    c.hyperlink = r["url"]
                continue
            if status == "PENDING_REVIEW":
                c.value = "?"
                c.font = Font(name=F, size=10, bold=True, color=WARN)
                c.alignment = Alignment(horizontal="center")
                c.comment = Comment("Mapping pending human review — not priced.",
                                    "pricematch", height=60, width=220)
                continue
            live = _f(r.get("live_modal"))
            ref = _f(r.get("ref_price"))
            diff = _f(r.get("diff"))
            c.value = live
            c.number_format = "₹#,##0"
            c.font = Font(name=F, size=10, color=INK)
            if r.get("url"):
                c.hyperlink = r["url"]
                c.font = Font(name=F, size=10, color="0563C1", underline="single")
            if status == "BELOW":                     # RED = below ref. Sacred.
                c.fill = RED_FILL
                c.font = Font(name=F, size=10, bold=True, color=NEG,
                              underline="single" if r.get("url") else None)
                c.comment = Comment(
                    f"−₹{abs(diff or 0):,.0f} BELOW {regime} ref ₹{ref:,.0f}"
                    + (f"\n{len(r.get('stores_below') or [])} store(s) below ref"
                       if r.get("stores_below") else ""),
                    "pricematch", height=70, width=240)
            elif status == "ABOVE":                   # GREEN = above ref.
                c.fill = GREEN_FILL
                c.font = Font(name=F, size=10, bold=True, color=POS,
                              underline="single" if r.get("url") else None)
                c.comment = Comment(f"+₹{abs(diff or 0):,.0f} ABOVE {regime} ref ₹{ref:,.0f}",
                                    "pricematch", height=60, width=240)
            elif status == "NO_REF":
                c.comment = Comment("No reference price for this SKU/regime.",
                                    "pricematch", height=50, width=220)
            # MATCH: value + hyperlink, no fill
        row += 1
    # (legend lives in the frozen top row — fresh-eyes: never the last row)
    return ws


def sheet_violations(wb, date, regime, vrows, below_listings):
    ws = wb.create_sheet("Violations")
    ws.sheet_view.showGridLines = False
    widths = [26, 16, 16, 10, 11, 11, 11]
    for i, w in enumerate(widths):
        ws.column_dimensions[get_column_letter(1 + i)].width = w
    title_cell(ws, 1, "Below-reference violations — every store", size=14, color=NEG, span=7)
    tot = sum(v["loss"] for v in vrows)
    # reconcile the cover's listing-level count with this sheet's store rows
    # (fresh-eyes MUST-3) in plain words (S6: no "modal"/"dark store" jargon).
    h = ws.cell(2, 1, f"The cover's {below_listings} listing-level violations expand to "
                      f"{len(vrows)} store-level rows under the {regime} reference "
                      f"({date}) · Σ loss ₹{tot:,.0f}. The most-common price can hide "
                      f"one cheaper store; this sheet lists every store below reference.")
    h.font = Font(name=F, size=10, color=MUTED)
    h.alignment = Alignment(horizontal="left", vertical="center", wrap_text=True, indent=1)
    ws.merge_cells(start_row=2, start_column=1, end_row=2, end_column=7)
    ws.row_dimensions[2].height = 28

    # ---- roll-up first (fresh-eyes S7: make the wall of rows navigable) ----
    groups = {}
    for v in vrows:
        g = groups.setdefault((v["sku"], v["platform"]),
                              {"n": 0, "loss": 0.0, "worst": None, "url": v.get("url")})
        g["n"] += 1
        g["loss"] += v["loss"]
        if g["worst"] is None or v["loss"] > g["worst"]["loss"]:
            g["worst"] = v
    ranked = sorted(groups.items(), key=lambda kv: -kv[1]["loss"])
    TOP = 15
    t = ws.cell(4, 1, "WORST FIRST — by SKU × platform"
                      + (f" (top {TOP} of {len(ranked)})" if len(ranked) > TOP else ""))
    t.font = Font(name=F, size=12, bold=True, color=NEG)
    table_header(ws, 5, ["SKU", "Platform", "Stores below", "Σ loss ₹",
                         "Worst store (city @ ₹)"])
    ws.merge_cells(start_row=5, start_column=5, end_row=5, end_column=7)
    row = 6
    if not ranked:
        c = ws.cell(row, 1, "None — no store anywhere is selling below reference today.")
        c.font = Font(name=F, size=10, italic=True, color=POS)
        row += 1
    for (sku, plat), g in ranked[:TOP]:
        sc = ws.cell(row, 1, sku)
        sc.font = Font(name=F, size=10, color=INK)
        if g.get("url"):
            sc.hyperlink = g["url"]
            sc.font = Font(name=F, size=10, color="0563C1", underline="single")
        ws.cell(row, 2, PDISP.get(plat, plat)).font = Font(name=F, size=10, color=MUTED)
        ws.cell(row, 3, g["n"]).font = Font(name=F, size=10, bold=True, color=INK)
        lc = ws.cell(row, 4, round(g["loss"]))
        lc.number_format = "₹#,##0"
        lc.font = Font(name=F, size=10, bold=True, color=NEG)
        lc.fill = RED_FILL
        w = g["worst"]
        wc = ws.cell(row, 5, f"{w['city']} @ ₹{w['price']:,.0f} (−₹{w['loss']:,.0f})")
        wc.font = Font(name=F, size=10, color=INK)
        ws.merge_cells(start_row=row, start_column=5, end_row=row, end_column=7)
        row += 1
    row += 1

    # ---- full store-level detail (appendix), filterable ----
    t = ws.cell(row, 1, f"EVERY STORE — all {len(vrows)} rows, by loss")
    t.font = Font(name=F, size=12, bold=True, color=INK)
    row += 1
    hdr_row = row
    table_header(ws, hdr_row, ["SKU", "Platform", "City", "Pincode",
                               "Store ₹", "Ref ₹", "Loss ₹"])
    row += 1
    for v in vrows:
        sc = ws.cell(row, 1, v["sku"])
        sc.font = Font(name=F, size=10, color=INK)
        if v.get("url"):
            sc.hyperlink = v["url"]
            sc.font = Font(name=F, size=10, color="0563C1", underline="single")
        ws.cell(row, 2, PDISP.get(v["platform"], v["platform"])).font = \
            Font(name=F, size=10, color=MUTED)
        ws.cell(row, 3, v["city"]).font = Font(name=F, size=10, color=INK)
        ws.cell(row, 4, str(v["pincode"])).font = Font(name=F, size=10, color=MUTED)
        money(ws.cell(row, 5, v["price"]), red=True)
        money(ws.cell(row, 6, v["ref"]))
        lc = ws.cell(row, 7, v["loss"])
        lc.number_format = "₹#,##0"
        lc.font = Font(name=F, size=10, bold=True, color=NEG)
        lc.fill = RED_FILL
        row += 1
    if vrows:
        ws.auto_filter.ref = "A%d:G%d" % (hdr_row, row - 1)
    return ws


def sheet_above(wb, date, regime, flat):
    ws = wb.create_sheet("Above reference")
    ws.sheet_view.showGridLines = False
    widths = [26, 13, 11, 11, 11, 9, 60]
    for i, w in enumerate(widths):
        ws.column_dimensions[get_column_letter(1 + i)].width = w
    title_cell(ws, 1, "Above-reference listings", size=14, color=POS, span=7)
    above = sorted([r for r in flat if r.get("status") == "ABOVE"],
                   key=lambda r: -(_f(r.get("diff")) or 0))
    over = sum(1 for r in above if (_f(r.get("diff_pct")) or 0) > 25)
    # fresh-eyes S8: heavy over-pricing is a sales risk, not a win — amber it
    h = ws.cell(2, 1, f"{len(above)} listings priced above the {regime} reference ({date})"
                      + (f" · AMBER = more than 25% over reference — overpriced, "
                         f"sales risk ({over})" if over else ""))
    h.font = Font(name=F, size=10, color=MUTED)
    ws.merge_cells(start_row=2, start_column=1, end_row=2, end_column=7)
    table_header(ws, 4, ["SKU", "Platform", "Ref ₹", "Live ₹", "Diff ₹", "Diff %", "Listing"])
    ws.freeze_panes = "A5"
    row = 5
    if not above:
        c = ws.cell(row, 1, "None above reference today.")
        c.font = Font(name=F, size=10, italic=True, color=MUTED)
    for r in above:
        overpriced = (_f(r.get("diff_pct")) or 0) > 25
        ws.cell(row, 1, r.get("sku")).font = Font(name=F, size=10, color=INK)
        ws.cell(row, 2, PDISP.get(r.get("platform"), r.get("platform"))).font = \
            Font(name=F, size=10, color=MUTED)
        money(ws.cell(row, 3, _f(r.get("ref_price"))))
        lv = ws.cell(row, 4, _f(r.get("live_modal")))
        if overpriced:
            lv.number_format = "₹#,##0"
            lv.font = Font(name=F, size=10, bold=True, color=WARN)
            lv.fill = AMBER_FILL
        else:
            money(lv, green=True)
            lv.fill = GREEN_FILL
        dc = ws.cell(row, 5, _f(r.get("diff")))
        dc.number_format = "+₹#,##0;-₹#,##0"
        dc.font = Font(name=F, size=10, bold=True, color=WARN if overpriced else POS)
        pc = ws.cell(row, 6, (_f(r.get("diff_pct")) or 0) / 100.0)
        pc.number_format = "+0.0%;-0.0%"
        pc.font = Font(name=F, size=10, color=MUTED)
        u = ws.cell(row, 7, r.get("url") or "")
        u.font = Font(name=F, size=9, color="0563C1", underline="single")
        if r.get("url"):
            u.hyperlink = r["url"]
        row += 1
    return ws


def sheet_coverage(wb, date, flat, by_key, sku_map):
    ws = wb.create_sheet("Coverage & pending")
    ws.sheet_view.showGridLines = False
    widths = [26, 13, 70]
    for i, w in enumerate(widths):
        ws.column_dimensions[get_column_letter(1 + i)].width = w
    title_cell(ws, 1, "Coverage gaps, pending mappings, out-of-stock", size=14, span=3)
    row = 3

    # NOT_LISTED gaps — one row per SKU listing its missing platforms
    skus = sku_map.get("skus", {})
    gaps = []
    for sku, entry in skus.items():
        if entry.get("retired"):
            continue
        missing = [p for p in CANONICAL
                   if (by_key.get((sku, p)) or {}).get("status", "NOT_LISTED") == "NOT_LISTED"]
        if missing:
            gaps.append((sku, missing))
    # zero-count sections are dropped entirely (fresh-eyes ed-S5)
    if gaps:
        t = ws.cell(row, 1, f"NOT LISTED — matrix gaps ({sum(len(m) for _, m in gaps)} "
                            f"SKU×platform cells across {len(gaps)} SKUs)")
        t.font = Font(name=F, size=12, bold=True, color=INK)
        row += 1
        table_header(ws, row, ["SKU", "Gaps", "Missing platforms"], start_col=1)
        row += 1
        all_str = ", ".join(PDISP.get(p, p) for p in CANONICAL)
        for sku, missing in sorted(gaps, key=lambda g: -len(g[1])):
            ws.cell(row, 1, sku).font = Font(name=F, size=10, color=INK)
            ws.cell(row, 2, len(missing)).font = Font(name=F, size=10, color=MUTED)
            miss_str = ", ".join(PDISP.get(p, p) for p in missing)
            if miss_str == all_str:
                miss_str = f"all {len(CANONICAL)} platforms in this report"
            ws.cell(row, 3, miss_str).font = Font(name=F, size=10, color=MUTED)
            row += 1
        row += 1

    # PENDING_REVIEW
    pend = [r for r in flat if r.get("status") == "PENDING_REVIEW"]
    if pend:
        t = ws.cell(row, 1, f"PENDING REVIEW — mapped but unconfirmed ({len(pend)})")
        t.font = Font(name=F, size=12, bold=True, color=WARN)
        row += 1
        table_header(ws, row, ["SKU", "Platform", "Listing"], start_col=1)
        row += 1
        for r in pend:
            ws.cell(row, 1, r.get("sku")).font = Font(name=F, size=10, color=INK)
            ws.cell(row, 2, PDISP.get(r.get("platform"), r.get("platform"))).font = \
                Font(name=F, size=10, color=MUTED)
            u = ws.cell(row, 3, r.get("url") or r.get("listing_id") or "")
            if r.get("url"):
                u.hyperlink = r["url"]
                u.font = Font(name=F, size=9, color="0563C1", underline="single")
            row += 1
        row += 1

    # OOS
    oos = [r for r in flat if r.get("status") == "OOS"]
    if oos:
        t = ws.cell(row, 1, f"OUT OF STOCK — no price verdict ({len(oos)})")
        t.font = Font(name=F, size=12, bold=True, color=MUTED)
        row += 1
        table_header(ws, row, ["SKU", "Platform", "Listing"], start_col=1)
        row += 1
        for r in oos:
            ws.cell(row, 1, r.get("sku")).font = Font(name=F, size=10, color=INK)
            ws.cell(row, 2, PDISP.get(r.get("platform"), r.get("platform"))).font = \
                Font(name=F, size=10, color=MUTED)
            u = ws.cell(row, 3, r.get("url") or r.get("listing_id") or "")
            if r.get("url"):
                u.hyperlink = r["url"]
                u.font = Font(name=F, size=9, color="0563C1", underline="single")
            row += 1
    if row == 3:
        ws.cell(3, 1, "No gaps — every master SKU is listed, confirmed and in stock."
                ).font = Font(name=F, size=10, italic=True, color=POS)
    return ws


# ---------------------------------------------------------------- summary sidecar
def tg_summary(date, regime, kpi, flat):
    """Deterministic 6-line Telegram markdown (run_all.sh spools/sends this)."""
    below = sorted([r for r in flat if r.get("status") == "BELOW"],
                   key=lambda r: _f(r.get("diff")) or 0)
    top3 = " · ".join(
        f"{esc_md(r.get('sku'))} ({esc_md(PDISP.get(r.get('platform'), r.get('platform')))} "
        f"−₹{abs(_f(r.get('diff')) or 0):,.0f})"
        for r in below[:3]) or "none"
    lines = [
        "*Jivo Price Match — master* \U0001F3AF",
        f"{date} · {regime} day",
        f"\U0001F534 Below ref: {kpi['below']} listings · ₹{kpi['exposure']:,} exposure",
        f"Top offenders: {top3}",
        f"\U0001F7E2 Above: {kpi['above']} · Match: {kpi['compliant']} · "
        f"OOS: {kpi['oos']} · Pending: {kpi['pending']}",
        f"Coverage: {kpi['skus_tracked']} SKUs × {kpi['platforms']} platforms "
        f"({kpi['not_listed']} not listed)",
    ]
    return "\n".join(lines)


# ---------------------------------------------------------------- byte-stability
def stabilize_xlsx(path, stamp, props):
    """LEAD ruling 2026-06-06: same date ⇒ byte-identical workbook.

    openpyxl re-stamps properties.modified=now inside save() AND embeds the
    wall-clock in every zip entry's local header, so pinning wb.properties
    before save is not enough. Rewrite the saved zip deterministically:
    every entry's mtime pinned to the report date, and docProps/core.xml
    re-serialized (via openpyxl's own tostring) with created=modified=stamp.
    """
    import zipfile
    from openpyxl.xml.functions import tostring

    props.created = stamp
    props.modified = stamp
    core_xml = tostring(props.to_tree())
    with zipfile.ZipFile(path) as zin:
        items = [(i.filename, zin.read(i.filename)) for i in zin.infolist()]
    dt = (stamp.year, stamp.month, stamp.day, 0, 0, 0)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as zout:
        for name, data in items:
            if name == "docProps/core.xml":
                data = core_xml
            zi = zipfile.ZipInfo(name, date_time=dt)
            zi.compress_type = zipfile.ZIP_DEFLATED
            zout.writestr(zi, data)


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description="Build the master Price Match workbook")
    ap.add_argument("--date", help="YYYY-MM-DD (default: today)")
    ap.add_argument("--out", help="output directory (default: this script's dir)")
    ap.add_argument("--platforms", help="CSV subset edition (e.g. amazon,amazon-now); default = all")
    ap.add_argument("--label", help="edition label for the filename (e.g. Amazon)")
    args = ap.parse_args()

    date, regime, comps, summ, sku_map = gather(args.date)
    if args.platforms:
        # Scoped edition: shrink the canonical column list IN PLACE (all sheet fns read it),
        # filter comps (flatten() has a defensive catch-all that would re-add others), and
        # drop the engine's GLOBAL summary so exposure falls back to the scoped sum.
        subset = [s.strip() for s in args.platforms.split(",") if s.strip()]
        CANONICAL[:] = [p for p in CANONICAL if p in subset]
        comps = {p: r for p, r in comps.items() if p in subset}
        summ = {}
    flat, by_key = flatten(comps)
    kpi = kpis_of(flat, summ, sku_map)
    vrows = store_violations(flat)

    wb = Workbook()
    wb.remove(wb.active)
    sheet_ecom_head(wb, date, regime, flat, comps, kpi, sku_map, label=args.label)
    sheet_matrix(wb, date, regime, by_key, sku_map, listed_only=bool(args.label))
    sheet_violations(wb, date, regime, vrows, kpi["below"])
    sheet_above(wb, date, regime, flat)
    sheet_coverage(wb, date, flat, by_key, sku_map)
    wb.active = 0

    out_dir = args.out or HERE
    tag = f"{args.label}-" if args.label else ""
    xlsx = os.path.join(out_dir, f"Jivo-Price-Match-{tag}{date}.xlsx")
    wb.save(xlsx)
    # Byte-stability (LEAD ruling 2026-06-06): pin doc props + zip mtimes to the
    # report date (midnight IST) so rebuilding the same day is byte-identical.
    stabilize_xlsx(xlsx, datetime.datetime.fromisoformat(date), wb.properties)

    sidecar = {
        "date": date, "regime": regime, "kpis": kpi,
        "store_violations": len(vrows),
        "summary_md": tg_summary(date, regime, kpi, flat),
        "caption": f"Jivo Price Match · {date} · {regime} day",
    }
    with open(xlsx + ".summary.json", "w", encoding="utf-8") as fh:
        json.dump(sidecar, fh, ensure_ascii=False, indent=1)

    # Best-effort: persist the machine price-match history (data/pricematch/*.csv) from
    # the comps/summ we already hold — AFTER the xlsx is saved + byte-stabilized, so a
    # history-write error can never fail the workbook build and can't touch the xlsx
    # bytes. Idempotent (replace-by-date). Skipped for scoped editions (--platforms): the
    # FULL national workbook owns the canonical daily history. (W1 — pm-history)
    if not args.platforms:
        try:
            import pricematch_history as pmh
            n, _ = pmh.record_run(date, regime, comps, store_violation_count=len(vrows))
            print(f"build_pricematch: pm-history captured {n} rows for {date}", file=sys.stderr)
        except Exception as e:  # never fail the build on a history hiccup
            print(f"build_pricematch: pm-history skipped (non-fatal): {e}", file=sys.stderr)

    print(f"build_pricematch: {regime} day · {kpi['below']} below-ref "
          f"(₹{kpi['exposure']:,} exposure) · {kpi['above']} above · "
          f"{kpi['compliant']} match · {kpi['oos']} OOS · {len(vrows)} store rows",
          file=sys.stderr)
    print(os.path.abspath(xlsx))               # LAST stdout line = the xlsx path
    return 0


if __name__ == "__main__":
    sys.exit(main())
