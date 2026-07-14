#!/usr/bin/env bash
set -euo pipefail

: "${TEST_DIR:?TEST_DIR is required}"
: "${AUTH_FILE:?AUTH_FILE is required}"

cd "$TEST_DIR"
rm -f result.json progress.json run.rc started_at.txt finished_at.txt
date -u +%FT%TZ > started_at.txt

rc=0
env \
  BLINKIT_AUTH_STATE_FILE="$AUTH_FILE" \
  BLINKIT_REQUIRE_AUTH=1 \
  BLINKIT_OOS_PROBE=1 \
  BLINKIT_PDP_OOS_PROBE=1 \
  BLINKIT_PDP_PRICE_PROBE=1 \
  CONCURRENCY=1 \
  PINCODES_FILE="$TEST_DIR/pincodes.json" \
  OUT_FILE="$TEST_DIR/result.json" \
  BLINKIT_PROGRESS_FILE="$TEST_DIR/progress.json" \
  node "$TEST_DIR/scrape.js" >stdout.log 2>stderr.log || rc=$?

printf '%s\n' "$rc" > run.rc
date -u +%FT%TZ > finished_at.txt
exit "$rc"
