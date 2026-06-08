#!/usr/bin/env bash
# tools/cron/safe_fixes/rerun_platform.sh <platform>
#
# SAFE-FIX #2 — re-run ONE platform's full pipeline (./run.sh <platform>) when a
# TRANSIENT failure or an empty/partial run is detected (e.g. a single platform threw
# a traceback or recorded 0 rows while the rest of the sweep was healthy).
#
# This is the ONE safe-fix that touches the network, so it is the most heavily guarded:
#   - REFUSES if a live sweep is in progress (logs/.sweep-chain.lock held) — never scrape
#     concurrently with a sweep (the cardinal rule in run_all.sh).
#   - REFUSES if a per-account Amazon lock is held (that platform is mid-run).
#   - Holds logs/.sweep-chain.lock itself for the duration so a sweep can't start under it.
#   - One attempt only (the self-heal already does bounded retries; the doctor is not a
#     retry loop). On failure -> exit 1 => PROPOSE-ONLY.
#
# Dry/testing: set RUNNER_OVERRIDE to replace ./run.sh (e.g. an echo stub) — the lock
# guards still run, but no real scrape happens.

SF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SF_DIR/_common.sh"

P="${1:?usage: rerun_platform.sh <platform>}"
PDIR="$REPO/platforms/$P"
[ -d "$PDIR" ] || ambiguous "no such platform dir: $PDIR"

RUNNER="${RUNNER_OVERRIDE:-./run.sh}"
SWEEP_CHAIN_LOCK="$REPO/logs/.sweep-chain.lock"

command -v flock >/dev/null 2>&1 || ambiguous "flock not available — cannot prove no concurrent sweep; refusing to scrape"

# --- Guard: a per-account Amazon lock held => that platform is mid-run ---------------
case "$P" in
  amazon-fresh|amazon-now)
    ACCT_LOCK="$REPO/.${P}.lock"
    if [ -e "$ACCT_LOCK" ] && ! ( flock -n 9 ) 9<"$ACCT_LOCK"; then
      ambiguous "$P: per-account lock ($ACCT_LOCK) is held — platform is mid-run; refusing"
    fi
    ;;
esac

log "BEGIN rerun for $P (runner=$RUNNER)"

# --- Take the sweep-chain lock NON-BLOCKING. Held => a sweep is live => refuse. ------
exec 7>"$SWEEP_CHAIN_LOCK"
if ! flock -n 7; then
  ambiguous "$P: a live sweep chain holds logs/.sweep-chain.lock — refusing to rerun during a sweep window"
fi
log "$P: acquired sweep-chain lock (no live sweep) — rerunning pipeline ..."

set +e
( cd "$REPO" && $RUNNER "$P" ) >>"$SAFE_FIX_LOG" 2>&1
RC=$?
set -e
flock -u 7 2>/dev/null || true

if [ "$RC" -ne 0 ]; then
  ambiguous "$P: rerun pipeline exited $RC — not cleanly recovered; propose-only"
fi

# Verify the rerun actually produced a fresh, non-held verdict.
LATEST="$(latest_review_file "$P")"
[ -n "$LATEST" ] || ambiguous "$P: rerun produced no review verdict — propose-only"
V="$(verdict_of "$LATEST")"
log "$P: rerun complete, latest verdict = $V ($(basename "$LATEST"))"
if [ "$V" = "OK" ]; then
  ok_done "$P: transient failure recovered — rerun verdict OK."
else
  ambiguous "$P: rerun still $V — not a transient issue; propose-only (escalate)"
fi
