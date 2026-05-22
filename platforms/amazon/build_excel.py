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

# Amazon (targeted /dp scrape) carries extra retailer + stock fields. Detect
# their presence so this same builder still works for platforms that don't.
HAS_SELLER = any('seller' in r for r in rows)
HAS_AVAIL = any('availability_text' in r for r in rows)


def gv(r, k, default=''):
    """safe getter for the new optional fields"""
    v = r.get(k, default)
    return default if v is None else v

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
if HAS_SELLER:
    n_instk = sum(1 for x in rows if x['in_stock'])
    n_miss = sum(1 for x in rows if gv(x, 'availability_text') in ("NOT FOUND", "BLOCKED"))
    n_sellers = len(set(gv(x, 'seller') for x in rows if gv(x, 'seller')))
    ws["A2"] = (f"Captured {summary['captured_at'][:16].replace('T',' ')} IST  -  "
                f"{summary.get('asins_targeted', summary['total_rows'])} ASINs targeted  -  "
                f"{n_instk} in stock  -  {n_miss} not-found/blocked  -  {n_sellers} distinct retailers  -  scrape {summary['wall_s']}s")
else:
    ws["A2"] = f"Captured {summary['captured_at'][:16].replace('T',' ')} IST  -  {summary['pincodes_with_jivo']}/{summary['pincodes_total']} pincodes carry Jivo  -  {summary['unique_skus']} unique SKUs  -  {summary['total_rows']} datapoints  -  scrape {summary['wall_s']}s"
ws["A2"].font = SUB_FONT; ws.merge_cells("A2:G2")

# KPI cards
if HAS_SELLER:
    n_instk = sum(1 for x in rows if x['in_stock'])
    n_miss = sum(1 for x in rows if gv(x, 'availability_text') in ("NOT FOUND", "BLOCKED"))
    n_sellers = len(set(gv(x, 'seller') for x in rows if gv(x, 'seller')))
    kpis = [("ASINs tracked", summary.get('asins_targeted', summary['total_rows'])), ("In stock", n_instk),
            ("Not found / blocked", n_miss), ("Distinct retailers", n_sellers)]
else:
    kpis = [("Unique SKUs", summary['unique_skus']), ("Pincodes w/ Jivo", f"{summary['pincodes_with_jivo']}/{summary['pincodes_total']}"),
            ("Datapoints", summary['total_rows']), ("Cities w/ ZERO Jivo", len(cities_without))]
r = 4
for i, (k, v) in enumerate(kpis):
    c = 1 + i * 2
    ws.cell(row=r, column=c, value=k).font = Font(bold=True, size=10, color="555555")
    cell = ws.cell(row=r + 1, column=c, value=v); cell.font = Font(bold=True, size=20, color=JIVO_GREEN)

# cheapest per SKU  (Amazon: show retailer/seller + stock prominently)
ws.cell(row=7, column=1, value="Best price per SKU (in-stock preferred) - retailer & stock").font = Font(bold=True, size=12)
if HAS_SELLER:
    hdr = ["SKU", "Retailer (Sold by)", "Sale Rs", "MRP Rs", "Disc %", "In stock", "Availability"]
else:
    hdr = ["SKU", "City", "Pincode", "Store", "Sale Rs", "MRP Rs", "Disc %"]
for j, h in enumerate(hdr, 1):
    ws.cell(row=8, column=j, value=h)
style_header(ws, 8, len(hdr))
rr = 9
for s in skus:
    cand = [x for x in rows if x['canonical'] == s and x['in_stock'] == 1 and x.get('sale') is not None]
    if not cand: cand = [x for x in rows if x['canonical'] == s and x.get('sale') is not None]
    if not cand: cand = [x for x in rows if x['canonical'] == s]
    if not cand: continue
    b = min(cand, key=lambda x: (x.get('sale') is None, x.get('sale') or 0))
    if HAS_SELLER:
        seller = gv(b, 'seller') or "(no buybox / unavailable)"
        instk = "Yes" if b['in_stock'] else "No"
        vals = [label(s), seller, b.get('sale'), b.get('mrp'), b['discount_pct'], instk, gv(b, 'availability_text')]
        nums_from = 3
    else:
        vals = [label(s), b['city'], b['pincode'], b['store_name'], b['sale'], b['mrp'], b['discount_pct']]
        nums_from = 5
    for j, v in enumerate(vals, 1):
        cell = ws.cell(row=rr, column=j, value=v); cell.border = BORDER
        if j >= nums_from: cell.alignment = CEN
        if HAS_SELLER and j == 6:
            cell.fill = GREEN if v == "Yes" else RED
    rr += 1
# distribution gaps
rr += 1
ws.cell(row=rr, column=1, value=f"WHITESPACE - Cities with ZERO Jivo on {PLATFORM}:").font = Font(bold=True, size=11, color="CC0000")
rr += 1
ws.cell(row=rr, column=1, value=", ".join(cities_without) if cities_without else "None - full coverage").font = Font(size=11)
ws.merge_cells(start_row=rr, start_column=1, end_row=rr, end_column=7)
autosize(ws)

# ---------- Sheet 2: Master Data ----------
ws = wb.create_sheet("Master Data")
if HAS_SELLER:
    # Amazon /dp scrape: lead with SKU + RETAILER + STOCK (what the user wants
    # front-and-centre), then price, then identity/metadata.
    cols = ["SKU", "ASIN", "Category", "Retailer (Sold by)", "Ships from", "In stock",
            "Availability", "Units left", "Sale Rs", "MRP Rs", "Disc %", "Pack", "Rs/L"]
    ASIN_C, CAT_C, SELLER_C, SHIP_C, INSTK_C, AVAIL_C, UNITS_C, SALE_C, MRP_C, DISC_C = 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
    for x in sorted(rows, key=lambda r: (not r['in_stock'], r.get('category', ''), (r.get('sale') is None, r.get('sale') or 0))):
        ws.append([x['sku_raw'], gv(x, 'asin'), gv(x, 'category'), gv(x, 'seller'), gv(x, 'ships_from'),
                   "Yes" if x['in_stock'] else "No", gv(x, 'availability_text'),
                   x.get('units_left'), x.get('sale'), x.get('mrp'), x['discount_pct'], x['pack'], x['per_litre']])
    style_header(ws)
    ws.freeze_panes = "A2"
    ws.auto_filter.ref = f"A1:{get_column_letter(len(cols))}{ws.max_row}"
    for row in ws.iter_rows(min_row=2):
        for cell in row:
            cell.border = BORDER
            if cell.column in (SALE_C, MRP_C): cell.number_format = '"Rs"#,##0'
            if cell.column == DISC_C: cell.number_format = '0.0"%"'
        # stock highlighting: green in-stock, red out / not-found / blocked
        avail = (row[AVAIL_C - 1].value or "")
        if row[INSTK_C - 1].value == "No":
            row[INSTK_C - 1].fill = RED
            row[AVAIL_C - 1].fill = RED if avail in ("NOT FOUND", "BLOCKED") else YEL
        else:
            row[INSTK_C - 1].fill = GREEN
        # missing retailer (no buybox / unavailable) flagged amber
        if not row[SELLER_C - 1].value:
            row[SELLER_C - 1].value = "-"; row[SELLER_C - 1].fill = YEL
        if isinstance(row[DISC_C - 1].value, (int, float)) and row[DISC_C - 1].value and row[DISC_C - 1].value >= 40:
            row[DISC_C - 1].fill = GREEN
    autosize(ws)
else:
    cols = ["City", "Pincode", "Locality", "Store", "SKU", "Pack", "Vol (ml)", "Sale Rs", "MRP Rs", "Disc %", "Rs/L", "ETA min", "In stock"]
    ws.append(cols)
    for x in sorted(rows, key=lambda r: (r['city'], r['pincode'], r['canonical'])):
        ws.append([x['city'], x['pincode'], x['locality'], x['store_name'], x['sku_raw'], x['pack'], x['vol_ml'],
                   x['sale'], x['mrp'], x['discount_pct'], x['per_litre'], x['eta_min'], "Yes" if x['in_stock'] else "No"])
    style_header(ws)
    ws.freeze_panes = "A2"
    ws.auto_filter.ref = f"A1:{get_column_letter(len(cols))}{ws.max_row}"
    for row in ws.iter_rows(min_row=2):
        for cell in row:
            cell.border = BORDER
            if cell.column in (8, 9): cell.number_format = '"Rs"#,##0'
            if cell.column == 10: cell.number_format = '0.0"%"'
        if row[12].value == "No": row[12].fill = RED
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

if HAS_SELLER:
    # Amazon is a single national "city", so per-city matrices add nothing.
    # Replace them with retailer-centric + stock-centric views the user wants.

    # ---- Sheet 3: Retailer Breakdown (who sells how many SKUs, price band) ----
    wsR = wb.create_sheet("Retailers")
    wsR.append(["Retailer (Sold by)", "SKUs sold", "In-stock SKUs", "Min Rs", "Median Rs", "Max Rs"])
    by_seller = defaultdict(list)
    for x in rows:
        sname = gv(x, 'seller') or "(no buybox / unavailable)"
        by_seller[sname].append(x)
    for sname in sorted(by_seller, key=lambda s: (-len(by_seller[s]), s)):
        grp = by_seller[sname]
        sales = sorted(x['sale'] for x in grp if x.get('sale') is not None)
        instk = sum(1 for x in grp if x['in_stock'])
        wsR.append([sname, len(grp), instk,
                    sales[0] if sales else None,
                    round(statistics.median(sales)) if sales else None,
                    sales[-1] if sales else None])
    style_header(wsR); wsR.freeze_panes = "A2"
    for row in wsR.iter_rows(min_row=2):
        for cell in row:
            cell.border = BORDER
            if cell.column >= 4 and isinstance(cell.value, (int, float)): cell.number_format = '"Rs"#,##0'
        if row[0].value == "(no buybox / unavailable)": row[0].fill = YEL
    autosize(wsR)

    # ---- Sheet 4: Stock Status by category (in-stock vs OOS vs not-found/blocked) ----
    wsS = wb.create_sheet("Stock Status")
    wsS.append(["Category", "Total ASINs", "In stock", "Out of stock", "Not found / blocked", "% in stock"])
    by_cat = defaultdict(list)
    for x in rows:
        by_cat[gv(x, 'category') or "(uncategorised)"].append(x)
    def _missing(x): return gv(x, 'availability_text') in ("NOT FOUND", "BLOCKED")
    for cat in sorted(by_cat):
        grp = by_cat[cat]
        instk = sum(1 for x in grp if x['in_stock'])
        miss = sum(1 for x in grp if _missing(x))
        oos = len(grp) - instk - miss
        pct = round(100 * instk / len(grp)) if grp else 0
        wsS.append([cat, len(grp), instk, oos, miss, pct])
    # totals row
    tot = rows
    t_in = sum(1 for x in tot if x['in_stock']); t_miss = sum(1 for x in tot if _missing(x))
    wsS.append(["ALL", len(tot), t_in, len(tot) - t_in - t_miss, t_miss, round(100 * t_in / len(tot)) if tot else 0])
    style_header(wsS); wsS.freeze_panes = "A2"
    for row in wsS.iter_rows(min_row=2):
        for cell in row: cell.border = BORDER
        last = row[-1]
        if isinstance(last.value, (int, float)):
            last.number_format = '0"%"'
            last.fill = GREEN if last.value >= 80 else (RED if last.value <= 20 else YEL)
        if row[0].value == "ALL":
            for cell in row: cell.font = Font(bold=True)
    autosize(wsS)
else:
    # Sheet 3: Pricing Matrix (avg sale per city) - green cheap -> red expensive
    matrix("Pricing Matrix", lambda c: round(statistics.mean([x['sale'] for x in c if x['sale'] is not None])) if any(x['sale'] is not None for x in c) else None, '"Rs"#,##0', scale=True)
    # Sheet 4: Stock Status (% in stock)
    def stock_cell(c):
        return round(100 * sum(x['in_stock'] for x in c) / len(c))
    wsS = matrix("Stock Status", stock_cell, '0"%"')
    for row in wsS.iter_rows(min_row=2):
        for cell in row:
            if cell.column > 1 and isinstance(cell.value, (int, float)):
                cell.fill = GREEN if cell.value == 100 else (RED if cell.value == 0 else YEL)
    # Sheet 5: Discount Analysis (avg disc per city) - higher = greener
    matrix("Discount Analysis", lambda c: round(statistics.mean([x['discount_pct'] for x in c if x['discount_pct'] is not None]), 1) if any(x['discount_pct'] is not None for x in c) else None, '0.0"%"', scale=True, scale_rev=True)

# ---------- Sheet 6: Coverage / Gaps ----------
ws = wb.create_sheet("Coverage & Gaps")
ws.append(["City", "Pincode", "Locality", "Store assigned", "Jivo SKUs found"])
for p in per:
    ws.append([p['city'], p['pincode'], p['locality'], p['store_name'], len(p['rows'])])
style_header(ws); ws.freeze_panes = "A2"
for row in ws.iter_rows(min_row=2):
    for cell in row: cell.border = BORDER
    if row[4].value == 0: row[4].fill = RED
    else: row[4].fill = GREEN
autosize(ws)

fname = f"Jivo-{PLATFORM.replace(' ', '')}-Live-Report-{datetime.date.today()}.xlsx"
wb.save(fname)
print("SAVED:", fname)
print("Sheets:", wb.sheetnames)
