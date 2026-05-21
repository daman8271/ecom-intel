#!/usr/bin/env python3
"""vault_rollup.py <daily|weekly|monthly> [date]

(Re)generates the time-rollup notes (daily / weekly / monthly) from the run
notes already in vault/runs/** and the machine-readable data/<platform>/history.csv.

  daily   [YYYY-MM-DD]   default = today (IST)
  weekly  [YYYY-Www]     default = current ISO week (IST)   (also accepts a YYYY-MM-DD)
  monthly [YYYY-MM]      default = current month (IST)       (also accepts a YYYY-MM-DD)

Idempotent: re-running fully overwrites the target note. The daily note's
auto-managed run-link block (maintained by vault_note.py) is preserved/rebuilt
from the run notes so the graph edges survive a rollup regeneration.

Pure Python 3 stdlib. No LLM. Deterministic. See vault/VAULT-SPEC.md.
"""

import sys
import os
import csv
import glob
import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
VAULT = os.path.join(ROOT, "vault")
DATA = os.path.join(ROOT, "data")
IST = datetime.timezone(datetime.timedelta(hours=5, minutes=30))


# ---------------------------------------------------------------- date helpers
def today_ist():
    return datetime.datetime.now(IST).strftime("%Y-%m-%d")


def iso_week(date_str):
    y, m, d = (int(x) for x in date_str.split("-"))
    g, w, _ = datetime.date(y, m, d).isocalendar()
    return "%04d-W%02d" % (g, w)


def month_id(date_str):
    return date_str[:7]


def week_dates(week_id):
    """'YYYY-Www' -> sorted list of the 7 ISO dates in that week."""
    g, w = week_id.split("-W")
    out = []
    for dow in range(1, 8):
        d = datetime.date.fromisocalendar(int(g), int(w), dow)
        out.append(d.strftime("%Y-%m-%d"))
    return out


# ---------------------------------------------------------------- run-note parsing
def parse_frontmatter(path):
    """Tiny flat-YAML reader: returns dict of scalar keys from the top --- block."""
    fm = {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return fm
    if not text.startswith("---"):
        return fm
    end = text.find("\n---", 3)
    if end < 0:
        return fm
    block = text[3:end].strip("\n").split("\n")
    cur_list = None
    for ln in block:
        if not ln.strip():
            continue
        if ln.startswith("  - ") and cur_list is not None:
            fm.setdefault(cur_list, []).append(ln[4:].strip())
            continue
        if ":" in ln:
            k, _, v = ln.partition(":")
            k = k.strip()
            v = v.strip()
            if v == "":
                cur_list = k
                fm[k] = []
            else:
                cur_list = None
                fm[k] = v
    return fm


def all_run_notes():
    """Return list of frontmatter dicts (with _basename) for every run note."""
    out = []
    for path in glob.glob(os.path.join(VAULT, "runs", "*", "*.md")):
        fm = parse_frontmatter(path)
        if fm.get("run_id"):
            fm["_basename"] = os.path.basename(path)[:-3]
            out.append(fm)
    return out


def runs_for_dates(dates):
    """All run-note frontmatters whose date is in `dates` (set/list)."""
    dset = set(dates)
    return [fm for fm in all_run_notes() if fm.get("date") in dset]


# ---------------------------------------------------------------- history.csv
def load_history():
    rows = []
    for path in glob.glob(os.path.join(DATA, "*", "history.csv")):
        with open(path, "r", encoding="utf-8", newline="") as f:
            for row in csv.DictReader(f):
                rows.append(row)
    return rows


def fnum(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def price_stats_for_dates(dates):
    """Per (platform, canonical) min/avg sale price over the given dates."""
    dset = set(dates)
    agg = {}
    for r in load_history():
        if r.get("date_ist") not in dset:
            continue
        p = fnum(r.get("price"))
        if p is None:
            continue
        key = (r.get("platform"), r.get("canonical_sku"))
        a = agg.setdefault(key, {"min": p, "sum": 0.0, "n": 0})
        a["min"] = min(a["min"], p)
        a["sum"] += p
        a["n"] += 1
    return agg


# ---------------------------------------------------------------- writers
def write_atomic(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def fmt_int(v, default="?"):
    try:
        return str(int(float(v)))
    except (TypeError, ValueError):
        return default


def run_table(runs):
    """Markdown table + body links for a set of run-note frontmatters."""
    lines = []
    lines.append("| Run | Platform | Verdict | Rows | Unique SKUs | Coverage |")
    lines.append("|---|---|---|--:|--:|--:|")
    for fm in sorted(runs, key=lambda x: x["_basename"]):
        cov = "national" if fm.get("shape") == "national" else (
            "%s/%s" % (fm.get("pincodes_with_jivo", "?"), fm.get("pincodes_total", "?")))
        lines.append("| [[%s]] | %s | %s | %s | %s | %s |" % (
            fm["_basename"], fm.get("platform", "?"), fm.get("verdict", "?"),
            fmt_int(fm.get("rows")), fmt_int(fm.get("unique_skus")), cov))
    return "\n".join(lines)


def cheapest_block(agg, limit=10):
    """Cheapest observed price per (platform, SKU) over the window."""
    items = []
    for (plat, sku), a in agg.items():
        avg = a["sum"] / a["n"] if a["n"] else None
        items.append((a["min"], plat, sku, avg))
    items.sort(key=lambda x: x[0])
    lines = ["| Platform | SKU | Min ₹ | Avg ₹ |", "|---|---|--:|--:|"]
    for mn, plat, sku, avg in items[:limit]:
        lines.append("| %s | %s | %s | %s |" % (
            plat, sku, ("%g" % mn),
            ("%g" % round(avg, 1)) if avg is not None else "-"))
    return "\n".join(lines)


def build_daily(date_str):
    runs = runs_for_dates([date_str])
    week = iso_week(date_str)
    mon = month_id(date_str)
    agg = price_stats_for_dates([date_str])
    platforms = sorted({r.get("platform") for r in runs if r.get("platform")})

    head = [
        "---",
        "title: %s" % date_str,
        "aliases:",
        "  - %s (daily)" % date_str,
        "type: daily",
        "date: %s" % date_str,
        "runs_count: %d" % len(runs),
        "platforms_count: %d" % len(platforms),
        "tags:",
        "  - daily",
        "---",
        "",
        "# %s — daily rollup" % date_str,
        "",
        "Up: [[index]] · Week: [[%s (weekly)]] · Month: [[%s (monthly)]]" % (week, mon),
        "",
        "%d runs across %d platform(s): %s." % (
            len(runs), len(platforms),
            ", ".join("[[%s (platform hub)]]" % p for p in platforms) or "—"),
        "",
        "## Runs",
        "",
        "<!-- runs:start -->",
    ]
    body_links = ["- [[%s]] — **%s** · verdict %s <!-- run -->" % (
        fm["_basename"], fm.get("platform", "?"), fm.get("verdict", "?"))
        for fm in sorted(runs, key=lambda x: x["_basename"], reverse=True)]
    tail = [
        "<!-- runs:end -->",
        "",
        run_table(runs) if runs else "_No run notes for this date yet._",
        "",
        "## Cheapest observed today",
        "",
        cheapest_block(agg) if agg else "_No priced rows in history for this date._",
        "",
        "---",
        "*Auto-generated by `tools/vault_rollup.py daily %s` — see [[VAULT-SPEC]].*" % date_str,
        "",
    ]
    text = "\n".join(head + body_links + tail)
    path = os.path.join(VAULT, "daily", "%s.md" % date_str)
    write_atomic(path, text)
    return path, len(runs)


def build_weekly(week_id):
    dates = week_dates(week_id)
    present = [d for d in dates if os.path.exists(os.path.join(VAULT, "daily", "%s.md" % d))
               or runs_for_dates([d])]
    runs = runs_for_dates(dates)
    agg = price_stats_for_dates(dates)
    platforms = sorted({r.get("platform") for r in runs if r.get("platform")})
    mons = sorted({month_id(d) for d in present}) or [month_id(dates[0])]

    head = [
        "---",
        "title: %s" % week_id,
        "aliases:",
        "  - %s (weekly)" % week_id,
        "type: weekly",
        "week: %s" % week_id,
        "runs_count: %d" % len(runs),
        "tags:",
        "  - weekly",
        "---",
        "",
        "# %s — weekly trend rollup" % week_id,
        "",
        "Up: [[index]] · Month: %s" % " ".join("[[%s (monthly)]]" % m for m in mons),
        "Span: %s → %s" % (dates[0], dates[-1]),
        "",
        "## Dailies this week",
        "",
    ]
    daily_links = ["- [[%s (daily)]]" % d for d in present] or ["_No dailies yet this week._"]
    tail = [
        "",
        "## Coverage",
        "",
        "%d runs across %d platform(s): %s." % (
            len(runs), len(platforms),
            ", ".join("[[%s (platform hub)]]" % p for p in platforms) or "—"),
        "",
        run_table(runs) if runs else "_No run notes this week yet._",
        "",
        "## Cheapest observed this week",
        "",
        cheapest_block(agg) if agg else "_No priced rows in history for this week._",
        "",
        "---",
        "*Auto-generated by `tools/vault_rollup.py weekly %s` — see [[VAULT-SPEC]].*" % week_id,
        "",
    ]
    text = "\n".join(head + daily_links + tail)
    path = os.path.join(VAULT, "weekly", "%s.md" % week_id)
    write_atomic(path, text)
    return path, len(present)


def build_monthly(mon_id):
    # all dailies/run-notes whose date starts with mon_id
    all_runs = [fm for fm in all_run_notes() if str(fm.get("date", "")).startswith(mon_id)]
    dates = sorted({fm["date"] for fm in all_runs})
    weeks = sorted({iso_week(d) for d in dates})
    daily_dates = sorted({d for d in dates})
    agg = price_stats_for_dates(dates)
    platforms = sorted({r.get("platform") for r in all_runs if r.get("platform")})

    head = [
        "---",
        "title: %s" % mon_id,
        "aliases:",
        "  - %s (monthly)" % mon_id,
        "type: monthly",
        "month: %s" % mon_id,
        "runs_count: %d" % len(all_runs),
        "tags:",
        "  - monthly",
        "---",
        "",
        "# %s — monthly trend rollup" % mon_id,
        "",
        "Up: [[index]]",
        "",
        "## Weeks this month",
        "",
    ]
    week_links = ["- [[%s (weekly)]]" % w for w in weeks] or ["_No weeks yet._"]
    daily_links = ["", "## Days this month", ""] + (
        ["- [[%s (daily)]]" % d for d in daily_dates] or ["_No days yet._"])
    tail = [
        "",
        "## Coverage",
        "",
        "%d runs across %d platform(s): %s." % (
            len(all_runs), len(platforms),
            ", ".join("[[%s (platform hub)]]" % p for p in platforms) or "—"),
        "",
        "## Cheapest observed this month",
        "",
        cheapest_block(agg) if agg else "_No priced rows in history for this month._",
        "",
        "---",
        "*Auto-generated by `tools/vault_rollup.py monthly %s` — see [[VAULT-SPEC]].*" % mon_id,
        "",
    ]
    text = "\n".join(head + week_links + daily_links + tail)
    path = os.path.join(VAULT, "monthly", "%s.md" % mon_id)
    write_atomic(path, text)
    return path, len(weeks)


# ---------------------------------------------------------------- main
def normalize_arg(kind, arg):
    """Accept a date for any kind and derive the right id."""
    if kind == "daily":
        return arg or today_ist()
    if kind == "weekly":
        if not arg:
            return iso_week(today_ist())
        if "-W" in arg:
            return arg
        return iso_week(arg)              # a YYYY-MM-DD was passed
    if kind == "monthly":
        if not arg:
            return month_id(today_ist())
        if len(arg) == 7:
            return arg                    # YYYY-MM
        return month_id(arg)              # a YYYY-MM-DD was passed
    return arg


def main(argv):
    if len(argv) < 2 or argv[1] not in ("daily", "weekly", "monthly"):
        sys.stderr.write("usage: vault_rollup.py <daily|weekly|monthly> [date]\n")
        sys.exit(1)
    kind = argv[1]
    arg = argv[2] if len(argv) > 2 else None
    ident = normalize_arg(kind, arg)

    if kind == "daily":
        path, n = build_daily(ident)
        print("vault_rollup: wrote %s (%d run notes)" % (os.path.relpath(path, ROOT), n))
    elif kind == "weekly":
        path, n = build_weekly(ident)
        print("vault_rollup: wrote %s (%d dailies)" % (os.path.relpath(path, ROOT), n))
    else:
        path, n = build_monthly(ident)
        print("vault_rollup: wrote %s (%d weeks)" % (os.path.relpath(path, ROOT), n))


if __name__ == "__main__":
    main(sys.argv)
