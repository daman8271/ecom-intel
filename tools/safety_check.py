#!/usr/bin/env python3
"""
tools/safety_check.py - daily read-only health snapshot for ecom-intel.

Deterministic, stdlib-only, NEVER mutates anything. Prints a per-check report
and an overall verdict, then exits:  0 = HEALTHY, 1 = DEGRADED, 2 = BROKEN.

Designed to be run by a daily cloud routine (or cron):
    git pull --ff-only && python3 tools/safety_check.py

Checks:
  1. Freshness        - per-platform last data date vs the fleet's newest day
  2. Cadence today    - 'run:' commits landed today, per platform (needs git)
  3. Review verdicts  - latest review verdict per platform (OK/SUSPECT/BROKEN)
  4. Vault freshness  - today's daily note + newest run note
  5. Flipkart guard   - ZERO non-master (non-Jivo) SKUs in flipkart history
                        (regression guard for the 2026-06 noise cleanup)
  6. Dangling links   - vault [[wikilinks]] pointing at a missing note
"""
import csv, json, os, re, glob, subprocess, sys, datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def P(*a): return os.path.join(ROOT, *a)
PLATFORMS = ["amazon", "amazon-fresh", "amazon-now", "bigbasket", "blinkit",
             "flipkart", "flipkart-minutes", "zepto"]

OK, WARN, BAD, UNK = "OK", "WARN", "BAD", "UNKNOWN"
RANK = {OK: 0, WARN: 1, UNK: 1, BAD: 2}
ICON = {OK: "[OK ]", WARN: "[WARN]", BAD: "[BAD]", UNK: "[ ?? ]"}
results = []
def add(name, status, lines):
    results.append((name, status, lines if isinstance(lines, list) else [lines]))
def worse(a, b): return a if RANK[a] >= RANK[b] else b
def dparse(s): return datetime.date.fromisoformat(s) if s else None
def date_of(row):
    m = re.search(r"\d{4}-\d{2}-\d{2}", (row.get("run_id") or row.get("date_ist") or ""))
    return m.group(0) if m else None

# ---- load per-platform history summary -------------------------------------
hist = {}
for p in PLATFORMS:
    try:
        with open(P("data", p, "history.csv"), newline="") as f:
            rows = list(csv.DictReader(f))
        dates = [d for d in (date_of(r) for r in rows) if d]
        last = max(dates) if dates else None
        hist[p] = {"rows": len(rows), "last": last,
                   "last_rows": sum(1 for r in rows if date_of(r) == last) if last else 0}
    except Exception as e:
        hist[p] = {"rows": 0, "last": None, "last_rows": 0, "err": str(e)}

# ---- 1. freshness (relative to the fleet's newest day) ---------------------
try:
    fleet = [hist[p]["last"] for p in PLATFORMS if hist[p]["last"]]
    fleet_latest = max(fleet) if fleet else None
    lines = [f"fleet newest day = {fleet_latest}"]; worst = OK
    for p in PLATFORMS:
        last = hist[p]["last"]
        if not last:
            lines.append(f"{ICON[BAD]} {p:17} NO DATA"); worst = worse(worst, BAD); continue
        behind = (dparse(fleet_latest) - dparse(last)).days
        st = OK if behind == 0 else (WARN if behind == 1 else BAD)
        worst = worse(worst, st)
        tag = "" if behind == 0 else f"  <-- {behind}d behind"
        lines.append(f"{ICON[st]} {p:17} last={last}  rows={hist[p]['rows']}{tag}")
    add("1. Freshness", worst, lines)
except Exception as e:
    add("1. Freshness", UNK, f"check failed: {e}")

# ---- 2. cadence today (git) ------------------------------------------------
try:
    today = datetime.date.today().isoformat()
    out = subprocess.run(["git", "-C", ROOT, "log", f"--since={today} 00:00", "--format=%s"],
                         capture_output=True, text=True, timeout=30).stdout
    cnt = {}
    for ln in out.splitlines():
        m = re.match(r"run: ([a-z0-9-]+)", ln)
        if m: cnt[m.group(1)] = cnt.get(m.group(1), 0) + 1
    lines = [f"'run:' commits since {today} 00:00 (runner clock)"]; worst = OK
    for p in PLATFORMS:
        n = cnt.get(p, 0); st = OK if n > 0 else WARN; worst = worse(worst, st)
        lines.append(f"{ICON[st]} {p:17} {n} run(s) today")
    add("2. Cadence today", worst, lines)
except Exception as e:
    add("2. Cadence today", UNK, f"git unavailable: {e}")

# ---- 3. review verdicts ----------------------------------------------------
try:
    latest = {}  # platform -> (sortkey, run_id, verdict, reasons)
    for fp in glob.glob(P("reviews", "*.json")):
        try: dj = json.load(open(fp))
        except Exception: continue
        pl = dj.get("platform")
        if pl not in PLATFORMS: continue
        key = str(dj.get("captured_at") or dj.get("run_id") or "")   # timestamp beats run_id
        if pl not in latest or key > latest[pl][0]:
            latest[pl] = (key, dj.get("run_id") or "", dj.get("verdict", "UNREVIEWED"), dj.get("reasons") or [])
    vmap = {"OK": OK, "SUSPECT": WARN, "UNREVIEWED": WARN, "BROKEN": BAD}
    lines = []; worst = OK
    for p in PLATFORMS:
        if p not in latest:
            lines.append(f"{ICON[WARN]} {p:17} (no review)"); worst = worse(worst, WARN); continue
        _, rid, v, reasons = latest[p]; st = vmap.get(v, WARN); worst = worse(worst, st)
        extra = f"  - {reasons[0][:64]}" if (st != OK and reasons) else ""
        lines.append(f"{ICON[st]} {p:17} {v:10} {rid}{extra}")
    add("3. Review verdicts", worst, lines)
except Exception as e:
    add("3. Review verdicts", UNK, f"check failed: {e}")

# ---- 4. vault freshness ----------------------------------------------------
try:
    today = datetime.date.today().isoformat(); worst = OK; lines = []
    dailies = sorted(os.path.basename(f)[:-3] for f in glob.glob(P("vault", "daily", "*.md")))
    if os.path.exists(P("vault", "daily", f"{today}.md")):
        lines.append(f"{ICON[OK]} daily note for {today} present")
    else:
        lines.append(f"{ICON[WARN]} no daily note for {today} (newest: {dailies[-1] if dailies else 'none'})")
        worst = worse(worst, WARN)
    runs = glob.glob(P("vault", "runs", "*", "*.md"))
    if runs:
        lines.append(f"newest run note: {max(os.path.basename(r) for r in runs)}")
    add("4. Vault freshness", worst, lines)
except Exception as e:
    add("4. Vault freshness", UNK, f"check failed: {e}")

# ---- 5. flipkart non-Jivo regression guard ---------------------------------
try:
    master = set()
    with open(P("platforms", "flipkart", "skus.master.tsv"), newline="") as f:
        for r in csv.DictReader(f, delimiter="\t"):
            fsn = (r.get("FORMAT SKU Code") or "").strip().upper()
            if re.fullmatch(r"[A-Z0-9]{16}", fsn): master.add(fsn)
    bad = set()
    with open(P("data", "flipkart", "history.csv"), newline="") as f:
        for r in csv.DictReader(f):
            s = (r.get("canonical_sku") or "").strip()
            if s and s.upper() not in master: bad.add(s)
    if bad:
        lines = [f"{ICON[BAD]} {len(bad)} NON-Jivo SKU(s) back in flipkart history -- junk regressed!"]
        lines += [f"   - {s}" for s in sorted(bad)[:8]]
        add("5. Flipkart junk guard", BAD, lines)
    else:
        add("5. Flipkart junk guard", OK,
            f"{ICON[OK]} all flipkart SKUs in master ({len(master)} FSNs); 0 non-Jivo")
except Exception as e:
    add("5. Flipkart junk guard", UNK, f"check failed: {e}")

# ---- 6. dangling vault wikilinks -------------------------------------------
try:
    md = glob.glob(P("vault", "**", "*.md"), recursive=True)
    existing = {os.path.basename(f)[:-3] for f in md}
    dangling = {}
    for f in md:
        if os.path.basename(f) == "VAULT-SPEC.md" or os.sep + "analysis" + os.sep in f:
            continue
        try: t = open(f).read()
        except Exception: continue
        for w in re.findall(r"\[\[([^\]]+)\]\]", t):
            tgt = w.split("|")[0].split("#")[0].strip()
            if tgt and tgt not in existing:
                dangling[tgt] = dangling.get(tgt, 0) + 1
    if dangling:
        top = sorted(dangling.items(), key=lambda kv: -kv[1])
        lines = [f"{ICON[WARN]} {len(dangling)} dangling target(s), {sum(dangling.values())} refs"]
        lines += [f"   - [[{k}]] x{v}" for k, v in top[:8]]
        add("6. Dangling links", WARN, lines)
    else:
        add("6. Dangling links", OK, f"{ICON[OK]} 0 dangling wikilinks")
except Exception as e:
    add("6. Dangling links", UNK, f"check failed: {e}")

# ---- report ----------------------------------------------------------------
overall = OK
for _, st, _ in results: overall = worse(overall, st)
banner = {OK: "HEALTHY", WARN: "DEGRADED", BAD: "BROKEN", UNK: "UNKNOWN"}[overall]
print("=" * 64)
print(f"ecom-intel daily safety check  |  {datetime.datetime.now():%Y-%m-%d %H:%M %Z}".rstrip())
print(f"OVERALL: {banner}")
print("=" * 64)
for name, st, lines in results:
    print(f"\n[{st}] {name}")
    for ln in lines: print("   " + ln)
print()
sys.exit({OK: 0, WARN: 1, UNK: 1, BAD: 2}[overall])
