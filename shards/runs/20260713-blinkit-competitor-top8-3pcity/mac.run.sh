#!/bin/bash
set -uo pipefail

BASE="/Users/danny./VPS-Migration"
PROJECT="$BASE/imported/ecom-intel"
RUN="$BASE/competitor-runs/20260713-blinkit-competitor-top8-3pcity"
REMOTE="root@187.127.129.132:/opt/ecom-intel/shards/runs/20260713-blinkit-competitor-top8-3pcity/"
CAPTURE="$PROJECT/tools/competitor/data/blinkit_competitor_2026-07-13-TOP8-3PCITY-MAC.json"

. "$BASE/bin/node22-env.sh"
cd "$PROJECT/platforms/blinkit" || exit 1
export COMPETITOR_MODE=1
export COMPETITOR_DATE="2026-07-13-TOP8-3PCITY-MAC"
export COMPETITOR_BRANDS="Jivo,Sano,Fortune,Saffola,Borges,Tata,Del Monte,Figaro,Sundrop,Gulab"
export BLINKIT_AUTH_STATE_FILE="$BASE/secrets/blinkit-auth-state.json"
export BLINKIT_REQUIRE_AUTH=1
export BLINKIT_OOS_PROBE=0
export BLINKIT_PDP_OOS_PROBE=0
export BLINKIT_PDP_PRICE_PROBE=0
export CONCURRENCY=2
export PINCODES_FILE="$RUN/pincodes.json"
export BLINKIT_PROGRESS_FILE="$RUN/progress.json"

rm -f "$BLINKIT_PROGRESS_FILE" "$CAPTURE"
node scrape.js >"$RUN/stdout.log" 2>"$RUN/run.log"
rc=$?
printf '%s\n' "$rc" >"$RUN/mac.run.rc"
date >"$RUN/mac.run.done"
if [[ -s "$CAPTURE" ]]; then
  cp "$CAPTURE" "$RUN/mac.capture.json"
fi
rsync -az "$RUN/mac.run.rc" "$RUN/mac.run.done" "$RUN/run.log" "$RUN/stdout.log" "$REMOTE" || true
if [[ -s "$RUN/mac.capture.json" ]]; then
  rsync -az "$RUN/mac.capture.json" "${REMOTE}mac.capture.json" || true
fi
exit "$rc"
