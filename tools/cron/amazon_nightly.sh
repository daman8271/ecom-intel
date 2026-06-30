#!/usr/bin/env bash
# Nightly Amazon per-pincode price run — DECOUPLED from the noon QC chain.
# Scrapes the Jivo-priced daily subsets (amazon-fresh 881, amazon-now 132) on their
# SEPARATE accounts (259 / 520), SERIALLY (zero clobber risk), builds each report,
# emits the coverage ledger, runs the Fresh!=Now clobber-check, commits + pushes,
# and Telegrams the owner. Runs early enough (cron @ ~02:00 IST) that both reports
# are ready well before the noon batch.
set -u
DIR=/opt/ecom-intel
cd "$DIR" || exit 1
LOG="$DIR/logs/amazon-nightly.log"
RID="$(date +%F)-amzdaily"
DATE="$(date +%F)"
say(){ echo "$(date '+%F %H:%M:%S') $*" | tee -a "$LOG"; }
tg(){ . "$DIR/secrets.env" 2>/dev/null || true
  local T="${TELEGRAM_BOT_TOKEN:-}"; local C="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
  [ -n "$T" ] && [ -n "$C" ] && curl -s --max-time 30 -X POST \
    "https://api.telegram.org/bot${T}/sendMessage" -d chat_id="$C" \
    --data-urlencode text="$1" >/dev/null 2>&1; return 0; }

say "amazon-nightly START rid=$RID pid=$$"
tg "🌙 Amazon nightly run started ($DATE): Fresh 881 + Now 132 Jivo-priced pincodes, serial. Reports + push before noon."

run_one(){  # $1 = platform
  local P="$1"
  say "scraping $P (COVERAGE_DAILY, daily list) ..."
  COVERAGE_DAILY=1 ./run.sh "$P" >> "$LOG" 2>&1
  local rc=$?
  say "$P run.sh exit=$rc"
  # coverage ledger from the fresh result.json (perPin has serviceable + rows)
  python3 "$DIR/tools/coverage/amazon_ledger.py" "$P" "${RID}-${P#amazon-}" "$DATE" \
    "$DIR/platforms/$P/result.json" "$DIR/data/coverage/ledger.csv" >> "$LOG" 2>&1 || true
  return $rc
}

run_one amazon-fresh ; FR=$?
run_one amazon-now   ; NW=$?

# ---- clobber-check: Fresh & Now must be DISTINCT surfaces ----
CLOB="🟢 distinct"
if ! python3 "$DIR/tools/coverage/amazon_clobber_check.py" >> "$LOG" 2>&1; then
  CLOB="🔴 CLOBBER SUSPECT — Fresh & Now look identical; check account locations"
  tg "⚠️ Amazon nightly $DATE: $CLOB. Data NOT trustworthy this run — see logs/amazon-nightly.log"
fi

# ---- report presence ----
freport=$(ls "$DIR"/platforms/amazon-fresh/Jivo-*"$DATE".xlsx 2>/dev/null | head -1)
nreport=$(ls "$DIR"/platforms/amazon-now/Jivo-*"$DATE".xlsx 2>/dev/null | head -1)
fcount=$(python3 -c "import json;print(sum(1 for x in json.load(open('platforms/amazon-fresh/result.json')).get('perPin',[]) if x.get('serviceable')))" 2>/dev/null || echo "?")
ncount=$(python3 -c "import json;print(sum(1 for x in json.load(open('platforms/amazon-now/result.json')).get('perPin',[]) if x.get('serviceable')))" 2>/dev/null || echo "?")

# ---- commit + push (own files only; behind the shared locks) ----
flock "$DIR/.gitcommit.lock" bash -c "
  git -C '$DIR' add platforms/amazon-fresh/result.json platforms/amazon-now/result.json \
    'platforms/amazon-fresh/Jivo-'*\"$DATE\".xlsx 'platforms/amazon-now/Jivo-'*\"$DATE\".xlsx \
    data/amazon-fresh/history.csv data/amazon-now/history.csv data/coverage/ledger.csv 2>/dev/null
  git -C '$DIR' commit -q -m 'run(amazon nightly $DATE): Fresh 881 + Now 132 Jivo-priced — reports + ledger' 2>/dev/null && echo committed
" >> "$LOG" 2>&1
flock "$DIR/.gitpush.lock" bash -c "git -C '$DIR' pull --rebase --autostash 2>&1 | tail -1; git -C '$DIR' push 2>&1 | tail -1" >> "$LOG" 2>&1

say "amazon-nightly DONE fresh=$fcount/881 (exit $FR) now=$ncount/132 (exit $NW) clobber=$CLOB"
tg "✅ Amazon nightly $DATE DONE. Fresh: $fcount serviceable (report $( [ -n "$freport" ] && echo built || echo MISSING)). Now: $ncount serviceable (report $( [ -n "$nreport" ] && echo built || echo MISSING)). $CLOB. Pushed."
