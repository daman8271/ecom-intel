#!/usr/bin/env bash
# run_all.sh — one cron-triggered sweep: scrape every LIVE platform SERIALLY (one at a time),
# then run the self-heal pass.
#
# SERIAL (not parallel) — accuracy over speed. Launching all 9 at once STARVED each scraper
# (CPU/network contention -> thin, partial data the hardened review.py correctly rejects) and
# made the 3 Amazon storefronts thrash their one shared account/server-side location. One
# platform at a time: each gets full resources, re-resolves its store cleanly (full coverage),
# and the Amazon trio can never overlap. Slower wall-clock (~1-1.5h), but correct + complete —
# a 2x/day window (10:00 + 15:00, 5h apart) has the headroom. Each ./run.sh is self-contained
# (scrape -> excel -> predict -> review -> vault -> telegram[verdict-gated] -> git push);
# per-platform stdout goes to logs/run-<p>.out.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
echo "[$(date '+%F %T')] run_all: START (serial — accuracy first)"
# Order: quick/light platforms first so their clean reports land early; the Amazon trio runs
# consecutively (serial guarantees no shared-account overlap); blinkit LAST (slowest — its
# per-pincode store re-resolution is intentionally patient for full clean coverage).
for P in  flipkart-minutes flipkart zepto bigbasket amazon amazon-fresh amazon-now blinkit; do
  echo "[$(date '+%F %T')] run_all: running $P (serial)"
  # AUTO-HEAL HOOK: after this platform's pipeline, the guardian re-evaluates the fresh
  # result.json (CALLs tools/review.py for the shared checks + its independent 11-bug-class deep
  # checks). On BROKEN -> QUARANTINE (keep last-good, nothing published — Telegram is already
  # verdict-gated) + bounded --heal retry + owner alert. Best-effort `|| true` so a guardian
  # hiccup can never fail the sweep.
  ( ./run.sh "$P"; python3 tools/guardian.py "$P" --heal || true ) >> "logs/run-${P}.out" 2>&1
done
echo "[$(date '+%F %T')] run_all: all platforms done -> self-heal pass"
# Backstop: the legacy self-heal pass still runs (it owns the staleness / row-collapse
# signals the inline guardian leaves to it). It runs AFTER the wait above, so the
# inline guardians have finished; it shares the same per-platform .heal-<p>.lock, so
# it can never run concurrently with a guardian heal (e.g. an overlapping daily pass).
# A platform the guardian already healed-but-left-BROKEN may get one more recovery
# attempt here — bounded and harmless (a deliberate second safety net).
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
