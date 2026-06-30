#!/usr/bin/env python3
"""Generate index.html for eloo-bangalore-report.vercel.app.

Jivo Extra Light Olive Oil availability across Bengaluru's 117 pincodes on the 3 QC
platforms. Serviceability footprint = the latest FULL Bengaluru census; ELOO stock /
pack mix = freshest-per-pincode observation. Recomputes the report's DATA object and
patches the hardcoded hero/Venn/reach/findings numbers from it (fail-closed on any
template drift). Deterministic, stdlib, no LLM.
"""
import os, sys, re, json, datetime, collections
sys.path.insert(0, os.path.dirname(__file__))
import sitelib as S

OUT = os.environ.get("ELOO_DIR", "/root/eloo-bangalore-report")
TEMPLATE = os.path.join(os.path.dirname(__file__), "templates", "eloo.template.html")
QC = ["zepto", "blinkit", "flipkart-minutes"]
CITY = "Bengaluru"
PACK_NAMES = ["jivo-extra-light-olive-oil-1l", "jivo-extra-light-olive-oil-2l",
              "jivo-extra-light-olive-oil-combo-2l", "jivo-extra-light-olive-oil-combo-4l",
              "jivo-extra-light-olive-oil-combo-1l"]


def is_eloo(sku):
    return "extra-light-olive" in sku


def freshest_eloo(platform, pins, min_date):
    """(pincode) -> {date, any_instock, instock_skus:set, listed:bool} for ELOO in Bengaluru.

    Only rows on/after min_date (the platform's census date) count, so weeks-old
    'last ever in stock' observations don't leak in as live (freshness_guard rule).
    """
    per = collections.defaultdict(dict)  # pin -> sku -> (date, instock)
    for r in S.load_history(platform):
        if (r.get("city") or "").strip() != CITY:
            continue
        sku = (r.get("canonical_sku") or "").strip()
        if not is_eloo(sku):
            continue
        d = r.get("date_ist") or ""
        if d < min_date:
            continue
        pin = r["pincode"]
        instock = (r.get("in_stock") or "").strip().lower() in ("1", "true", "yes")
        cur = per[pin].get(sku)
        if cur is None or d > cur[0]:
            per[pin][sku] = (d, instock)
    out = {}
    for pin, skus in per.items():
        date = max(v[0] for v in skus.values())
        instock_skus = {sk for sk, v in skus.items() if v[1]}
        out[pin] = {"date": date, "any_instock": bool(instock_skus),
                    "instock_skus": instock_skus, "listed": True}
    return out


def build():
    ledger = S.load_ledger()
    # Bengaluru census footprint + per-pincode census status, per platform
    census_status = {}     # platform -> {pin: status}
    runs = {}
    beng = set()
    census_dates = {}
    for p in QC:
        d, rid, cr = S.census(ledger, p)
        runs[p] = rid
        census_dates[p] = d
        st = {}
        for r in cr:
            if (r.get("city") or "").strip() != CITY:
                continue
            st[r["pincode"]] = r["status"]
            beng.add(r["pincode"])
        census_status[p] = st
    beng = sorted(beng)
    universe = len(beng)

    eloo = {p: freshest_eloo(p, beng, census_dates[p]) for p in QC}
    stock_date = ""
    for p in QC:
        for v in eloo[p].values():
            stock_date = max(stock_date, v["date"])
    census_date = max(census_dates.values())

    def status_of(p, pin):
        e = eloo[p].get(pin)
        if e:
            return "in_stock" if e["any_instock"] else "listed_oos"
        cs = census_status[p].get(pin, "not_serviceable")
        if cs == "price_captured":
            return "jivo_no_eloo"
        if cs == "serviceable_no_jivo":
            return "serviceable_no_jivo"
        return "not_serviceable"

    matrix = [{"pincode": pin, **{p: status_of(p, pin) for p in QC}} for pin in beng]

    platforms = {}
    sku_breakdown = {}
    instock = {}
    for p in QC:
        st = census_status[p]
        rows = [r for r in matrix]
        instock_set = sorted(r["pincode"] for r in rows if r[p] == "in_stock")
        listed_set = sorted(r["pincode"] for r in rows if r[p] in ("in_stock", "listed_oos"))
        instock[p] = set(instock_set)
        platforms[p] = {
            "tested": universe,
            "not_serviceable": sum(1 for pin in beng if st.get(pin, "not_serviceable") == "not_serviceable"),
            "serviceable_no_jivo": sum(1 for pin in beng if st.get(pin) == "serviceable_no_jivo"),
            "jivo_present": sum(1 for pin in beng if st.get(pin) == "price_captured"),
            "jivo_present_rows": sum(1 for pin in beng if st.get(pin) == "price_captured"),
            "eloo_instock": len(instock_set),
            "eloo_listed": len(listed_set),
            "instock_set": instock_set,
            "listed_set": listed_set,
        }
        # per-sku in-stock pincode counts (a pincode counts once per in-stock sku)
        cnt = collections.Counter()
        for pin in beng:
            for sk in eloo[p].get(pin, {}).get("instock_skus", set()):
                cnt[sk] += 1
        sku_breakdown[p] = {sk: cnt[sk] for sk in PACK_NAMES if cnt[sk]} or dict(cnt)

    union_any = sorted(set().union(*instock.values()))
    both = sorted(instock["zepto"] & instock["blinkit"])
    all3 = sorted(instock["zepto"] & instock["blinkit"] & instock["flipkart-minutes"])
    z_only = sorted(instock["zepto"] - instock["blinkit"] - instock["flipkart-minutes"])
    b_only = sorted(instock["blinkit"] - instock["zepto"] - instock["flipkart-minutes"])
    f_only = sorted(instock["flipkart-minutes"] - instock["zepto"] - instock["blinkit"])
    cross = {
        "union_any": union_any, "union_n": len(union_any),
        "all3": all3, "all3_n": len(all3),
        "zepto_and_blinkit": len(both), "zepto_only": len(z_only),
        "blinkit_only": len(b_only), "fkm_only": len(f_only),
        "total_universe": universe,
    }

    meta = {
        "city": "Bengaluru (Bangalore)",
        "sku": "Jivo Extra Light Olive Oil (all pack sizes)",
        "run_date": census_date,
        "stock_refreshed": stock_date,
        "run_type": "full per-pincode coverage census (serviceability) + freshest stock overlay",
        "runs": runs,
        "source": "/opt/ecom-intel/data/<platform>/history.csv + data/coverage/ledger.csv",
        "doc": "docs/coverage-runs/2026-06-29-EXCEPTION-full-coverage.md",
        "universe_pincodes": universe,
    }

    data = {"platforms": platforms, "sku_breakdown": sku_breakdown,
            "cross": cross, "meta": meta, "matrix": matrix}
    return data, census_date, stock_date


def rep(html, old, new):
    n = html.count(old)
    if n != 1:
        raise SystemExit(f"[eloo] FAIL-CLOSED: anchor not unique ({n}x): {old[:70]!r}")
    return html.replace(old, new)


def findings_html(d):
    P = d["platforms"]
    c = d["cross"]
    U = c["total_universe"]
    fkm_serv = P["flipkart-minutes"]["not_serviceable"]
    fkm_serv = U - P["flipkart-minutes"]["not_serviceable"]
    blk = P["blinkit"]
    blk_serve = blk["jivo_present"] + blk["serviceable_no_jivo"]
    blk_oos = blk["eloo_listed"] - blk["eloo_instock"]
    single = c["zepto_only"] + c["blinkit_only"]
    blind = U - c["union_n"]
    # sample pincodes
    snj = sorted(p["pincode"] for p in d["matrix"] if p["blinkit"] == "serviceable_no_jivo")[:2]
    blind_pins = sorted(p["pincode"] for p in d["matrix"]
                        if "in_stock" not in (p["zepto"], p["blinkit"], p["flipkart-minutes"]))[:3]
    snj_txt = ", ".join(snj) if snj else "—"
    return (
        f'<div class="ins rev"><div class="ix">FINDING 01</div><h3>Flipkart Minutes is a <em>whitespace</em></h3>'
        f'<p>Flipkart Minutes delivers in only <b>{fkm_serv}</b> Bengaluru pincodes, and in every one of them it '
        f'stocks <b>only Jivo canola</b> — <span class="stat">zero</span> Extra Light olive oil. Listing it here is '
        f'pure upside, not a defence play.</p></div>\n'
        f'      <div class="ins rev"><div class="ix">FINDING 02</div><h3>A real <em>distribution</em> gap, not a data gap</h3>'
        f'<p>Blinkit <b>delivers</b> to ~{blk_serve} Bengaluru pincodes but stocks Extra Light in <b>{blk["eloo_instock"]}</b>, '
        f'and {blk_oos} more list it only as out-of-stock. The serve-but-no-Jivo pockets (e.g. {snj_txt}) are concrete '
        f'placement targets.</p></div>\n'
        f'      <div class="ins rev"><div class="ix">FINDING 03</div><h3>The core is <em>Blinkit ∩ Zepto</em></h3>'
        f'<p><b>{c["zepto_and_blinkit"]}</b> pincodes carry it on both platforms — resilient coverage. But <b>{single}</b> '
        f'rest on a single platform; if that one delists, the pincode goes dark. Worth a redundancy push.</p></div>\n'
        f'      <div class="ins rev"><div class="ix">FINDING 04</div><h3><em>{blind}</em> pincodes are dark</h3>'
        f'<p>{blind} of {U} Bengaluru pincodes can’t get Extra Light from any of the three — mostly outer pincodes none '
        f'of the platforms deliver to yet ({", ".join(blind_pins)}). These move only when q-commerce serviceability '
        f'expands.</p></div>'
    )


def patch(template, d, census_date, stock_date):
    c = d["cross"]
    U = c["total_universe"]
    fkm_instock = d["platforms"]["flipkart-minutes"]["eloo_instock"]
    single = c["zepto_only"] + c["blinkit_only"]
    blind = U - c["union_n"]
    h = template
    # DATA block
    h = re.sub(r"const DATA = \{.*?\};\n",
               "const DATA = " + json.dumps(d, ensure_ascii=False) + ";\n",
               h, count=1, flags=re.S)
    # hero
    h = rep(h, '<span class="n" data-count="90">0</span>',
            f'<span class="n" data-count="{c["union_n"]}">0</span>')
    h = rep(h, 'pincodes<b data-count="117">0</b>tested',
            f'pincodes<b data-count="{U}">0</b>tested')
    # venn
    h = rep(h, '<div class="vc vz"><span class="vn" data-count="12">0</span>',
            f'<div class="vc vz"><span class="vn" data-count="{c["zepto_only"]}">0</span>')
    h = rep(h, '<div class="vc vb"><span class="vn" data-count="14">0</span>',
            f'<div class="vc vb"><span class="vn" data-count="{c["blinkit_only"]}">0</span>')
    h = rep(h, '<div class="vmid"><div class="vn" data-count="64">0</div>',
            f'<div class="vmid"><div class="vn" data-count="{c["zepto_and_blinkit"]}">0</div>')
    h = rep(h, '<div class="vfkm">Flipkart Minutes<b>0</b>pincodes</div>',
            f'<div class="vfkm">Flipkart Minutes<b>{fkm_instock}</b>pincodes</div>')
    # reach stats (anchored with enough context to be unique)
    h = rep(h, '<div class="rstat"><span class="rn" data-count="90">0</span>',
            f'<div class="rstat"><span class="rn" data-count="{c["union_n"]}">0</span>')
    h = rep(h, '<div class="rstat"><span class="rn" data-count="64">0</span>',
            f'<div class="rstat"><span class="rn" data-count="{c["zepto_and_blinkit"]}">0</span>')
    h = rep(h, '<span class="rn" data-count="26">0</span><span class="rt">Single-platform pincodes (<b>12</b> Zepto-only + <b>14</b> Blinkit-only)',
            f'<span class="rn" data-count="{single}">0</span><span class="rt">Single-platform pincodes (<b>{c["zepto_only"]}</b> Zepto-only + <b>{c["blinkit_only"]}</b> Blinkit-only)')
    h = rep(h, '<div class="rstat dead"><span class="rn" data-count="27">0</span>',
            f'<div class="rstat dead"><span class="rn" data-count="{blind}">0</span>')
    # findings block
    h = re.sub(r'<div class="ins rev"><div class="ix">FINDING 01.*?</p></div>(?=\s*</div>\s*</section>)',
               findings_html(d), h, count=1, flags=re.S)
    if 'FINDING 01' not in h:
        raise SystemExit("[eloo] FAIL-CLOSED: findings block replacement failed")
    # run-id codes in methodology
    h = rep(h,
            'Run-ids: Zepto <code>2026-06-29-1319</code>, Blinkit <code>2026-06-29-1203</code>, FK&nbsp;Minutes <code>2026-06-29-1605</code>.',
            f'Run-ids: Zepto <code>{d["meta"]["runs"]["zepto"]}</code>, Blinkit <code>{d["meta"]["runs"]["blinkit"]}</code>, FK&nbsp;Minutes <code>{d["meta"]["runs"]["flipkart-minutes"]}</code>.')
    # dates (best-effort, future-proof)
    cd = datetime.date.fromisoformat(census_date).strftime("%-d %b %Y")
    h = h.replace("29 Jun 2026", cd)
    today = datetime.date.today().strftime("%-d %b %Y")
    h = h.replace("built from the data bank · 30 Jun 2026",
                  f"built from the data bank · {today}")
    return h


def main():
    d, census_date, stock_date = build()
    template = open(TEMPLATE).read()
    page = patch(template, d, census_date, stock_date)
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, "index.html"), "w").write(page)
    c = d["cross"]
    P = d["platforms"]
    print(f"[eloo] wrote {os.path.join(OUT,'index.html')} ({len(page)} bytes)")
    print(f"  census={census_date} stock_refreshed={stock_date} universe={c['total_universe']}")
    print(f"  in-stock: zepto={P['zepto']['eloo_instock']} blinkit={P['blinkit']['eloo_instock']} "
          f"fkm={P['flipkart-minutes']['eloo_instock']}")
    print(f"  union={c['union_n']} both={c['zepto_and_blinkit']} "
          f"single={c['zepto_only']+c['blinkit_only']} blind={c['total_universe']-c['union_n']}")


if __name__ == "__main__":
    main()
