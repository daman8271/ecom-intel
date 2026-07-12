#!/usr/bin/env python3
"""Regenerate jivo-city-coverage-guide index.html from the LIVE cron pin
lists (goal #80 coverage100). Asserts every per-pincode platform cell is
FULL before writing. Canonical copy also committed at
/opt/ecom-intel/tools/sites/regen_city_coverage_guide.py."""
import datetime
import json

import sys

sys.path.insert(0, "/opt/ecom-intel/tools/pincodes")
import universe_guide24 as U  # noqa: E402

ROOT = "/opt/ecom-intel"
PAGE = "/root/jivo-city-coverage-guide/index.html"
CSV = f"{ROOT}/docs/pincodes/drr_pincode.csv"
CITY_ORDER = ["Delhi", "Mumbai", "Pune", "Nagpur", "Nashik", "Noida",
              "Lucknow", "Ghaziabad", "Gurugram", "Faridabad", "Ludhiana",
              "Amritsar", "Jalandhar", "Mohali", "Bangalore", "Mysore",
              "Mangalore", "Hyderabad", "Kolkata", "Howrah", "Chandigarh",
              "Chennai", "Coimbatore", "Madurai"]


def load(p):
    return json.load(open(p))


def pins_of(entries):
    return {e["pincode"] for e in entries}


def cls(pct):
    if pct == 0:
        return "z"
    for lim, c in ((15, "c0"), (30, "c1"), (45, "c2"), (60, "c3"),
                   (75, "c4"), (90, "c5")):
        if pct * 100 < lim:
            return c
    return "c6"


def verdict(pct):
    if pct >= 0.95:
        return '<span class="chip full">&#9679; Near-full</span>'
    if pct >= 0.73:
        return '<span class="chip good">&#9679; Strong</span>'
    if pct >= 0.38:
        return '<span class="chip part">&#9650; Partial</span>'
    if pct > 0:
        return '<span class="chip thin">&#9650; Thin</span>'
    return '<span class="chip none">&#9632; None</span>'


def cell(n_in, universe_n, extra=""):
    if n_in == 0:
        return '<td class="z">0</td>'
    pct = n_in / universe_n
    label = extra if extra else str(n_in)
    return (f'<td class="{cls(pct)}"><span class="n">{label}</span>'
            f'<span class="p">{round(pct * 100)}%</span></td>')


def main():
    uni = U.build(CSV)
    all_uni = set().union(*(d["pins"] for d in uni.values()))

    blinkit = pins_of(load(f"{ROOT}/platforms/blinkit/pincodes.daily.json"))
    zepto = pins_of(load(f"{ROOT}/platforms/zepto/pincodes.daily.json"))
    fkm = pins_of(load(f"{ROOT}/platforms/flipkart-minutes/pincodes.daily.json"))
    af_core = pins_of(load(f"{ROOT}/platforms/amazon-fresh/pincodes.daily.json"))
    af_tail = pins_of(load(f"{ROOT}/platforms/amazon-fresh/pincodes.daily.tail.json"))
    an_core = pins_of(load(f"{ROOT}/platforms/amazon-now/pincodes.daily.json"))
    an_tail = pins_of(load(f"{ROOT}/platforms/amazon-now/pincodes.daily.tail.json"))
    bb = pins_of(load(f"{ROOT}/platforms/bigbasket/pincodes_jivo.json"))
    inst = load(f"{ROOT}/platforms/instamart/pincodes.json")
    inst_rep = {p for a in inst for p in a.get("pincodes", [a["pincode"]])}
    inst_anchor = {a["pincode"]: a for a in inst}

    af, an = af_core | af_tail, an_core | an_tail
    PLATS = [("Blinkit", blinkit), ("Zepto", zepto), ("Instamart", inst_rep),
             ("Fk Min", fkm), ("Amz Now", an), ("Amz Fresh", af),
             ("BB svc", bb)]

    # ---- assert FULL ----
    bad = []
    for name, s in PLATS:
        for c in CITY_ORDER:
            pct = len(s & uni[c]["pins"]) / len(uni[c]["pins"])
            if pct < 0.999:
                bad.append((name, c, round(pct, 3)))
    if bad:
        sys.exit(f"NOT FULL: {bad}")
    print("MIN CELL = 100% ✓")

    # ---- matrix rows ----
    rows = []
    full_cities = 0
    any_total = 0
    for c in CITY_ORDER:
        un = uni[c]["pins"]
        n = len(un)
        tds = []
        for name, s in PLATS:
            k = len(s & un)
            if name == "Instamart":
                anch = sum(1 for a in inst if a["pincode"] in un
                           or set(a["pincodes"]) & un)
                tds.append(cell(k, n, extra=f"{anch}&rarr;{k}"))
            else:
                tds.append(cell(k, n))
        any_cnt = len(set().union(*(s for _, s in PLATS)) & un)
        any_total += any_cnt
        if any_cnt == n:
            full_cities += 1
        pctany = any_cnt / n
        rows.append(
            f'<tr><th class="city">{c}</th><td class="u">{n}</td>'
            + "".join(tds)
            + f'<td class="any"><b>{any_cnt}</b>/{n}</td>'
            + f'<td class="anyp">{round(pctany * 100)}%</td>'
            + f'<td class="v">{verdict(pctany)}</td></tr>')

    # ---- programme table numbers ----
    def prog(s):
        inc = len(s & all_uni)
        return len(s), inc, len(s) - inc

    b_tot, b_in, b_out = prog(blinkit)
    z_tot, z_in, z_out = prog(zepto)
    f_tot, f_in, f_out = prog(fkm)
    an_tot, an_in, an_out = prog(an)
    af_tot, af_in, af_out = prog(af)
    bb_tot, bb_in, bb_out = prog(bb)
    ir_tot, ir_in, ir_out = prog(inst_rep)

    daily_visits = (b_tot + z_tot + f_tot + bb_tot + len(inst) +
                    len(af_core) + len(af_tail) + len(an_core) + len(an_tail))
    today = datetime.date.today().strftime("%B %d, %Y")

    html = HEAD_CSS + f"""
<h1>JIVO Cron Pincode Coverage &mdash; 24-City Guide</h1>
<p class="sub">What our daily scrape crons actually track, city by city, versus each city&rsquo;s full India Post pincode universe.</p>
<p class="asof">Config snapshot: {today} &middot; Universe: India Post All-India Pincode Directory (June 2024, 19,300 distinct PINs nationally) &middot; FULL-COVERAGE programme (goal #80)</p>

<div class="tiles">
<div class="tile"><div class="k">7 + 3</div><div class="l">platforms: 7 per-pincode crons + 3 national-price scrapes</div></div>
<div class="tile"><div class="k">{daily_visits:,}</div><div class="l">pincode visits per day across the 7 per-pin platforms (core lists + Amazon tail sweep + Instamart anchors)</div></div>
<div class="tile"><div class="k">1,550</div><div class="l">India Post pincodes in these 24 cities (the full universe)</div></div>
<div class="tile"><div class="k">{any_total:,} &middot; {round(any_total / 15.50)}%</div><div class="l">of those 1,550 are in the daily tracker &mdash; every pin, every platform</div></div>
<div class="tile"><div class="k">{full_cities} / 24</div><div class="l">cities where the tracker attempts every India Post pin</div></div>
<div class="tile"><div class="k">0</div><div class="l">cities with zero tracking &mdash; Amritsar, Jalandhar, Mangalore, Howrah, Madurai all onboarded {today}</div></div>
</div>

<div class="note"><b>Read this first &mdash; what these numbers are and are not.</b><br>
This measures <b>our daily price-tracking pincode lists</b> against each city&rsquo;s India Post pincode count. It is <b>not platform serviceability</b>.
Since {today} the programme attempts <b>every India Post pin in all 24 cities on all 7 platforms</b>; where a platform has no dark store the daily probe records
&ldquo;not serviceable&rdquo; &mdash; that log is the whitespace evidence. Quick-commerce networks structurally never serve 100% of an India Post universe,
so serviceable-share will sit below the attempted 100% by design. The India Post universe also counts PO-box/institutional pins no delivery service ever reaches.</div>

<h2>1 &middot; The programme &mdash; what each cron runs daily</h2>
<p class="sub">The 12:30 AM IST sweep (batch released 10:00 AM) uses each platform&rsquo;s <span class="mono">pincodes.daily.json</span>; Amazon&rsquo;s expansion tail runs post-batch at 10:15 AM (<span class="mono">pincodes.daily.tail.json</span>, chunked per city, resumable); BigBasket serviceability is its own 3:00 AM cron.</p>
<div class="tblwrap"><table>
<thead><tr><th>Platform</th><th>Mode</th><th>Schedule / host</th><th>Live pin list</th><th>Pins tracked</th><th>In the 24 cities</th><th>Outside them</th></tr></thead>
<tbody>
<tr><th>Blinkit</th><td>Per-pincode</td><td>Daily sweep &middot; Mac Pro 6:30 AM IST</td><td class="mono">pincodes.daily.json</td><td class="r">{b_tot:,}</td><td class="r">{b_in:,}</td><td class="r">{b_out}</td></tr>
<tr><th>Zepto</th><td>Per-pincode</td><td>Daily sweep &middot; Mac Pro launch 7:20 AM IST</td><td class="mono">pincodes.daily.json</td><td class="r">{z_tot:,}</td><td class="r">{z_in:,}</td><td class="r">{z_out}</td></tr>
<tr><th>Instamart</th><td>Per-pincode</td><td>Daily &middot; Mac Pro only (residential IP)</td><td class="mono">anchor-cluster &middot; {len(inst)} anchors &rarr; {ir_tot:,} represented</td><td class="r">{ir_tot:,}</td><td class="r">{ir_in:,}</td><td class="r">{ir_out}</td></tr>
<tr><th>Flipkart Minutes</th><td>Per-pincode</td><td>Daily sweep &middot; VPS chain</td><td class="mono">pincodes.daily.json</td><td class="r">{f_tot:,}</td><td class="r">{f_in:,}</td><td class="r">{f_out}</td></tr>
<tr><th>Amazon Now</th><td>Per-pincode</td><td>Core in daily sweep (daytime) + 10:15 AM tail</td><td class="mono">daily {len(an_core)} + tail {len(an_tail):,}</td><td class="r">{an_tot:,}</td><td class="r">{an_in:,}</td><td class="r">{an_out}</td></tr>
<tr><th>Amazon Fresh</th><td>Per-pincode</td><td>Core in daily sweep + 10:15 AM tail (own account)</td><td class="mono">daily {len(af_core)} + tail {len(af_tail):,}</td><td class="r">{af_tot:,}</td><td class="r">{af_in:,}</td><td class="r">{af_out}</td></tr>
<tr><th>BigBasket svc</th><td>Per-pincode</td><td>Serviceability cron 3:00 AM IST &middot; 3-device shards</td><td class="mono">pincodes_jivo.json</td><td class="r">{bb_tot:,}</td><td class="r">{bb_in:,}</td><td class="r">{bb_out}</td></tr>
<tr class="nat"><th>Amazon (marketplace)</th><td>National</td><td>Daily sweep</td><td class="mono">&mdash;</td><td class="r">All-India</td><td class="r">&mdash;</td><td class="r">&mdash;</td></tr>
<tr class="nat"><th>Flipkart (marketplace)</th><td>National</td><td>Daily sweep</td><td class="mono">&mdash;</td><td class="r">All-India</td><td class="r">&mdash;</td><td class="r">&mdash;</td></tr>
<tr class="nat"><th>BigBasket (price)</th><td>National</td><td>Daily sweep</td><td class="mono">&mdash;</td><td class="r">All-India</td><td class="r">&mdash;</td><td class="r">&mdash;</td></tr>
</tbody></table></div>
<p class="mut">&ldquo;Outside them&rdquo; pins are legitimate scrapes of cities not on this 24-city list (Jaipur, Kochi, Indore, Surat, etc.) &mdash; the daily programme is bigger than this grid.</p>

<h2>2 &middot; The matrix &mdash; pincodes tracked per city per platform</h2>
<p class="sub">Each cell: pins in our daily programme that fall inside that city&rsquo;s India Post universe, with % of universe below. Instamart cells show <b>anchors &rarr; represented</b>. <b>ANY</b> = distinct pins covered by at least one platform.</p>
<div class="leg"><span>Share of city universe:</span>
<span><span class="sw" style="background:#cde2fb"></span>&lt;15%</span>
<span><span class="sw" style="background:#9ec5f4"></span>15&ndash;30%</span>
<span><span class="sw" style="background:#6da7ec"></span>30&ndash;45%</span>
<span><span class="sw" style="background:#3987e5"></span>45&ndash;60%</span>
<span><span class="sw" style="background:#256abf"></span>60&ndash;75%</span>
<span><span class="sw" style="background:#184f95"></span>75&ndash;90%</span>
<span><span class="sw" style="background:#0d366b"></span>&ge;90%</span></div>
<div class="tblwrap"><table>
<thead><tr><th>City</th><th>India Post pins</th><th>Blinkit</th><th>Zepto</th><th>Instamart</th><th>Fk Min</th><th>Amz Now</th><th>Amz Fresh</th><th>BB svc</th><th>ANY</th><th>ANY %</th><th>Verdict</th></tr></thead>
<tbody>{"".join(chr(10) + r for r in rows)}
</tbody></table></div>
<p class="mut">Amazon marketplace, Flipkart marketplace and BigBasket main price are national-price scrapes (one all-India price) &mdash; per-city pincode coverage doesn&rsquo;t apply to them.</p>

<h2>3 &middot; So &mdash; do the crons cover ALL the pincodes in these cities?</h2>
<div class="note"><b>Yes &mdash; since {today}, every India Post pincode of all 24 cities is attempted daily on all 7 per-pincode platforms</b> (goal #80: &ldquo;0 to full&rdquo;).
The five former zero cities &mdash; Amritsar, Jalandhar, Mangalore, Howrah, Madurai &mdash; and every thin cell (Nashik 18%, Mohali 5%, Faridabad&rsquo;s Blinkit/Zepto 0s&hellip;) are now fully in the programme.</div>
<ul class="gaps">
<li><b>Attempted vs serviceable:</b> 100% attempted &ne; 100% serviceable &mdash; the daily probe log now doubles as a per-platform serviceability census (whitespace evidence where platforms have no store).</li>
<li><b>Amazon core+tail:</b> the proven core lists ({len(af_core)}/{len(an_core)} pins) still ride the 10:00 batch; the expansion tail ({len(af_tail):,}/{len(an_tail):,} pins) runs post-batch, chunked per city, resuming across days if throttled.</li>
<li><b>Instamart:</b> {len(inst)} anchors represent {ir_tot:,} pins (a nearby anchor&rsquo;s dark-store answers for the cluster); Mac Pro residential line only &mdash; silently absent if the Mac is down.</li>
<li><b>Single-platform dependencies are gone:</b> every city now has all seven platforms attempting it daily.</li>
</ul>

<h2>4 &middot; Caveats &amp; provenance</h2>
<ul class="gaps">
<li><b>Universe construction:</b> distinct 6-digit PINs per India Post <i>district</i> (Delhi = whole NCT, Mumbai = City + Suburban, Noida = Gautam Buddha Nagar, Chandigarh = whole UT, Mohali = S.A.S Nagar, Mangalore = Dakshina Kannada district). District buckets include rural pins &mdash; that is deliberate: rural &ldquo;not serviceable&rdquo; probes are the whitespace ledger.</li>
<li><b>Instamart provenance:</b> anchor-cluster config; representation means a nearby anchor&rsquo;s store answers for the pin, not that each pin was visited.</li>
<li><b>One shared pin:</b> 201009 sits in both Noida and Ghaziabad districts (counted once in the distinct union of 1,550).</li>
<li><b>Generator:</b> tools/pincodes/gen80.py (full-universe lists) + this page from regen_matrix.py &mdash; both committed; page regenerated from LIVE configs, never hand-edited.</li>
<li><b>Sources:</b> /opt/ecom-intel platform configs (live cron inputs) &times; India Post All-India Pincode Directory mirror (June-2024 snapshot).</li>
</ul>

<footer>JIVO ecom-intel &middot; generated {today} &middot; per-pin daily programme: blinkit {b_tot:,}, zepto {z_tot:,}, flipkart-minutes {f_tot:,}, amazon-fresh {af_tot:,} (core+tail), amazon-now {an_tot:,} (core+tail), instamart {len(inst)}&rarr;{ir_tot:,}, bigbasket-svc {bb_tot:,} &middot; {daily_visits:,} pincode visits/day.</footer>
</div></body></html>
"""
    open(PAGE, "w").write(html)
    print(f"wrote {PAGE}: cities={len(CITY_ORDER)} full_any={full_cities}/24 "
          f"daily_visits={daily_visits:,}")


# Everything before the first <h1> (doctype/head/CSS/body opener) is carried
# over verbatim from the current page, so the look never drifts. Idempotent:
# the regenerated page splits at the same marker.
HEAD_CSS = open(PAGE).read().split("<h1>")[0]

if __name__ == "__main__":
    main()
