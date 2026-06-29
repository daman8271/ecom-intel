#!/usr/bin/env python3
"""Lean by-brand competitor gap report (V1, quick-commerce).

Reads the env-gated competitor capture written by a scraper running in
COMPETITOR_MODE=1 (tools/competitor/data/<platform>_competitor_<date>.json,
shape {"summary":{...},"allRows":[...]}), normalises every competitor + JIVO
row onto the V1 comparison buckets (maps_to_jivo.json), and emits a 3-sheet
workbook to output/Competitor-Price-Watch-<Platform>-<date>.xlsx.

House style matches platforms/<p>/build_excel.py: JIVO green #008B3A headers,
freeze panes, autofilter, MODAL aggregation (most common value, ties -> lowest).

GUARDRAILS honoured here:
  - reads ONLY from tools/competitor/data/ (never data/ vault/ reviews/ baselines/)
  - writes ONLY to output/ with the "Competitor-Price-Watch-" prefix (NEVER "Jivo-",
    which the daily mailer auto-emails)
  - read-only on maps_to_jivo.json / competitor_brands.json; never touches pricematch.

Usage:
  build_competitor_report.py <platform> [date]
    <platform>  e.g. blinkit | zepto | flipkart-minutes
    [date]      YYYY-MM-DD (default: today, IST)
Env overrides (have sane defaults; used for offline smoke tests):
  COMPETITOR_DATA_DIR  default /root/ecom-intel/tools/competitor/data
  COMPETITOR_OUT_DIR   default /root/ecom-intel/output
  COMPETITOR_INPUT     explicit path to the <platform>_competitor_<date>.json
"""
import json, os, re, sys, datetime
from collections import Counter, OrderedDict
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter
from openpyxl.formatting.rule import ColorScaleRule

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))

# ---- palette / styling (house build_excel.py) ----
JIVO_GREEN = "008B3A"
HDR = PatternFill("solid", fgColor=JIVO_GREEN)
HDR_FONT = Font(bold=True, color="FFFFFF", size=11)
TITLE_FONT = Font(bold=True, color=JIVO_GREEN, size=18)
SUB_FONT = Font(italic=True, color="555555", size=10)
RED = PatternFill("solid", fgColor="F4CCCC")     # competitor CHEAPER than JIVO = threat
GREEN = PatternFill("solid", fgColor="D9EAD3")    # JIVO cheaper = good
YEL = PatternFill("solid", fgColor="FFF2CC")      # ~level
thin = Side(style="thin", color="D0D0D0")
BORDER = Border(left=thin, right=thin, top=thin, bottom=thin)
CEN = Alignment(horizontal="center", vertical="center")
LEFT = Alignment(horizontal="left", vertical="center")
EPS_PCT = 0.02  # within 2% per-litre counts as "level", not a threat/win


def style_header(ws, row=1, ncols=None):
    ncols = ncols or ws.max_column
    for c in range(1, ncols + 1):
        cell = ws.cell(row=row, column=c)
        cell.fill = HDR; cell.font = HDR_FONT; cell.alignment = CEN; cell.border = BORDER


def autosize(ws, maxw=44):
    for col in ws.columns:
        L = get_column_letter(col[0].column)
        w = max((len(str(c.value)) for c in col if c.value is not None), default=8)
        ws.column_dimensions[L].width = min(maxw, max(10, w + 2))


def modal(values):
    """Most common value, ties -> lowest (matches house modal_price)."""
    vals = [round(v) for v in values if v is not None]
    if not vals:
        return None
    cnt = Counter(vals); top = max(cnt.values())
    return min(v for v, n in cnt.items() if n == top)


# ---- config / inputs ----------------------------------------------------------
def load_json(path):
    with open(path, 'r') as f:
        return json.load(f)


def ist_today():
    return (datetime.datetime.utcnow() + datetime.timedelta(hours=5, minutes=30)).date().isoformat()


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: build_competitor_report.py <platform> [date]")
    platform = sys.argv[1]
    date = sys.argv[2] if len(sys.argv) > 2 else ist_today()

    data_dir = os.environ.get('COMPETITOR_DATA_DIR', os.path.join(HERE, 'data'))
    out_dir = os.environ.get('COMPETITOR_OUT_DIR', os.path.join(ROOT, 'output'))
    in_path = os.environ.get('COMPETITOR_INPUT') or os.path.join(data_dir, f'{platform}_competitor_{date}.json')

    if not os.path.exists(in_path):
        sys.exit(f"competitor capture not found: {in_path}\n"
                 f"  run the scraper first: bash {HERE}/run_competitor.sh {platform}")

    cap = load_json(in_path)
    rows = cap.get('allRows', []) or []
    summary = cap.get('summary', {}) or {}

    maps = load_json(os.path.join(HERE, 'maps_to_jivo.json'))
    brands_cfg = load_json(os.path.join(HERE, 'competitor_brands.json'))

    density = maps.get('density_g_per_ml', {"oil": 0.916, "ghee": 0.91})
    ROUND_VOL = maps.get('round_vol_ml', [200, 250, 500, 1000, 2000, 4000, 5000, 15000])
    buckets = {b['key']: b for b in maps.get('buckets', [])}

    # V1 priority order (must line up with maps_to_jivo.json keys)
    V1_ORDER = [
        'olive.extra_light.1L', 'olive.extra_light.2L', 'olive.pomace.1L', 'olive.pomace.5L',
        'canola.1L', 'canola.5L', 'mustard.kachi_ghani.1L', 'mustard.kachi_ghani.5L',
        'sunflower.1L', 'olive.extra_virgin.1L',
    ]
    V1 = [buckets[k] for k in V1_ORDER if k in buckets]

    # brand identity ------------------------------------------------------------
    ours = [str(x).lower() for x in brands_cfg.get('ours', ['jivo', 'sano'])]
    alias_to_brand = {}
    for b in brands_cfg.get('brands', []):
        alias_to_brand[b['brand'].lower()] = b['brand']
        for a in b.get('aliases', []) or []:
            if a:
                alias_to_brand[a.lower()] = b['brand']

    def is_jivo(r):
        raw = (r.get('brand') or '').lower()
        nm = (r.get('name') or '').lower()
        return any(o in raw or o in nm for o in ours)

    def brand_label(r):
        if is_jivo(r):
            return 'JIVO'
        raw = (r.get('brand') or '').strip().lower()
        if raw in alias_to_brand:
            return alias_to_brand[raw]
        nm = (r.get('name') or '').lower()
        for alias, brand in alias_to_brand.items():
            if alias and alias in nm:
                return brand
        return (r.get('brand') or 'Unknown').title()

    # bucket assignment ---------------------------------------------------------
    def norm_cat(c):
        return re.sub(r'\s*oil\s*$', '', (c or '').lower()).strip().replace(' ', '_')

    def is_combo(r):
        s = ((r.get('name') or '') + ' ' + (r.get('pack') or '')).lower()
        return bool(re.search(r'\d\s*[x×+]\s*\d', s)) or 'combo' in s or 'pack of' in s or '1+1' in s

    def snap_vol(v):
        if v is None:
            return None
        return min(ROUND_VOL, key=lambda x: abs(x - v))

    def grade_ok(bucket, cat, grade):
        bg = bucket.get('sub_grade')
        if bg is None:
            return True              # canola / sunflower: no grade constraint
        if cat == 'mustard':
            return True              # mustard oil in scope == kachi ghani
        g = (grade or '').lower().replace(' ', '_')
        if bg == 'extra_light':
            return g in ('extra_light', 'light')
        if bg == 'pomace':
            return g == 'pomace'
        if bg == 'extra_virgin':
            return g == 'extra_virgin'
        if bg == 'kachi_ghani':
            return True
        return g == bg

    def bucket_for(r):
        if is_combo(r):                       # combos are their own pack axis - never folded in
            return None
        cat = norm_cat(r.get('category'))
        sv = snap_vol(r.get('vol_ml'))
        if sv is None:
            return None
        grade = r.get('sub_grade')
        for b in V1:
            if b['category'] != cat:
                continue
            if b['vol_ml'] != sv:
                continue
            if not grade_ok(b, cat, grade):
                continue
            return b['key']
        return None

    # index rows by bucket + brand ---------------------------------------------
    for r in rows:
        r['_bucket'] = bucket_for(r)
        r['_brand'] = brand_label(r)
        r['_jivo'] = is_jivo(r)

    def pl_modal(filter_fn):
        return modal([r.get('per_litre') for r in rows if filter_fn(r)])

    def jivo_pl(bkey, bucket):
        """JIVO modal per-litre from scraped rows; fall back to the agreed BAU anchor."""
        m = pl_modal(lambda r: r['_bucket'] == bkey and r['_jivo'] and r.get('per_litre'))
        if m is not None:
            return m, 'scraped'
        anc = bucket.get('jivo_bau_per_litre')
        return (round(anc) if anc is not None else None), 'anchor'

    # competitor brands present in any V1 bucket (sorted, JIVO excluded)
    comp_brands = sorted({r['_brand'] for r in rows if r['_bucket'] and not r['_jivo']})

    def bucket_label(b):
        cat = b['category'].replace('_', ' ').title()
        grade = (b.get('sub_grade') or '').replace('_', ' ').title()
        return f"{cat} - {grade} - {b['pack_label']}" if grade else f"{cat} - {b['pack_label']}"

    # ==========================================================================
    wb = Workbook()
    PLAT_DISP = platform.replace('-', ' ').title()

    # ---------- Sheet 1: Summary ----------
    ws = wb.active; ws.title = "Summary"
    ws["A1"] = f"Competitor Price Watch - {PLAT_DISP}"; ws["A1"].font = TITLE_FONT
    ws.merge_cells("A1:H1")
    cap_at = (summary.get('captured_at') or '')[:16].replace('T', ' ')
    ws["A2"] = (f"{date}  -  per-litre gap vs JIVO across V1 buckets  -  "
                f"{summary.get('total_rows', len(rows))} datapoints  -  captured {cap_at} "
                f"-  modal aggregation (ties->lowest)")
    ws["A2"].font = SUB_FONT; ws.merge_cells("A2:H2")

    comp_rows = [r for r in rows if not r['_jivo']]
    kpis = [
        ("Competitor brands seen", len({r['_brand'] for r in comp_rows})),
        ("Competitor SKUs", len({r.get('canonical') for r in comp_rows})),
        ("Cities", len({r.get('city') for r in rows})),
        ("Pincodes", len({r.get('pincode') for r in rows})),
    ]
    r0 = 4
    for i, (k, v) in enumerate(kpis):
        c = 1 + i * 2
        ws.cell(row=r0, column=c, value=k).font = Font(bold=True, size=10, color="555555")
        ws.cell(row=r0 + 1, column=c, value=v).font = Font(bold=True, size=20, color=JIVO_GREEN)

    # headline: JIVO vs cheapest rival per V1 bucket
    ws.cell(row=7, column=1, value="JIVO vs rivals - per-litre headline per V1 bucket").font = Font(bold=True, size=12)
    hdr = ["V1 Bucket", "JIVO Rs/L", "JIVO src", "Cheapest rival", "Rival Rs/L", "Gap Rs/L", "Gap %", "Verdict"]
    for j, h in enumerate(hdr, 1):
        ws.cell(row=8, column=j, value=h)
    style_header(ws, 8, len(hdr))
    rr = 9
    for b in V1:
        bkey = b['key']
        jpl, src = jivo_pl(bkey, b)
        # cheapest rival in this bucket
        rivals = [(br, pl_modal(lambda r, _b=bkey, _br=br: r['_bucket'] == _b and not r['_jivo'] and r['_brand'] == _br and r.get('per_litre')))
                  for br in comp_brands]
        rivals = [(br, pl) for br, pl in rivals if pl is not None]
        if rivals:
            cheap_br, cheap_pl = min(rivals, key=lambda x: x[1])
        else:
            cheap_br, cheap_pl = "-", None
        gap = (cheap_pl - jpl) if (cheap_pl is not None and jpl is not None) else None
        gap_pct = round(100 * gap / jpl, 1) if (gap is not None and jpl) else None
        if gap is None:
            verdict = "no rival data"
        elif jpl and gap < -EPS_PCT * jpl:
            verdict = "THREAT - rival cheaper"
        elif jpl and gap > EPS_PCT * jpl:
            verdict = "JIVO cheaper"
        else:
            verdict = "level"
        vals = [bucket_label(b), jpl, src, cheap_br, cheap_pl, gap, gap_pct, verdict]
        for j, v in enumerate(vals, 1):
            cell = ws.cell(row=rr, column=j, value=v); cell.border = BORDER
            if j >= 2:
                cell.alignment = CEN
            if j in (2, 5, 6):
                cell.number_format = '"Rs"#,##0'
            if j == 7 and v is not None:
                cell.number_format = '0.0"%"'
        # colour the verdict / gap cell: red = rival cheaper (threat)
        vc = ws.cell(row=rr, column=8)
        gc = ws.cell(row=rr, column=6)
        if "THREAT" in verdict:
            vc.fill = RED; gc.fill = RED
        elif "JIVO cheaper" in verdict:
            vc.fill = GREEN; gc.fill = GREEN
        elif verdict == "level":
            vc.fill = YEL; gc.fill = YEL
        rr += 1
    ws.cell(row=rr + 1, column=1,
            value="Notes: per-litre computed from MEASURED volume (grams -> ml via density "
                  f"oil {density.get('oil')}, ghee {density.get('ghee')}), so '910 g labelled 1L' "
                  "pack deflation is caught. Olive grades never compared across tiers; blends & "
                  "combos excluded from single-pack buckets; ghee is a separate per-kg axis. "
                  "JIVO src=anchor means the BAU street price was used (no JIVO row scraped in that bucket)."
            ).font = Font(italic=True, size=9, color="777777")
    ws.merge_cells(start_row=rr + 1, start_column=1, end_row=rr + 1, end_column=8)
    autosize(ws)

    # ---------- Sheet 2: Master Data ----------
    ws = wb.create_sheet("Master Data")
    cols = ["Brand", "JIVO?", "Category", "Sub-grade", "V1 Bucket", "City", "Pincode",
            "Store", "Store ID", "Name", "Pack", "Vol (ml)", "MRP Rs", "Sale Rs",
            "Rs/L", "Disc %", "In stock", "Rank", "Ad?", "Captured"]
    ws.append(cols)
    for x in sorted(rows, key=lambda r: (norm_cat(r.get('category')), r.get('_brand') or '',
                                         r.get('city') or '', r.get('pincode') or '')):
        b = x.get('_bucket')
        ws.append([
            x.get('_brand'), "Yes" if x['_jivo'] else "", norm_cat(x.get('category')),
            x.get('sub_grade') or '', (b or ''),
            x.get('city'), x.get('pincode'), x.get('store_name'), x.get('store_id'),
            x.get('name'), x.get('pack'), x.get('vol_ml'), x.get('mrp'), x.get('sale'),
            x.get('per_litre'), x.get('discount_pct'),
            "Yes" if x.get('in_stock') else "No", x.get('rank'),
            "Yes" if x.get('is_ad') else "", (x.get('captured_at') or '')[:16].replace('T', ' '),
        ])
    style_header(ws)
    ws.freeze_panes = "A2"
    ws.auto_filter.ref = f"A1:{get_column_letter(len(cols))}{ws.max_row}"
    for row in ws.iter_rows(min_row=2):
        for cell in row:
            cell.border = BORDER
            if cell.column in (13, 14, 15):
                cell.number_format = '"Rs"#,##0'
            if cell.column == 16:
                cell.number_format = '0.0"%"'
        if row[1].value == "Yes":
            row[0].fill = GREEN
        if row[16].value == "No":
            row[16].fill = RED
    autosize(ws)

    # ---------- Sheet 3: Gap Matrix ----------
    ws = wb.create_sheet("Gap Matrix")
    cols = ["V1 Bucket", "JIVO Rs/L"] + comp_brands + ["Cheapest rival", "Min rival Rs/L", "Gap vs JIVO Rs/L"]
    ws.append(cols)
    GAP_COL = len(cols)  # last col = gap vs jivo (cheapest rival - jivo)
    for b in V1:
        bkey = b['key']
        jpl, src = jivo_pl(bkey, b)
        rowvals = [bucket_label(b), jpl]
        brand_pls = {}
        for br in comp_brands:
            pl = pl_modal(lambda r, _b=bkey, _br=br: r['_bucket'] == _b and not r['_jivo'] and r['_brand'] == _br and r.get('per_litre'))
            brand_pls[br] = pl
            rowvals.append(pl)
        present = {br: pl for br, pl in brand_pls.items() if pl is not None}
        if present:
            cheap_br = min(present, key=lambda k: present[k])
            cheap_pl = present[cheap_br]
            gap = (cheap_pl - jpl) if jpl is not None else None
        else:
            cheap_br, cheap_pl, gap = "-", None, None
        rowvals += [cheap_br, cheap_pl, gap]
        ws.append(rowvals)
    style_header(ws)
    ws.freeze_panes = "B2"
    last = get_column_letter(ws.max_column)
    for ri, row in enumerate(ws.iter_rows(min_row=2), start=2):
        jpl = ws.cell(row=ri, column=2).value
        for cell in row:
            cell.border = BORDER
            if cell.column > 1:
                cell.alignment = CEN
                if isinstance(cell.value, (int, float)):
                    cell.number_format = '"Rs"#,##0'
            # per-brand cells: colour relative to THIS row's JIVO Rs/L (red = rival cheaper)
            if 3 <= cell.column <= 2 + len(comp_brands) and isinstance(cell.value, (int, float)) and isinstance(jpl, (int, float)) and jpl:
                d = cell.value - jpl
                if d < -EPS_PCT * jpl:
                    cell.fill = RED
                elif d > EPS_PCT * jpl:
                    cell.fill = GREEN
                else:
                    cell.fill = YEL
            if cell.value is None:
                cell.value = "-"
    # gradient on the final gap column: red (rival cheaper) -> white (level) -> green (JIVO cheaper)
    if ws.max_row >= 2:
        gcol = get_column_letter(GAP_COL)
        ws.conditional_formatting.add(
            f"{gcol}2:{gcol}{ws.max_row}",
            ColorScaleRule(start_type="min", start_color="F4CCCC",
                           mid_type="num", mid_value=0, mid_color="FFFFFF",
                           end_type="max", end_color="D9EAD3"))
    autosize(ws, maxw=18)

    # ---- save (Competitor-Price-Watch- prefix; NEVER Jivo-) ----
    os.makedirs(out_dir, exist_ok=True)
    plat_file = platform.replace('-', ' ').title().replace(' ', '-')
    fname = os.path.join(out_dir, f"Competitor-Price-Watch-{plat_file}-{date}.xlsx")
    assert not os.path.basename(fname).startswith("Jivo-"), "filename must never start with Jivo-"
    wb.save(fname)
    print("SAVED:", fname)
    print("Sheets:", wb.sheetnames)
    print("Rows:", len(rows), "| competitor brands:", len(comp_brands),
          "| V1 buckets:", len(V1))


if __name__ == "__main__":
    main()
