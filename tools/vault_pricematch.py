#!/usr/bin/env python3
"""
vault_pricematch.py - Price-match compliance section of the ecom-intel Obsidian vault.

Surfaces the price-match history (W1's data/pricematch/history.csv + daily.csv) inside the
existing knowledge graph so the owner can track violations / exposure over time, cross-linked
to the platform hubs and (when a confident canonical mapping exists) the per-SKU memory notes.

Emits, under the namespaced vault/pricematch/ tree (ADDITIVE - never touches the ~1720
existing notes, basenames globally unique by the `pricematch-`/`pm-`/`Price-Match-MOC` prefix):

  - daily PM notes    vault/pricematch/pricematch-<date>.md   (regime, KPI line, top-offenders table)
  - per-SKU rollups   vault/pricematch/pm-<sku>.md            (ref-vs-live status over time, all platforms)
  - the PM MOC        vault/pricematch/Price-Match-MOC.md     (index + exposure trend + worst offenders)

DESIGN: same rules as tools/vault_build.py (which this hooks into) - links target REAL
BASENAMES, every edge is a body [[wikilink]], complete data lives in fenced ```csv blocks,
deterministic / stdlib-only / no network / no LLM, idempotent (identical CSVs -> identical notes).
The reader is column-name tolerant (alias map) so it binds to W1's schema with minor renames;
it degrades cleanly to a no-op when data/pricematch/ has not landed yet.

Usage:  python3 tools/vault_pricematch.py     # build ONLY the PM section (helpers reused from vault_build)
        (normally invoked as a section of `python3 tools/vault_build.py`)
"""
import csv
import os
import sys

# Reuse the vault's formatting/link/file helpers verbatim - one source of truth for the
# conventions (safe_name, link, link_row, csv_block, frontmatter, footer, write_file, money,
# pct, fnum). Import is side-effect-free (vault_build only defines on import).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vault_build as vb
from vault_build import (safe_name, link, link_row, csv_block, frontmatter, footer,
                         write_file, money, pct, fnum)

ROOT = vb.ROOT
VAULT = vb.VAULT
PM_DATA = os.environ.get("PM_DATA") or os.path.join(ROOT, "data", "pricematch")
PM_VAULT = os.path.join(VAULT, "pricematch")
GEN = "tools/vault_pricematch.py"

# Status -> (emoji, label). BELOW = live under the reference (compliance exposure); ABOVE =
# live over reference; MATCH = within tolerance; the rest are coverage states.
STATUS_LABEL = {
    "BELOW": "🔴 below ref", "ABOVE": "🟢 above ref", "MATCH": "✅ match",
    "OOS": "⚪ out of stock", "PENDING_REVIEW": "🟡 pending", "NO_REF": "▫️ no ref",
    "NOT_LISTED": "▫️ not listed",
}
TOP_OFFENDERS = 15  # rows in a daily note's offender table
WORST_RECURRING = 20  # SKUs in the MOC's recurring-offender list


# ----------------------------------------------------------------------------- tolerant reader
def _resolve(fieldnames, *aliases):
    """First header in `fieldnames` (case-insensitive) matching any alias, else None."""
    low = {f.lower(): f for f in (fieldnames or [])}
    for a in aliases:
        if a.lower() in low:
            return low[a.lower()]
    return None


def _read_csv(path):
    if not os.path.isfile(path):
        return [], []
    with open(path, encoding="utf-8", newline="") as fh:
        rd = csv.DictReader(fh)
        return list(rd), (rd.fieldnames or [])


def load_history():
    """Normalize data/pricematch/history.csv (1 row per listing per day) to a stable shape.
    Returns [] when the file is absent (W1 not landed) so the section is a clean no-op."""
    raw, fn = _read_csv(os.path.join(PM_DATA, "history.csv"))
    if not raw:
        return []
    col = {
        "date": _resolve(fn, "date", "date_ist", "day"),
        "platform": _resolve(fn, "platform", "plat"),
        "sku": _resolve(fn, "sku", "pm_sku", "master_sku", "sku_name"),
        "canonical": _resolve(fn, "canonical_sku", "canonical", "vault_sku"),
        "title": _resolve(fn, "title", "product_name", "name"),
        "regime": _resolve(fn, "regime"),
        "ref": _resolve(fn, "ref_price", "ref", "reference", "reference_price"),
        "live": _resolve(fn, "live_modal", "live", "live_price", "modal"),
        "live_min": _resolve(fn, "live_min", "min"),
        "live_max": _resolve(fn, "live_max", "max"),
        "diff": _resolve(fn, "diff", "delta"),
        "diff_pct": _resolve(fn, "diff_pct", "diff_percent", "pct"),
        "status": _resolve(fn, "status", "verdict"),
        "in_stock": _resolve(fn, "in_stock", "instock"),
        "stores_below": _resolve(fn, "stores_below", "stores_below_count", "store_violations"),
        "mrp": _resolve(fn, "mrp_official", "mrp"),
    }
    out = []
    for r in raw:
        def g(key):
            c = col[key]
            v = r.get(c) if c else ""
            return v.strip() if isinstance(v, str) else (v or "")
        date, sku = g("date"), g("sku")
        if not date or not sku:
            continue
        out.append({
            "date": date, "platform": g("platform"), "sku": sku, "canonical": g("canonical"),
            "title": g("title"), "regime": g("regime"), "ref": g("ref"), "live": g("live"),
            "live_min": g("live_min"), "live_max": g("live_max"), "diff": g("diff"),
            "diff_pct": g("diff_pct"), "status": (g("status") or "").upper(),
            "in_stock": g("in_stock"), "stores_below": g("stores_below"), "mrp": g("mrp"),
        })
    return out


def load_daily():
    """Normalize data/pricematch/daily.csv (1 row per day) -> list of dicts keyed by `date`."""
    raw, fn = _read_csv(os.path.join(PM_DATA, "daily.csv"))
    if not raw:
        return []
    col = {
        "date": _resolve(fn, "date", "date_ist", "day"),
        "regime": _resolve(fn, "regime"),
        "skus_tracked": _resolve(fn, "skus_tracked", "skus", "listed_skus"),
        "platforms": _resolve(fn, "platforms", "platforms_count"),
        "match": _resolve(fn, "match", "compliant"),
        "below": _resolve(fn, "below"),
        "above": _resolve(fn, "above"),
        "oos": _resolve(fn, "oos"),
        "pending": _resolve(fn, "pending"),
        "not_listed": _resolve(fn, "not_listed", "notlisted"),
        "exposure": _resolve(fn, "exposure"),
        "listings": _resolve(fn, "listings"),
        "store_violations": _resolve(fn, "store_violations", "violations", "store_below"),
        "top_offender_sku": _resolve(fn, "top_offender_sku"),
        "top_offender_platform": _resolve(fn, "top_offender_platform"),
        "top_offender_diff": _resolve(fn, "top_offender_diff"),
    }
    out = []
    for r in raw:
        d = {k: ((r.get(c) or "").strip() if c and isinstance(r.get(c), str) else (r.get(c) if c else ""))
             for k, c in col.items()}
        if d.get("date"):
            out.append(d)
    return {d["date"]: d for d in out}


# ----------------------------------------------------------------------------- link resolution
def existing_sku_hubs():
    """Lowercased set of real SKU-hub basenames in vault/skus/ — so a canonical cross-link is
    only emitted when it actually resolves (the task's hard rule)."""
    d = os.path.join(VAULT, "skus")
    if not os.path.isdir(d):
        return set()
    return {fn[:-3].lower() for fn in os.listdir(d) if fn.endswith(".md")}


def sku_hub_link(canonical, hubs):
    """A [[real-sku-hub]] link if the row's canonical resolves to one, else ''."""
    if not canonical:
        return ""
    base = safe_name(canonical)
    return link(base) if base.lower() in hubs else ""


def pm_sku_base(sku):
    return safe_name("pm-" + sku)


def daily_base(date):
    return "pricematch-" + safe_name(date)


# ----------------------------------------------------------------------------- aggregation
def _diff_val(r):
    v = fnum(r["diff"])
    if v is not None:
        return v
    ref, live = fnum(r["ref"]), fnum(r["live"])
    return (live - ref) if (ref is not None and live is not None) else None


def _kpis_for_day(date, rows, daily):
    """Prefer W1's daily.csv KPIs; fall back to counting the history rows for that day."""
    d = daily.get(date)
    if d and any(d.get(k) not in (None, "") for k in ("below", "exposure")):
        return d
    c = {"below": 0, "above": 0, "match": 0, "oos": 0, "pending": 0, "not_listed": 0,
         "exposure": 0.0, "store_violations": 0, "listings": len(rows)}
    skus = set()
    for r in rows:
        skus.add(r["sku"])
        st = r["status"]
        if st == "BELOW":
            c["below"] += 1
            dv = _diff_val(r)
            if dv is not None:
                c["exposure"] += abs(dv)
        elif st == "ABOVE":
            c["above"] += 1
        elif st == "MATCH":
            c["match"] += 1
        elif st == "OOS":
            c["oos"] += 1
        elif st == "PENDING_REVIEW":
            c["pending"] += 1
        elif st == "NOT_LISTED":
            c["not_listed"] += 1
        sb = fnum(r["stores_below"])
        if sb:
            c["store_violations"] += int(sb)
    c["exposure"] = round(c["exposure"])
    c["skus_tracked"] = len(skus)
    c["regime"] = next((r["regime"] for r in rows if r["regime"]), "")
    return c


def _ival(x):
    v = fnum(x)
    return str(int(round(v))) if v is not None else (str(x) if x not in (None, "") else "-")


# ----------------------------------------------------------------------------- builders
def build_daily_note(date, rows, daily, hubs, sku_bases):
    rows = sorted(rows, key=lambda r: (r["sku"], r["platform"]))
    k = _kpis_for_day(date, rows, daily)
    dmeta = daily.get(date, {})
    kpi_only = not rows  # backfilled day: daily.csv KPIs exist but no per-listing rows
    regime = k.get("regime") or dmeta.get("regime") or next((r["regime"] for r in rows if r["regime"]), "—")
    dbase = daily_base(date)

    fm = [("type", "pricematch-daily"), ("date", date), ("regime", regime),
          ("below", _ival(k.get("below"))), ("above", _ival(k.get("above"))),
          ("match", _ival(k.get("match"))), ("exposure", _ival(k.get("exposure"))),
          ("store_violations", _ival(k.get("store_violations"))),
          ("listings", _ival(k.get("listings"))),
          ("tags", ["type/pricematch-daily", f"regime/{regime}"])]

    nav = ("Up: " + link("Price-Match-MOC") + " · Day: " + link(date)
           + " · Home: " + link("index"))
    kpi = (f"**{regime}** · 🔴 below {_ival(k.get('below'))} · 🟢 above {_ival(k.get('above'))} "
           f"· ✅ match {_ival(k.get('match'))} · 💸 exposure ₹{_ival(k.get('exposure'))} "
           f"· 🏪 store-violations {_ival(k.get('store_violations'))}")

    body = [f"# Price match — {date}", "", nav, "",
            f"- **Regime:** {regime}",
            f"- **KPIs:** {kpi}",
            f"- **Coverage:** {_ival(k.get('skus_tracked'))} SKUs · {_ival(k.get('listings'))} listings"
            f" · {_ival(k.get('oos'))} OOS · {_ival(k.get('not_listed'))} not listed", ""]

    def _sku_cell(sku, canon):
        # link the master pm note when it exists; append the real canonical SKU hub if it resolves
        cell = link(pm_sku_base(sku), sku) if sku in sku_bases else sku
        sl = sku_hub_link(canon, hubs)
        return cell + (f" · {sl}" if sl else "")

    if kpi_only:
        # backfilled KPI-only day: single top offender from daily.csv, no per-listing detail
        body.append("## Top offender (KPI-only backfill day)")
        tsku = dmeta.get("top_offender_sku")
        if tsku:
            body += ["", "| SKU | Platform | Diff ₹ |", "|---|---|--:|",
                     f"| {_sku_cell(tsku, '')} | {link(dmeta.get('top_offender_platform') or '-')} | "
                     f"{money(dmeta.get('top_offender_diff'))} |"]
        else:
            body.append("_no offender recorded_")
        body += ["", "_Per-listing detail not retained for this backfilled day; KPIs above are from "
                 "`data/pricematch/daily.csv`. Full per-SKU rows exist for days the engine ran live._"]
    else:
        # top offenders: BELOW rows, most-negative diff first
        offenders = sorted(
            (r for r in rows if r["status"] == "BELOW" and _diff_val(r) is not None),
            key=lambda r: (_diff_val(r), r["sku"], r["platform"]))[:TOP_OFFENDERS]
        body.append(f"## Top offenders below reference ({len(offenders)})")
        if offenders:
            body += ["", "| SKU | Platform | Ref ₹ | Live ₹ | Diff ₹ |", "|---|---|--:|--:|--:|"]
            for r in offenders:
                body.append(f"| {_sku_cell(r['sku'], r['canonical'])} | {link(r['platform'])} | "
                            f"{money(r['ref'])} | {money(r['live'])} | {money(_diff_val(r))} |")
        else:
            body.append("_no listings below reference today_")
        # complete record (cheap csv block)
        body += ["", f"## Complete record ({len(rows)} listings)", "",
                 csv_block(rows, ["sku", "platform", "status", "regime", "ref", "live",
                                  "live_min", "live_max", "diff", "diff_pct", "stores_below",
                                  "in_stock"])]
    body += ["", footer("Do not hand-edit.")]
    write_file(os.path.join(PM_VAULT, dbase + ".md"), frontmatter(fm) + "\n\n" + "\n".join(body))
    return dbase


def build_sku_note(sku, srows, hubs):
    srows = sorted(srows, key=lambda r: (r["date"], r["platform"]))
    platforms = sorted({r["platform"] for r in srows if r["platform"]})
    dates = sorted({r["date"] for r in srows})
    latest = srows[-1]
    below_days = sorted({r["date"] for r in srows if r["status"] == "BELOW"})
    canon = next((r["canonical"] for r in srows if r["canonical"]), "")
    hub = sku_hub_link(canon, hubs)
    title = next((r["title"] for r in srows if r["title"]), "")

    fm = [("type", "pricematch-sku"), ("sku", sku), ("platforms", platforms),
          ("first_seen", dates[0]), ("last_seen", dates[-1]),
          ("observations", len(srows)), ("latest_status", latest["status"]),
          ("below_days", len(below_days)),
          ("tags", ["type/pricematch-sku"] + [f"platform/{p}" for p in platforms])]
    if canon:
        fm.insert(2, ("canonical_sku", canon))

    body = [f"# Price match — {sku}", "", "Up: " + link("Price-Match-MOC")]
    if title:
        body += ["", f"*{title}*"]
    if hub:
        body += ["", f"SKU memory: {hub}"]
    body += ["", "## Sold on", link_row(platforms) if platforms else "_none_"]
    body += ["", f"- **Latest status:** {STATUS_LABEL.get(latest['status'], latest['status'])}"
             f" on {link(latest['platform'])} ({latest['date']})"
             f" — ref ₹{money(latest['ref'])} vs live ₹{money(latest['live'])}",
             f"- **Days below reference:** {len(below_days)} of {len(dates)}"]
    if below_days:
        body.append("- **Below on:** " + link_row(below_days))

    body += ["", f"## Ref-vs-live history ({len(srows)} observations)", "",
             csv_block(srows, ["date", "platform", "status", "regime", "ref", "live",
                               "live_min", "live_max", "diff", "diff_pct", "stores_below",
                               "in_stock"])]
    body += ["", footer()]
    base = pm_sku_base(sku)
    write_file(os.path.join(PM_VAULT, base + ".md"), frontmatter(fm) + "\n\n" + "\n".join(body))
    return base


def build_moc(history, daily, day_bases, sku_bases):
    dates = sorted(day_bases)  # every day with a note (KPI-only backfill + live history days)
    # recurring offenders: SKUs ranked by #days-below then total exposure
    agg = {}
    for r in history:
        a = agg.setdefault(r["sku"], {"days": set(), "exposure": 0.0, "platforms": set()})
        if r["status"] == "BELOW":
            a["days"].add(r["date"])
            dv = _diff_val(r)
            if dv is not None:
                a["exposure"] += abs(dv)
            if r["platform"]:
                a["platforms"].add(r["platform"])
    worst = sorted(((s, a) for s, a in agg.items() if a["days"]),
                   key=lambda kv: (-len(kv[1]["days"]), -kv[1]["exposure"], kv[0]))[:WORST_RECURRING]

    fm = [("type", "moc"), ("title", "Price Match"), ("days", len(dates)),
          ("skus_tracked", len(sku_bases)),
          ("tags", ["moc", "type/pricematch-moc"])]
    body = [f"# Price Match — Map of Content ({len(dates)} days)", "",
            "Up: " + link("index"), "",
            "Compliance history — reference (regime) price vs live across platforms. "
            "Each day links its top offenders; each SKU links its full ref-vs-live timeline.",
            "", "## Daily notes — newest first"]
    body += ["\n".join(f"- {link(day_bases[d])} — {d}" for d in sorted(dates, reverse=True))
             or "_none_"]

    # exposure trend straight from daily.csv (or computed fallback)
    trend = []
    for d in dates:
        k = _kpis_for_day(d, [r for r in history if r["date"] == d], daily)
        trend.append({"date": d, "regime": k.get("regime", ""), "below": _ival(k.get("below")),
                      "above": _ival(k.get("above")), "match": _ival(k.get("match")),
                      "exposure": _ival(k.get("exposure")),
                      "store_violations": _ival(k.get("store_violations")),
                      "listings": _ival(k.get("listings"))})
    body += ["", "## Exposure trend", "",
             csv_block(trend, ["date", "regime", "below", "above", "match", "exposure",
                               "store_violations", "listings"])]

    body += ["", f"## Worst recurring offenders ({len(worst)})"]
    if worst:
        body += ["", "| SKU | Days below | Exposure ₹ | Platforms |", "|---|--:|--:|---|"]
        for s, a in worst:
            body.append(f"| {link(sku_bases[s], s)} | {len(a['days'])} | "
                        f"{money(round(a['exposure']))} | {link_row(sorted(a['platforms']))} |")
    else:
        body.append("_none_")
    body += ["", footer()]
    write_file(os.path.join(PM_VAULT, "Price-Match-MOC.md"),
               frontmatter(fm) + "\n\n" + "\n".join(body))
    return "Price-Match-MOC"


# ----------------------------------------------------------------------------- orchestration
def build_section():
    """Build the whole PM section. Returns count of notes written (0 = no PM data yet)."""
    history = load_history()
    if not history:
        return 0
    daily = load_daily()
    hubs = existing_sku_hubs()

    by_date, by_sku = {}, {}
    for r in history:
        by_date.setdefault(r["date"], []).append(r)
        by_sku.setdefault(r["sku"], []).append(r)

    sku_bases = {s: build_sku_note(s, rows, hubs) for s, rows in sorted(by_sku.items())}
    # a daily note for EVERY date with KPIs (daily.csv) or per-listing rows (history.csv);
    # backfilled days are KPI-only.
    all_dates = sorted(set(by_date) | set(daily))
    day_bases = {d: build_daily_note(d, by_date.get(d, []), daily, hubs, sku_bases)
                 for d in all_dates}
    build_moc(history, daily, day_bases, sku_bases)
    n = len(sku_bases) + len(day_bases) + 1
    return n


def main(argv):
    n = build_section()
    if n == 0:
        print("vault_pricematch: no data/pricematch/history.csv yet — nothing to do (no-op)")
        return 0
    print(f"vault_pricematch: {n} PM notes written to vault/pricematch/")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
