#!/usr/bin/env bash
# run_all.sh — one cron-triggered sweep: scrape every LIVE platform IN PARALLEL,
# then run the self-heal pass.
#
# Parallel (not sequential): the VPS has headroom (~15G RAM / 4 CPU), so we launch
# all platforms at once to finish the window faster. Each ./run.sh is self-contained
# (scrape -> excel -> predict -> review -> vault -> telegram -> git push) and
# best-effort; their git pushes are serialized by an flock inside run.sh so the
# concurrent commits don't collide. Per-platform stdout goes to logs/run-<p>.out.
#
# amazon-fresh and amazon-now are BOTH launched here, but run.sh holds a shared
# .amazon-account.lock around their scrape step so the two (which share one Amazon
# account + server-side delivery location) never scrape concurrently — one waits for
# the other. They share a single Chromium slot, so peak concurrency is unchanged.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
echo "[$(date '+%F %T')] run_all: START (parallel)"
pids=()
for P in blinkit  flipkart-minutes flipkart amazon zepto amazon-fresh amazon-now bigbasket; do
  echo "[$(date '+%F %T')] run_all: launching $P"
  ./run.sh "$P" >> "logs/run-${P}.out" 2>&1 &
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid" || true; done
echo "[$(date '+%F %T')] run_all: all platforms done -> self-heal pass"
./healthcheck.sh || true

# ---- Rebuild the COMPLETE Obsidian memory graph from the full price history. ----
# vault_build.py regenerates EVERY run note (complete: every observation as a fenced ```csv
# block) plus the SKU / city / pincode entity hubs, the two MOCs, the daily/weekly/monthly
# rollups, the home index and the .obsidian graph config — all densely cross-linked by
# real-basename [[wikilinks]] (NOT aliases, which Obsidian does not resolve). Deterministic +
# idempotent (stdlib only). Runs ONCE here after the parallel sweep — never per-platform — so
# the whole-graph rebuild can't race the concurrent run.sh instances. Then persist to git
# (same flock on .gitpush.lock as run.sh). Never fails the sweep.
echo "[$(date '+%F %T')] run_all: rebuilding Obsidian memory graph"
python3 tools/vault_build.py || echo "vault_build failed (non-fatal)" >&2
(
  set +e
  cd "$DIR"
  exec 9>"$DIR/.gitpush.lock"
  command -v flock >/dev/null 2>&1 && flock 9
  git add vault data reviews baselines >/dev/null 2>&1
  if ! git diff --cached --quiet; then
    git commit -m "vault: rebuild memory graph $(date '+%F-%H%M')" >/dev/null 2>&1
    git pull --rebase --autostash >/dev/null 2>&1
    git push >/dev/null 2>&1 || { git pull --rebase --autostash >/dev/null 2>&1; git push >/dev/null 2>&1; }
    echo "[$(date '+%F %T')] run_all: vault graph committed + pushed."
  else
    echo "[$(date '+%F %T')] run_all: vault graph unchanged."
  fi
) || true

echo "[$(date '+%F %T')] run_all: DONE"
