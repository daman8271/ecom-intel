#!/usr/bin/env python3
"""vault_note.py <platform> <RUN_ID>

Per-run vault writer for the ecom-intel memory vault.

Reads:
  platforms/<platform>/result.json          (required)
  reviews/<platform>-<RUN_ID>.json           (optional; the review verdict)

Writes / upserts (all idempotent for a given RUN_ID):
  vault/runs/<platform>/<platform>-<RUN_ID>.md   one note per platform per run
  vault/platforms/<platform>.md                  platform hub / MOC (link list upserted)
  vault/daily/<YYYY-MM-DD>.md                     daily rollup (run link upserted)
  data/<platform>/history.csv                     machine-readable rows for ML

Design / conventions: see vault/VAULT-SPEC.md.

Pure Python 3 stdlib. No LLM. Deterministic. Safe inside the cron loop.
Handles BOTH result.json shapes:
  - national  (perPin == 1 entry, pincode "-")  -> amazon, flipkart
  - per-pincode (perPin == 40 entries)          -> blinkit, flipkart-minutes
"""

import sys
import os
import csv
import json
import datetime

# ---------------------------------------------------------------- paths
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                      # /opt/ecom-intel
VAULT = os.path.join(ROOT, "vault")
DATA = os.path.join(ROOT, "data")

IST = datetime.timezone(datetime.timedelta(hours=5, minutes=30))

CSV_COLUMNS = [
    "run_id", "date_ist", "platform", "canonical_sku", "city",
    "pincode", "price", "mrp", "discount_pct", "in_stock",
]

# Markers used to upsert a single line into hub/daily link lists idempotently.
RUN_LINK_TAG = "<!-- run -->"      # marks an auto-managed run-link bullet


# ---------------------------------------------------------------- helpers
def die(msg):
    sys.stderr.write("vault_note: %s\n" % msg)
    sys.exit(1)


def fnum(v):
    """Coerce to float or None."""
    try:
        if v is None or v == "":
            return None
        return float(v)
    except (TypeError, ValueError):
        return None


def money(v):
    """Format a price/MRP for the Markdown table."""
    f = fnum(v)
    if f is None:
        return "-"
    if abs(f - round(f)) < 1e-9:
        return str(int(round(f)))
    return ("%.2f" % f).rstrip("0").rstrip(".")


def pct(v):
    f = fnum(v)
    if f is None:
        return "-"
    return "%.1f%%" % f


def md_escape_cell(text):
    """Escape pipes/newlines so a value is safe inside a Markdown table cell."""
    s = "" if text is None else str(text)
    return s.replace("|", "\\|").replace("\n", " ").strip()


def all_rows(result):
    """Flat list of observation rows, regardless of shape."""
    rows = result.get("allRows")
    if rows:
        return rows
    out = []
    for p in result.get("perPin", []) or []:
        out.extend(p.get("rows", []) or [])
    return out


def is_national(result):
    """National catalog shape (one synthetic 'All India' pin) vs per-pincode."""
    pp = result.get("perPin") or []
    s = result.get("summary") or {}
    if s.get("pincodes_total") == 1:
        return True
    if len(pp) == 1 and str(pp[0].get("pincode", "")).strip() in ("-", ""):
        return True
    # fall back: if every row has pincode "-"
    rows = all_rows(result)
    if rows and all(str(r.get("pincode", "")).strip() in ("-", "") for r in rows):
        return True
    return False


def ist_from_captured(captured_at, run_id):
    """Return (date_str 'YYYY-MM-DD', time_str 'HH:MM IST') in IST.

    Prefer summary.captured_at (UTC ISO). Fall back to the RUN_ID timestamp,
    which is already wall-clock IST (date +%Y-%m-%d-%H%M on the IST box)."""
    if captured_at:
        try:
            dt = datetime.datetime.fromisoformat(str(captured_at).replace("Z", "+00:00"))
            ist = dt.astimezone(IST)
            return ist.strftime("%Y-%m-%d"), ist.strftime("%H:%M IST")
        except Exception:
            pass
    # RUN_ID looks like 2026-05-21-1600
    try:
        d, t = run_id.rsplit("-", 1)
        return d, "%s:%s IST" % (t[:2], t[2:])
    except Exception:
        return run_id, "?"


def iso_week(date_str):
    """'YYYY-MM-DD' -> ISO week id 'YYYY-Www' (matches vault_rollup.py)."""
    y, m, d = (int(x) for x in date_str.split("-"))
    g, w, _ = datetime.date(y, m, d).isocalendar()
    return "%04d-W%02d" % (g, w)


def month_id(date_str):
    return date_str[:7]   # YYYY-MM


def read_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


# ---------------------------------------------------------------- run note
def build_run_note(platform, run_id, result, review, date_str, time_str):
    rows = all_rows(result)
    summary = result.get("summary") or {}
    national = is_national(result)

    instock = [r for r in rows if r.get("in_stock")]

    # unique SKUs
    skus = sorted({r.get("canonical") for r in rows if r.get("canonical")})
    unique_skus = summary.get("unique_skus") or len(skus)
    total_rows = summary.get("total_rows") or len(rows)
    pin_with = summary.get("pincodes_with_jivo")
    pin_tot = summary.get("pincodes_total")

    verdict = (review or {}).get("verdict", "UNREVIEWED")

    # ---- frontmatter ----
    tags = [
        "run",
        "platform/%s" % platform,
        "verdict/%s" % verdict,
        "shape/%s" % ("national" if national else "per-pincode"),
    ]
    fm = []
    fm.append("---")
    fm.append("platform: %s" % platform)
    fm.append("run_id: %s" % run_id)
    fm.append("date: %s" % date_str)
    fm.append("time_ist: %s" % time_str.replace(" IST", ""))
    fm.append("verdict: %s" % verdict)
    fm.append("rows: %d" % int(total_rows))
    fm.append("unique_skus: %d" % int(unique_skus))
    fm.append("pincodes_with_jivo: %s" % (pin_with if pin_with is not None else "null"))
    fm.append("pincodes_total: %s" % (pin_tot if pin_tot is not None else "null"))
    fm.append("shape: %s" % ("national" if national else "per-pincode"))
    fm.append("tags:")
    for t in tags:
        fm.append("  - %s" % t)
    fm.append("---")

    # ---- body ----
    b = []
    b.append("# %s — run %s" % (platform, run_id))
    b.append("")
    # navigation links (BODY links = graph edges)
    nav = "Up: [[%s (platform hub)]] · Day: [[%s (daily)]]" % (platform, date_str)
    prev = prev_run_id(platform, run_id)
    if prev:
        nav += " · Prev: [[%s-%s]]" % (platform, prev)
    b.append(nav)
    b.append("")
    b.append("- **Verdict:** %s" % verdict)
    b.append("- **Captured (IST):** %s %s" % (date_str, time_str))
    if national:
        b.append("- **Pricing:** national (All India) — %d SKUs in catalog" % int(unique_skus))
    else:
        cov = "%s/%s" % (pin_with, pin_tot) if pin_with is not None else "?"
        b.append("- **Coverage:** %s pincodes carry Jivo · %d rows · %d unique SKUs"
                 % (cov, int(total_rows), int(unique_skus)))
    if review:
        reasons = review.get("reasons") or []
        if reasons:
            b.append("- **Review reasons:** %s" % md_escape_cell("; ".join(str(x) for x in reasons)))
        note = review.get("llm_note")
        if note:
            b.append("- **Note:** %s" % md_escape_cell(note))
    b.append("")

    # headline: cheapest in-stock by per-litre, top discount
    plr = [r for r in instock if fnum(r.get("per_litre"))]
    if plr:
        c = min(plr, key=lambda r: fnum(r.get("per_litre")))
        b.append("- **Cheapest (per litre, in-stock):** %s — ₹%s/L (%s)"
                 % (md_escape_cell(c.get("sku_raw") or c.get("canonical")),
                    money(c.get("per_litre")), md_escape_cell(c.get("city"))))
    disc = [r for r in rows if (fnum(r.get("discount_pct")) or 0) > 0]
    if disc:
        t = max(disc, key=lambda r: fnum(r.get("discount_pct")))
        b.append("- **Top discount:** %s — %s off (%s)"
                 % (md_escape_cell(t.get("sku_raw") or t.get("canonical")),
                    pct(t.get("discount_pct")), md_escape_cell(t.get("city"))))
    b.append("")

    # ---- SKU table (one row per canonical SKU; aggregate across locations) ----
    b.append("## SKUs")
    b.append("")
    b.append("| SKU | Pack | Price | MRP | Discount | In stock |")
    b.append("|---|---|---:|---:|---:|:--:|")
    by_sku = {}
    for r in rows:
        key = r.get("canonical") or r.get("sku_raw")
        if key is None:
            continue
        by_sku.setdefault(key, []).append(r)
    for key in sorted(by_sku):
        group = by_sku[key]
        # representative = cheapest in-stock else cheapest overall
        ins = [r for r in group if r.get("in_stock")]
        pool = ins if ins else group
        rep = min(pool, key=lambda r: fnum(r.get("sale")) if fnum(r.get("sale")) is not None else 1e18)
        name = rep.get("sku_raw") or key
        any_stock = any(r.get("in_stock") for r in group)
        b.append("| %s | %s | %s | %s | %s | %s |" % (
            md_escape_cell(name),
            md_escape_cell(rep.get("pack")),
            money(rep.get("sale")),
            money(rep.get("mrp")),
            pct(rep.get("discount_pct")),
            "yes" if any_stock else "no",
        ))
    b.append("")

    # ---- per-city coverage (per-pincode shape only) ----
    if not national:
        b.append("## Per-city coverage")
        b.append("")
        b.append("| City | Pincodes with Jivo | SKUs seen |")
        b.append("|---|--:|--:|")
        cities = {}
        for p in result.get("perPin", []) or []:
            city = p.get("city") or "?"
            prows = p.get("rows") or []
            c = cities.setdefault(city, {"pins": set(), "skus": set()})
            if prows:
                c["pins"].add(p.get("pincode"))
                for r in prows:
                    if r.get("canonical"):
                        c["skus"].add(r.get("canonical"))
        for city in sorted(cities):
            c = cities[city]
            if not c["pins"]:
                continue
            b.append("| %s | %d | %d |" % (md_escape_cell(city), len(c["pins"]), len(c["skus"])))
        b.append("")

    b.append("---")
    b.append("*Auto-generated by `tools/vault_note.py` — see [[VAULT-SPEC]]. Do not hand-edit.*")
    b.append("")

    return "\n".join(fm) + "\n\n" + "\n".join(b)


def prev_run_id(platform, run_id):
    """Find the most recent existing run note for this platform before run_id."""
    rdir = os.path.join(VAULT, "runs", platform)
    if not os.path.isdir(rdir):
        return None
    prefix = platform + "-"
    ids = []
    for fn in os.listdir(rdir):
        if fn.startswith(prefix) and fn.endswith(".md"):
            rid = fn[len(prefix):-3]
            if rid != run_id:
                ids.append(rid)
    earlier = sorted([r for r in ids if r < run_id])
    return earlier[-1] if earlier else None


# ---------------------------------------------------------------- hub upsert
def upsert_platform_hub(platform, run_id, date_str, verdict, national):
    path = os.path.join(VAULT, "platforms", "%s.md" % platform)
    link_line = "- [[%s-%s]] — %s · verdict %s %s" % (
        platform, run_id, date_str, verdict, RUN_LINK_TAG)

    if not os.path.exists(path):
        shape = "national (All India catalog)" if national else "per-pincode (top-20 cities, ~40 pincodes)"
        head = [
            "---",
            "title: %s" % platform,
            "aliases:",
            "  - %s (platform hub)" % platform,
            "type: platform-hub",
            "platform: %s" % platform,
            "tags:",
            "  - moc",
            "  - platform-hub",
            "  - platform/%s" % platform,
            "---",
            "",
            "# %s — platform hub" % platform,
            "",
            "Up: [[index]]",
            "",
            "Hub / Map of Content for the **%s** platform. Pricing shape: **%s**."
            % (platform, shape),
            "Every scrape run for this platform is listed below (newest managed by",
            "`tools/vault_note.py`).",
            "",
            "## Runs",
            "",
            "<!-- runs:start -->",
            "<!-- runs:end -->",
            "",
            "---",
            "*Hub auto-maintained by `tools/vault_note.py` — see [[VAULT-SPEC]].*",
            "",
        ]
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(head))

    _upsert_run_link(path, run_id, link_line, platform)


def _upsert_run_link(path, run_id, link_line, platform):
    """Insert/replace the managed run-link bullet in a hub/daily note.

    De-dupes on the run note basename '<platform>-<run_id>', keeps the managed
    block sorted descending (newest first)."""
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    lines = text.split("\n")

    start = end = None
    for i, ln in enumerate(lines):
        if ln.strip() == "<!-- runs:start -->":
            start = i
        elif ln.strip() == "<!-- runs:end -->":
            end = i
            break
    if start is None or end is None:
        # no managed block (shouldn't happen) — append one
        lines += ["", "<!-- runs:start -->", "<!-- runs:end -->"]
        start = len(lines) - 2
        end = len(lines) - 1

    block = [l for l in lines[start + 1:end] if l.strip()]
    # drop any existing line for this exact run note
    token = "[[%s-%s]]" % (platform, run_id)
    block = [l for l in block if token not in l]
    block.append(link_line)

    # sort by the run note basename, descending (newest first)
    def sort_key(l):
        # extract token like blinkit-2026-05-21-1600
        a = l.find("[[")
        bx = l.find("]]", a)
        return l[a + 2:bx] if a >= 0 and bx >= 0 else l
    block.sort(key=sort_key, reverse=True)

    new_lines = lines[:start + 1] + block + lines[end:]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(new_lines))


# ---------------------------------------------------------------- daily upsert
def upsert_daily(platform, run_id, date_str, verdict):
    path = os.path.join(VAULT, "daily", "%s.md" % date_str)
    link_line = "- [[%s-%s]] — **%s** · verdict %s %s" % (
        platform, run_id, platform, verdict, RUN_LINK_TAG)

    if not os.path.exists(path):
        week = iso_week(date_str)
        mon = month_id(date_str)
        head = [
            "---",
            "title: %s" % date_str,
            "aliases:",
            "  - %s (daily)" % date_str,
            "type: daily",
            "date: %s" % date_str,
            "tags:",
            "  - daily",
            "---",
            "",
            "# %s — daily rollup" % date_str,
            "",
            "Up: [[index]] · Week: [[%s (weekly)]] · Month: [[%s (monthly)]]" % (week, mon),
            "",
            "All scrape runs captured on %s (across all platforms)." % date_str,
            "",
            "## Runs",
            "",
            "<!-- runs:start -->",
            "<!-- runs:end -->",
            "",
            "---",
            "*Daily note auto-maintained by `tools/vault_note.py`; richer rollups via",
            "`tools/vault_rollup.py daily %s`. See [[VAULT-SPEC]].*" % date_str,
            "",
        ]
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(head))

    _upsert_run_link(path, run_id, link_line, platform)


# ---------------------------------------------------------------- history.csv
def append_history(platform, run_id, date_str, result):
    rows = all_rows(result)
    ddir = os.path.join(DATA, platform)
    os.makedirs(ddir, exist_ok=True)
    path = os.path.join(ddir, "history.csv")

    # read existing, drop this run's rows (idempotent), keep the rest
    existing = []
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8", newline="") as f:
            r = csv.DictReader(f)
            for row in r:
                if row.get("run_id") == run_id and row.get("platform") == platform:
                    continue
                existing.append(row)

    # build this run's rows, de-duped on (run_id, platform, canonical, pincode)
    new_rows = {}
    for r in rows:
        canonical = r.get("canonical") or r.get("sku_raw") or ""
        pincode = str(r.get("pincode", "")).strip() or "-"
        key = (run_id, platform, canonical, pincode)
        new_rows[key] = {
            "run_id": run_id,
            "date_ist": date_str,
            "platform": platform,
            "canonical_sku": canonical,
            "city": r.get("city") or "",
            "pincode": pincode,
            "price": _csv_num(r.get("sale")),
            "mrp": _csv_num(r.get("mrp")),
            "discount_pct": _csv_num(r.get("discount_pct")),
            "in_stock": 1 if r.get("in_stock") else 0,
        }

    all_out = existing + list(new_rows.values())

    # deterministic sort for clean git diffs
    def k(row):
        return (row.get("date_ist", ""), row.get("run_id", ""),
                row.get("platform", ""), row.get("canonical_sku", ""),
                str(row.get("pincode", "")))
    all_out.sort(key=k)

    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=CSV_COLUMNS)
        w.writeheader()
        for row in all_out:
            w.writerow({c: row.get(c, "") for c in CSV_COLUMNS})

    return path, len(new_rows)


def _csv_num(v):
    f = fnum(v)
    if f is None:
        return ""
    if abs(f - round(f)) < 1e-9:
        return str(int(round(f)))
    return ("%g" % f)


# ---------------------------------------------------------------- main
def main(argv):
    if len(argv) != 3:
        die("usage: vault_note.py <platform> <RUN_ID>")
    platform, run_id = argv[1], argv[2]

    result_path = os.path.join(ROOT, "platforms", platform, "result.json")
    if not os.path.exists(result_path):
        die("no result.json for platform '%s' at %s" % (platform, result_path))
    result = read_json(result_path)

    review = None
    review_path = os.path.join(ROOT, "reviews", "%s-%s.json" % (platform, run_id))
    if os.path.exists(review_path):
        try:
            review = read_json(review_path)
        except Exception as e:
            sys.stderr.write("vault_note: warning: could not read review %s: %s\n"
                             % (review_path, e))

    summary = result.get("summary") or {}
    date_str, time_str = ist_from_captured(summary.get("captured_at"), run_id)
    national = is_national(result)
    verdict = (review or {}).get("verdict", "UNREVIEWED")

    # write run note
    note = build_run_note(platform, run_id, result, review, date_str, time_str)
    rdir = os.path.join(VAULT, "runs", platform)
    os.makedirs(rdir, exist_ok=True)
    note_path = os.path.join(rdir, "%s-%s.md" % (platform, run_id))
    with open(note_path, "w", encoding="utf-8") as f:
        f.write(note)

    # upsert hub + daily, append history
    upsert_platform_hub(platform, run_id, date_str, verdict, national)
    upsert_daily(platform, run_id, date_str, verdict)
    csv_path, n_csv = append_history(platform, run_id, date_str, result)

    print("vault_note: wrote %s" % os.path.relpath(note_path, ROOT))
    print("vault_note: upserted %s" % os.path.relpath(
        os.path.join(VAULT, "platforms", "%s.md" % platform), ROOT))
    print("vault_note: upserted %s" % os.path.relpath(
        os.path.join(VAULT, "daily", "%s.md" % date_str), ROOT))
    print("vault_note: %s rows -> %s (verdict %s, shape %s)" % (
        n_csv, os.path.relpath(csv_path, ROOT), verdict,
        "national" if national else "per-pincode"))


if __name__ == "__main__":
    main(sys.argv)
