#!/usr/bin/env python3
"""
freshness_guard.py — data-freshness / coverage guard for the Jivo price-intel pipeline.

WHY THIS EXISTS
    The user compiles graphs & evidence from this pipeline. When a platform or a
    set of SKUs silently STOPS updating, the series freezes into a misleading flat
    line that looks like real (stable) data on a graph — and the freeze is usually
    discovered late. This guard makes any freeze LOUD before it reaches a graph.

WHAT IT CHECKS  (read-only; never mutates the pipeline)
    1. Per competitor platform: most-recent data date + rows/SKU trend, from BOTH
       baselines/<p>.json AND data/<p>/history.csv (freshest signal wins, so a
       lagging baseline on a still-flowing platform does not false-alarm).
       -> GREEN / AMBER / RED.
    2. The user-facing vault (~/jivo-data-bank/ecom/skus/*.md): buckets SKUs by
       `last_seen` and surfaces any CLUSTER frozen at a single past date. The known
       2026-06-04 amazon-now correction is labelled KNOWN/EXPECTED; anything else is
       flagged INVESTIGATE.
    3. First-party tables (~/jivo-data-bank/jivo/data/*price*.md): reads the real
       data-date column (upload_date), NOT the vault-touch columns (__last_seen),
       and flags tables stuck in the past (e.g. amazon_price_data @ mid-May).

OUTPUT
    - ~/jivo-data-bank/DATA-FRESHNESS.md   (human-scannable RED/AMBER/GREEN report)
    - ~/jivo-data-bank/data-freshness.json (machine-readable)
    - stdout summary
    - EXIT NONZERO if any ACTIONABLE RED (a live platform that froze / zero rows),
      so it can gate a cron/deploy. Known-dead platforms (swiggy-instamart) and
      historical/expected vault clusters do NOT gate.

    --alert : if a Telegram notifier is configured (secrets.env TELEGRAM_BOT_TOKEN +
              TELEGRAM_CHAT_ID, same pattern as tools/guardian.py), send the RED
              summary. Otherwise prints a clearly-marked hook stub.

Python 3 stdlib only. Robust: a missing file / platform => RED, never an exception.
"""

import os
import sys
import csv
import json
import re
import subprocess
from datetime import date, datetime, timezone

# ----------------------------------------------------------------------------- #
# CONFIG — tune thresholds here.                                                 #
# ----------------------------------------------------------------------------- #
CONFIG = {
    "green_max_age_days": 2,      # data <= 2 days old  -> GREEN
    "amber_max_age_days": 6,      # 3..6 days old       -> AMBER ; > 6 -> RED
    "row_drop_amber_pct": 40,     # latest rows  < (100-X)% of trailing median -> AMBER
    "sku_drop_amber_pct": 30,     # latest uniq_skus drop vs trailing median   -> AMBER
    "trailing_window": 8,         # # of prior samples used for the trailing median
    "baseline_lag_note_days": 2,  # baseline date lags freshest data by > this -> info note
    "frozen_cluster_min": 10,     # >= N SKUs frozen at one past date => a reported cluster
    "first_party_stale_days": 7,  # first-party table older than this => STALE
}

# The platforms we EXPECT to update daily. A totally-missing one shows RED.
EXPECTED_PLATFORMS = [
    "amazon", "amazon-fresh", "amazon-now",
    "blinkit", "zepto",
    "flipkart", "flipkart-minutes", "bigbasket",
]

# Known-dead / off-box surfaces: still reported, but their RED is EXPECTED and
# does NOT gate the exit code (would otherwise fail every cron run forever).
KNOWN_DEAD_PLATFORMS = {
    "instamart": "swiggy-instamart — known-dead / off-box (not scraped on this box)",
}

# Vault last_seen clusters we already root-caused. A cluster at one of these dates
# is labelled KNOWN/EXPECTED instead of INVESTIGATE.
KNOWN_FROZEN_CLUSTERS = {
    "2026-06-04": {
        "label": "KNOWN/EXPECTED (delisted-from-Now correction)",
        "reason": ("On 2026-06-04 amazon-now was deliberately corrected (wrong-surface "
                   "fix), which legitimately orphaned ~63 long-tail Amazon SKUs. The "
                   "resulting ~190 vault notes frozen at last_seen 2026-06-04 are CORRECT "
                   "data, NOT a breakage. Do not graph these as live."),
        "expected_platforms": ["amazon", "amazon-now", "amazon-fresh"],
    },
}

# Paths — auto-detect Mac (~/ecom-intel, ~/jivo-data-bank) vs VPS (/opt/ecom-intel,
# /root/jivo-data-bank); override with ECOM_ROOT / VAULT_ROOT env vars.
HOME = os.path.expanduser("~")


def _resolve_root(env_key, candidates):
    v = os.environ.get(env_key)
    if v:
        return v
    for c in candidates:
        if c and os.path.isdir(c):
            return c
    return candidates[0]


ECOM_ROOT = _resolve_root("ECOM_ROOT", [os.path.join(HOME, "ecom-intel"), "/opt/ecom-intel"])
VAULT_ROOT = _resolve_root("VAULT_ROOT", [os.path.join(HOME, "jivo-data-bank"), "/root/jivo-data-bank"])
BASELINES_DIR = os.path.join(ECOM_ROOT, "baselines")
DATA_DIR = os.path.join(ECOM_ROOT, "data")
SKUS_DIR = os.path.join(VAULT_ROOT, "ecom", "skus")
FIRSTPARTY_DIR = os.path.join(VAULT_ROOT, "jivo", "data")
OUT_MD = os.path.join(VAULT_ROOT, "DATA-FRESHNESS.md")
OUT_JSON = os.path.join(VAULT_ROOT, "data-freshness.json")
SECRETS_ENV = os.path.join(ECOM_ROOT, "secrets.env")

SEV = {"GREEN": 0, "AMBER": 1, "RED": 2}


# ----------------------------------------------------------------------------- #
# Small helpers                                                                  #
# ----------------------------------------------------------------------------- #
def today_ref():
    """Reference 'today'. Overridable for testing via --today / FRESHNESS_TODAY."""
    env = os.environ.get("FRESHNESS_TODAY")
    if env:
        try:
            return datetime.strptime(env.strip(), "%Y-%m-%d").date()
        except Exception:
            pass
    return date.today()


def parse_date(s):
    """Parse a date out of many shapes: 'YYYY-MM-DD', ISO ts, run_id 'YYYY-MM-DD-HHMM'."""
    if not s:
        return None
    s = str(s).strip()
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})", s)
    if not m:
        return None
    try:
        return date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
    except Exception:
        return None


def median(xs):
    xs = sorted(x for x in xs if x is not None)
    n = len(xs)
    if n == 0:
        return None
    if n % 2:
        return float(xs[n // 2])
    return (xs[n // 2 - 1] + xs[n // 2]) / 2.0


def worst(*colors):
    out = "GREEN"
    for c in colors:
        if SEV.get(c, 0) > SEV.get(out, 0):
            out = c
    return out


# ----------------------------------------------------------------------------- #
# Source readers                                                                 #
# ----------------------------------------------------------------------------- #
def load_baseline(platform):
    """Return parsed baseline dict or None. Never raises."""
    path = os.path.join(BASELINES_DIR, platform + ".json")
    if not os.path.isfile(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return None


def csv_latest(platform):
    """
    Stream data/<platform>/history.csv -> (latest_date, rows_on_latest, skus_on_latest).
    Authoritative for 'is the series still moving' (this is the table graphs are built on).
    Returns (None, 0, 0) if no file / unreadable. Never raises.
    """
    path = os.path.join(DATA_DIR, platform, "history.csv")
    if not os.path.isfile(path):
        return (None, 0, 0)
    latest = None
    rows_on_latest = 0
    skus_on_latest = set()
    try:
        with open(path, "r", encoding="utf-8", errors="replace", newline="") as fh:
            reader = csv.DictReader(fh)
            # tolerate odd headers
            date_field = "date_ist" if (reader.fieldnames and "date_ist" in reader.fieldnames) else None
            sku_field = "canonical_sku" if (reader.fieldnames and "canonical_sku" in reader.fieldnames) else None
            for row in reader:
                d = parse_date(row.get(date_field)) if date_field else None
                if d is None:
                    # fall back: try run_id column
                    d = parse_date(row.get("run_id"))
                if d is None:
                    continue
                if latest is None or d > latest:
                    latest = d
                    rows_on_latest = 0
                    skus_on_latest = set()
                if d == latest:
                    rows_on_latest += 1
                    if sku_field:
                        skus_on_latest.add(row.get(sku_field))
    except Exception:
        return (latest, rows_on_latest, len(skus_on_latest))
    return (latest, rows_on_latest, len(skus_on_latest))


# ----------------------------------------------------------------------------- #
# 1. Per-platform classification                                                 #
# ----------------------------------------------------------------------------- #
def classify_platform(platform, ref):
    """Return a result dict for one platform. Never raises."""
    res = {
        "platform": platform,
        "color": "RED",
        "latest_data_date": None,
        "age_days": None,
        "rows_latest": 0,
        "unique_skus_latest": None,
        "rows_trailing_median": None,
        "skus_trailing_median": None,
        "baseline_last_date": None,
        "known_dead": platform in KNOWN_DEAD_PLATFORMS,
        "notes": [],
        "reasons": [],
    }
    try:
        baseline = load_baseline(platform)
        samples = (baseline or {}).get("samples") or []
        # baseline latest date (prefer captured_at, else run_id)
        b_dates = []
        for s in samples:
            d = parse_date(s.get("captured_at")) or parse_date(s.get("run_id"))
            if d:
                b_dates.append(d)
        baseline_last = max(b_dates) if b_dates else None
        res["baseline_last_date"] = baseline_last.isoformat() if baseline_last else None

        # csv latest (authoritative for "series still moving")
        csv_date, csv_rows, csv_skus = csv_latest(platform)
        res["rows_latest"] = csv_rows
        if csv_skus:
            res["unique_skus_latest"] = csv_skus

        # freshest signal across both sources
        candidates = [d for d in (baseline_last, csv_date) if d]
        latest = max(candidates) if candidates else None

        # trailing trend from baseline samples (these numbers are comparable across runs;
        # CSV row counts are per-pincode-expanded and NOT comparable, so we do NOT mix them)
        rows_series = [s.get("rows") for s in samples if isinstance(s.get("rows"), (int, float))]
        skus_series = [s.get("unique_skus") for s in samples if isinstance(s.get("unique_skus"), (int, float))]

        # ---- no data at all => RED -------------------------------------------------
        if latest is None:
            res["color"] = "RED"
            res["reasons"].append("no data files (no baseline samples, no history.csv)")
            _apply_known_dead(res)
            return res

        res["latest_data_date"] = latest.isoformat()
        age = (ref - latest).days
        res["age_days"] = age

        # ---- zero rows on the latest day => RED ------------------------------------
        zero_rows = (csv_date is not None and csv_date == latest and csv_rows == 0)
        if zero_rows:
            res["reasons"].append("zero rows on latest data date")

        # ---- age-based color -------------------------------------------------------
        if age <= CONFIG["green_max_age_days"]:
            age_color = "GREEN"
        elif age <= CONFIG["amber_max_age_days"]:
            age_color = "AMBER"
            res["reasons"].append("stale: last data %d days ago" % age)
        else:
            age_color = "RED"
            res["reasons"].append("FROZEN: no update for %d days (> %d)" % (age, CONFIG["amber_max_age_days"]))

        color = worst("RED" if zero_rows else "GREEN", age_color)

        # ---- drop-vs-trailing-median (escalate to AMBER) ---------------------------
        if len(rows_series) >= 3:
            trail = rows_series[-(CONFIG["trailing_window"] + 1):-1] or rows_series[:-1]
            med = median(trail)
            res["rows_trailing_median"] = med
            cur = rows_series[-1]
            if med and med > 0:
                drop = (med - cur) / med * 100.0
                if drop >= CONFIG["row_drop_amber_pct"]:
                    color = worst(color, "AMBER")
                    res["reasons"].append("rows dropped %.0f%% vs trailing median (%d -> %d)" % (drop, med, cur))
        if len(skus_series) >= 3:
            trail = skus_series[-(CONFIG["trailing_window"] + 1):-1] or skus_series[:-1]
            med = median(trail)
            res["skus_trailing_median"] = med
            cur = skus_series[-1]
            if med and med > 0:
                drop = (med - cur) / med * 100.0
                if drop >= CONFIG["sku_drop_amber_pct"]:
                    color = worst(color, "AMBER")
                    res["reasons"].append("unique_skus dropped %.0f%% vs trailing median (%d -> %d)" % (drop, med, cur))

        # ---- baseline-vs-csv lag (informational note, does not change color) -------
        if baseline_last and csv_date and (csv_date - baseline_last).days > CONFIG["baseline_lag_note_days"]:
            res["notes"].append(
                "baseline last seeded %s but raw history current to %s — runs landing but "
                "review/baseline not seeding (likely SUSPECT/BROKEN verdicts)."
                % (baseline_last.isoformat(), csv_date.isoformat()))

        res["color"] = color
        if not res["reasons"]:
            res["reasons"].append("up to date")
        _apply_known_dead(res)
        return res
    except Exception as e:  # absolute belt-and-suspenders — a platform must never crash the build
        res["color"] = "RED"
        res["reasons"] = ["guard error: %s" % e]
        _apply_known_dead(res)
        return res


def _apply_known_dead(res):
    if res["known_dead"]:
        res["notes"].insert(0, "KNOWN-DEAD: " + KNOWN_DEAD_PLATFORMS[res["platform"]] + " (does not gate)")


# ----------------------------------------------------------------------------- #
# 2. Vault frozen-cluster scan                                                   #
# ----------------------------------------------------------------------------- #
def _parse_frontmatter(path):
    """Return (last_seen_str, [platforms]) from a vault SKU note. Best-effort, never raises."""
    last_seen = None
    platforms = []
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            in_fm = False
            in_pf = False
            seen_open = False
            for line in fh:
                stripped = line.rstrip("\n")
                if stripped.strip() == "---":
                    if not seen_open:
                        seen_open = True
                        in_fm = True
                        continue
                    else:
                        break  # end of frontmatter
                if not in_fm:
                    continue
                m = re.match(r"^last_seen:\s*(.+?)\s*$", stripped)
                if m:
                    last_seen = m.group(1).strip().strip('"').strip("'")
                    in_pf = False
                    continue
                if re.match(r"^platforms:\s*$", stripped):
                    in_pf = True
                    continue
                if in_pf:
                    mm = re.match(r"^\s*-\s+(.+?)\s*$", stripped)
                    if mm:
                        platforms.append(mm.group(1).strip().strip('"').strip("'"))
                        continue
                    # a non-list, non-indented line ends the platforms block
                    if re.match(r"^\S", stripped):
                        in_pf = False
    except Exception:
        pass
    return last_seen, platforms


def scan_vault_clusters():
    """
    Bucket every ecom/skus/*.md by last_seen. The freshest date is 'live'; any
    OTHER date carrying >= frozen_cluster_min SKUs is a frozen cluster.
    Returns (clusters list, summary dict). Never raises.
    """
    buckets = {}            # date_str -> count
    platform_by_date = {}   # date_str -> {platform: count}
    total = 0
    if not os.path.isdir(SKUS_DIR):
        return [], {"error": "skus dir missing: %s" % SKUS_DIR, "total_notes": 0}
    try:
        for name in os.listdir(SKUS_DIR):
            if not name.endswith(".md"):
                continue
            total += 1
            ls, pfs = _parse_frontmatter(os.path.join(SKUS_DIR, name))
            if not ls:
                ls = "(none)"
            buckets[ls] = buckets.get(ls, 0) + 1
            pb = platform_by_date.setdefault(ls, {})
            for p in pfs:
                pb[p] = pb.get(p, 0) + 1
    except Exception as e:
        return [], {"error": "scan failed: %s" % e, "total_notes": total}

    # freshest real date = the live edge
    real_dates = [d for d in buckets if re.match(r"\d{4}-\d{2}-\d{2}", d)]
    freshest = max(real_dates) if real_dates else None

    clusters = []
    for d, cnt in buckets.items():
        if d == freshest or d == "(none)":
            continue
        if not re.match(r"\d{4}-\d{2}-\d{2}", d):
            continue
        if cnt < CONFIG["frozen_cluster_min"]:
            continue
        known = KNOWN_FROZEN_CLUSTERS.get(d)
        pbreak = sorted(platform_by_date.get(d, {}).items(), key=lambda kv: (-kv[1], kv[0]))
        clusters.append({
            "date": d,
            "count": cnt,
            "platform_breakdown": pbreak,
            "classification": "KNOWN" if known else "INVESTIGATE",
            "label": known["label"] if known else "INVESTIGATE — unexplained frozen cluster",
            "reason": known["reason"] if known else
                      ("%d SKUs last_seen on %s and never since. Verify whether the source "
                       "surface genuinely delisted these (real) or the scraper silently stopped "
                       "covering them (breakage). Do NOT graph these as live until confirmed."
                       % (cnt, d)),
        })
    clusters.sort(key=lambda c: c["date"], reverse=True)
    summary = {
        "total_notes": total,
        "freshest_last_seen": freshest,
        "live_count": buckets.get(freshest, 0) if freshest else 0,
        "frozen_cluster_count": len(clusters),
    }
    return clusters, summary


# ----------------------------------------------------------------------------- #
# 3. First-party tables                                                          #
# ----------------------------------------------------------------------------- #
# Real data-date columns, in priority order. Columns starting with '__' are vault
# bookkeeping (e.g. __last_seen = vault-touch date) and must NEVER be treated as
# the data date.
_FP_DATE_COLS = ["upload_date", "date", "captured_at", "created_at", "updated_at"]


def _read_embedded_csv_dates(path):
    """Extract the max real data date from a vault note's embedded ```csv block."""
    table = None
    best = None
    used_col = None
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        m = re.search(r"^table:\s*(.+?)\s*$", text, re.MULTILINE)
        if m:
            table = m.group(1).strip()
        block = re.search(r"```csv\s*\n(.*?)```", text, re.DOTALL)
        if not block:
            return table, None, None
        rdr = csv.DictReader(block.group(1).splitlines())
        cols = rdr.fieldnames or []
        date_col = None
        for c in _FP_DATE_COLS:
            if c in cols:
                date_col = c
                break
        if not date_col:
            return table, None, None
        used_col = date_col
        for row in rdr:
            d = parse_date(row.get(date_col))
            if d and (best is None or d > best):
                best = d
    except Exception:
        return table, best, used_col
    return table, best, used_col


def scan_first_party(ref):
    """
    Group ~/jivo-data-bank/jivo/data/*price*.md by `table:` and report each table's
    max real data date. Flag tables older than first_party_stale_days. Never raises.
    """
    tables = {}  # table -> {"max_date": date, "files": int, "date_col": str}
    if not os.path.isdir(FIRSTPARTY_DIR):
        return {"error": "first-party dir missing: %s" % FIRSTPARTY_DIR, "tables": []}
    try:
        for name in os.listdir(FIRSTPARTY_DIR):
            if not name.endswith(".md") or "price" not in name:
                continue
            tbl, d, col = _read_embedded_csv_dates(os.path.join(FIRSTPARTY_DIR, name))
            if not tbl:
                continue
            slot = tables.setdefault(tbl, {"max_date": None, "files": 0, "date_col": col})
            slot["files"] += 1
            if col and not slot["date_col"]:
                slot["date_col"] = col
            if d and (slot["max_date"] is None or d > slot["max_date"]):
                slot["max_date"] = d
    except Exception as e:
        return {"error": "scan failed: %s" % e, "tables": []}

    out = []
    for tbl, slot in sorted(tables.items()):
        md = slot["max_date"]
        age = (ref - md).days if md else None
        if md is None:
            status = "UNKNOWN"
        elif age > CONFIG["first_party_stale_days"]:
            status = "STALE"
        elif age > CONFIG["green_max_age_days"]:
            status = "AGING"
        else:
            status = "CURRENT"
        out.append({
            "table": tbl,
            "latest_data_date": md.isoformat() if md else None,
            "date_column": slot["date_col"],
            "age_days": age,
            "files": slot["files"],
            "status": status,
        })
    return {"tables": out}


# ----------------------------------------------------------------------------- #
# Rendering                                                                       #
# ----------------------------------------------------------------------------- #
def build_report(ref):
    platforms = [classify_platform(p, ref) for p in EXPECTED_PLATFORMS]
    # include known-dead platforms that exist on disk but aren't in EXPECTED
    for p in KNOWN_DEAD_PLATFORMS:
        if p not in EXPECTED_PLATFORMS:
            platforms.append(classify_platform(p, ref))
    clusters, cl_summary = scan_vault_clusters()
    firstparty = scan_first_party(ref)

    actionable_red = [p for p in platforms if p["color"] == "RED" and not p["known_dead"]]
    gate_fail = len(actionable_red) > 0

    # Headline severity. RED only when the gate fails (a live platform actually froze).
    # AMBER = attention needed but the scraper itself is fine: an AMBER/known-dead
    # platform, a stale first-party table, or an INVESTIGATE vault cluster.
    attention = (
        any(p["color"] in ("AMBER", "RED") for p in platforms)
        or any(t["status"] == "STALE" for t in firstparty.get("tables", []))
        or any(c["classification"] == "INVESTIGATE" for c in clusters)
    )
    if gate_fail:
        overall = "RED"
    elif attention:
        overall = "AMBER"
    else:
        overall = "GREEN"

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "reference_date": ref.isoformat(),
        "config": CONFIG,
        "overall": overall,
        "gate_fail": gate_fail,
        "actionable_red_platforms": [p["platform"] for p in actionable_red],
        "platforms": platforms,
        "vault_clusters": clusters,
        "vault_summary": cl_summary,
        "first_party": firstparty,
    }


def _badge(color):
    return {"GREEN": "GREEN", "AMBER": "AMBER", "RED": "RED"}.get(color, color)


def render_markdown(rep):
    L = []
    L.append("# DATA FRESHNESS / COVERAGE GUARD")
    L.append("")
    L.append("> Auto-generated by `ecom-intel/tools/freshness_guard.py`. "
             "Catches data series that have **silently frozen** before they reach a graph.")
    L.append("")
    L.append("- **Generated:** %s" % rep["generated_at"])
    L.append("- **Reference date:** %s" % rep["reference_date"])
    L.append("- **Overall:** %s" % _badge(rep["overall"]))
    L.append("- **Cron gate:** %s" % ("FAIL (actionable RED present)" if rep["gate_fail"]
                                       else "pass (no actionable RED)"))
    L.append("")

    # ---- DO NOT GRAPH AS LIVE call-out -------------------------------------------
    dng = []
    for p in rep["platforms"]:
        if p["color"] == "RED":
            tag = " (KNOWN-DEAD, expected)" if p["known_dead"] else " (ACTIONABLE)"
            dng.append("- **%s** — RED%s: %s" % (p["platform"], tag, "; ".join(p["reasons"])))
    for c in rep["vault_clusters"]:
        dng.append("- **vault: %d SKUs frozen at last_seen %s** — %s" % (c["count"], c["date"], c["label"]))
    for t in rep["first_party"].get("tables", []):
        if t["status"] in ("STALE",):
            dng.append("- **first-party `%s`** — STALE: latest data %s (%s days old)"
                       % (t["table"], t["latest_data_date"], t["age_days"]))
    L.append("## DO NOT GRAPH THESE AS LIVE")
    L.append("")
    if dng:
        L.append("The following series are frozen, dead, or stale. Plotting them as current "
                 "produces a misleading flat line:")
        L.append("")
        L.extend(dng)
    else:
        L.append("Nothing frozen — all series current.")
    L.append("")

    # ---- platform table ----------------------------------------------------------
    L.append("## Competitor platform freshness")
    L.append("")
    L.append("| Platform | Status | Latest data | Age (d) | Rows (latest) | SKUs | Notes |")
    L.append("|---|---|---|---|---|---|---|")
    for p in rep["platforms"]:
        notes = "; ".join(p["reasons"])
        if p["notes"]:
            notes += (" — " if notes else "") + "; ".join(p["notes"])
        L.append("| %s | %s | %s | %s | %s | %s | %s |" % (
            p["platform"], _badge(p["color"]),
            p["latest_data_date"] or "—",
            "—" if p["age_days"] is None else p["age_days"],
            p["rows_latest"],
            "—" if p["unique_skus_latest"] is None else p["unique_skus_latest"],
            notes.replace("|", "/"),
        ))
    L.append("")

    # ---- frozen clusters ---------------------------------------------------------
    cs = rep["vault_summary"]
    L.append("## Frozen-SKU clusters in the user-facing vault")
    L.append("")
    L.append("_Scanned %s SKU notes in `ecom/skus/`. Live edge (freshest `last_seen`): "
             "**%s** (%s SKUs). Clusters below are SKUs stuck at an OLDER single date "
             "(threshold: >= %d SKUs)._" % (
                 cs.get("total_notes"), cs.get("freshest_last_seen"),
                 cs.get("live_count"), CONFIG["frozen_cluster_min"]))
    L.append("")
    if rep["vault_clusters"]:
        L.append("| Frozen at | # SKUs | Classification | Platforms (frontmatter) |")
        L.append("|---|---|---|---|")
        for c in rep["vault_clusters"]:
            pb = ", ".join("%s:%d" % (k, v) for k, v in c["platform_breakdown"]) or "—"
            L.append("| %s | %d | **%s** | %s |" % (c["date"], c["count"], c["classification"], pb))
        L.append("")
        for c in rep["vault_clusters"]:
            L.append("- **%s (%d SKUs) — %s**" % (c["date"], c["count"], c["label"]))
            L.append("  - %s" % c["reason"])
        L.append("")
        L.append("> Note: platform counts can exceed the SKU count because a SKU note lists "
                 "every platform it has ever appeared on (multi-platform frontmatter).")
    else:
        L.append("No frozen clusters above threshold.")
    L.append("")

    # ---- first-party -------------------------------------------------------------
    L.append("## First-party tables (`jivo/data/*price*`)")
    L.append("")
    fp = rep["first_party"]
    if fp.get("error"):
        L.append("_%s_" % fp["error"])
    elif fp.get("tables"):
        L.append("_Data date read from the real source column (e.g. `upload_date`), NOT the "
                 "vault-touch column `__last_seen`._")
        L.append("")
        L.append("| Table | Latest data | Date col | Age (d) | Files | Status |")
        L.append("|---|---|---|---|---|---|")
        for t in fp["tables"]:
            L.append("| `%s` | %s | `%s` | %s | %d | %s |" % (
                t["table"], t["latest_data_date"] or "—", t["date_column"] or "—",
                "—" if t["age_days"] is None else t["age_days"], t["files"], t["status"]))
    else:
        L.append("No first-party price tables found.")
    L.append("")

    # ---- legend ------------------------------------------------------------------
    L.append("## How to read this")
    L.append("")
    L.append("- **GREEN** — data updated within %d days." % CONFIG["green_max_age_days"])
    L.append("- **AMBER** — stale %d-%d days, or rows/SKUs dropped sharply vs the trailing median."
             % (CONFIG["green_max_age_days"] + 1, CONFIG["amber_max_age_days"]))
    L.append("- **RED** — no update for > %d days, or zero rows. **Actionable RED gates the cron "
             "(nonzero exit).** Known-dead platforms are RED but excluded from the gate."
             % CONFIG["amber_max_age_days"])
    L.append("- Freshness uses the **freshest** signal across `baselines/<p>.json` AND "
             "`data/<p>/history.csv`, so a lagging baseline on a still-flowing platform does "
             "not raise a false alarm.")
    L.append("")
    return "\n".join(L) + "\n"


def print_summary(rep):
    print("=" * 72)
    print("DATA FRESHNESS GUARD — %s  (overall: %s)" % (rep["reference_date"], rep["overall"]))
    print("=" * 72)
    for p in rep["platforms"]:
        tag = "[%s]" % p["color"]
        extra = ""
        if p["known_dead"]:
            extra = "  (KNOWN-DEAD, no gate)"
        print("  %-6s %-18s latest=%s age=%sd rows=%s skus=%s  %s%s" % (
            tag, p["platform"],
            p["latest_data_date"] or "none",
            "?" if p["age_days"] is None else p["age_days"],
            p["rows_latest"],
            "?" if p["unique_skus_latest"] is None else p["unique_skus_latest"],
            "; ".join(p["reasons"]), extra))
    print("-" * 72)
    cs = rep["vault_summary"]
    print("VAULT: %s notes; live edge last_seen=%s (%s SKUs); %s frozen cluster(s):" % (
        cs.get("total_notes"), cs.get("freshest_last_seen"),
        cs.get("live_count"), len(rep["vault_clusters"])))
    for c in rep["vault_clusters"]:
        pb = ", ".join("%s:%d" % (k, v) for k, v in c["platform_breakdown"][:4])
        print("  [%s] %s  %d SKUs  (%s)" % (c["classification"], c["date"], c["count"], pb))
    print("-" * 72)
    fp = rep["first_party"]
    if fp.get("tables"):
        print("FIRST-PARTY price tables:")
        for t in fp["tables"]:
            print("  [%s] %-22s latest=%s (%s days, col=%s, %d files)" % (
                t["status"], t["table"], t["latest_data_date"], t["age_days"],
                t["date_column"], t["files"]))
    print("-" * 72)
    if rep["gate_fail"]:
        print("GATE: FAIL — actionable RED: %s  (exit 1)" % ", ".join(rep["actionable_red_platforms"]))
    else:
        print("GATE: PASS — no actionable RED (exit 0)")
    print("=" * 72)


# ----------------------------------------------------------------------------- #
# Alerting (--alert)                                                              #
# ----------------------------------------------------------------------------- #
def _read_secret(key):
    v = os.environ.get(key)
    if v:
        return v.strip()
    if os.path.isfile(SECRETS_ENV):
        try:
            for line in open(SECRETS_ENV, "r", encoding="utf-8"):
                line = line.strip()
                if line.startswith(key + "="):
                    return line.split("=", 1)[1].strip().strip('"').strip("'")
        except Exception:
            pass
    return None


def maybe_alert(rep):
    """Best-effort RED alert. Uses the same Telegram pattern as tools/guardian.py."""
    if not (rep["gate_fail"] or any(
            t["status"] == "STALE" for t in rep["first_party"].get("tables", []))):
        print("[--alert] nothing actionable to alert on.")
        return
    lines = ["[ALERT] Jivo price-intel FRESHNESS guard (%s)" % rep["reference_date"]]
    for p in rep["platforms"]:
        if p["color"] == "RED" and not p["known_dead"]:
            lines.append("RED %s: %s" % (p["platform"], "; ".join(p["reasons"])))
    for t in rep["first_party"].get("tables", []):
        if t["status"] == "STALE":
            lines.append("STALE first-party %s: latest %s (%sd old)"
                         % (t["table"], t["latest_data_date"], t["age_days"]))
    for c in rep["vault_clusters"]:
        if c["classification"] == "INVESTIGATE":
            lines.append("INVESTIGATE vault cluster %s: %d SKUs frozen" % (c["date"], c["count"]))
    text = "\n".join(lines)

    tg = _read_secret("TELEGRAM_BOT_TOKEN")
    ch = _read_secret("TELEGRAM_CHAT_ID")
    if tg and ch:
        try:
            subprocess.run(
                ["curl", "-s", "--max-time", "60", "-X", "POST",
                 "https://api.telegram.org/bot%s/sendMessage" % tg,
                 "--data-urlencode", "chat_id=%s" % ch,
                 "--data-urlencode", "text=%s" % text],
                capture_output=True, timeout=70)
            print("[--alert] Telegram alert sent.")
        except Exception as e:
            print("[--alert] Telegram send failed (ignored): %s" % e)
        return

    # ----- HOOK STUB (no notifier configured) -----
    print("[--alert] >>> HOOK STUB: no TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID found "
          "(env or %s)." % SECRETS_ENV)
    print("[--alert] >>> Wire your notifier here (Telegram/Slack/webhook). Payload was:")
    for ln in text.splitlines():
        print("[--alert]     " + ln)


# ----------------------------------------------------------------------------- #
# main                                                                            #
# ----------------------------------------------------------------------------- #
def main(argv):
    do_alert = "--alert" in argv
    # optional --today YYYY-MM-DD
    ref = today_ref()
    for i, a in enumerate(argv):
        if a == "--today" and i + 1 < len(argv):
            d = parse_date(argv[i + 1])
            if d:
                ref = d

    rep = build_report(ref)

    # write outputs (best-effort; never crash the build)
    try:
        with open(OUT_MD, "w", encoding="utf-8") as fh:
            fh.write(render_markdown(rep))
    except Exception as e:
        print("WARN: could not write %s: %s" % (OUT_MD, e), file=sys.stderr)
    try:
        with open(OUT_JSON, "w", encoding="utf-8") as fh:
            json.dump(rep, fh, indent=2, default=str)
    except Exception as e:
        print("WARN: could not write %s: %s" % (OUT_JSON, e), file=sys.stderr)

    print_summary(rep)
    print("\nWrote: %s\nWrote: %s" % (OUT_MD, OUT_JSON))

    if do_alert:
        maybe_alert(rep)

    return 1 if rep["gate_fail"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
