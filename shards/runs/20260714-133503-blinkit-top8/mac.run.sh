#!/bin/bash
set -uo pipefail
BASE="/Users/danny./VPS-Migration"
PROJECT="/Users/danny./VPS-Migration/imported/ecom-intel"
RUN="/Users/danny./VPS-Migration/competitor-runs/20260714-133503-blinkit-top8"
REMOTE="root@187.127.129.132:/opt/ecom-intel/shards/runs/20260714-133503-blinkit-top8/"
CAPTURE="$PROJECT/tools/competitor/data/blinkit_competitor_2026-07-14-TOP8-3PCITY-MAC.json"
LOCK_DIR="/tmp/com.danny.blinkit-top8.lock"
mkdir -p "$RUN"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  printf '75\n' > "$RUN/mac.run.rc"
  date > "$RUN/mac.run.done"
  rsync -az "$RUN/mac.run.rc" "$RUN/mac.run.done" "$REMOTE" || true
  exit 75
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
. "$BASE/bin/node22-env.sh"
cd "$PROJECT/platforms/blinkit" || exit 1
export COMPETITOR_MODE=1
export COMPETITOR_DATE="2026-07-14-TOP8-3PCITY-MAC"
export COMPETITOR_BRANDS="Jivo,Sano,Fortune,Saffola,Borges,Tata,Del Monte,Figaro,Sundrop,Gulab"
export BLINKIT_AUTH_STATE_FILE="$BASE/secrets/blinkit-auth-state.json"
export BLINKIT_REQUIRE_AUTH=1
export BLINKIT_OOS_PROBE=0
export BLINKIT_PDP_OOS_PROBE=0
export BLINKIT_PDP_PRICE_PROBE=0
export CONCURRENCY="2"
export PINCODES_FILE="$RUN/pincodes.json"
export BLINKIT_PROGRESS_FILE="$RUN/progress.json"
rm -f "$CAPTURE"
node scrape.js >"$RUN/mac.stdout.log" 2>"$RUN/mac.run.log"
rc=$?
printf '%s\n' "$rc" > "$RUN/mac.run.rc"
date > "$RUN/mac.run.done"
[ -s "$CAPTURE" ] && cp "$CAPTURE" "$RUN/mac.capture.json"
[ -s "$RUN/progress.json" ] && cp "$RUN/progress.json" "$RUN/mac.progress.json"
for file in mac.run.rc mac.run.done mac.run.log mac.stdout.log mac.capture.json mac.progress.json; do
  [ -f "$RUN/$file" ] && rsync -az "$RUN/$file" "$REMOTE$file" || true
done
exit "$rc"
