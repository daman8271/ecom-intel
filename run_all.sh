#!/usr/bin/env bash
# run_all.sh — one cron-triggered sweep: scrape every LIVE platform IN PARALLEL,
# then run the self-heal pass.
#
# Parallel (not sequential): the VPS has headroom (~15G RAM / 4 CPU), so we launch
# all platforms at once to finish the window faster. Each ./run.sh is self-contained
# (scrape -> excel -> predict -> review -> vault -> telegram -> git push) and
# best-effort; their git pushes are serialized by an flock inside run.sh so the
# concurrent commits don't collide. Per-platform stdout goes to logs/run-<p>.out.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
echo "[$(date '+%F %T')] run_all: START (parallel)"
pids=()
for P in blinkit instamart flipkart-minutes flipkart amazon; do
  echo "[$(date '+%F %T')] run_all: launching $P"
  ./run.sh "$P" >> "logs/run-${P}.out" 2>&1 &
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid" || true; done
echo "[$(date '+%F %T')] run_all: all platforms done -> self-heal pass"
./healthcheck.sh || true
echo "[$(date '+%F %T')] run_all: DONE"
