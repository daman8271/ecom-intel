#!/usr/bin/env python3
"""predict_lead.py — predict how early the sweep must START so it FINISHES by the slot.

Per platform lead = p90 of the last 10 recorded durations  x 1.15  + 120s.
Sources, in order:
  1. tools/cron/durations.jsonl   ({"platform","secs","sweep","ts"} lines, written by
     record_duration.sh from run_all.sh)
  2. bootstrap from logs/cron.log history when a platform has no recorded lines —
     the serial sweeps log "[ts] run_all: running <p> (serial)" so consecutive
     timestamps give each platform's wall duration for free.
  3. defaults: 600s per platform (: 120s — it is currently IP-blocked and
     0-rows fast UNLESS the guardian heal-retries it, which history will reflect).

Prints ONE JSON object: {"<platform>": lead_secs, ..., "total": secs}.
total = sum(per-platform leads) + 600s sweep buffer (self-heal/vault/git tail),
clamped to [1200, LEAD_MAX-120]   (LEAD_MAX env, default 7200).

Modes:
  predict_lead.py                  -> print the prediction JSON
  predict_lead.py --bootstrap      -> parse logs/cron.log and APPEND any sweep
                                      durations not already in durations.jsonl
                                      (idempotent: keyed on (platform, sweep)).

Env:
  PLATFORMS_OVERRIDE  space-separated platform list (testing; default = the 9 live)
  LEAD_MAX            clamp ceiling input, seconds (default 7200)

Fail-safe: any parse error degrades to defaults — this script must never leave
the sweep without a usable number.
"""
import json
import math
import os
import re
import sys
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))          # tools/cron -> repo root
# DURATIONS_FILE env override keeps W4's sim hermetic (never touches real history)
DURATIONS = os.environ.get("DURATIONS_FILE") or os.path.join(HERE, "durations.jsonl")
CRON_LOG = os.path.join(ROOT, "logs", "cron.log")

CANONICAL = [
    "", "flipkart-minutes", "flipkart", "zepto", "bigbasket",
    "amazon", "amazon-fresh", "amazon-now", "blinkit",
]

DEFAULT_LEAD = 600
DEFAULT_LEAD_BY_PLATFORM = {"": 120}
PER_PLATFORM_PAD = 120      # fixed safety pad per platform, seconds
P90_MULT = 1.15             # multiplicative margin on the p90
SWEEP_BUFFER = 600          # tail: self-heal pass + vault rebuild + git
LAST_N = 10                 # window of most-recent durations per platform

LOG_LINE = re.compile(
    r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] run_all: "
    r"(?:running (\S+) \(serial\)|all platforms done|START)"
)


def platforms():
    ov = os.environ.get("PLATFORMS_OVERRIDE", "").split()
    return ov if ov else CANONICAL


def load_recorded():
    """durations.jsonl -> {platform: [(ts_str, secs), ...]} plus seen (p, sweep) keys."""
    by_p, seen = {}, set()
    try:
        with open(DURATIONS) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    d = json.loads(line)
                    p, secs = d["platform"], int(d["secs"])
                except Exception:
                    continue
                by_p.setdefault(p, []).append((str(d.get("ts", "")), secs))
                seen.add((p, str(d.get("sweep", ""))))
    except OSError:
        pass
    return by_p, seen


def parse_cron_log():
    """logs/cron.log serial-sweep history -> [(platform, secs, sweep_id, ts_iso)].

    A platform's duration = its "running <p>" timestamp to the NEXT
    "running"/"all platforms done" line of the same sweep (resets on START).
    sweep_id = log-<YYYY-MM-DD-HHMM> of the sweep's first platform line.
    """
    out = []
    prev = None        # (platform, datetime)
    sweep_id = None
    try:
        with open(CRON_LOG, errors="replace") as f:
            for line in f:
                m = LOG_LINE.match(line)
                if not m:
                    continue
                ts = datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S")
                plat = m.group(2)
                if "START" in line and plat is None:
                    prev, sweep_id = None, None
                    continue
                if prev is not None:
                    secs = int((ts - prev[1]).total_seconds())
                    if 0 < secs < 6 * 3600:      # sanity: drop junk/log gaps
                        out.append((prev[0], secs, sweep_id, prev[1].isoformat()))
                if plat is not None:             # a "running <p>" line
                    if sweep_id is None:
                        sweep_id = "log-" + ts.strftime("%Y-%m-%d-%H%M")
                    prev = (plat, ts)
                else:                            # "all platforms done" closes the sweep
                    prev, sweep_id = None, None
    except OSError:
        pass
    return out


def p90(values):
    """Nearest-rank p90 over the LAST_N most recent values."""
    vals = sorted(values[-LAST_N:])
    idx = max(0, math.ceil(0.9 * len(vals)) - 1)
    return vals[idx]


def lead_for(durs):
    return int(round(p90(durs) * P90_MULT)) + PER_PLATFORM_PAD


def predict():
    recorded, _ = load_recorded()
    log_durs = None     # lazy: only parse cron.log if some platform needs it
    leads = {}
    for p in platforms():
        entries = recorded.get(p, [])
        if len(entries) < 3:
            if log_durs is None:
                bl = {}
                for plat, secs, _sw, ts in parse_cron_log():
                    bl.setdefault(plat, []).append((ts, secs))
                log_durs = bl
            # merge log history under the recorded entries, keep chronology
            entries = sorted(log_durs.get(p, []) + entries)
        if entries:
            leads[p] = lead_for([s for _t, s in entries])
        else:
            leads[p] = DEFAULT_LEAD_BY_PLATFORM.get(p, DEFAULT_LEAD)

    lead_max = 7200
    try:
        lead_max = int(os.environ.get("LEAD_MAX", "7200"))
    except ValueError:
        pass
    total = sum(leads.values()) + SWEEP_BUFFER
    # CLAMP ORDER MATTERS (W4): raise to the 1200s floor FIRST, then apply the
    # LEAD_MAX cap LAST so a small LEAD_MAX (e.g. sim LEAD_MAX=300 -> cap 180)
    # always wins. max()-last would silently re-inflate to 1200.
    total = min(max(total, 1200), max(lead_max - 120, 60))
    out = dict(leads)
    out["total"] = total
    return out


def bootstrap():
    """Append cron.log-derived durations missing from durations.jsonl (idempotent)."""
    _, seen = load_recorded()
    added = 0
    with open(DURATIONS, "a") as f:
        for plat, secs, sweep, ts in parse_cron_log():
            if (plat, sweep) in seen:
                continue
            seen.add((plat, sweep))
            f.write(json.dumps(
                {"platform": plat, "secs": secs, "sweep": sweep, "ts": ts}) + "\n")
            added += 1
    print(f"bootstrap: appended {added} duration lines from logs/cron.log", file=sys.stderr)


def main():
    if "--bootstrap" in sys.argv[1:]:
        bootstrap()
        return
    try:
        out = predict()
    except Exception as e:                                  # absolute fail-safe
        print(f"predict_lead: degraded to defaults ({e})", file=sys.stderr)
        out = {p: DEFAULT_LEAD_BY_PLATFORM.get(p, DEFAULT_LEAD) for p in platforms()}
        try:
            lead_max = int(os.environ.get("LEAD_MAX", "7200"))
        except ValueError:
            lead_max = 7200
        out["total"] = min(max(sum(out.values()) + SWEEP_BUFFER, 1200),
                           max(lead_max - 120, 60))
    print(json.dumps(out))


if __name__ == "__main__":
    main()
