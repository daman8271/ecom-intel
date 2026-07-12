#!/usr/bin/env bash
# verify_coverage80.sh — run manually the morning after the coverage100 flip
# (goal #80). Checks lists, batch, blinkit ingest, per-platform result sizes,
# amazon tail census, and chain lead. Exit 0 = all green.
set -u
DIR=/opt/ecom-intel
cd "$DIR" || exit 1
TODAY="$(date +%F)"
RC=0
say(){ printf '%-46s %s\n' "$1" "$2"; }
fail(){ say "$1" "❌ $2"; RC=1; }

echo "== coverage100 morning verify $TODAY =="

# 1) lists still expanded (nothing rolled them back overnight)
python3 - <<'PY' || RC=1
import json
mins = {"blinkit": 1700, "zepto": 1600, "flipkart-minutes": 1550}
ok = True
for p, m in mins.items():
    n = len(json.load(open(f"/opt/ecom-intel/platforms/{p}/pincodes.daily.json")))
    print(f"{p:20s} list={n:5d}  {'✅' if n >= m else '❌ TOO SMALL'}")
    ok &= n >= m
for p in ("amazon-fresh", "amazon-now"):
    n = len(json.load(open(f"/opt/ecom-intel/platforms/{p}/pincodes.daily.tail.json")))
    print(f"{p:20s} tail={n:5d}")
raise SystemExit(0 if ok else 1)
PY

# 2) batch went out at 10:00
if ls output/.batch/sent-"$TODAY"-1000 >/dev/null 2>&1; then
  say "10:00 batch sent-marker" "✅"
else
  fail "10:00 batch sent-marker" "missing (check logs/cron.log + send_batch)"
fi

# 3) blinkit ingested a full-size mac drop
python3 - <<'PY'
import json
try:
    s = json.load(open("/opt/ecom-intel/platforms/blinkit/result.json")).get("summary", {})
    print(f"blinkit result: pincodes_total={s.get('pincodes_total')} "
          f"with_jivo={s.get('pincodes_with_jivo')} "
          f"unresolved={s.get('pincodes_unresolved', '?')}")
except Exception as e:
    print("blinkit result unreadable:", e)
PY

# 4) zepto / fkm result sizes
for p in zepto flipkart-minutes; do
  python3 -c "
import json
s = json.load(open('/opt/ecom-intel/platforms/$p/result.json')).get('summary', {})
print('$p result:', s.get('pincodes_total'), 'pins,', s.get('pincodes_with_jivo'), 'with jivo')" 2>/dev/null || say "$p result" "unreadable"
done

# 5) amazon tail census (runs 10:15+; empty before that)
for p in amazon-fresh amazon-now; do
  f="data/coverage/amazon-tail-$p-$TODAY.json"
  if [ -f "$f" ]; then
    python3 -c "import json;d=json.load(open('$f'));print(f\"tail {d['platform']}: {d['cities_done']}/{d['cities_total']} cities, {d['pins_attempted']} attempted, {d['pins_with_jivo']} with jivo\")"
  else
    say "tail $p" "not yet run today (cron 10:15)"
  fi
done

# 6) chain lead used
grep "deadline_sweep(10:00)" logs/cron.log | grep "$TODAY" | head -2 || true

# 7) blinkit WhatsApp delivery time (10:30 hard rule)
grep -h "$TODAY" logs/blinkit-main-wa.log 2>/dev/null | tail -2 || say "blinkit WA log" "no entries yet"

exit $RC
