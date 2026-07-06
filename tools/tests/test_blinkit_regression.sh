#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

(cd platforms/blinkit && npm test)
tools/cron/tests/test_blinkit_quality_monitor.sh
python3 -m unittest discover -s tools/pricematch/tests

node -c platforms/blinkit/scrape.js
python3 -m py_compile platforms/blinkit/build_excel.py tools/pricematch/pricematch_core.py
bash -n platforms/blinkit/ingest.sh tools/cron/blinkit_quality_monitor.sh tools/cron/tests/test_blinkit_quality_monitor.sh

echo "PASS blinkit regression suite"
