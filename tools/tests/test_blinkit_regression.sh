#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

(cd platforms/blinkit && npm test)
tools/cron/tests/test_blinkit_quality_monitor.sh
bash tools/mailer/tests/test_blinkit_quality_holdback.sh
bash tools/mailer/tests/test_blinkit_main_direct_whatsapp.sh
bash tools/mailer/tests/test_blinkit_not_listed_direct_whatsapp.sh
python3 -m unittest discover -s tools/pricematch/tests

node -c platforms/blinkit/scrape.js
python3 -m py_compile platforms/blinkit/build_excel.py tools/pricematch/pricematch_core.py
bash -n platforms/blinkit/ingest.sh tools/cron/blinkit_quality_monitor.sh tools/cron/tests/test_blinkit_quality_monitor.sh tools/mailer/mail_price_data.sh tools/mailer/tests/test_blinkit_quality_holdback.sh tools/mailer/tests/test_blinkit_main_direct_whatsapp.sh tools/mailer/tests/test_blinkit_not_listed_direct_whatsapp.sh tools/whatsapp/send_blinkit_main_direct.sh

echo "PASS blinkit regression suite"
