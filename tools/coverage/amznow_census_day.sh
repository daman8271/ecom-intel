#!/usr/bin/env bash
# amznow_census_day.sh — owner ask 2026-07-07: grow the Amazon Now daily pincode
# set (currently 132 = every pin the June census found serviceable; 1,753/1,885
# were not_serviceable — the ctnow footprint itself is the limit, so growth can
# only come from a fresh census catching newly opened zones).
#
# Re-censuses the full 1,885-pin universe for amazon-now in daily 11:30->17:30
# windows (amazon_chunked.sh is resumable per city). Holds the shared
# .amazon-account.lock the whole time so it can never co-scrape with the cron
# chain, competitor pass, or the 18:00 guardian (timeout ends it 17:30).
# When all 25 cities are done: merge -> coverage ledger -> regenerate
# pincodes.daily.json = ALL serviceable pins (same rule that gives fresh 973)
# -> Telegram alert. After that it self-noops; the cron line can be removed.
set -u
DIR=/opt/ecom-intel
cd "$DIR" || exit 0
P=amazon-now
CH="platforms/$P/.cov-chunks"
MARK="platforms/$P/.census-202607.complete"
LOG(){ echo "[$(date '+%F %T')] amznow_census: $*"; }

tg(){ ( set +e
  [ -f "$DIR/secrets.env" ] && . "$DIR/secrets.env"
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] || exit 0
  curl -s --max-time 30 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=$1" >/dev/null ) || true; }

[ -f "$MARK" ] && { LOG "census already complete — noop (cron line can be removed)"; exit 0; }

# First run: archive the June chunk state so this census probes fresh instead of
# skipping every city on old .done markers.
if [ -f "$CH/amazon-now.runfinished" ] && [ ! -d "${CH}.pre-202607" ]; then
  mv "$CH" "${CH}.pre-202607"
  LOG "archived June chunk state -> ${CH}.pre-202607"
fi

LOG "acquiring .amazon-account.lock (waits up to 30m)"
exec 9>".amazon-account.lock"
if ! flock -w 1800 9; then
  LOG "lock busy >30m — skipping today's window"
  exit 0
fi

timeout 6h bash tools/coverage/amazon_chunked.sh "$P"
RC=$?
done_n=$(ls "$CH/done"/*.done 2>/dev/null | wc -l)
LOG "chunked run rc=$RC — cities done: $done_n/25"

if [ "$done_n" -lt 25 ]; then
  tg "🌙 Amazon Now census: ${done_n}/25 cities done — resumes tomorrow 11:30 (window 11:30-17:30, account-locked)"
  exit 0
fi

RUN_ID="census-$(date +%Y%m%d)"
if ! python3 tools/coverage/amazon_merge.py "$P" || \
   ! python3 tools/coverage/amazon_ledger.py "$P" "$RUN_ID" "$(date +%F)"; then
  tg "🔴 Amazon Now census: merge/ledger step FAILED — see logs/amznow-census.log"
  exit 1
fi

# Regenerate the daily config = every serviceable pin, last-wins per pincode.
python3 - <<'PY' || { tg "🔴 Amazon Now census: daily-config regen FAILED — old config untouched"; exit 1; }
import csv, json, shutil
base = "/opt/ecom-intel/platforms/amazon-now"
full = json.load(open(f"{base}/pincodes.full25.json"))
last = {}
for r in csv.DictReader(open("/opt/ecom-intel/data/coverage/ledger.csv")):
    if r["platform"] == "amazon-now":
        last[r["pincode"]] = r["status"]          # last row wins
ok = {p for p, s in last.items() if s in ("price_captured", "serviceable_no_jivo")}
daily = [e for e in full if str(e.get("pincode")) in ok]
if not daily:
    raise SystemExit("refusing to write an EMPTY daily config")
shutil.copy(f"{base}/pincodes.daily.json", f"{base}/pincodes.daily.json.bak-pre-census-202607")
json.dump(daily, open(f"{base}/pincodes.daily.json", "w"), indent=1)
print(f"amazon-now daily config regenerated: {len(daily)} serviceable pins (was 132)")
PY

touch "$MARK"
NEW_N=$(python3 -c "import json;print(len(json.load(open('platforms/$P/pincodes.daily.json'))))" 2>/dev/null || echo "?")
tg "✅ Amazon Now census COMPLETE — daily config regenerated: ${NEW_N} serviceable pins (was 132). Old config backed up. Tomorrow's 00:30 sweep uses the new set."
LOG "census complete — daily config now ${NEW_N} pins"
