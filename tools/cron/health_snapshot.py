#!/usr/bin/env python3
"""
tools/cron/health_snapshot.py [--scope daily|weekly|monthly] [--json]

Ecom Doctor — deterministic health collector. Reads EXISTING artifacts only
(reviews/, baselines/, logs/, platforms/<p>/result.json, tools/pricematch/*.summary.json,
tools/cron/durations.jsonl). NO scraping, NO network, pure stdlib.

It emits one structured JSON health report (schema posted on the doctor bus). The
report — not the exit code — is the product: this tool ALWAYS exits 0 so the
orchestrator (doctor.sh) can react. Any single signal that errors is degraded into
a YELLOW "collector_error" issue rather than crashing the whole snapshot.

The headline signal: **held_streak** — a platform whose most-recent consecutive
sweep reviews are verdict != OK. That is the exact failure mode that went silent
for 2 days (flipkart+zepto SUSPECT-HELD, nobody alerted).

Output: {scope, ts, date, overall: GREEN|YELLOW|RED, issues:[...], stats:{...}}
With --json (or by default) prints the JSON to stdout. Always also returns it.
"""

import os
import re
import sys
import json
import glob
import time
import shutil
import datetime
import subprocess
import traceback

# ---- paths (resolve relative to repo root = parent of tools/) --------------
# HEALTH_ROOT env override lets W3's dry-run point the collector at a FIXTURE repo
# (a temp dir staging reviews/ baselines/ logs/ platforms/) so detection can be
# tested without touching the live repo. Unset => the real repo.
CRON_DIR = os.path.dirname(os.path.abspath(__file__))
TOOLS_DIR = os.path.dirname(CRON_DIR)
ROOT = os.environ.get("HEALTH_ROOT") or os.path.dirname(TOOLS_DIR)
REVIEWS_DIR = os.path.join(ROOT, "reviews")
BASELINES_DIR = os.path.join(ROOT, "baselines")
LOGS_DIR = os.path.join(ROOT, "logs")
PLATFORMS_DIR = os.path.join(ROOT, "platforms")
PRICEMATCH_DIR = os.path.join(ROOT, "tools", "pricematch")
CRON_LOG = os.path.join(LOGS_DIR, "cron.log")
DURATIONS = os.path.join(ROOT, "tools", "cron", "durations.jsonl")

# ---- the canonical live platform list (matches run_all.sh) ------------------
LIVE_PLATFORMS = [
    "flipkart-minutes", "flipkart", "zepto", "bigbasket",
    "amazon", "amazon-fresh", "amazon-now", "blinkit",
]

# ---- deadline slots (IST) the cron must land; used to detect missing batch --
SWEEP_SLOTS = ["1200"]           # single noon batch (owner cut 2x->1x 2026-06-28; was 1200+1500)
SLOT_GRACE_MIN = 30              # only flag a slot missing this long after its time

# ---- thresholds -------------------------------------------------------------
HELD_STREAK_FLAG = 2            # >= 2 consecutive non-OK sweeps = YELLOW
ROWS_COLLAPSE_PCT = 50         # latest rows < 50% of baseline mean = collapse
SKUS_COLLAPSE_PCT = 70         # latest SKUs  < 70% of baseline mean = collapse
FRESHNESS_MAX_AGE_H = 15       # matches review.py / healthcheck.sh
SWEEP_RUNID_RE = re.compile(r"^\d{4}-\d{2}-\d{2}-\d{4}$")  # real sweep run-ids only

IST = datetime.timezone(datetime.timedelta(hours=5, minutes=30))
UTC = datetime.timezone.utc


# ============================================================================
# small helpers
# ============================================================================
def now_utc():
    return datetime.datetime.now(UTC)


def now_ist():
    return now_utc().astimezone(IST)


def ist_date_str():
    return now_ist().strftime("%Y-%m-%d")


def jload(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def parse_iso(s):
    """Lenient ISO8601 -> aware datetime (UTC). None on failure."""
    if not s:
        return None
    try:
        dt = datetime.datetime.fromisoformat(str(s).replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=UTC)
        return dt
    except Exception:
        return None


def review_run_id(platform, path):
    """reviews/<platform>-<run_id>.json -> run_id (strip exactly the platform prefix)."""
    base = os.path.basename(path)[:-5]  # drop .json
    prefix = platform + "-"
    if base.startswith(prefix):
        return base[len(prefix):]
    return None


def sweep_reviews_for(platform):
    """All (run_id, path) for a platform whose run_id is a real sweep, newest first.

    Globbing reviews/<p>-*.json also catches sibling platforms (flipkart vs
    flipkart-minutes vs flipkart-daily); the SWEEP_RUNID_RE filter rejects those
    because their leftover run_id starts with 'minutes-' / 'daily-' / a test tag.
    """
    out = []
    for path in glob.glob(os.path.join(REVIEWS_DIR, f"{platform}-*.json")):
        rid = review_run_id(platform, path)
        if rid and SWEEP_RUNID_RE.match(rid):
            out.append((rid, path))
    # run_ids are YYYY-MM-DD-HHMM -> lexicographic sort == chronological
    out.sort(key=lambda t: t[0], reverse=True)
    return out


def baseline_mean(platform):
    """Mean rows/unique_skus/priced_rows over baseline samples. {} on any failure."""
    path = os.path.join(BASELINES_DIR, f"{platform}.json")
    try:
        bl = jload(path)
    except Exception:
        return {}
    samples = bl.get("samples") if isinstance(bl, dict) else None
    if not samples:
        return {}

    def avg(key):
        vals = [s[key] for s in samples
                if isinstance(s.get(key), (int, float))]
        return (sum(vals) / len(vals)) if vals else None

    return {
        "rows": avg("rows"),
        "unique_skus": avg("unique_skus"),
        "priced_rows": avg("priced_rows"),
        "n": len(samples),
    }


# ============================================================================
# signal collectors — each returns (issues, stats_fragment) and never raises
# ============================================================================
def collect_platforms(scope):
    """held_streak + coverage_collapse + freshness per live platform."""
    issues = []
    pstats = {}

    for p in LIVE_PLATFORMS:
        st = {"held_streak": 0, "last_verdict": None, "last_run_id": None,
              "last_reasons": [], "rows": None, "baseline_rows": None,
              "rows_pct": None, "skus": None, "captured_age_h": None}
        try:
            sweeps = sweep_reviews_for(p)
            base = baseline_mean(p)
            st["baseline_rows"] = round(base["rows"]) if base.get("rows") else None

            # --- held_streak: leading run of verdict != OK -------------------
            streak = 0
            streak_reasons = []
            for rid, path in sweeps:
                try:
                    rv = jload(path)
                except Exception:
                    break
                verdict = rv.get("verdict")
                if streak == 0:
                    st["last_verdict"] = verdict
                    st["last_run_id"] = rid
                    st["last_reasons"] = rv.get("reasons") or []
                    st["rows"] = rv.get("rows")
                    st["skus"] = rv.get("unique_skus")
                if verdict and verdict != "OK":
                    streak += 1
                    streak_reasons.append(
                        f"{rid}={verdict}: " + "; ".join((rv.get('reasons') or [])[:2])
                    )
                else:
                    break
            st["held_streak"] = streak

            if streak >= HELD_STREAK_FLAG:
                # BROKEN in the streak -> RED, otherwise (SUSPECT held) -> YELLOW
                verdicts = streak_reasons
                sev = "RED" if any("=BROKEN" in r for r in verdicts) else "YELLOW"
                issues.append({
                    "id": f"held_streak:{p}",
                    "severity": sev,
                    "platform": p,
                    "signal": "held_streak",
                    "detail": f"{p} held {streak} consecutive sweeps "
                              f"(verdict != OK, latest={st['last_verdict']})",
                    "evidence": " | ".join(streak_reasons[:4]),
                })

            # --- coverage_collapse vs baseline mean --------------------------
            if st["rows"] is not None and base.get("rows"):
                pct = round(100.0 * st["rows"] / base["rows"], 1)
                st["rows_pct"] = pct
                if pct < ROWS_COLLAPSE_PCT and st["last_verdict"] == "OK":
                    # only flag as a fresh issue when review itself passed (else
                    # held_streak already owns it) — avoids double-alerting.
                    issues.append({
                        "id": f"coverage_collapse:{p}",
                        "severity": "YELLOW",
                        "platform": p,
                        "signal": "coverage_collapse",
                        "detail": f"{p} rows {st['rows']} = {pct}% of baseline "
                                  f"{round(base['rows'])} (OK-verdict but thin)",
                        "evidence": f"rows={st['rows']} baseline_mean={round(base['rows'])} "
                                    f"n={base.get('n')}",
                    })
            if (st["skus"] is not None and base.get("unique_skus")
                    and st["last_verdict"] == "OK"):
                spct = round(100.0 * st["skus"] / base["unique_skus"], 1)
                if spct < SKUS_COLLAPSE_PCT:
                    issues.append({
                        "id": f"sku_collapse:{p}",
                        "severity": "YELLOW",
                        "platform": p,
                        "signal": "coverage_collapse",
                        "detail": f"{p} SKUs {st['skus']} = {spct}% of baseline "
                                  f"{round(base['unique_skus'])}",
                        "evidence": f"skus={st['skus']} baseline_mean="
                                    f"{round(base['unique_skus'])}",
                    })

            # --- freshness: result.json captured_at age ----------------------
            rj = os.path.join(PLATFORMS_DIR, p, "result.json")
            cap = None
            try:
                d = jload(rj)
                cap = (d.get("summary") or {}).get("captured_at") or d.get("captured_at")
            except Exception:
                cap = None
            cdt = parse_iso(cap)
            if cdt is not None:
                age_h = round((now_utc() - cdt).total_seconds() / 3600.0, 1)
                st["captured_age_h"] = age_h
                if age_h > FRESHNESS_MAX_AGE_H:
                    issues.append({
                        "id": f"freshness:{p}",
                        "severity": "YELLOW",
                        "platform": p,
                        "signal": "freshness",
                        "detail": f"{p} result.json is {age_h}h old "
                                  f"(> {FRESHNESS_MAX_AGE_H}h threshold)",
                        "evidence": f"captured_at={cap}",
                    })
        except Exception as e:
            issues.append({
                "id": f"collector_error:platforms:{p}",
                "severity": "YELLOW", "platform": p, "signal": "errors",
                "detail": f"health collector errored on {p}: {e}",
                "evidence": traceback.format_exc()[-400:],
            })
        pstats[p] = st

    return issues, pstats


def collect_batches(scope):
    """Did today's 12:00 batch deliver? Parse logs/cron.log send_batch lines."""
    issues = []
    batches = {}
    today = ist_date_str()
    delivered_re = re.compile(
        r"send_batch:\s*sweep\s+(\S+):\s*batch delivered "
        r"\((\d+) reports?, (\d+) held, (\d+) missing\)"
    )
    try:
        if os.path.exists(CRON_LOG):
            with open(CRON_LOG, "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    m = delivered_re.search(line)
                    if not m:
                        continue
                    sweep = m.group(1)
                    if not sweep.startswith(today):
                        continue
                    batches[sweep] = {
                        "delivered": True,
                        "reports": int(m.group(2)),
                        "held": int(m.group(3)),
                        "missing": int(m.group(4)),
                    }

        # missing-batch detection: a slot whose time + grace has passed today
        # but for which no delivered line exists => RED.
        now = now_ist()
        for slot in SWEEP_SLOTS:
            sweep_id = f"{today}-{slot}"
            hh, mm = int(slot[:2]), int(slot[2:])
            slot_dt = now.replace(hour=hh, minute=mm, second=0, microsecond=0)
            grace_dt = slot_dt + datetime.timedelta(minutes=SLOT_GRACE_MIN)
            b = batches.get(sweep_id)
            if b is None:
                if now > grace_dt:
                    issues.append({
                        "id": f"batch_missing:{sweep_id}",
                        "severity": "RED",
                        "platform": None,
                        "signal": "batch_delivery",
                        "detail": f"sweep {sweep_id} batch did NOT deliver "
                                  f"(no send_batch line {SLOT_GRACE_MIN}min past slot)",
                        "evidence": f"searched {CRON_LOG} for 'sweep {sweep_id}: batch delivered'",
                    })
                    batches[sweep_id] = {"delivered": False, "reports": 0,
                                         "held": None, "missing": None}
            else:
                if b["missing"] and b["missing"] > 0:
                    issues.append({
                        "id": f"batch_missing_reports:{sweep_id}",
                        "severity": "RED",
                        "platform": None,
                        "signal": "batch_delivery",
                        "detail": f"sweep {sweep_id} delivered but {b['missing']} report(s) MISSING",
                        "evidence": f"reports={b['reports']} held={b['held']} missing={b['missing']}",
                    })
                elif b["held"] and b["held"] > 0:
                    issues.append({
                        "id": f"batch_held:{sweep_id}",
                        "severity": "YELLOW",
                        "platform": None,
                        "signal": "batch_delivery",
                        "detail": f"sweep {sweep_id} delivered with {b['held']} platform(s) HELD",
                        "evidence": f"reports={b['reports']} held={b['held']} missing={b['missing']}",
                    })
    except Exception as e:
        issues.append({
            "id": "collector_error:batches", "severity": "YELLOW",
            "platform": None, "signal": "batch_delivery",
            "detail": f"batch collector errored: {e}",
            "evidence": traceback.format_exc()[-400:],
        })
    return issues, batches


def collect_errors(scope):
    """Tracebacks / BROKEN / 'lock not acquired' / FAILED in today's cron.log + run-*.out."""
    issues = []
    today = ist_date_str()
    hits = []
    # cron.log: only today's dated lines
    try:
        if os.path.exists(CRON_LOG):
            with open(CRON_LOG, "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    if not line.startswith(f"[{today}"):
                        continue
                    low = line
                    if ("Traceback" in low or "BROKEN" in low
                            or "lock not acquired" in low or "FAILED" in low):
                        hits.append(("cron.log", line.rstrip()[:300]))
    except Exception as e:
        issues.append({
            "id": "collector_error:errors:cron", "severity": "YELLOW",
            "platform": None, "signal": "errors",
            "detail": f"error-scan of cron.log failed: {e}",
            "evidence": traceback.format_exc()[-300:],
        })

    # run-*.out tails (these are overwritten per run, so the whole tail is "recent")
    try:
        for outp in glob.glob(os.path.join(LOGS_DIR, "run-*.out")):
            try:
                # only consider files modified today (IST)
                mtime = datetime.datetime.fromtimestamp(os.path.getmtime(outp), UTC)
                if mtime.astimezone(IST).strftime("%Y-%m-%d") != today:
                    continue
                with open(outp, "r", encoding="utf-8", errors="replace") as f:
                    tail = f.readlines()[-60:]
                for line in tail:
                    if ("Traceback" in line or "BROKEN" in line or "FAILED" in line):
                        hits.append((os.path.basename(outp), line.rstrip()[:300]))
            except Exception:
                continue
    except Exception:
        pass

    # roll up hits into at most a few issues (BROKEN/Traceback => RED-ish, but a
    # BROKEN review is already owned by held_streak; here it's a corroborating signal)
    if hits:
        broken = [h for h in hits if "BROKEN" in h[1] or "Traceback" in h[1]
                  or "FAILED" in h[1]]
        sev = "YELLOW"   # log-scan corroborates; held_streak/batch own RED escalation
        sample = "; ".join(f"{src}: {txt}" for src, txt in hits[:5])
        issues.append({
            "id": "errors:today_logs",
            "severity": sev,
            "platform": None,
            "signal": "errors",
            "detail": f"{len(hits)} error-marker line(s) in today's logs "
                      f"({len(broken)} BROKEN/Traceback/FAILED)",
            "evidence": sample[:900],
        })
    return issues, {"error_hits": len(hits)}


def collect_chain(scope):
    """Sweep timing / lock contention / durations drift from cron.log + durations.jsonl."""
    issues = []
    stats = {"last_sweep": None, "platform_secs": {}, "lock_contention": 0}
    today = ist_date_str()
    try:
        # latest durations per platform (whole-ledger last value per platform)
        if os.path.exists(DURATIONS):
            with open(DURATIONS, "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        rec = json.loads(line)
                    except Exception:
                        continue
                    p = rec.get("platform")
                    if p:
                        stats["platform_secs"][p] = rec.get("secs")
                        stats["last_sweep"] = rec.get("sweep") or stats["last_sweep"]
        # lock contention notes in today's cron.log (informational, not alarm)
        if os.path.exists(CRON_LOG):
            with open(CRON_LOG, "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    if line.startswith(f"[{today}") and "sweep-chain.lock busy" in line:
                        stats["lock_contention"] += 1
        # chain lateness: a delivered batch whose deadline we missed shows as
        # "holding batch ... until" (early) vs an overshoot. Overshoot is rare;
        # we surface contention only as a YELLOW when it actually stacked sweeps.
        if stats["lock_contention"] >= 2:
            issues.append({
                "id": "chain:lock_contention",
                "severity": "YELLOW",
                "platform": None,
                "signal": "chain",
                "detail": f"{stats['lock_contention']} sweep-chain lock contention "
                          f"events today (sweeps overlapping)",
                "evidence": "logs/cron.log: 'logs/.sweep-chain.lock busy'",
            })
    except Exception as e:
        issues.append({
            "id": "collector_error:chain", "severity": "YELLOW",
            "platform": None, "signal": "chain",
            "detail": f"chain collector errored: {e}",
            "evidence": traceback.format_exc()[-300:],
        })
    return issues, stats


def collect_pricematch(scope):
    """Price-match exposure trend from tools/pricematch/*.summary.json sidecars."""
    stats = {"latest_date": None, "exposure": None, "below": None, "trend": []}
    issues = []
    try:
        files = sorted(glob.glob(os.path.join(PRICEMATCH_DIR, "*.summary.json")))
        trend = []
        for fp in files[-30:]:
            try:
                d = jload(fp)
                k = d.get("kpis") or {}
                trend.append({
                    "date": d.get("date"),
                    "exposure": k.get("exposure"),
                    "below": k.get("below"),
                })
            except Exception:
                continue
        stats["trend"] = trend
        if trend:
            last = trend[-1]
            stats["latest_date"] = last.get("date")
            stats["exposure"] = last.get("exposure")
            stats["below"] = last.get("below")
    except Exception as e:
        issues.append({
            "id": "collector_error:pricematch", "severity": "YELLOW",
            "platform": None, "signal": "freshness",
            "detail": f"pricematch collector errored: {e}",
            "evidence": traceback.format_exc()[-300:],
        })
    return issues, stats


def collect_disk_process(scope):
    """df on the repo fs + orphaned node/python scan."""
    issues = []
    stats = {"pct_used": None, "avail": None, "orphan_node": 0, "orphan_python": 0}
    try:
        usage = shutil.disk_usage(ROOT)
        pct = round(100.0 * usage.used / usage.total)
        stats["pct_used"] = pct
        stats["avail"] = f"{usage.free // (1024**3)}G"
        if pct >= 95:
            issues.append({
                "id": "disk:full", "severity": "RED", "platform": None,
                "signal": "disk_process",
                "detail": f"repo filesystem {pct}% full ({stats['avail']} free)",
                "evidence": f"shutil.disk_usage({ROOT})",
            })
        elif pct >= 85:
            issues.append({
                "id": "disk:high", "severity": "YELLOW", "platform": None,
                "signal": "disk_process",
                "detail": f"repo filesystem {pct}% full ({stats['avail']} free)",
                "evidence": f"shutil.disk_usage({ROOT})",
            })
    except Exception as e:
        issues.append({
            "id": "collector_error:disk", "severity": "YELLOW",
            "platform": None, "signal": "disk_process",
            "detail": f"disk collector errored: {e}",
            "evidence": traceback.format_exc()[-300:],
        })

    # orphaned node/python — best-effort; absence of pgrep just yields 0
    for name, key in (("node", "orphan_node"), ("playwright", "orphan_node")):
        pass
    try:
        out = subprocess.run(["pgrep", "-af", "node"], capture_output=True,
                             text=True, timeout=10)
        if out.returncode == 0:
            # count node procs that look like scrapers but whose run is long gone
            lines = [l for l in out.stdout.splitlines()
                     if "scrape" in l or "playwright" in l]
            stats["orphan_node"] = len(lines)
    except Exception:
        pass
    try:
        out = subprocess.run(["pgrep", "-af", "python"], capture_output=True,
                             text=True, timeout=10)
        if out.returncode == 0:
            lines = [l for l in out.stdout.splitlines()
                     if "build_excel" in l or "review.py" in l]
            stats["orphan_python"] = len(lines)
    except Exception:
        pass
    return issues, stats


# ============================================================================
# weekly / monthly trend rollups (additive)
# ============================================================================
def collect_trends(scope, pstats):
    """held-platform frequency, recurring SUSPECT reasons, coverage trend over N days."""
    days = 7 if scope == "weekly" else 30
    stats = {"window_days": days, "held_frequency": {}, "recurring_reasons": {},
             "coverage_trend": {}}
    issues = []
    try:
        cutoff = (now_utc() - datetime.timedelta(days=days))
        reason_counter = {}
        for p in LIVE_PLATFORMS:
            held_count = 0
            total = 0
            rows_series = []
            for rid, path in sweep_reviews_for(p):
                # rid date prefix
                try:
                    d = datetime.datetime.strptime(rid[:10], "%Y-%m-%d").replace(tzinfo=UTC)
                except Exception:
                    continue
                if d < cutoff:
                    continue
                try:
                    rv = jload(path)
                except Exception:
                    continue
                total += 1
                if rv.get("verdict") and rv.get("verdict") != "OK":
                    held_count += 1
                    for r in (rv.get("reasons") or []):
                        key = r.split(":")[0][:60]
                        reason_counter[key] = reason_counter.get(key, 0) + 1
                if isinstance(rv.get("rows"), (int, float)):
                    rows_series.append(rv["rows"])
            if total:
                stats["held_frequency"][p] = {
                    "held": held_count, "total": total,
                    "pct": round(100.0 * held_count / total, 1),
                }
            if rows_series:
                stats["coverage_trend"][p] = {
                    "min": min(rows_series), "max": max(rows_series),
                    "avg": round(sum(rows_series) / len(rows_series)),
                    "n": len(rows_series),
                }
        # top recurring reasons
        stats["recurring_reasons"] = dict(
            sorted(reason_counter.items(), key=lambda kv: kv[1], reverse=True)[:10]
        )
        # a platform held in a majority of the window's sweeps -> chronic YELLOW
        for p, hf in stats["held_frequency"].items():
            if hf["total"] >= 4 and hf["pct"] >= 50:
                issues.append({
                    "id": f"chronic_held:{p}",
                    "severity": "YELLOW",
                    "platform": p,
                    "signal": "held_streak",
                    "detail": f"{p} held in {hf['held']}/{hf['total']} sweeps "
                              f"over {days}d ({hf['pct']}%) — chronic",
                    "evidence": f"window={days}d held_frequency={hf}",
                })
    except Exception as e:
        issues.append({
            "id": "collector_error:trends", "severity": "YELLOW",
            "platform": None, "signal": "errors",
            "detail": f"trend collector errored: {e}",
            "evidence": traceback.format_exc()[-300:],
        })
    return issues, stats


# ============================================================================
# main assembly
# ============================================================================
def build_report(scope):
    issues = []
    stats = {}

    pl_issues, pstats = collect_platforms(scope)
    issues += pl_issues
    stats["platforms"] = pstats

    b_issues, batches = collect_batches(scope)
    issues += b_issues
    stats["batches"] = batches

    e_issues, estats = collect_errors(scope)
    issues += e_issues
    stats["errors"] = estats

    c_issues, cstats = collect_chain(scope)
    issues += c_issues
    stats["chain"] = cstats

    pm_issues, pmstats = collect_pricematch(scope)
    issues += pm_issues
    stats["pricematch"] = pmstats

    d_issues, dstats = collect_disk_process(scope)
    issues += d_issues
    stats["disk"] = {"pct_used": dstats["pct_used"], "avail": dstats["avail"]}
    stats["process"] = {"orphan_node": dstats["orphan_node"],
                        "orphan_python": dstats["orphan_python"]}

    if scope in ("weekly", "monthly"):
        t_issues, tstats = collect_trends(scope, pstats)
        issues += t_issues
        stats["trends"] = tstats

    # overall severity
    sev_rank = {"GREEN": 0, "YELLOW": 1, "RED": 2}
    overall = "GREEN"
    for i in issues:
        if sev_rank.get(i.get("severity"), 0) > sev_rank[overall]:
            overall = i["severity"]

    return {
        "scope": scope,
        "ts": now_utc().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "date": ist_date_str(),
        "overall": overall,
        "issues": issues,
        "stats": stats,
    }


def main(argv):
    scope = "daily"
    want_json = False
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--scope" and i + 1 < len(argv):
            scope = argv[i + 1]
            i += 2
            continue
        if a == "--json":
            want_json = True
        i += 1
    if scope not in ("daily", "weekly", "monthly"):
        scope = "daily"

    try:
        report = build_report(scope)
    except Exception as e:
        # absolute last-resort: never crash; emit a RED self-report
        report = {
            "scope": scope,
            "ts": now_utc().strftime("%Y-%m-%dT%H:%M:%SZ"),
            "date": ist_date_str(),
            "overall": "RED",
            "issues": [{
                "id": "collector_error:fatal", "severity": "RED",
                "platform": None, "signal": "errors",
                "detail": f"health_snapshot fatal error: {e}",
                "evidence": traceback.format_exc()[-600:],
            }],
            "stats": {},
        }

    # --json is the default behavior anyway; always print the JSON product.
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
