#!/usr/bin/env bash
# run_all.sh — one cron-triggered sweep: scrape every LIVE platform SEQUENTIALLY,
# then run the self-heal pass.
#
# Why sequential (not the old staggered per-platform cron lines): at ~796 pincodes
# a single Blinkit run is ~30+ min, which would overlap every other platform and
# the healthcheck on this single VPS (4 concurrent Chromium = OOM/chaos). Running
# them one after another keeps exactly one heavy scrape alive at a time. The 3-hour
# gaps between windows (09/12/16 IST) comfortably fit the full ~35-40 min sweep.
#
# Each ./run.sh <p> is self-contained (scrape -> excel -> review -> vault -> telegram
# -> git push) and best-effort; one platform failing must not stop the rest.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
echo "[$(date '+%F %T')] run_all: START"
for P in blinkit flipkart-minutes flipkart amazon; do
  echo "[$(date '+%F %T')] run_all: -> $P"
  ./run.sh "$P" || echo "[$(date '+%F %T')] run_all: $P exited non-zero (continuing)"
done
echo "[$(date '+%F %T')] run_all: -> self-heal pass"
./healthcheck.sh || true
echo "[$(date '+%F %T')] run_all: DONE"
