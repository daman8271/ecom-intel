#!/usr/bin/env bash
# Env-gated competitor price-watch runner (V1, quick-commerce). NOT cron-wired.
#
# Usage: run_competitor.sh <platform>          e.g. run_competitor.sh blinkit
#
# Flips the platform scraper into COMPETITOR_MODE=1 (keep + tag rival rows instead of
# dropping them to JIVO-only), points it at the ~60-pin competitor geography, then builds
# the lean by-brand gap report. With COMPETITOR_MODE unset the scrapers behave exactly as
# the live pipeline; this wrapper is the ONLY thing that sets it for a manual run.
#
# GUARDRAILS: competitor capture lands ONLY under tools/competitor/data/ ; the report lands
# under output/ with a "Competitor-Price-Watch-" prefix (NEVER "Jivo-", which the daily
# mailer auto-emails). Nothing here touches cron, the mailer, or the price-match master.
set -euo pipefail

PLATFORM="${1:?usage: run_competitor.sh <platform>  (blinkit | zepto | flipkart-minutes)}"
COMP_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$COMP_DIR/../.." && pwd)"
PDIR="$ROOT/platforms/$PLATFORM"
SCRAPER="$PDIR/scrape.js"

[ -d "$PDIR" ] || { echo "[run_competitor] no such platform: $PLATFORM ($PDIR)" >&2; exit 1; }
[ -f "$SCRAPER" ] || { echo "[run_competitor] no scrape.js for $PLATFORM ($SCRAPER)" >&2; exit 1; }

# Competitor mode + geography. PINCODES_FILE is overridable but defaults to the ~60-pin
# competitor set; normalise to an absolute path (the scraper runs with cwd=$PDIR).
export COMPETITOR_MODE=1
export PINCODES_FILE="${PINCODES_FILE:-$COMP_DIR/top_pincodes.json}"
case "$PINCODES_FILE" in /*) ;; *) PINCODES_FILE="$ROOT/$PINCODES_FILE";; esac
export PINCODES_FILE

# Pin one IST date across the scraper and the report so the report reads the file the
# scraper just wrote (avoids a midnight-IST split between the two steps).
DATE_IST="$(TZ='Asia/Kolkata' date +%F)"
export COMPETITOR_DATE="$DATE_IST"

mkdir -p "$COMP_DIR/data" "$ROOT/output" "$ROOT/logs"
RUN_ID="$(date +%Y-%m-%d-%H%M)"
LOG="$ROOT/logs/competitor-${PLATFORM}-${RUN_ID}.log"

echo "[run_competitor] platform=$PLATFORM COMPETITOR_MODE=1 date=$DATE_IST" >&2
echo "[run_competitor] PINCODES_FILE=$PINCODES_FILE" >&2
echo "[run_competitor] scraping (log: $LOG) ..." >&2

# Run the scraper from the platform dir so it resolves its own node_modules (matches run.sh).
( cd "$PDIR" && node "$SCRAPER" ) 2> "$LOG"

echo "[run_competitor] building gap report ..." >&2
python3 "$COMP_DIR/build_competitor_report.py" "$PLATFORM" "$DATE_IST"

echo "[run_competitor] done. capture: $COMP_DIR/data/${PLATFORM}_competitor_${DATE_IST}.json" >&2
