#!/usr/bin/env python3
"""
vault_build.py - Full-vault deterministic rebuilder for the ecom-intel Obsidian memory graph.

Reads the COMPLETE price history (data/<platform>/history.csv - the single source of
truth, append-only across every cron run) and regenerates the entire Obsidian vault as a
densely-linked knowledge graph:

  - run notes        vault/runs/<p>/<p>-<RUN_ID>.md   (COMPLETE: every observation as a ```csv block)
  - SKU hubs         vault/skus/<slug>.md             (per-SKU memory + full price history)
  - city hubs        vault/locations/<City>.md
  - pincode nodes    vault/locations/pincodes/<pin>.md
  - SKU MOC          vault/skus/skus-index.md
  - locations MOC    vault/locations/locations-index.md
  - platform hubs    vault/platforms/<p>.md           (editorial prose preserved; managed blocks rebuilt)
  - rollups          vault/daily|weekly|monthly/       (uncapped)
  - home MOC         vault/index.md                   (dynamic time-spine)
  - graph config     vault/.obsidian/graph.json       (color groups by note-type + platform)

DESIGN RULES (verified against Obsidian docs - see VAULT-SPEC.md):
  * Links target REAL BASENAMES, never aliases:  [[blinkit]] not [[blinkit (platform hub)]].
    A bare [[alias]] does NOT resolve in Obsidian; only [[realname|alias]] does. The previous
    vault relied on aliases and its graph silently failed to connect.
  * Every graph edge is a BODY [[wikilink]] (frontmatter property links do NOT create edges).
  * Basenames are GLOBALLY UNIQUE (wikilinks resolve by basename, case-insensitive); the build
    asserts uniqueness and aborts on any collision.
  * COMPLETE data lives in fenced ```csv blocks (render cheaply at any size). Rendered Markdown
    tables are kept small - Obsidian's table renderer freezes on hundreds of rows.
  * Numeric tags are prefixed (#pin/110001 - bare numeric tags are invalid). YAML is spaces-only,
    UTF-8 (no BOM), and carries no wikilinks.

Deterministic, Python-3 stdlib only, no network, no LLM. Idempotent: identical CSVs -> identical vault.

Usage:  python3 tools/vault_build.py            # rebuild whole vault from data/*/history.csv
        python3 tools/vault_build.py --check    # build + assert uniqueness/link integrity, exit nonzero on fail
"""
import csv
import io
import json
import os
import sys
from collections import defaultdict
from datetime import date

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
VAULT = os.path.join(ROOT, "vault")
PLATFORMS_SRC = os.path.join(ROOT, "platforms")
REVIEWS = os.path.join(ROOT, "reviews")
OBSIDIAN = os.path.join(VAULT, ".obsidian")

CSV_COLUMNS = ["run_id", "date_ist", "platform", "canonical_sku", "city",
               "pincode", "price", "mrp", "discount_pct", "in_stock"]
FORBIDDEN = set('[]#^|/\\:')          # unsafe in Obsidian basenames AND inside [[wikilinks]]
NATIONAL_CITY = {"All India", "-", ""}
NATIONAL_PIN = {"-", ""}
GEN = "tools/vault_build.py"
SPEC = "[[VAULT-SPEC]]"

# Per-platform editorial blurb for the platform hub (prose preserved across rebuilds via markers).
PLATFORM_INFO = {
    "blinkit":          ("quick-commerce", "per-pincode", "low",
                         "Blinkit 10-20 min delivery; pricing is per-pincode (top-cities sweep)."),
    "":        ("quick-commerce", "per-pincode", "low",
                         "  quick-commerce; per-pincode pricing across top cities."),
    "flipkart-minutes": ("quick-commerce", "per-pincode", "low",
                         "Flipkart Minutes hyperlocal quick-commerce; per-pincode pricing."),
    "flipkart":         ("marketplace", "national", "low",
                         "Flipkart marketplace; national catalog (single All-India price)."),
    "amazon":           ("marketplace", "national", "low",
                         "Amazon marketplace; richest national catalog (single All-India price)."),
}


# ----------------------------------------------------------------------------- formatting helpers
def fnum(x):
    if x is None or x == "":
        return None
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def money(x):
    v = fnum(x)
    if v is None:
        return "-"
    if abs(v - round(v)) < 1e-9:
        return str(int(round(v)))
    return f"{v:.2f}".rstrip("0").rstrip(".")


def pct(x):
    v = fnum(x)
    if v is None:
        return "-"
    return f"{v:.1f}%"


def yv(v):
    """Quote a scalar for safe flat YAML."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    s = str(v)
    if s == "":
        return '""'
    if (any(c in s for c in ':#|[]{}",\'') or s[0] in '-?&*!%@`>' or
            s.lower() in ("null", "true", "false", "yes", "no")):
        return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'
    return s


def frontmatter(pairs):
    """pairs: list of (key, value); value scalar or list."""
    out = ["---"]
    for k, v in pairs:
        if isinstance(v, list):
            out.append(f"{k}:")
            for it in v:
                out.append(f"  - {yv(it)}")
        else:
            out.append(f"{k}: {yv(v)}")
    out.append("---")
    return "\n".join(out)


def safe_name(s):
    """Make a string safe + non-empty as a globally-resolvable note basename.
    Keeps spaces and case (city names); replaces only Obsidian-forbidden chars."""
    s = (s or "").strip()
    cleaned = []
    for ch in s:
        cleaned.append("-" if (ch in FORBIDDEN or ord(ch) < 32) else ch)
    s = "".join(cleaned).strip(" .")
    while "--" in s:
        s = s.replace("--", "-")
    return s or "untitled"


def link(basename, display=None):
    b = str(basename)
    return f"[[{b}|{display}]]" if display and display != b else f"[[{b}]]"


def link_row(basenames, sep=" · "):
    return sep.join(link(b) for b in basenames)


def csv_block(rows, cols):
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    w.writerow(cols)
    for r in rows:
        w.writerow([r.get(c, "") for c in cols])
    return "```csv\n" + buf.getvalue().rstrip("\n") + "\n```"


def footer(extra=""):
    tail = f" {extra}" if extra else ""
    return f"---\n*Auto-generated by `{GEN}` from `data/*/history.csv` - see {SPEC}.{tail}*"


def write_file(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if not text.endswith("\n"):
        text += "\n"
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def iso_week(d):
    y, w, _ = d.isocalendar()
    return f"{y}-W{w:02d}"


def month_id(d):
    return d.strftime("%Y-%m")


def parse_date(s):
    return date.fromisoformat(s)


def run_time(run_id):
    """RUN_ID YYYY-MM-DD-HHMM -> 'HH:MM' (best-effort)."""
    tail = run_id.rsplit("-", 1)[-1]
    if len(tail) == 4 and tail.isdigit():
        return f"{tail[:2]}:{tail[2:]}"
    return ""


# ----------------------------------------------------------------------------- data loading
def load_rows():
    rows = []
    if not os.path.isdir(DATA):
        return rows
    for p in sorted(os.listdir(DATA)):
        fp = os.path.join(DATA, p, "history.csv")
        if not os.path.isfile(fp):
            continue
        with open(fp, encoding="utf-8", newline="") as fh:
            for r in csv.DictReader(fh):
                row = {}
                for k in CSV_COLUMNS:
                    v = r.get(k, "")
                    row[k] = v.strip() if isinstance(v, str) else (v or "")
                if not row["run_id"] or not row["platform"]:
                    continue
                rows.append(row)
    return rows


def load_verdicts():
    """{(platform, run_id): verdict} from reviews/<p>-<rid>.json (verdict field only - no leaked notes)."""
    out = {}
    if not os.path.isdir(REVIEWS):
        return out
    for fn in os.listdir(REVIEWS):
        if not fn.endswith(".json"):
            continue
        stem = fn[:-5]
        try:
            with open(os.path.join(REVIEWS, fn), encoding="utf-8") as fh:
                v = (json.load(fh) or {}).get("verdict")
        except Exception:
            continue
        if not v:
            continue
        # stem = <platform>-<YYYY-MM-DD-HHMM>; run_id is the trailing 4 dash-groups.
        parts = stem.split("-")
        if len(parts) >= 5:
            rid = "-".join(parts[-4:])
            plat = "-".join(parts[:-4])
            out[(plat, rid)] = v
    return out


def load_enrichment():
    """{(platform, canonical_sku): display_name} harvested from the latest result.json per platform."""
    out = {}
    if not os.path.isdir(PLATFORMS_SRC):
        return out
    for p in sorted(os.listdir(PLATFORMS_SRC)):
        fp = os.path.join(PLATFORMS_SRC, p, "result.json")
        if not os.path.isfile(fp):
            continue
        try:
            with open(fp, encoding="utf-8") as fh:
                data = json.load(fh)
        except Exception:
            continue
        rows = data.get("allRows") or []
        if not rows:
            for pin in data.get("perPin", []):
                rows.extend(pin.get("rows", []))
        for r in rows:
            canon = (r.get("canonical") or "").strip()
            if not canon:
                continue
            name = (r.get("product_name") or r.get("fk_name") or r.get("sku_raw") or "").strip()
            pack = (r.get("pack") or "").strip()
            if name and pack and pack.lower() not in name.lower():
                name = f"{name} ({pack})"
            if name and (p, canon) not in out:
                out[(p, canon)] = name
    return out


# ----------------------------------------------------------------------------- builders
def platform_shape(prows):
    return "national" if all(r["pincode"] in NATIONAL_PIN for r in prows) else "per-pincode"


def humanize_sku(canon):
    """Last-resort display name derived from the canonical slug, so a hub is NEVER nameless.
    'jivo-a2-ghee-500-ml-500ml' -> 'Jivo A2 Ghee 500 Ml 500ml'. Title-cases word-initial
    alphabetic tokens, leaves tokens that touch a digit (pack sizes, '1l', 'a2') untouched."""
    words = [w for w in str(canon or "").replace("_", " ").replace("-", " ").split() if w]
    out = []
    for w in words:
        out.append(w if (w[0].isdigit() or w[-1].isdigit()) else w[:1].upper() + w[1:])
    return " ".join(out) or str(canon or "untitled")


def sku_display(enrich, platform, canon):
    """Best available human name; falls back to the slug so it is never blank."""
    return (enrich.get((platform, canon)) or enrich.get(("", canon))
            or humanize_sku(canon))


def build_run_note(platform, run_id, rrows, verdict, prev_rid, next_rid, enrich):
    rrows = sorted(rrows, key=lambda r: (r["canonical_sku"], r["city"], r["pincode"]))
    d = rrows[0]["date_ist"]
    dt = parse_date(d)
    shape = "national" if all(r["pincode"] in NATIONAL_PIN for r in rrows) else "per-pincode"
    skus = sorted({r["canonical_sku"] for r in rrows if r["canonical_sku"]})
    cities = sorted({r["city"] for r in rrows if r["city"] not in NATIONAL_CITY})
    pins = sorted({r["pincode"] for r in rrows if r["pincode"] not in NATIONAL_PIN})
    n_instock = sum(1 for r in rrows if r["in_stock"] == "1")

    fm = [("type", "run"), ("platform", platform), ("run_id", run_id), ("date", d),
          ("time_ist", run_time(run_id)), ("verdict", verdict), ("shape", shape),
          ("rows", len(rrows)), ("unique_skus", len(skus)), ("in_stock_rows", n_instock)]
    if shape == "per-pincode":
        fm.append(("pincodes_with_jivo", len(pins)))
    tags = ["type/run", f"platform/{platform}", f"verdict/{verdict}", f"shape/{shape}"]
    fm.append(("tags", tags))

    nav = [link(f"{platform}"), link(d), link(iso_week(dt)), link(month_id(dt))]
    navline = "Up: " + link(platform) + " · Day: " + link(d) + \
              " · Week: " + link(iso_week(dt)) + " · Month: " + link(month_id(dt))
    if prev_rid:
        navline += " · Prev: " + link(f"{platform}-{prev_rid}")
    if next_rid:
        navline += " · Next: " + link(f"{platform}-{next_rid}")

    # headline picks
    instock_priced = [r for r in rrows if r["in_stock"] == "1" and fnum(r["price"]) is not None]
    body = [f"# {platform} — run {run_id}", "", navline, "",
            f"- **Verdict:** {verdict}",
            f"- **Captured:** {d} {run_time(run_id)} IST"]
    if shape == "per-pincode":
        body.append(f"- **Coverage:** {len(pins)} pincodes carry Jivo · {len(rrows)} rows · {len(skus)} unique SKUs")
    else:
        body.append(f"- **Pricing:** national (All India) · {len(skus)} SKUs in catalog")
    if instock_priced:
        ch = min(instock_priced, key=lambda r: fnum(r["price"]))
        loc = "" if ch["city"] in NATIONAL_CITY else f" ({ch['city']})"
        body.append(f"- **Cheapest (in-stock):** {link(ch['canonical_sku'])} — ₹{money(ch['price'])}{loc}")
    disc = [r for r in rrows if (fnum(r["discount_pct"]) or 0) > 0]
    if disc:
        td = max(disc, key=lambda r: fnum(r["discount_pct"]))
        loc = "" if td["city"] in NATIONAL_CITY else f" ({td['city']})"
        body.append(f"- **Top discount:** {link(td['canonical_sku'])} — {pct(td['discount_pct'])} off{loc}")

    # SKU summary (one bullet per SKU -> SKU memory)
    body += ["", "## SKUs seen"]
    by_sku_here = defaultdict(list)
    for r in rrows:
        if r["canonical_sku"]:
            by_sku_here[r["canonical_sku"]].append(r)
    for s in skus:
        grp = by_sku_here[s]
        priced = [r for r in grp if fnum(r["price"]) is not None]
        rep = min((r for r in priced if r["in_stock"] == "1"), default=None,
                  key=lambda r: fnum(r["price"]))
        if rep is None:
            rep = min(priced, default=None, key=lambda r: fnum(r["price"]))
        disp = sku_display(enrich, platform, s)
        seen = f" · in {len({r['pincode'] for r in grp if r['pincode'] not in NATIONAL_PIN})} pincodes" if shape == "per-pincode" else ""
        if rep is not None:
            extra = f" — ₹{money(rep['price'])}"
            if (fnum(rep['discount_pct']) or 0) > 0:
                extra += f" ({pct(rep['discount_pct'])} off)"
        else:
            extra = " — (out of stock / unpriced)"
        name = f" — {disp}" if disp else ""
        body.append(f"- {link(s)}{name}{extra}{seen}")

    if cities:
        body += ["", "## Cities covered", link_row(cities)]

    body += ["", f"## Complete observations ({len(rrows)} rows)",
             "Every SKU × location captured this run (the full record; see `data/%s/history.csv`)." % platform,
             ""]
    cols = (["canonical_sku", "city", "pincode", "price", "mrp", "discount_pct", "in_stock"]
            if shape == "per-pincode" else
            ["canonical_sku", "price", "mrp", "discount_pct", "in_stock"])
    body.append(csv_block(rrows, cols))
    body += ["", footer("Do not hand-edit.")]

    text = frontmatter(fm) + "\n\n" + "\n".join(body)
    path = os.path.join(VAULT, "runs", platform, f"{platform}-{run_id}.md")
    write_file(path, text)
    return f"{platform}-{run_id}"


def build_sku_hub(canon, srows, enrich):
    srows = sorted(srows, key=lambda r: (r["run_id"], r["platform"], r["city"], r["pincode"]))
    platforms = sorted({r["platform"] for r in srows})
    cities = sorted({r["city"] for r in srows if r["city"] not in NATIONAL_CITY})
    runs = sorted({(r["platform"], r["run_id"]) for r in srows}, reverse=True)
    dates = sorted({r["date_ist"] for r in srows})
    priced = [r for r in srows if fnum(r["price"]) is not None]
    prices = [fnum(r["price"]) for r in priced]
    disp = ""
    for p in platforms:
        disp = sku_display(enrich, p, canon)
        if disp:
            break
    if not disp:
        disp = humanize_sku(canon)

    fm = [("type", "sku-hub"), ("canonical_sku", canon), ("display_name", disp)]
    fm += [("platforms", platforms), ("first_seen", dates[0]), ("last_seen", dates[-1]),
           ("observations", len(srows))]
    if prices:
        fm += [("min_price", money(min(prices))), ("max_price", money(max(prices))),
               ("latest_price", money(fnum(priced[-1]["price"])))]
    fm.append(("tags", ["type/sku-hub"] + [f"platform/{p}" for p in platforms]))

    body = [f"# {canon}", "", "Up: " + link("skus-index")]
    if disp:
        body += ["", f"**{disp}**"]
    body += ["", "## Sold on"]
    for p in platforms:
        prows = [r for r in priced if r["platform"] == p]
        last = prows[-1] if prows else None
        if last:
            body.append(f"- {link(p)} — latest ₹{money(last['price'])}"
                        + (f" ({pct(last['discount_pct'])} off)" if (fnum(last['discount_pct']) or 0) > 0 else ""))
        else:
            body.append(f"- {link(p)}")
    if cities:
        body += ["", "## Available in cities", link_row(cities)]
    body += ["", f"## Runs that observed this SKU ({len(runs)})",
             link_row([f"{p}-{rid}" for p, rid in runs])]
    body += ["", f"## Price history ({len(srows)} observations)", "",
             csv_block(srows, ["run_id", "date_ist", "platform", "city", "pincode",
                               "price", "mrp", "discount_pct", "in_stock"])]
    body += ["", footer()]
    write_file(os.path.join(VAULT, "skus", f"{safe_name(canon)}.md"),
               frontmatter(fm) + "\n\n" + "\n".join(body))
    return safe_name(canon)


def build_city_hub(city, crows, sku_basename):
    crows = sorted(crows, key=lambda r: (r["pincode"], r["canonical_sku"], r["run_id"]))
    platforms = sorted({r["platform"] for r in crows})
    pins = sorted({r["pincode"] for r in crows if r["pincode"] not in NATIONAL_PIN})
    skus = sorted({r["canonical_sku"] for r in crows if r["canonical_sku"]})
    fm = [("type", "city-hub"), ("city", city), ("platforms", platforms),
          ("pincodes", len(pins)), ("skus", len(skus)), ("observations", len(crows)),
          ("tags", ["type/city-hub"] + [f"platform/{p}" for p in platforms])]
    body = [f"# {city}", "", "Up: " + link("locations-index"),
            "", "## Platforms serving " + city, link_row(platforms),
            "", f"## Pincodes ({len(pins)})", link_row(pins) if pins else "_none_",
            "", f"## SKUs available in {city} ({len(skus)})",
            link_row([sku_basename[s] for s in skus]) if skus else "_none_",
            "", f"## Observations ({len(crows)} rows)", "",
            csv_block(crows, ["run_id", "date_ist", "platform", "canonical_sku", "pincode",
                              "price", "mrp", "discount_pct", "in_stock"]),
            "", footer()]
    write_file(os.path.join(VAULT, "locations", f"{safe_name(city)}.md"),
               frontmatter(fm) + "\n\n" + "\n".join(body))
    return safe_name(city)


def build_pincode_node(pin, prows, sku_basename, pin_city):
    prows = sorted(prows, key=lambda r: (r["canonical_sku"], r["run_id"]))
    platforms = sorted({r["platform"] for r in prows})
    skus = sorted({r["canonical_sku"] for r in prows if r["canonical_sku"]})
    city = pin_city.get(pin, "")
    fm = [("type", "pincode"), ("pincode", pin), ("city", city), ("platforms", platforms),
          ("skus", len(skus)), ("observations", len(prows)),
          ("tags", ["type/pincode", f"pin/{pin}"] + [f"platform/{p}" for p in platforms])]
    body = [f"# {pin}", ""]
    body.append("Up: " + link(safe_name(city)) if city else "Up: " + link("locations-index"))
    body += ["", "## Platforms", link_row(platforms),
             "", f"## SKUs seen here ({len(skus)})",
             link_row([sku_basename[s] for s in skus]) if skus else "_none_",
             "", f"## Observations ({len(prows)} rows)", "",
             csv_block(prows, ["run_id", "date_ist", "platform", "canonical_sku",
                               "price", "mrp", "discount_pct", "in_stock"]),
             "", footer()]
    write_file(os.path.join(VAULT, "locations", "pincodes", f"{safe_name(pin)}.md"),
               frontmatter(fm) + "\n\n" + "\n".join(body))
    return safe_name(pin)


def build_platform_hub(platform, prows, runs_desc, skus, sku_basename):
    """Fully regenerate the platform hub (consistent alias-free frontmatter). The Runs list is
    wrapped in <!-- runs:start/end --> markers so the live per-run vault_note.py upserts into it
    cleanly between full rebuilds."""
    kind, shape, risk, blurb = PLATFORM_INFO.get(
        platform, ("marketplace", platform_shape(prows), "low", f"{platform} scraper."))
    skus = sorted(skus)
    fm = [("type", "platform-hub"), ("platform", platform), ("kind", kind),
          ("shape", shape), ("risk", risk), ("runs", len(runs_desc)), ("skus_tracked", len(skus)),
          ("tags", ["type/platform-hub", "moc", f"platform/{platform}"])]
    run_lines = "\n".join(
        f"- {link(f'{platform}-{rid}')} — {d} · verdict {v} <!-- run -->"
        for rid, d, v in runs_desc) or "_no runs_"
    body = [f"# {platform} — platform hub", "", "Up: " + link("index"), "",
            f"Hub / Map of Content for **{platform}**. {blurb}", "",
            f"- **Type:** {kind} · **Shape:** {shape} · **Block risk:** {risk}",
            f"- **Runs captured:** {len(runs_desc)} · **SKUs tracked:** {len(skus)}",
            "", f"## SKUs on {platform} ({len(skus)})",
            link_row([sku_basename[s] for s in skus]) if skus else "_none_",
            "", f"## Runs ({len(runs_desc)}) — newest first", "",
            "<!-- runs:start -->", run_lines, "<!-- runs:end -->",
            "", footer()]
    write_file(os.path.join(VAULT, "platforms", f"{platform}.md"),
               frontmatter(fm) + "\n\n" + "\n".join(body))


def coverage_str(run_meta):
    return ("national" if run_meta["shape"] == "national"
            else f"{run_meta.get('pins', 0)} pins")


def run_table(metas):
    out = ["| Run | Platform | Verdict | Rows | SKUs | Coverage |",
           "|---|---|---|--:|--:|--:|"]
    for m in metas:
        out.append(f"| {link(m['base'])} | {m['platform']} | {m['verdict']} | "
                   f"{m['rows']} | {m['skus']} | {coverage_str(m)} |")
    return "\n".join(out)


def cheapest_block(rows):
    agg = defaultdict(lambda: {"min": None, "sum": 0.0, "n": 0, "platform": "", "sku": ""})
    for r in rows:
        v = fnum(r["price"])
        if v is None:
            continue
        k = (r["platform"], r["canonical_sku"])
        a = agg[k]
        a["platform"], a["sku"] = r["platform"], r["canonical_sku"]
        a["min"] = v if a["min"] is None else min(a["min"], v)
        a["sum"] += v
        a["n"] += 1
    items = sorted((a for a in agg.values() if a["n"]),
                   key=lambda a: (a["min"], a["platform"], a["sku"]))
    out = ["| Platform | SKU | Min ₹ | Avg ₹ | n |", "|---|---|--:|--:|--:|"]
    for a in items:
        out.append(f"| {a['platform']} | {link(safe_name(a['sku']))} | {money(a['min'])} | "
                   f"{money(round(a['sum'] / a['n'], 1))} | {a['n']} |")
    return "\n".join(out)


def build_daily(d, metas, rows):
    dt = parse_date(d)
    platforms = sorted({m["platform"] for m in metas})
    fm = [("type", "daily"), ("date", d), ("runs_count", len(metas)),
          ("platforms_count", len(platforms)), ("tags", ["type/daily"])]
    body = [f"# {d} — daily rollup", "",
            "Up: " + link("index") + " · Week: " + link(iso_week(dt)) + " · Month: " + link(month_id(dt)),
            "", f"{len(metas)} runs across {len(platforms)} platform(s): " + link_row(platforms),
            "", "## Runs", run_table(sorted(metas, key=lambda m: m["base"])),
            "", "## Cheapest observed today", cheapest_block(rows),
            "", footer()]
    write_file(os.path.join(VAULT, "daily", f"{d}.md"), frontmatter(fm) + "\n\n" + "\n".join(body))


def build_weekly(wk, days, metas, rows):
    platforms = sorted({m["platform"] for m in metas})
    months = sorted({month_id(parse_date(d)) for d in days})
    fm = [("type", "weekly"), ("week", wk), ("runs_count", len(metas)), ("tags", ["type/weekly"])]
    body = [f"# {wk} — weekly trend rollup", "",
            "Up: " + link("index") + " · Month: " + link_row(months),
            "", "## Days this week", "\n".join(f"- {link(d)}" for d in days) or "_none_",
            "", f"## Coverage — {len(metas)} runs, {len(platforms)} platform(s): " + link_row(platforms),
            "", run_table(sorted(metas, key=lambda m: m["base"])),
            "", "## Cheapest observed this week", cheapest_block(rows),
            "", footer()]
    write_file(os.path.join(VAULT, "weekly", f"{wk}.md"), frontmatter(fm) + "\n\n" + "\n".join(body))


def build_monthly(mo, weeks, days, metas, rows):
    platforms = sorted({m["platform"] for m in metas})
    fm = [("type", "monthly"), ("month", mo), ("runs_count", len(metas)), ("tags", ["type/monthly"])]
    body = [f"# {mo} — monthly trend rollup", "",
            "Up: " + link("index"),
            "", "## Weeks this month", "\n".join(f"- {link(w)}" for w in weeks) or "_none_",
            "", "## Days this month", "\n".join(f"- {link(d)}" for d in days) or "_none_",
            "", f"## Coverage — {len(metas)} runs, {len(platforms)} platform(s): " + link_row(platforms),
            "", "## Cheapest observed this month", cheapest_block(rows),
            "", footer()]
    write_file(os.path.join(VAULT, "monthly", f"{mo}.md"), frontmatter(fm) + "\n\n" + "\n".join(body))


def build_skus_index(by_platform_skus, sku_basename, enrich):
    total = sum(len(v) for v in by_platform_skus.values())
    fm = [("type", "moc"), ("title", "SKUs"), ("sku_count", len(sku_basename)),
          ("tags", ["moc", "type/sku-moc"])]
    body = [f"# SKUs — Map of Content ({len(sku_basename)} unique)", "",
            "Up: " + link("index"),
            "", "Every Jivo SKU tracked, grouped by platform. Each links to its per-SKU memory note."]
    for p in sorted(by_platform_skus):
        skus = sorted(by_platform_skus[p])
        body += ["", f"## {link(p)} ({len(skus)})"]
        for s in skus:
            disp = sku_display(enrich, p, s)
            body.append(f"- {link(sku_basename[s])}" + (f" — {disp}" if disp else ""))
    body += ["", footer()]
    write_file(os.path.join(VAULT, "skus", "skus-index.md"), frontmatter(fm) + "\n\n" + "\n".join(body))


def build_locations_index(cities, city_pins):
    fm = [("type", "moc"), ("title", "Locations"), ("city_count", len(cities)),
          ("tags", ["moc", "type/location-moc"])]
    body = [f"# Locations — Map of Content ({len(cities)} cities)", "",
            "Up: " + link("index"),
            "", "Cities and pincodes where Jivo is sold. Each city links to its pincodes."]
    for c in sorted(cities):
        pins = sorted(city_pins.get(c, []))
        body += ["", f"## {link(safe_name(c))} ({len(pins)} pincodes)",
                 link_row(pins) if pins else "_none_"]
    body += ["", footer()]
    write_file(os.path.join(VAULT, "locations", "locations-index.md"),
               frontmatter(fm) + "\n\n" + "\n".join(body))


def build_index(platforms, latest_day, latest_week, latest_month, n_skus, n_cities, n_pins, n_runs):
    fm = [("type", "home-moc"), ("title", "Jivo Price Intelligence — Index"),
          ("tags", ["moc", "home"])]
    body = [
        "# Jivo Price Intelligence — Memory Vault", "",
        "**Home MOC** — entry point to the whole vault. Every cron run leaves a complete, linked "
        "note here; the notes form an Obsidian knowledge graph backed by `data/<platform>/history.csv`.",
        "", f"New here? Read {SPEC} for the design + Obsidian conventions.",
        "", "## Platform hubs", ]
    for p in platforms:
        kind, shape, _, _ = PLATFORM_INFO.get(p, ("marketplace", "national", "low", ""))
        body.append(f"- {link(p)} — {kind} · {shape}")
    body += ["", "## Maps of Content",
             f"- {link('skus-index')} — {n_skus} SKUs",
             f"- {link('locations-index')} — {n_cities} cities · {n_pins} pincodes",
             "", "## Time spine (latest)",
             f"- Today: {link(latest_day)}",
             f"- This week: {link(latest_week)}",
             f"- This month: {link(latest_month)}",
             "", f"_{n_runs} runs · {n_skus} SKU hubs · {n_cities} city + {n_pins} pincode nodes._",
             "", footer()]
    write_file(os.path.join(VAULT, "index.md"), frontmatter(fm) + "\n\n" + "\n".join(body))


def write_obsidian():
    groups = [
        ("tag:#type/run", 0x4C8DFF), ("tag:#type/sku-hub", 0xFFB020),
        ("tag:#type/city-hub", 0x35C28B), ("tag:#type/pincode", 0x9AE6B4),
        ("tag:#type/platform-hub", 0xFF5C7A), ("tag:#type/daily", 0xB794F4),
        ("tag:#type/weekly", 0x9F7AEA), ("tag:#type/monthly", 0x805AD5),
        ("tag:#moc", 0xF6E05E), ("tag:#home", 0xF6AD55),
    ]
    graph = {
        "collapse-filter": True, "search": "", "showTags": True, "showAttachments": False,
        "hideUnresolved": False, "showOrphans": True, "collapse-color-groups": False,
        "colorGroups": [{"query": q, "color": {"a": 1, "rgb": rgb}} for q, rgb in groups],
        "collapse-display": False, "showArrow": False, "textFadeMultiplier": 0,
        "nodeSizeMultiplier": 1.1, "lineSizeMultiplier": 1, "collapse-forces": False,
        "centerStrength": 0.5, "repelStrength": 12, "linkStrength": 1,
        "linkDistance": 130, "scale": 1, "close": True,
    }
    write_file(os.path.join(OBSIDIAN, "graph.json"), json.dumps(graph, indent=2))
    app = {"alwaysUpdateLinks": True, "newLinkFormat": "shortest",
           "useMarkdownLinks": False, "attachmentFolderPath": "attachments"}
    write_file(os.path.join(OBSIDIAN, "app.json"), json.dumps(app, indent=2))


# ----------------------------------------------------------------------------- orchestration
def build():
    rows = load_rows()
    if not rows:
        print("vault_build: no rows in data/*/history.csv — nothing to do", file=sys.stderr)
        return 0
    verdicts = load_verdicts()
    enrich = load_enrichment()

    by_run, by_sku, by_city, by_pin = defaultdict(list), defaultdict(list), defaultdict(list), defaultdict(list)
    by_platform = defaultdict(list)
    runs_by_platform = defaultdict(set)
    by_date = defaultdict(list)
    pin_city, city_pins = {}, defaultdict(set)
    platform_skus = defaultdict(set)

    for r in rows:
        p, rid = r["platform"], r["run_id"]
        by_run[(p, rid)].append(r)
        by_platform[p].append(r)
        runs_by_platform[p].add(rid)
        by_date[r["date_ist"]].append(r)
        if r["canonical_sku"]:
            by_sku[r["canonical_sku"]].append(r)
            platform_skus[p].add(r["canonical_sku"])
        c, pin = r["city"], r["pincode"]
        if c not in NATIONAL_CITY:
            by_city[c].append(r)
        if pin not in NATIONAL_PIN:
            by_pin[pin].append(r)
            if c not in NATIONAL_CITY:
                pin_city[pin] = c
                city_pins[c].add(pin)

    platforms = sorted(by_platform)
    sku_basename = {s: safe_name(s) for s in by_sku}

    # ----- run notes (+ per-run metadata for rollups)
    run_meta = {}
    for p in platforms:
        rids = sorted(runs_by_platform[p])
        for i, rid in enumerate(rids):
            rrows = by_run[(p, rid)]
            prev_rid = rids[i - 1] if i > 0 else None
            next_rid = rids[i + 1] if i + 1 < len(rids) else None
            verdict = verdicts.get((p, rid), "UNREVIEWED")
            base = build_run_note(p, rid, rrows, verdict, prev_rid, next_rid, enrich)
            shape = "national" if all(x["pincode"] in NATIONAL_PIN for x in rrows) else "per-pincode"
            run_meta[(p, rid)] = {
                "base": base, "platform": p, "verdict": verdict, "shape": shape,
                "rows": len(rrows), "skus": len({x["canonical_sku"] for x in rrows if x["canonical_sku"]}),
                "pins": len({x["pincode"] for x in rrows if x["pincode"] not in NATIONAL_PIN}),
                "date": rrows[0]["date_ist"],
            }

    # ----- entity hubs
    for s, srows in by_sku.items():
        build_sku_hub(s, srows, enrich)
    for c, crows in by_city.items():
        build_city_hub(c, crows, sku_basename)
    for pin, prows in by_pin.items():
        build_pincode_node(pin, prows, sku_basename, pin_city)

    # ----- platform hubs
    for p in platforms:
        rids = sorted(runs_by_platform[p], reverse=True)
        runs_desc = [(rid, by_run[(p, rid)][0]["date_ist"], verdicts.get((p, rid), "UNREVIEWED"))
                     for rid in rids]
        build_platform_hub(p, by_platform[p], runs_desc, platform_skus[p], sku_basename)

    # ----- MOCs
    build_skus_index(platform_skus, sku_basename, enrich)
    build_locations_index(set(by_city), city_pins)

    # ----- rollups
    all_dates = sorted(by_date)
    metas_by_date = defaultdict(list)
    for (p, rid), m in run_meta.items():
        metas_by_date[m["date"]].append(m)
    for d in all_dates:
        build_daily(d, metas_by_date[d], by_date[d])

    weeks = defaultdict(list)
    for d in all_dates:
        weeks[iso_week(parse_date(d))].append(d)
    for wk, days in weeks.items():
        wm = [m for d in days for m in metas_by_date[d]]
        wr = [r for d in days for r in by_date[d]]
        build_weekly(wk, sorted(days), wm, wr)

    months = defaultdict(list)
    for d in all_dates:
        months[month_id(parse_date(d))].append(d)
    for mo, days in months.items():
        mm = [m for d in days for m in metas_by_date[d]]
        mr = [r for d in days for r in by_date[d]]
        mweeks = sorted({iso_week(parse_date(d)) for d in days})
        build_monthly(mo, mweeks, sorted(days), mm, mr)

    # ----- index + obsidian config
    latest = all_dates[-1]
    build_index(platforms, latest, iso_week(parse_date(latest)), month_id(parse_date(latest)),
                len(by_sku), len(by_city), len(by_pin), len(run_meta))
    write_obsidian()

    print(f"vault_build: {len(run_meta)} run notes · {len(by_sku)} SKU hubs · "
          f"{len(by_city)} city + {len(by_pin)} pincode nodes · "
          f"{len(weeks)} weeks · {len(months)} months")
    return 0


def check_unique():
    """Assert every .md basename in the vault is globally unique (Obsidian resolves by basename)."""
    seen = defaultdict(list)
    for dp, _, fns in os.walk(VAULT):
        if ".obsidian" in dp:
            continue
        for fn in fns:
            if fn.endswith(".md"):
                seen[fn.lower()].append(os.path.relpath(os.path.join(dp, fn), VAULT))
    dups = {k: v for k, v in seen.items() if len(v) > 1}
    if dups:
        print("vault_build: BASENAME COLLISIONS (links would mis-resolve):", file=sys.stderr)
        for k, v in sorted(dups.items()):
            print(f"  {k}: {v}", file=sys.stderr)
        return False
    print(f"vault_build: OK — {len(seen)} unique note basenames")
    return True


def main(argv):
    rc = build()
    if rc:
        return rc
    if not check_unique():
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
