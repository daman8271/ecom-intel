#!/usr/bin/env bash
# seed_durations.sh [target.jsonl] — seed fake duration history for the W4 simulation.
# Writes 10 records per fake platform (alpha~10s beta~25s gamma~40s, slight jitterless
# spread so p90 is meaningful) in W1's schema: {"platform","secs","sweep","ts"}.
# Default target: tools/cron/tests/durations.sim.jsonl (hermetic — pass
# DURATIONS_FILE=<this> to predict_lead/record_duration if W1 supports it; otherwise
# append to the real tools/cron/durations.jsonl, then restore from .pre-sim backup).
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-$TESTS_DIR/durations.sim.jsonl}"
python3 - "$TARGET" <<'PYEOF'
import json, sys, time
target = sys.argv[1]
now = int(time.time())
base = {"alpha": 10, "beta": 25, "gamma": 40}
with open(target, "w") as f:
    for i in range(10):
        for p, secs in base.items():
            # deterministic small spread: p90 lands just above the base duration
            rec = {"platform": p, "secs": secs + (i % 3),
                   "sweep": f"sim-seed-{i}", "ts": now - (10 - i) * 3600}
            f.write(json.dumps(rec) + "\n")
print(f"seeded 30 records -> {target}")
PYEOF
