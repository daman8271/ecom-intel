import json, datetime, statistics, os
from collections import defaultdict, OrderedDict
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter
from openpyxl.formatting.rule import ColorScaleRule

d = json.load(open('result.json'))
rows = d['allRows']
per = d['perPin']
summary = d['summary']

# platform name derived from the folder this runs in (blinkit, zepto, ...)
PLATFORM = os.path.basename(os.getcwd()).replace('-', ' ').title()

# --- Amazon Now (ctnow surface) -----------------------------------------------
# Every published row is a GENUINE Amazon Now offer (the scraper keeps only cards
# carrying the blue Now badge). The speed-tier data (now_eta/now_slot) stays in
# result.json but is NOT displayed: owner order 2026-06-06 — "that thing is not
# our thing, kindly remove from all the sheets".

# Catalog coverage: classify the full Jivo catalog (the core Amazon scraper's
# products.json, the authoritative 314-ASIN list) into PRESENT / OUT OF STOCK /
# NOT ON NOW. Matched by ASIN (the stable key across surfaces). Best-effort: if the
# catalog file is unavailable the Catalog Coverage sheet is simply skipped.
CATALOG = {}
for cat_path in ('../amazon/products.json', 'products.json'):
    try:
        for p in json.load(open(cat_path)):
            if p.get('asin'):
                CATALOG[p['asin']] = p
        if CATALOG:
            break
    except Exception:
        continue

now_by_asin = defaultdict(list)
for r in rows:
    if r.get('asin'):
        now_by_asin[r['asin']].append(r)

def coverage_status(asin):
    rs = now_by_asin.get(asin)
    if not rs:
        return "NOT ON NOW"
    return "PRESENT" if any(x.get('in_stock') for x in rs) else "OUT OF STOCK"

cov_counts = OrderedDict([("PRESENT", 0), ("OUT OF STOCK", 0), ("NOT ON NOW", 0)])
for asin in CATALOG:
    cov_counts[coverage_status(asin)] += 1

JIVO_GREEN = "008B3A"
HDR = PatternFill("solid", fgColor=JIVO_GREEN)
HDR_FONT = Font(bold=True, color="FFFFFF", size=11)
TITLE_FONT = Font(bold=True, color=JIVO_GREEN, size=18)
SUB_FONT = Font(italic=True, color="555555", size=10)
RED = PatternFill("solid", fgColor="F4CCCC")
GREEN = PatternFill("solid", fgColor="D9EAD3")
YEL = PatternFill("solid", fgColor="FFF2CC")
thin = Side(style="thin", color="D0D0D0")
BORDER = Border(left=thin, right=thin, top=thin, bottom=thin)
CEN = Alignment(horizontal="center", vertical="center")
LEFT = Alignment(horizontal="left", vertical="center")

wb = Workbook()

# pretty SKU label from canonical
def label(canon):
    parts = canon.rsplit('-', 1)
    name = parts[0].replace('-', ' ').title()
    pack = parts[1].upper().replace('ML', ' ml').replace('L', ' L') if len(parts) > 1 else ''
    return f"{name} {pack}".strip()

skus = sorted(set(r['canonical'] for r in rows))
cities_with = sorted(set(r['city'] for r in rows))
all_cities = OrderedDict()
for p in per:
    all_cities.setdefault(p['city'], 0)
    all_cities[p['city']] += len(p['rows'])
cities_without = [c for c, n in all_cities.items() if n == 0]

def style_header(ws, row=1, ncols=None):
    ncols = ncols or ws.max_column
    for c in range(1, ncols + 1):
        cell = ws.cell(row=row, column=c)
        cell.fill = HDR; cell.font = HDR_FONT; cell.alignment = CEN; cell.border = BORDER

def autosize(ws, maxw=42):
    for col in ws.columns:
        L = get_column_letter(col[0].column)
        w = max((len(str(c.value)) for c in col if c.value is not None), default=8)
        ws.column_dimensions[L].width = min(maxw, max(10, w + 2))

# ---------- Sheet 1: Executive Summary ----------
ws = wb.active; ws.title = "Summary"
ws["A1"] = f"Jivo x {PLATFORM} - Live Pricing Intelligence"; ws["A1"].font = TITLE_FONT
ws.merge_cells("A1:G1")
ws["A2"] = f"Captured {summary['captured_at'][:16].replace('T',' ')} IST  -  {summary['pincodes_with_jivo']}/{summary['pincodes_total']} pincodes carry Jivo  -  {summary['unique_skus']} unique SKUs  -  {summary['total_rows']} datapoints  -  scrape {summary['wall_s']}s"
ws["A2"].font = SUB_FONT; ws.merge_cells("A2:G2")
# Source caption: genuine Amazon Now (ctnow) only. No speed-tier text (owner order).
ws["A3"] = "Source: genuine Amazon Now storefront (almBrandId=ctnow)."
ws["A3"].font = SUB_FONT; ws.merge_cells("A3:G3")

# KPI cards
kpis = [("Unique SKUs", summary['unique_skus']), ("Pincodes w/ Jivo", f"{summary['pincodes_with_jivo']}/{summary['pincodes_total']}"),
        ("Datapoints", summary['total_rows']), ("Cities w/ ZERO Jivo", len(cities_without))]
r = 4
for i, (k, v) in enumerate(kpis):
    c = 1 + i * 2
    ws.cell(row=r, column=c, value=k).font = Font(bold=True, size=10, color="555555")
    cell = ws.cell(row=r + 1, column=c, value=v); cell.font = Font(bold=True, size=20, color=JIVO_GREEN)

# cheapest per SKU
ws.cell(row=7, column=1, value="Cheapest pincode per SKU (in-stock, sale price)").font = Font(bold=True, size=12)
hdr = ["SKU", "City", "Pincode", "Store", "Sale Rs", "MRP Rs", "Disc %"]
for j, h in enumerate(hdr, 1):
    ws.cell(row=8, column=j, value=h)
style_header(ws, 8, len(hdr))
rr = 9
for s in skus:
    cand = [x for x in rows if x['canonical'] == s and x['in_stock'] == 1]
    if not cand: cand = [x for x in rows if x['canonical'] == s]
    if not cand: continue
    cand = [x for x in cand if x.get('sale') is not None]
    if not cand: continue
    b = min(cand, key=lambda x: x['sale'])
    for j, v in enumerate([label(s), b['city'], b['pincode'], b['store_name'], b['sale'], b['mrp'], b['discount_pct']], 1):
        cell = ws.cell(row=rr, column=j, value=v); cell.border = BORDER
        if j >= 5: cell.alignment = CEN
    rr += 1
# distribution gaps
rr += 1
ws.cell(row=rr, column=1, value=f"WHITESPACE - Cities with ZERO Jivo on {PLATFORM}:").font = Font(bold=True, size=11, color="CC0000")
rr += 1
ws.cell(row=rr, column=1, value=", ".join(cities_without) if cities_without else "None - full coverage").font = Font(size=11)
ws.merge_cells(start_row=rr, start_column=1, end_row=rr, end_column=7)
autosize(ws)

# ---------- Sheet 2: Master Data ----------
# Amazon Now-specific: show ASIN (the stable cross-surface key). No slot/speed-tier
# column (owner order 2026-06-06).
ws = wb.create_sheet("Master Data")
cols = ["City", "Pincode", "Locality", "ASIN", "SKU", "Pack", "Vol (ml)", "Sale Rs", "MRP Rs", "Disc %", "Rs/L", "In stock"]
ws.append(cols)
for x in sorted(rows, key=lambda r: (r['city'], r['pincode'], r['canonical'])):
    ws.append([x['city'], x['pincode'], x['locality'], x.get('asin'), x['sku_raw'], x['pack'], x['vol_ml'],
               x['sale'], x['mrp'], x['discount_pct'], x['per_litre'], "Yes" if x['in_stock'] else "No"])
style_header(ws)
ws.freeze_panes = "A2"
ws.auto_filter.ref = f"A1:{get_column_letter(len(cols))}{ws.max_row}"
for row in ws.iter_rows(min_row=2):
    for cell in row:
        cell.border = BORDER
        if cell.column in (8, 9): cell.number_format = '"Rs"#,##0'
        if cell.column == 10: cell.number_format = '0.0"%"'
    if row[11].value == "No": row[11].fill = RED
    if isinstance(row[9].value, (int, float)) and row[9].value and row[9].value >= 40: row[9].fill = GREEN
autosize(ws)

# ---------- Matrix builder ----------
def matrix(sheet_name, valfn, fmt=None, scale=False, scale_rev=False):
    ws = wb.create_sheet(sheet_name)
    cols = ["SKU"] + cities_with
    ws.append(cols)
    for s in skus:
        rowvals = [label(s)]
        for c in cities_with:
            cand = [x for x in rows if x['canonical'] == s and x['city'] == c]
            rowvals.append(valfn(cand) if cand else None)
        ws.append(rowvals)
    style_header(ws)
    ws.freeze_panes = "B2"
    for row in ws.iter_rows(min_row=2):
        for cell in row:
            cell.border = BORDER
            if cell.column > 1:
                cell.alignment = CEN
                if fmt and isinstance(cell.value, (int, float)): cell.number_format = fmt
                if cell.value is None: cell.value = "-"
    if scale:
        last = get_column_letter(ws.max_column)
        lo, hi = ("F4CCCC", "D9EAD3") if scale_rev else ("D9EAD3", "F4CCCC")
        ws.conditional_formatting.add(f"B2:{last}{ws.max_row}",
            ColorScaleRule(start_type="min", start_color=lo, end_type="max", end_color=hi))
    autosize(ws, maxw=14)
    return ws

# Sheet 3: Pricing Matrix (avg sale per city) - green cheap -> red expensive
matrix("Pricing Matrix", lambda c: (round(statistics.mean([x['sale'] for x in c if x['sale'] is not None])) if any(x['sale'] is not None for x in c) else None), '"Rs"#,##0', scale=True)
# Sheet 4: Stock Status (% in stock)
def stock_cell(c):
    pct = round(100 * sum(x['in_stock'] for x in c) / len(c))
    return pct
wsS = matrix("Stock Status", stock_cell, '0"%"')
for row in wsS.iter_rows(min_row=2):
    for cell in row:
        if cell.column > 1 and isinstance(cell.value, (int, float)):
            cell.fill = GREEN if cell.value == 100 else (RED if cell.value == 0 else YEL)
# Sheet 5: Discount Analysis (avg disc per city) - higher = greener
matrix("Discount Analysis", lambda c: round(statistics.mean([x['discount_pct'] for x in c if x['discount_pct'] is not None]), 1) if any(x['discount_pct'] is not None for x in c) else None, '0.0"%"', scale=True, scale_rev=True)

# ---------- Sheet 6: Now Serviceability & Coverage ----------
# For Amazon Now the key per-pincode facts are: is Now serviceable here at all, and
# does Jivo appear (vs only competitors). Three states: green=Jivo on Now,
# yellow=Now serviceable but NO Jivo (competitor-only whitespace), red=no Now here.
ws = wb.create_sheet("Now Serviceability")
ws.append(["City", "Pincode", "Locality", "Now serviceable", "Jivo SKUs on Now"])
for p in sorted(per, key=lambda p: (p['city'], p['pincode'])):
    svc = p.get('serviceable', len(p['rows']) > 0)
    ws.append([p['city'], p['pincode'], p['locality'], "Yes" if svc else "No", len(p['rows'])])
style_header(ws); ws.freeze_panes = "A2"
ws.auto_filter.ref = f"A1:E{ws.max_row}"
for row in ws.iter_rows(min_row=2):
    for cell in row: cell.border = BORDER
    njivo = row[4].value
    svc = row[3].value == "Yes"
    row[4].fill = GREEN if njivo else (YEL if svc else RED)
    row[3].fill = GREEN if svc else RED
autosize(ws)

# (the former "Now Speed Tiers" sheet was REMOVED — owner order 2026-06-06)

# ---------- Sheet 7: Catalog Coverage (PRESENT / OUT OF STOCK / NOT ON NOW) ----------
# The honest answer to "how much of the Jivo catalog is actually on Amazon Now?".
# Classifies the full 314-SKU core catalog by ASIN. NOT ON NOW is by Amazon's design
# (the Now storefront indexes only a subset), not a scrape gap.
if CATALOG:
    ws = wb.create_sheet("Catalog Coverage")
    ws["A1"] = f"Jivo catalog on Amazon Now — {cov_counts['PRESENT']} present · {cov_counts['OUT OF STOCK']} out of stock · {cov_counts['NOT ON NOW']} not on Now (of {len(CATALOG)} catalog SKUs)"
    ws["A1"].font = Font(bold=True, size=11, color=JIVO_GREEN); ws.merge_cells("A1:E1")
    ws.append([])
    hdr_row = ws.max_row + 1
    ws.append(["ASIN", "Catalog name", "Category", "Status", "Now sale Rs (min)"])
    style_header(ws, hdr_row, 5)
    STATUS_ORDER = {"PRESENT": 0, "OUT OF STOCK": 1, "NOT ON NOW": 2}
    for asin in sorted(CATALOG, key=lambda a: (STATUS_ORDER[coverage_status(a)], CATALOG[a].get('category') or '', CATALOG[a].get('name') or '')):
        p = CATALOG[asin]
        st = coverage_status(asin)
        rs = now_by_asin.get(asin, [])
        sales = [x['sale'] for x in rs if x.get('sale') is not None]
        ws.append([asin, (p.get('name') or '')[:60], p.get('category') or p.get('item') or '',
                   st, (min(sales) if sales else None)])
    style_header(ws, hdr_row, 5)
    ws.freeze_panes = "A4"
    ws.auto_filter.ref = f"A3:E{ws.max_row}"
    for row in ws.iter_rows(min_row=hdr_row + 1):
        for cell in row:
            cell.border = BORDER
            if cell.column in (4, 5):
                cell.alignment = CEN
        sc = row[3].value
        row[3].fill = GREEN if sc == "PRESENT" else (YEL if sc == "OUT OF STOCK" else RED)
    autosize(ws)

fname = f"Jivo-{PLATFORM.replace(' ', '')}-Live-Report-{datetime.date.today()}.xlsx"
wb.save(fname)
print("SAVED:", fname)
print("Sheets:", wb.sheetnames)
