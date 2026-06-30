#!/usr/bin/env python3
"""Fold the day's competitor capture into the ecom-intel Obsidian vault so it flows into the
JIVO data bank (which losslessly copies /opt/ecom-intel/vault -> combined-vault/ecom/).

Writes, under vault/competitor/:
  data/competitor_history.csv   - copy of the canonical append-only history (the dataset)
  daily/Competitor-<date>.md    - a per-day digest note
  Competitor-Watch.md           - an index of the daily notes

Deterministic; plain markdown only (no [[wikilinks]]) so it can never trip the data bank's
fail-closed link-integrity verify. Usage: to_vault.py <YYYY-MM-DD>
"""
import json, sys, glob, os, shutil

ROOT = os.environ.get('ECOM_ROOT', '/opt/ecom-intel')
DATE = sys.argv[1] if len(sys.argv) > 1 else None
if not DATE:
    sys.exit('usage: to_vault.py <YYYY-MM-DD>')

DATA = f'{ROOT}/tools/competitor/data'
VDIR = f'{ROOT}/vault/competitor'
os.makedirs(f'{VDIR}/data', exist_ok=True)
os.makedirs(f'{VDIR}/daily', exist_ok=True)

# 1) the canonical dataset: copy the append-only history into the vault
hist = f'{DATA}/competitor_history.csv'
if os.path.exists(hist):
    shutil.copyfile(hist, f'{VDIR}/data/competitor_history.csv')

# 2) per-platform digest for the day
plats, brands = {}, {}
for f in sorted(glob.glob(f'{DATA}/*_competitor_{DATE}.json')):
    plat = os.path.basename(f).split('_competitor_')[0]
    try:
        rows = (json.load(open(f)) or {}).get('allRows', [])
    except Exception:
        continue
    cities = sorted({r.get('city') for r in rows if r.get('city')})
    bset = sorted({r.get('brand') for r in rows if r.get('brand')})
    plats[plat] = {'rows': len(rows), 'cities': len(cities), 'brands': len(bset)}
    for r in rows:
        b = r.get('brand')
        if b:
            brands[b] = brands.get(b, 0) + 1

# 3) the daily note (plain markdown)
out = [f'# Competitor Price Watch — {DATE}', '',
       'Quick-commerce competitor price capture (Blinkit + Zepto; Flipkart-Minutes pending login).', '',
       '| Platform | Rows | Cities | Brands |', '|---|---|---|---|']
for p, s in plats.items():
    out.append(f"| {p} | {s['rows']} | {s['cities']} | {s['brands']} |")
out += ['', '## Competitor brands seen (SKU count)', '']
for b, n in sorted(brands.items(), key=lambda x: (-x[1], x[0])):
    out.append(f'- {b} — {n}')
out += ['', f'Full comparison report: `output/Competitor-Price-Watch-AllQcomm-{DATE}.xlsx`',
        'Underlying data: `competitor/data/competitor_history.csv`', '']
open(f'{VDIR}/daily/Competitor-{DATE}.md', 'w').write('\n'.join(out))

# 4) index note (plain relative-path markdown links — not wikilinks)
idx = ['# Competitor Price Watch', '',
       'Daily quick-commerce competitor price intelligence (JIVO vs rivals), folded from the',
       'live scrapers. JIVO 9-SKU anchors matched to true same-oil-type+grade rivals.', '',
       '## Daily captures', '']
for f in sorted(glob.glob(f'{VDIR}/daily/Competitor-*.md'), reverse=True):
    n = os.path.basename(f)[:-3]
    idx.append(f'- [{n}](daily/{n}.md)')
open(f'{VDIR}/Competitor-Watch.md', 'w').write('\n'.join(idx))

total = sum(s['rows'] for s in plats.values())
print(f'vault: competitor/{DATE} -> {total} rows, {len(plats)} platforms, {len(brands)} brands')
