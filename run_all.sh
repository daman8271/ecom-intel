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
#
# Overrides (for the cron-deadline simulation harness ONLY — both UNSET in production, which
# leaves the loop byte-for-byte identical to before):
#   PLATFORMS_OVERRIDE — space-separated platform list replacing the default 9
#   RUNNER_OVERRIDE    — command run instead of ./run.sh (word-split on purpose: may carry args)
PLATFORMS="${PLATFORMS_OVERRIDE:- flipkart-minutes flipkart zepto bigbasket amazon amazon-fresh amazon-now blinkit}"
RUNNER="${RUNNER_OVERRIDE:-./run.sh}"
# SIM MODE hard gate (LEAD ruling): ANY override set => this is the simulation harness, NOT a
# production sweep. Skip everything that touches live platforms or shared state: the per-platform
# guardian.py (undefined on fake platforms), healthcheck.sh -> selfheal (would RE-RUN REAL
# platforms on staleness/BROKEN = live scrapes), vault_build.py, and the final git block.
# The send_batch barrier still runs — it is exactly what the sim exercises.
SIM_MODE=0
if [ -n "${PLATFORMS_OVERRIDE:-}" ] || [ -n "${RUNNER_OVERRIDE:-}" ]; then
  SIM_MODE=1
  echo "[$(date '+%F %T')] run_all: SIM MODE (override set) — guardian/healthcheck/vault/git SKIPPED"
fi
for P in $PLATFORMS; do
  echo "[$(date '+%F %T')] run_all: running $P (serial)"
  # AUTO-HEAL HOOK: after this platform's pipeline, the guardian re-evaluates the fresh
  # result.json (CALLs tools/review.py for the shared checks + its independent 11-bug-class deep
  # checks). On BROKEN -> QUARANTINE (keep last-good, nothing published — Telegram is already
  # verdict-gated) + bounded --heal retry + owner alert. Best-effort `|| true` so a guardian
  # hiccup can never fail the sweep. In SIM MODE the guardian is skipped (fake platforms).
  P_START="$(date +%s)"
  if [ "$SIM_MODE" = "1" ]; then
    ( $RUNNER "$P" ) >> "logs/run-${P}.out" 2>&1
  else
    ( $RUNNER "$P"; python3 tools/guardian.py "$P" --heal || true ) >> "logs/run-${P}.out" 2>&1
  fi
  P_END="$(date +%s)"
  # Duration ledger for the deadline scheduler (W1's tools/cron). Best-effort, only if the
  # recorder exists; sweep_id falls back to "adhoc" on manual runs without SWEEP_ID.
  if [ -f tools/cron/record_duration.sh ]; then
    bash tools/cron/record_duration.sh "$P" "$((P_END - P_START))" "${SWEEP_ID:-adhoc}" || true
  fi
done
echo "[$(date '+%F %T')] run_all: all platforms done -> self-heal pass"

# ---- Deferred-delivery batch barrier (cron-deadline mode) ----
# When the deadline sweep set DEFER_DELIVERY=1, each platform's OK report was spooled to
# output/.batch/$SWEEP_ID/ instead of being curled (run.sh). send_batch.py sleeps until the
# slot deadline, then delivers the whole sweep in one batch. Best-effort: a batch failure
# never blocks the self-heal/vault steps below. Inert when the env vars are unset.
if [ "${DEFER_DELIVERY:-}" = "1" ] && [ -n "${SWEEP_ID:-}" ] && [ -n "${SWEEP_DEADLINE:-}" ] && [ -f tools/cron/send_batch.py ]; then
  echo "[$(date '+%F %T')] run_all: batch barrier -> send_batch.py $SWEEP_ID (deadline epoch $SWEEP_DEADLINE)"
  python3 tools/cron/send_batch.py "$SWEEP_ID" "$SWEEP_DEADLINE" || true
fi
# SIM MODE hard gate: everything below (selfheal, vault rebuild, git) is production-only.
if [ "$SIM_MODE" != "1" ]; then

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

fi  # end SIM MODE gate

echo "[$(date '+%F %T')] run_all: DONE"
