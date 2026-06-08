#!/usr/bin/env python3
"""
W3 adversarial regression harness (side-effect-free).

Runs review.py's DETERMINISTIC checks against every platform's CURRENT
result.json without ever calling update_baseline() or write_verdict() — so it
can be run before/after W1's review.py change to prove the only verdict flips
are flipkart (->OK) and zepto (per W2), with the other 6 byte-identical.

The LLM layer is intentionally skipped: it is non-deterministic and can only
downgrade OK->SUSPECT, so it is not part of the deterministic regression gate.

Usage: python3 tools/pricematch/tests/unhold_regress.py [run_id]
Emits a JSON blob (sorted, stable) to stdout: {platform: {verdict, failed_checks}}.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
sys.path.insert(0, os.path.join(ROOT, "tools"))

import review  # noqa: E402

PLATFORMS = [
    "flipkart-minutes", "flipkart", "zepto", "bigbasket",
    "amazon", "amazon-fresh", "amazon-now", "blinkit",
]


def deterministic_verdict(platform, run_id):
    data, _ = review.load_result(platform)
    rows = review.extract_rows(data)
    per_pincode = review.is_per_pincode(data)
    expected = review.baseline_expected(
        review.normalize_baseline(platform, review.load_baseline(platform)))
    checks, reasons, hard_broken, soft_suspect = review.run_checks(
        data, rows, per_pincode, expected, run_id, platform)
    if hard_broken:
        verdict = "BROKEN"
    elif soft_suspect:
        verdict = "SUSPECT"
    else:
        verdict = "OK"
    failed = [{"name": c["name"], "detail": c["detail"]}
              for c in checks if not c["pass"]]
    return verdict, failed


def main(argv):
    run_id = argv[1] if len(argv) > 1 else "2026-06-08-1247"
    out = {}
    for p in PLATFORMS:
        try:
            verdict, failed = deterministic_verdict(p, run_id)
            out[p] = {"verdict": verdict,
                      "failed_checks": [f["name"] for f in failed],
                      "failed_detail": {f["name"]: f["detail"] for f in failed}}
        except Exception as e:
            out[p] = {"verdict": "ERROR", "error": repr(e)}
    print(json.dumps(out, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
