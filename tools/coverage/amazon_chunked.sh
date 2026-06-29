#!/usr/bin/env bash
# Resilient per-city Amazon per-pincode coverage runner.
# Splits the 1,885-pincode full25 config by city; runs each city as its own
# scraper invocation with a .done marker, so a crash only loses one city and
# a re-run resumes. amazon-fresh and amazon-now run on SEPARATE accounts, so
# this script is launched once per platform (in parallel) — the account-global
# delivery location can't collide across accounts.
#   usage: bash tools/coverage/amazon_chunked.sh <amazon-fresh|amazon-now>
set -u
P="${1:?usage: amazon_chunked.sh <amazon-fresh|amazon-now>}"
DIR=/opt/ecom-intel
PDIR="$DIR/platforms/$P"
SCRAPER="scrape.js"; [ "$P" = "amazon-now" ] && SCRAPER="scrape.ctnow.js"
CH="$PDIR/.cov-chunks"
LOG="$DIR/logs/amz-$P-cov-$(date +%F).log"
mkdir -p "$CH/done" "$CH/out" "$CH/cfg"

# 1) split full25 by city (idempotent)
python3 - "$P" <<'PY'
import json,sys
P=sys.argv[1]; base=f"/opt/ecom-intel/platforms/{P}"
cfg=json.load(open(f"{base}/pincodes.full25.json"))
cities={}
for e in cfg: cities.setdefault(e['city'],[]).append(e)
for c,ents in cities.items():
    json.dump(ents, open(f"{base}/.cov-chunks/cfg/{c.replace(' ','_')}.json","w"))
print(f"[{P}] {len(cities)} city chunks, {len(cfg)} pincodes")
PY

cd "$PDIR" || exit 1
echo "[$(date +%T)] $P chunked run START" | tee -a "$LOG"
for cfgf in "$CH"/cfg/*.json; do
  city=$(basename "$cfgf" .json)
  if [ -f "$CH/done/$city.done" ]; then echo "[skip] $city"; continue; fi
  echo "[$(date +%T)] [$P] $city ..." | tee -a "$LOG"
  if env PINCODES_FILE="$cfgf" OUT_FILE="$CH/out/$city.json" node "$SCRAPER" >> "$LOG" 2>&1; then
    touch "$CH/done/$city.done"
    echo "[$(date +%T)] [$P] $city OK" | tee -a "$LOG"
  else
    echo "[$(date +%T)] [$P] $city FAILED (left for retry)" | tee -a "$LOG"
  fi
done
done_n=$(ls "$CH/done"/*.done 2>/dev/null | wc -l)
echo "[$(date +%T)] $P DONE — $done_n/25 cities complete" | tee -a "$LOG"
touch "$CH/$P.runfinished"
