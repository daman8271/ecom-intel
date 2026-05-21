#!/usr/bin/env bash
# Usage: ./run.sh <platform>   e.g. ./run.sh blinkit
set -euo pipefail
P="${1:?usage: ./run.sh <platform>  (blinkit|zepto|flipkart-minutes|amazon-now|flipkart|amazon)}"
DIR="$(cd "$(dirname "$0")" && pwd)"
PDIR="$DIR/platforms/$P"
[ -d "$PDIR" ] || { echo "no such platform: $P"; exit 1; }
mkdir -p "$DIR/output" "$DIR/logs"
RUN_ID="$(date +%Y-%m-%d-%H%M)"

cd "$PDIR"
echo "[$RUN_ID] scraping $P ..."
node scrape.js 2> "$DIR/logs/${P}-${RUN_ID}.log"
echo "[$RUN_ID] building excel ..."
python3 build_excel.py
cp Jivo-*.xlsx "$DIR/output/" 2>/dev/null || true

echo "[$RUN_ID] $P done. Excel -> $DIR/output/  | log -> $DIR/logs/${P}-${RUN_ID}.log"
tail -1 "$DIR/logs/${P}-${RUN_ID}.log" || true
