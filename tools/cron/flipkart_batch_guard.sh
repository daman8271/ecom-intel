#!/usr/bin/env bash
# flipkart_batch_guard.sh — owner rule 2026-07-07 (house pattern: blinkit_batch_guard.sh,
# goal #70): the Flipkart report MUST be in the 10:00 batch / Ecom-group post.
#
# ROOT CAUSE of the 2026-07-06 + 2026-07-07 misses: since the night of Jul 6 the
# ~01:00 IST in-chain flipkart run collapses to ~3 priced in-stock rows vs baseline 99
# (Flipkart's national listings read unavailable/unpriced overnight), so review.py's
# priced_floor_block CORRECTLY holds it. Night runs were healthy through Jul 5
# (99/94/101 priced in-stock at 01:0x); daytime runs are healthy (97 at 10:09 Jul 6).
# The only existing catch-up is run_all.sh's selfheal backstop, which by design runs
# AFTER send_batch has already delivered — 10:09 on Jul 6, nine minutes too late,
# every day. The schedule is the bug, not the guard.
#
# WHAT THIS DOES: cron runs it at 06:40 ("early") and 08:50 ("late"). For each of
# flipkart + flipkart-minutes: if today's report is already OK in the pending batch
# spool (output/.batch/<sid>/<p>.json) — or, with no pending batch, the latest
# per-run review today is OK — quiet no-op. Otherwise re-run ./run.sh <p> at
# store-open hours with the sweep's DEFER env so the healed report spools INTO
# today's 10:00 batch. NEVER loosens the priced floor / review gates — review.py
# re-verdicts every re-run and a BROKEN re-run stays held.
#
# CONCURRENCY (cardinal rule: never scrape concurrently with the chain):
#   - own pass lock   logs/.flipkart_guard.lock   flock -n (one pass at a time)
#   - sweep chain     logs/.sweep-chain.lock      early: flock -n -> skip if busy
#                                                 late:  flock -w until 09:32 IST
#     …then HELD for the duration of the re-run (same as safe_fixes/rerun_platform.sh)
#     so a late-launching sweep can never start scraping under us.
#   - per-platform    pgrep -f "run.sh <p>$"      skip if that platform is mid-run
# DEFER CUTOFF (W4 dead-spool rule): a re-run only joins the batch if it starts by
# 09:35 with a 1320s timeout => worst finish ~09:57, before send_batch reads the
# spool at 10:00. Later starts run in immediate-send mode instead (selfheal parity).
# Test hook: GUARD_DRYRUN=1 -> decisions logged, no scrape, no Telegram.
set -u
DIR=/opt/ecom-intel
cd "$DIR" || exit 0
PASS="${1:-early}"
TODAY="$(date +%F)"
NOW="$(date +%s)"
T="$(date -d "$TODAY 10:00" +%s)"
DRY="${GUARD_DRYRUN:-0}"
LOG(){ echo "[$(date '+%F %T')] flipkart_guard($PASS): $*"; }

tg(){ ( set +e
  [ "$DRY" = "1" ] && { LOG "[DRYRUN] would notify: ${1//$'\n'/ }"; exit 0; }
  [ -f "$DIR/secrets.env" ] && . "$DIR/secrets.env"
  CH="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "$CH" ] || exit 0
  curl -s --max-time 30 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CH}" \
    --data-urlencode "text=$1" >/dev/null ) || true; }

# Never scrape inside the night-collapse / chain-launch window, and after 10:00
# the post-batch selfheal owns recovery (this guard's job is the BATCH).
HOUR=$((10#$(date +%H)))
if [ "$HOUR" -lt 6 ]; then
  LOG "before 06:00 IST — inside the night window; exit"
  [ "$DRY" = "1" ] || exit 0
fi
if [ "$NOW" -ge "$T" ]; then
  LOG "past the 10:00 slot — post-batch selfheal owns recovery now; exit"
  [ "$DRY" = "1" ] || exit 0
fi

# ---- one guard pass at a time ----------------------------------------------
exec 8>logs/.flipkart_guard.lock
if ! flock -n 8; then LOG "another guard pass holds the lock — exit"; exit 0; fi

# ---- pending batch (same detection as tools/cron/spool_into_batch.sh) -------
BROOT="$DIR/output/.batch"
SID=""
for l in "$BROOT"/launched-"$TODAY"-*; do
  [ -e "$l" ] || continue
  s="${l##*/launched-}"
  [ -e "$BROOT/sent-$s" ] && continue
  SID="$s"
done
if [ -n "$SID" ]; then LOG "pending batch: $SID"; else LOG "no pending batch today (already sent or launch tick dropped)"; fi

verdict_file(){ # newest REAL per-run review for platform $1 today (excl. synthetic)
  ls -t "$DIR"/reviews/"$1"-"$TODAY"-*.json 2>/dev/null \
    | grep -Ev -- '-(unhold|doctor|probe|w2probe)\.json$' | head -1
}
verdict_of(){ python3 - "$1" <<'PY' 2>/dev/null || echo BROKEN
import json, sys
try:
    print((json.load(open(sys.argv[1])).get("verdict") or "BROKEN").upper())
except Exception:
    print("BROKEN")
PY
}
spool_is_ok(){ # 0 if the pending-batch spool for platform $1 is a deliverable OK report
  python3 - "$BROOT/$SID/$1.json" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if d.get("verdict") == "OK" and not d.get("held") else 1)
PY
}
needs_rescue(){ # 0 (yes) if platform $1 is held/missing for today
  local p="$1" f
  if [ -n "$SID" ]; then
    [ -f "$BROOT/$SID/$p.json" ] && spool_is_ok "$p" && return 1
    return 0
  fi
  f="$(verdict_file "$p")"
  [ -n "$f" ] && [ "$(verdict_of "$f")" = "OK" ] && return 1
  return 0
}

# ---- quick exit when nothing needs rescuing (don't touch the chain lock) ----
NEEDY=""
for P in flipkart flipkart-minutes; do
  if needs_rescue "$P"; then NEEDY="$NEEDY $P"; else LOG "$P: already OK for $TODAY (batch spool/review) — skip"; fi
done
[ -n "$NEEDY" ] || { LOG "all covered — nothing to do"; exit 0; }

# ---- sweep-chain lock: NEVER scrape concurrently with the chain --------------
CHAIN_LOCK="$DIR/logs/.sweep-chain.lock"
exec 7>"$CHAIN_LOCK"
if [ "$PASS" = "late" ] && [ "$DRY" != "1" ]; then
  WAIT_END=$((T - 1680))            # 09:32 IST — leave runway for a defer-mode run
  W=$((WAIT_END - NOW)); [ "$W" -lt 0 ] && W=0
  if ! flock -w "$W" 7; then
    LOG "chain still holds logs/.sweep-chain.lock after ${W}s wait — cannot re-run safely before the batch"
    tg "⏳ Flipkart guard 08:50: the main scrape chain is STILL running at $(date +%H:%M) IST — cannot re-run flipkart concurrently (serial rule). It will miss the 10:00 batch; the post-batch selfheal should deliver it ~10:10."
    exit 0
  fi
else
  if ! flock -n 7; then
    LOG "sweep chain active (logs/.sweep-chain.lock busy) — skipping this pass (the late pass waits for the lock)"
    exit 0
  fi
fi
LOG "sweep-chain lock acquired — safe to re-run:$NEEDY"

DEFER_CUTOFF=$((T - 1500))          # 09:35 IST — last start that can still make the batch
RESCUED=0
for P in $NEEDY; do
  if pgrep -f "run\.sh ${P}\$" >/dev/null 2>&1; then
    LOG "$P: a run.sh $P is already active — not double-running"
    continue
  fi
  NOW="$(date +%s)"
  MODE=immediate
  [ -n "$SID" ] && [ "$NOW" -le "$DEFER_CUTOFF" ] && MODE=defer
  LOG "$P: HELD/missing for $TODAY -> re-running at store-open hours (mode=$MODE)"
  if [ "$DRY" = "1" ]; then LOG "[DRYRUN] would run: mode=$MODE COVERAGE_DAILY=1 ./run.sh $P"; continue; fi
  tg "🛠 Flipkart guard ($PASS): $P was HELD at the ~01:00 night run (priced-rows collapse) — re-running now at store-open hours (mode=$MODE)."
  RC=0
  if [ "$MODE" = "defer" ]; then
    DEFER_DELIVERY=1 SWEEP_ID="$SID" COVERAGE_DAILY=1 timeout 1320 ./run.sh "$P" >> logs/flipkart_guard_runs.log 2>&1 || RC=$?
  else
    DEFER_DELIVERY= SWEEP_ID= COVERAGE_DAILY=1 timeout 2400 ./run.sh "$P" >> logs/flipkart_guard_runs.log 2>&1 || RC=$?
  fi
  F="$(verdict_file "$P")"; V="none"; [ -n "$F" ] && V="$(verdict_of "$F")"
  LOG "$P: re-run rc=$RC latest verdict=$V ($(basename "${F:-none}"))"
  if [ "$V" = "OK" ]; then
    RESCUED=$((RESCUED + 1))
    if [ "$MODE" = "defer" ]; then
      tg "✅ Flipkart guard ($PASS): fresh $P run verdict OK — spooled into today's 10:00 batch."
    else
      tg "✅ Flipkart guard ($PASS): fresh $P run verdict OK — delivered immediately (batch window closed/absent)."
    fi
  else
    NEXTHINT="the 08:50 late pass will retry"
    [ "$PASS" = "late" ] && NEXTHINT="the post-batch selfheal (~10:10) is the next retry"
    tg "⚠️ Flipkart guard ($PASS): $P re-run still ${V} (rc=$RC) — HELD BACK (price floor NOT loosened); $NEXTHINT."
  fi
done
LOG "pass done (rescued=$RESCUED)"
