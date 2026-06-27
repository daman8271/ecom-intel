#!/usr/bin/env python3
"""
warmstart_durations.py [--apply] — seed the deadline predictor for the new pincode count.

predict_lead.py sizes the sweep's lead from p90 of each platform's LAST 10 recorded
durations. Those durations were all measured at ~332 anchors, so the FIRST run after we
add anchors would be under-predicted -> start too late -> land after noon on day 1.

This appends 10 synthetic-but-realistic durations per pincode-DRIVEN platform reflecting
the NEW anchor count, tagged sweep="warmstart-pincode-<date>". Real runs flush them out of
the 10-entry window within ~10 days. National platforms (amazon, flipkart) don't scale and
are left alone.

per-pincode seconds (measured, from cron history): af 13.5, blinkit 12.0, amazon-now 7.7,
zepto 2.1, flipkart-minutes 0.27.
"""
import json, os, sys, glob, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
DUR = os.path.join(HERE, "..", "cron", "durations.jsonl")
DUR = os.path.abspath(DUR)
APPLY = "--apply" in sys.argv

PER_PIN = {"amazon-fresh": 13.5, "blinkit": 12.0, "amazon-now": 7.7,
           "zepto": 2.1, "flipkart-minutes": 0.27}
BASE_N = {"amazon-fresh": 332, "blinkit": 332, "amazon-now": 332,
          "zepto": 332, "flipkart-minutes": 345}

def new_anchor_count():
    n = 0
    for fp in glob.glob("/tmp/claude-0/-root/a109040d-d8ca-400d-acfe-ff278d391f4e/scratchpad/*.anchors.json"):
        n += len(json.load(open(fp)))
    return n

def main():
    A = new_anchor_count()
    if not A:
        sys.exit("no anchors found — run cluster first")
    ts = datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    day = datetime.datetime.now().strftime("%Y%m%d")
    lines = []
    print(f"new anchors = {A}.  Seeding predictor durations for the {332+A}/{345+A}-anchor chain:")
    for p, pp in PER_PIN.items():
        newN = BASE_N[p] + A
        secs = int(round(pp * newN))
        old = int(round(pp * BASE_N[p]))
        print(f"  {p:18s} {BASE_N[p]:4d}->{newN:4d} anchors  ~{old}s -> ~{secs}s/run")
        for i in range(10):
            lines.append(json.dumps({"platform": p, "secs": secs,
                                     "sweep": f"warmstart-pincode-{day}-{i}", "ts": ts}))
    if APPLY:
        with open(DUR, "a") as f:
            f.write("\n".join(lines) + "\n")
        print(f"\nAPPLIED: appended {len(lines)} warm-start durations to {DUR}")
    else:
        print(f"\nDRY-RUN: would append {len(lines)} lines to {DUR}. Use --apply.")

if __name__ == "__main__":
    main()
