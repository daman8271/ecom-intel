#!/usr/bin/env bash
# amazon_tail_sweep.sh — 10:15 IST daily (goal #80 coverage100): scrape the
# full-universe expansion TAIL pins (pincodes.daily.tail.json) for amazon-fresh
# + amazon-now, per-city chunks with per-day .done markers — a crash or tarpit
# loses one city, a re-run resumes. Runs strictly AFTER the 10:00 batch so it
# can never delay it; each platform holds the same per-account lock run.sh
# flocks (.<platform>.lock), so it can never collide with the chain or a
# selfheal re-run. Coverage evidence only: no Excel, no Telegram, no
# history.csv — the census summary lands in data/coverage/.
set -u
DIR=/opt/ecom-intel
TODAY="$(date +%F)"
LOG(){ echo "[$(date '+%F %T')] tail($1): $2"; }

run_platform(){
  local P="$1" SCRAPER="scrape.js"
  [ "$P" = "amazon-now" ] && SCRAPER="scrape.ctnow.js"
  local PDIR="$DIR/platforms/$P" CH="$DIR/platforms/$P/.tail-chunks"
  [ -s "$PDIR/pincodes.daily.tail.json" ] || { LOG "$P" "no tail config"; return 0; }
  mkdir -p "$CH/cfg" "$CH/out/$TODAY" "$CH/done/$TODAY"
  python3 - "$P" <<'PY'
import json, sys, os
P = sys.argv[1]; base = f"/opt/ecom-intel/platforms/{P}"
cfg = json.load(open(f"{base}/pincodes.daily.tail.json"))
cities = {}
for e in cfg: cities.setdefault(e["city"], []).append(e)
os.makedirs(f"{base}/.tail-chunks/cfg", exist_ok=True)
for c, ents in cities.items():
    json.dump(ents, open(f"{base}/.tail-chunks/cfg/{c.replace(' ','_')}.json", "w"))
print(f"[{P}] {len(cities)} city chunks / {len(cfg)} tail pins")
PY
  (
    flock -w 900 9 || { LOG "$P" "account lock busy >15m — skipping today"; exit 75; }
    cd "$PDIR" || exit 1
    for cfgf in "$CH"/cfg/*.json; do
      city="$(basename "$cfgf" .json)"
      [ -f "$CH/done/$TODAY/$city.done" ] && continue
      LOG "$P" "$city ..."
      if env PINCODES_FILE="$cfgf" OUT_FILE="$CH/out/$TODAY/$city.json" \
         timeout --foreground -k 60 3600 node "$SCRAPER" \
         >> "$DIR/logs/amz-tail-$P-$TODAY.log" 2>&1; then
        touch "$CH/done/$TODAY/$city.done"; LOG "$P" "$city OK"
      else
        LOG "$P" "$city FAILED rc=$? (resumes on next run)"
      fi
    done
  ) 9>"$DIR/.${P}.lock"
  python3 - "$P" "$TODAY" <<'PY'
import json, sys, glob, os
P, day = sys.argv[1], sys.argv[2]
base = f"/opt/ecom-intel/platforms/{P}/.tail-chunks"
att = sv = 0
for o in glob.glob(f"{base}/out/{day}/*.json"):
    try:
        s = json.load(open(o)).get("summary", {})
    except Exception:
        continue
    att += s.get("pincodes_total") or 0
    sv += s.get("pincodes_with_jivo") or 0
os.makedirs("/opt/ecom-intel/data/coverage", exist_ok=True)
out = {"date": day, "platform": P,
       "cities_done": len(glob.glob(f"{base}/done/{day}/*.done")),
       "cities_total": len(glob.glob(f"{base}/cfg/*.json")),
       "pins_attempted": att, "pins_with_jivo": sv}
json.dump(out, open(f"/opt/ecom-intel/data/coverage/amazon-tail-{P}-{day}.json", "w"))
print(f"[{P}] census: {out}")
PY
}

run_platform amazon-fresh & F=$!
run_platform amazon-now  & N=$!
wait "$F"; wait "$N"
LOG all "tail sweep finished"
