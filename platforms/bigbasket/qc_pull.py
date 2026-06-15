"""Pull Jivo-only BigBasket per-pincode pricing via QuickCommerce API (licensed).
Multi-key: rotates through secrets/qc_keys.txt (one key per line) as each runs low, so a
one-time full-332 survey completes across available credits. NOTE: for the ongoing daily
cron use a single PAID key — rotating trial keys daily is neither reliable nor right.
Writes result_pincode.json in the scraper schema. Brand == 'Jivo' only."""
import json, urllib.request, urllib.parse, urllib.error, time, os, re, datetime
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
_kf = os.path.join(HERE, 'secrets', 'qc_keys.txt')
KEYS = [l.strip() for l in open(_kf) if l.strip()] if os.path.exists(_kf) else [open(os.path.join(HERE, 'secrets', 'qc_key.txt')).read().strip()]
KEY_IDX = 0
LIMIT = int(os.environ.get('QC_LIMIT', '999'))
PER_CITY = int(os.environ.get('QC_PER_CITY', '30'))

PFILE = os.environ.get('PINCODES_FILE') or os.path.join(HERE, '..', 'blinkit', 'pincodes.json')
if not os.path.isabs(PFILE):
    PFILE = os.path.join(HERE, PFILE)
allp = [p for p in json.load(open(PFILE))
        if isinstance(p.get('lat'), (int, float)) and isinstance(p.get('lon'), (int, float))]
if LIMIT >= len(allp):
    PINS = list(allp)
else:
    percity = defaultdict(list)
    for p in allp:
        percity[p['city']].append(p)
    PINS = []
    for rnd in range(PER_CITY):
        for city, lst in percity.items():
            if rnd < len(lst):
                PINS.append(lst[rnd])
            if len(PINS) >= LIMIT:
                break
        if len(PINS) >= LIMIT:
            break
    PINS = PINS[:LIMIT]


def vol_ml(q):
    if not q:
        return None
    m = re.search(r'([\d.]+)\s*(ml|l|ltr|litre|g|kg)', q.lower())
    if not m:
        return None
    n = float(m.group(1)); u = m.group(2)
    return n * 1000 if u in ('l', 'ltr', 'litre', 'kg') else n


def canon(name, q):
    base = re.sub(r'[^a-z0-9 ]', '', re.sub(r'\(.*?\)', '', (name or '').lower()))
    base = re.sub(r'\s+', ' ', base).strip().replace(' ', '-')
    v = vol_ml(q)
    vt = ('%g' % (v / 1000) + 'l') if (v and v >= 1000) else ((str(int(v)) + 'ml') if v else 'na')
    return re.sub(r'-+', '-', base + '-' + vt)


def num(x):
    try:
        return float(re.sub(r'[^\d.]', '', str(x)))
    except Exception:
        return None


def call(lat, lon, key):
    url = 'https://api.quickcommerceapi.com/v1/search?' + urllib.parse.urlencode({'q': 'jivo', 'lat': lat, 'lon': lon, 'platform': 'BigBasket'})
    req = urllib.request.Request(url, headers={'X-API-Key': key})
    with urllib.request.urlopen(req, timeout=45) as r:
        return json.load(r)


perPin, allRows, credits, t0 = [], [], None, time.time()
for i, rec in enumerate(PINS):
    rows, status = [], 0
    for _ in range(len(KEYS) + 1):
        try:
            d = call(rec['lat'], rec['lon'], KEYS[KEY_IDX]); status = 200
            credits = d.get('credits_remaining', credits)
            for p in d.get('data', {}).get('products', []):
                if (p.get('brand') or '').strip().lower() != 'jivo':
                    continue
                sale = num(p.get('offer_price')); mrp = num(p.get('mrp')); q = p.get('quantity') or ''
                v = vol_ml(q)
                rows.append({'city': rec['city'], 'pincode': rec['pincode'], 'locality': rec.get('locality', ''),
                             'store_name': 'BigBasket', 'sku_raw': p.get('name', ''), 'canonical': canon(p.get('name', ''), q),
                             'pack': q, 'vol_ml': v, 'sale': sale, 'mrp': mrp,
                             'discount_pct': round((mrp - sale) / mrp * 100, 1) if (mrp and sale and mrp > sale) else 0,
                             'per_litre': round(sale / (v / 1000), 2) if (sale and v) else None, 'eta_min': None,
                             'in_stock': 1 if p.get('available') else 0, 'sku_id': str(p.get('id', '')), 'brand': 'Jivo'})
            break
        except urllib.error.HTTPError as he:
            if he.code in (401, 402, 403, 429) and KEY_IDX < len(KEYS) - 1:
                KEY_IDX += 1; credits = None; print(f'  [rotate] HTTP {he.code} -> key #{KEY_IDX + 1}/{len(KEYS)}'); continue
            print('  ERR', rec['city'], rec['pincode'], 'HTTP', he.code); break
        except Exception as e:
            print('  ERR', rec['city'], rec['pincode'], str(e)[:80]); break
    seen, dd = set(), []
    for r in rows:
        k = r['sku_id'] or r['canonical']
        if k in seen:
            continue
        seen.add(k); dd.append(r)
    perPin.append({'city': rec['city'], 'pincode': rec['pincode'], 'locality': rec.get('locality', ''), 'tier': rec.get('tier', 0),
                   'store_id': '', 'store_name': 'BigBasket', 'set_status': status, 'fetch_ok': status == 200, 'serving_sa': None, 'rows': dd})
    allRows.extend(dd)
    print(f"  [{i + 1}/{len(PINS)}] {rec['city']} {rec['pincode']} jivo={len(dd)} instock={sum(x['in_stock'] for x in dd)} key#{KEY_IDX + 1} credits={credits}")
    if (i + 1) % 20 == 0:
        json.dump({'perPin': perPin, 'allRows': allRows}, open(os.path.join(HERE, 'result_pincode.partial.json'), 'w'))  # incremental
    if credits is not None and credits <= 2:
        if KEY_IDX < len(KEYS) - 1:
            KEY_IDX += 1; credits = None; print(f'  [rotate] low credits -> key #{KEY_IDX + 1}/{len(KEYS)}')
        else:
            print(f'  [stop] all keys exhausted at pincode {i + 1}/{len(PINS)}'); break
    time.sleep(0.4)

byid = {}
for p in perPin:
    for r in p['rows']:
        byid.setdefault(r['sku_id'] or r['canonical'], set()).add(r['sale'])
pv = sum(1 for s in byid.values() if len(s) > 1)
summary = {'pincodes_total': len(perPin), 'pincodes_with_jivo': sum(1 for p in perPin if p['rows']),
           'unique_skus': len({r['canonical'] for r in allRows}), 'total_rows': len(allRows),
           'skus_with_price_variance': pv, 'verdict': ('HYPERLOCAL — Jivo price varies by pincode' if pv > 0 else 'uniform across sampled pincodes'),
           'source': 'QuickCommerce API (licensed)', 'credits_remaining_last_key': credits, 'wall_s': round(time.time() - t0),
           'captured_at': datetime.datetime.now().isoformat()}
json.dump({'summary': summary, 'perPin': perPin, 'allRows': allRows}, open(os.path.join(HERE, 'result_pincode.json'), 'w'), indent=2)
print('SUMMARY', json.dumps(summary))
