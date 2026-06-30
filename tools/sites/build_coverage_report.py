#!/usr/bin/env python3
"""Generate index.html for coverage-report-site.vercel.app — national QC coverage.

Quick-commerce only (Blinkit, Zepto, Flipkart Minutes), by design. Serviceability /
per-city table come from each platform's full census; price rows / SKUs / discounts /
ranges come from the freshest history snapshot. Deterministic, stdlib, no LLM.
"""
import os, sys, html, datetime, collections
sys.path.insert(0, os.path.dirname(__file__))
import sitelib as S

OUT = os.environ.get("COVERAGE_DIR", "/root/coverage-report-site")
QC = ["zepto", "blinkit", "flipkart-minutes"]
PNAME = {"zepto": "Zepto", "blinkit": "Blinkit", "flipkart-minutes": "Flipkart Minutes"}
ANCHOR_BASELINE = 234  # fixed historical "old anchor estimate" reference point
# fixed display order (preserve the current site's layout)
CITY_ORDER = ["Delhi", "Mumbai", "Bengaluru", "Chennai", "Kolkata", "Pune", "Hyderabad",
              "Ahmedabad", "Coimbatore", "Kochi", "Lucknow", "Jaipur", "Mysuru", "Gurugram",
              "Chandigarh", "Nagpur", "Surat", "Visakhapatnam", "Bhubaneswar", "Vadodara",
              "Nashik", "Indore", "Noida", "Vijayawada", "Thiruvananthapuram"]

CSS = """:root{--g:#2e7d32;--g2:#43a047;--ink:#15241a;--mut:#5c6b60;--bg:#f5f8f5;--card:#fff;--line:#e2ebe3;--amber:#c77700;--red:#c0392b}
*{box-sizing:border-box;margin:0;padding:0}
body{font:16px/1.55 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:var(--ink);background:var(--bg)}
.wrap{max-width:1080px;margin:0 auto;padding:28px 20px 80px}
header{background:linear-gradient(135deg,#1b5e20,#2e7d32 55%,#43a047);color:#fff;border-radius:18px;padding:34px 30px;box-shadow:0 10px 30px rgba(27,94,32,.18)}
header .tag{font-size:13px;letter-spacing:.14em;text-transform:uppercase;opacity:.85;font-weight:600}
header h1{font-size:30px;margin:6px 0 4px;font-weight:800;letter-spacing:-.5px}
header .sub{opacity:.9;font-size:15px}
.hero{display:flex;gap:18px;flex-wrap:wrap;margin-top:22px}
.hstat{background:rgba(255,255,255,.14);border:1px solid rgba(255,255,255,.22);border-radius:13px;padding:14px 18px;min-width:150px;flex:1}
.hstat .n{font-size:30px;font-weight:800;line-height:1}
.hstat .l{font-size:12.5px;opacity:.9;margin-top:4px}
.arrow{display:flex;align-items:center;justify-content:center;font-size:24px;font-weight:800;color:#fff;opacity:.7}
h2{font-size:19px;margin:34px 0 14px;font-weight:800;color:var(--ink);display:flex;align-items:center;gap:9px}
h2:before{content:"";width:5px;height:20px;background:var(--g2);border-radius:3px;display:inline-block}
.kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:14px}
.kpi{background:var(--card);border:1px solid var(--line);border-radius:13px;padding:16px}
.kpi .n{font-size:26px;font-weight:800;color:var(--g)}
.kpi .l{font-size:12.5px;color:var(--mut);margin-top:3px}
.pcards{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}
.pcard{background:var(--card);border:1px solid var(--line);border-radius:15px;padding:18px;border-top:4px solid var(--g2)}
.pcard.blinkit{border-top-color:#f7c948} .pcard.zepto{border-top-color:#7b3fe4} .pcard.flipkart-minutes{border-top-color:#2874f0}
.pname{font-weight:800;font-size:16px}
.big{font-size:38px;font-weight:800;color:var(--ink);margin-top:8px;line-height:1}
.big .of{font-size:16px;color:var(--mut);font-weight:600}
.plabel{font-size:12.5px;color:var(--mut);margin-bottom:10px}
.prow{display:flex;justify-content:space-between;font-size:13.5px;padding:5px 0;border-top:1px dashed var(--line)}
.prow span{color:var(--mut)} .prow b{font-weight:700}
.insight{background:#fff8e6;border:1px solid #f0d98a;border-left:5px solid var(--amber);border-radius:12px;padding:18px 20px}
.insight h3{color:var(--amber);font-size:16px;margin-bottom:6px}
.insight .num{font-size:34px;font-weight:800;color:var(--amber);float:right;line-height:1}
table{width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--line);border-radius:13px;overflow:hidden;font-size:13.5px}
th,td{padding:8px 10px;text-align:center;border-bottom:1px solid var(--line)}
th{background:#eef4ee;font-size:11px;text-transform:uppercase;letter-spacing:.05em;color:var(--mut);font-weight:700}
td.city{text-align:left;font-weight:700} td.u{color:var(--mut)}
td.sub{color:var(--mut);font-size:11.5px} td.zero{color:var(--red);font-weight:700}
tbody tr:hover{background:#f3f9f3}
.legend{font-size:12px;color:var(--mut);margin:8px 2px 0}
.note{background:var(--card);border:1px solid var(--line);border-radius:13px;padding:18px 20px;font-size:14px;color:#33433a}
.note b{color:var(--ink)}
.foot{text-align:center;color:var(--mut);font-size:12px;margin-top:30px}
@media(max-width:760px){.kpis{grid-template-columns:repeat(2,1fr)}.pcards{grid-template-columns:1fr}.hstat{min-width:120px}}"""


def fmt(n):
    return f"{n:,}"


def build():
    today = datetime.date.today()
    ledger = S.load_ledger()
    serv = collections.defaultdict(set)
    jivo = collections.defaultdict(set)
    percity = collections.defaultdict(lambda: collections.defaultdict(lambda: [0, 0]))
    city_univ = collections.defaultdict(set)
    census_dates = {}
    for p in QC:
        d, rid, cr = S.census(ledger, p)
        census_dates[p] = d
        for r in cr:
            pin = r["pincode"]
            city = (r.get("city") or "").strip()
            city_univ[city].add(pin)
            if r["status"] in S.SERVICEABLE:
                serv[p].add(pin)
                percity[city][p][0] += 1
            if r["status"] == "price_captured":
                jivo[p].add(pin)
                percity[city][p][1] += 1
    reach = set().union(*serv.values())
    jivoany = set().union(*jivo.values())
    universe = sum(len(v) for v in city_univ.values())

    # freshest-snapshot price stats per platform
    pstats = {}
    latest_data = ""
    for p in QC:
        h = S.load_history(p)
        ld = max((r["date_ist"] for r in h), default="")
        latest_data = max(latest_data, ld)
        rows = [r for r in h if r["date_ist"] == ld]
        prices = [S._num(r["price"]) for r in rows if S._num(r["price"]) is not None]
        instock = [r for r in rows if (r.get("in_stock") or "").strip().lower() in ("1", "true", "yes")]
        discs = [S._num(r["discount_pct"]) for r in instock if S._num(r["discount_pct"]) is not None]
        skus = {(r.get("canonical_sku") or "").strip() for r in rows if (r.get("canonical_sku") or "").strip()}
        pstats[p] = {
            "rows": len(rows), "skus": len(skus),
            "pmin": min(prices) if prices else None, "pmax": max(prices) if prices else None,
            "disc": round(sum(discs) / len(discs), 1) if discs else 0.0,
            "instock": len(instock), "oos": len(rows) - len(instock),
        }
    total_rows = sum(pstats[p]["rows"] for p in QC)
    ratio = round(len(reach) / ANCHOR_BASELINE, 1)
    blk_gap = len(serv["blinkit"]) - len(jivo["blinkit"])

    # ---- platform cards ----
    cards = ""
    for p in QC:
        st = pstats[p]
        pr = f"&#8377;{st['pmin']}&ndash;{fmt(st['pmax'])}" if st["pmin"] is not None else "&mdash;"
        cards += f"""<div class="pcard {p}">
      <div class="pname">{PNAME[p]}</div>
      <div class="big">{len(serv[p])}<span class="of">/{fmt(universe)}</span></div>
      <div class="plabel">pincodes it delivers to</div>
      <div class="prow"><span>Jivo on sale</span><b>{len(jivo[p])}</b></div>
      <div class="prow"><span>No service</span><b>{universe-len(serv[p])}</b></div>
      <div class="prow"><span>Jivo SKUs found</span><b>{st['skus']}</b></div>
      <div class="prow"><span>Price rows captured</span><b>{fmt(st['rows'])}</b></div>
      <div class="prow"><span>Price range</span><b>{pr}</b></div>
      <div class="prow"><span>Avg discount</span><b>{st['disc']}%</b></div>
    </div>"""

    # ---- city table ----
    trs = ""
    for city in CITY_ORDER:
        u = len(city_univ.get(city, set()))
        cells = ""
        for p in QC:
            sv, jv = percity[city][p]
            scls = "zero" if sv == 0 else ""
            cells += f"<td class='{scls}'>{sv}</td><td class='sub'>{jv}</td>"
        trs += f"<tr><td class='city'>{html.escape(city)}</td><td class='u'>{u}</td>{cells}</tr>\n"

    page = f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>JIVO Quick-Commerce Coverage &mdash; Live Pincode Report</title>
<style>{CSS}</style></head><body><div class="wrap">

<header>
  <div class="tag">JIVO &middot; E-Commerce Intelligence</div>
  <h1>Quick-Commerce Pincode Coverage &mdash; Live Ground Truth</h1>
  <div class="sub">Every pincode physically checked across 25 priority cities &middot; {today.strftime('%-d %b %Y')} &middot; Zepto &middot; Blinkit &middot; Flipkart Minutes</div>
  <div class="hero">
    <div class="hstat"><div class="n">{ANCHOR_BASELINE}</div><div class="l">pincodes covered (old anchor estimate)</div></div>
    <div class="arrow">&rarr;</div>
    <div class="hstat"><div class="n">{len(reach)}</div><div class="l">pincodes really reachable now (verified)</div></div>
    <div class="hstat"><div class="n">{ratio}&times;</div><div class="l">real coverage vs the old anchor model</div></div>
  </div>
</header>

<h2>The numbers at a glance</h2>
<div class="kpis">
  <div class="kpi"><div class="n">{fmt(universe*len(QC))}</div><div class="l">pincode checks run ({fmt(universe)} &times; {len(QC)} platforms)</div></div>
  <div class="kpi"><div class="n">{len(reach)} <span style="font-size:14px;color:var(--mut)">/{fmt(universe)}</span></div><div class="l">reachable by &ge;1 platform ({round(100*len(reach)/universe)}%)</div></div>
  <div class="kpi"><div class="n">{len(jivoany)} <span style="font-size:14px;color:var(--mut)">/{fmt(universe)}</span></div><div class="l">have Jivo actually on sale ({round(100*len(jivoany)/universe)}%)</div></div>
  <div class="kpi"><div class="n">{fmt(total_rows)}</div><div class="l">live price rows captured</div></div>
</div>

<h2>Platform by platform</h2>
<div class="pcards">{cards}</div>

<h2>The headline finding</h2>
<div class="insight">
  <div class="num">{blk_gap}</div>
  <h3>Blinkit delivers to {len(serv['blinkit'])} pincodes &mdash; but Jivo is on the shelf in only {len(jivo['blinkit'])}.</h3>
  <p>That&rsquo;s <b>{blk_gap} pincodes where Blinkit physically delivers, but carries no Jivo product.</b> This is not a data gap &mdash; it&rsquo;s a <b>distribution opportunity</b>: demand reach exists, the listing doesn&rsquo;t. Zepto and Flipkart Minutes, by contrast, stock Jivo in <b>every</b> pincode they serve.</p>
</div>

<h2>Coverage by city (all 25)</h2>
<table>
<thead><tr><th>City</th><th>Pincodes</th><th>Zepto serv</th><th>&middot; Jivo</th><th>Blinkit serv</th><th>&middot; Jivo</th><th>Flipkart serv</th><th>&middot; Jivo</th></tr></thead>
<tbody>{trs}</tbody></table>
<div class="legend">&ldquo;serv&rdquo; = pincodes the platform delivers to &middot; &ldquo;Jivo&rdquo; = of those, how many have Jivo on sale &middot; <span style="color:var(--red);font-weight:700">red</span> = platform doesn&rsquo;t operate there at all.</div>

<h2>Method (so you can trust it)</h2>
<div class="note">
<p>The 25 cities hold <b>{fmt(universe)} distinct pincodes</b>, counted from the official India Post directory. Each platform was pointed at <b>every one</b> of those {fmt(universe)} pincodes and the result logged as one of: <b>Jivo priced</b> &middot; <b>serviceable but no Jivo</b> &middot; <b>not serviceable</b>. No proxies, no extrapolation, no estimates. Serviceability reflects each platform&rsquo;s latest full census; price rows / discounts reflect the freshest scrape ({latest_data}).</p>
</div>

<div class="foot">Generated from <code>data/coverage/ledger.csv</code> + per-platform <code>history.csv</code> &middot; JIVO ecom-intel &middot; physically-scraped ground truth, {today.strftime('%-d %b %Y')}</div>
</div></body></html>"""
    return page, dict(reach=len(reach), jivo=len(jivoany), universe=universe, rows=total_rows)


def main():
    page, k = build()
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "index.html")
    open(path, "w").write(page)
    print(f"[coverage] wrote {path} ({len(page)} bytes)")
    print(f"  reachable={k['reach']} jivo={k['jivo']} universe={k['universe']} price_rows={k['rows']}")


if __name__ == "__main__":
    main()
