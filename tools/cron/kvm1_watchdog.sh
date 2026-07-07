#!/usr/bin/env bash
# kvm1_watchdog.sh — VPS-side liveness + fallback for the KVM1 store-open trio.
#
# Phase 2 split (2026-07-07): flipkart/zepto scrape on KVM1 at ~07:30 IST and
# dead-drop into today's 10:00 batch (flipkart-minutes stayed in the VPS chain —
# DC-bound API, see run_all.sh). THIS script is the safety
# net (model: sweep_watchdog.sh + check_macpro_worker_health.sh). Cron ticks at
# 08:10 / 08:40 / 09:05 IST. Each tick:
#   - every trio platform already OK in the pending batch spool -> quiet no-op
#   - trio still RUNNING on KVM1 -> no-op (09:05 tick: overrun alert — the late
#     platform joins the batch if its ingest lands by 10:00, else ships late)
#   - KVM1 alive but trio never started (both launch paths missed) -> relaunch
#     it remotely ONCE (08:10 tick), else fall through to local rescue
#   - KVM1 dead / trio failed a platform -> LOCAL RESCUE: re-run the missing
#     platforms serially on the VPS (flipkart -> zepto), holding the
#     sweep-chain lock (cardinal rule: never scrape concurrently with a chain),
#     in DEFER mode when the run can still land by ~09:55, else leave it to the
#     post-batch selfheal (~10:01) and say so. Review gates never loosened.
#
# Coexistence: flipkart_batch_guard (06:40/08:50) also covers fkm+flipkart; both
# scripts skip platforms that are mid-run (pgrep) and both serialize scrapes on
# logs/.sweep-chain.lock, so they can never double-scrape. Test: WATCHDOG_DRYRUN=1.
set -uo pipefail
DIR=/opt/ecom-intel
cd "$DIR" || exit 0
mkdir -p logs
TODAY="$(date +%F)"
NOW="$(date +%s)"
T="$(date -d "$TODAY 10:00" +%s)"
DRY="${WATCHDOG_DRYRUN:-0}"
LOG(){ echo "[$(date '+%F %T')] kvm1_watchdog: $*"; }
tg(){ ( set +e
  [ "$DRY" = "1" ] && { LOG "[DRYRUN] would notify: ${1//$'\n'/ }"; exit 0; }
  [ -f "$DIR/secrets.env" ] && . "$DIR/secrets.env"
  CH="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "$CH" ] || exit 0
  curl -s --max-time 30 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CH}" \
    --data-urlencode "text=$1" >/dev/null ) || true; }

# after the batch the selfheal backstop owns recovery
if [ "$NOW" -ge "$T" ]; then LOG "past 10:00 — selfheal owns recovery; exit"; exit 0; fi

# ---- one watchdog pass at a time ---------------------------------------------
exec 8>logs/.kvm1_watchdog.lock
if ! flock -n 8; then LOG "another pass holds the lock — exit"; exit 0; fi

# ---- pending batch + needy detection (same as flipkart_batch_guard.sh) --------
BROOT="$DIR/output/.batch"
SID=""
for l in "$BROOT"/launched-"$TODAY"-*; do
  [ -e "$l" ] || continue
  s="${l##*/launched-}"
  [ -e "$BROOT/sent-$s" ] && continue
  SID="$s"
done
verdict_file(){ ls -t "$DIR"/reviews/"$1"-"$TODAY"-*.json 2>/dev/null \
  | grep -Ev -- '-(unhold|doctor|probe|w2probe)\.json$' | head -1; }
verdict_of(){ python3 - "$1" <<'PY' 2>/dev/null || echo BROKEN
import json, sys
try: print((json.load(open(sys.argv[1])).get("verdict") or "BROKEN").upper())
except Exception: print("BROKEN")
PY
}
spool_is_ok(){ python3 - "$BROOT/$SID/$1.json" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if d.get("verdict") == "OK" and not d.get("held") else 1)
PY
}
needs_rescue(){ local p="$1" f
  if [ -n "$SID" ]; then
    [ -f "$BROOT/$SID/$p.json" ] && spool_is_ok "$p" && return 1
    return 0
  fi
  f="$(verdict_file "$p")"
  [ -n "$f" ] && [ "$(verdict_of "$f")" = "OK" ] && return 1
  return 0
}

NEEDY=""
for P in flipkart zepto; do
  needs_rescue "$P" && NEEDY="$NEEDY $P"
done
[ -n "$NEEDY" ] || { LOG "trio fully covered for $TODAY — nothing to do"; exit 0; }
LOG "needy:$NEEDY (sid=${SID:-none})"

# ---- KVM1 state ---------------------------------------------------------------
KSSH="ssh -o BatchMode=yes -o ConnectTimeout=10 kvm1"
kvm1_alive(){ timeout 20 $KSSH true >/dev/null 2>&1; }
trio_running(){ # rc 0 = the trio flock is HELD on KVM1 (running)
  timeout 20 $KSSH "flock -n /opt/ecom-intel/logs/.trio.lock -c true 2>/dev/null && exit 1 || exit 0" 2>/dev/null; }
trio_done(){ timeout 20 $KSSH "[ -f /opt/ecom-intel/logs/trio-done-$TODAY ]" 2>/dev/null; }
kvm_blinkit_active(){
  timeout 20 $KSSH "pgrep -f 'run_platform_shard.sh blinkit' >/dev/null 2>&1 && exit 0
for p in /proc/[0-9]*/cwd; do
  cwd=\$(readlink \"\$p\" 2>/dev/null || true)
  case \"\$cwd\" in */platforms/blinkit|*/work/blinkit) exit 0 ;; esac
done
exit 1" 2>/dev/null; }

ALIVE=0; kvm1_alive && ALIVE=1
BLINKIT_BUSY=0
if [ "$ALIVE" = "1" ] && kvm_blinkit_active; then
  if [ "$NOW" -lt "$(date -d "$TODAY 08:40" +%s)" ]; then
    LOG "KVM1 is busy with priority Blinkit fallback — waiting before trio rescue"
    exit 0
  fi
  BLINKIT_BUSY=1
  LOG "KVM1 is still busy with priority Blinkit fallback — local rescue for$NEEDY"
fi

if [ "$ALIVE" = "1" ] && [ "$BLINKIT_BUSY" != "1" ]; then
  if trio_running; then
    if [ "$NOW" -ge "$(date -d "$TODAY 09:00" +%s)" ]; then
      LOG "trio still running on KVM1 at $(date +%H:%M) — overrun"
      tg "⏳ KVM1 trio OVERRUN: still scraping at $(date +%H:%M) IST with$NEEDY missing. A platform whose ingest lands before 10:00 still joins the batch; anything later ships late (selfheal parity)."
    else
      LOG "trio running on KVM1 — waiting (needy:$NEEDY)"
    fi
    exit 0
  fi
  if ! trio_done; then
    # box alive, trio neither running nor done -> both launch paths failed
    RELAUNCH_MARK="logs/.kvm1_relaunched-$TODAY"
    if [ ! -f "$RELAUNCH_MARK" ] && [ "$NOW" -lt "$(date -d "$TODAY 08:20" +%s)" ]; then
      : > "$RELAUNCH_MARK"
      LOG "trio never started but KVM1 is alive — relaunching remotely"
      if [ "$DRY" = "1" ]; then LOG "[DRYRUN] would relaunch trio"; exit 0; fi
      tg "⚠️ KVM1 trio never started (07:30/07:40 launch ticks missed) — watchdog relaunched it at $(date +%H:%M) IST."
      ./tools/cron/kvm1_trio_launch.sh >> logs/kvm1_launch.log 2>&1 || true
      exit 0
    fi
    LOG "trio not running/done on live KVM1 and relaunch window used — falling back to local rescue"
  else
    LOG "trio done on KVM1 but$NEEDY still missing (scrape/push/ingest failure) — local rescue"
  fi
else
  if [ "$BLINKIT_BUSY" = "1" ]; then
    tg "[WARN] KVM1 is busy with priority Blinkit fallback at $(date +%H:%M) IST — re-running$NEEDY on the VPS instead."
  else
    LOG "KVM1 UNREACHABLE — local rescue"
    tg "🛑 KVM1 is unreachable at $(date +%H:%M) IST — re-running$NEEDY on the VPS (fallback chain)."
  fi
fi

# ---- LOCAL RESCUE (serial, under the sweep-chain lock) ------------------------
est(){ case "$1" in flipkart-minutes) echo 300 ;; flipkart) echo 1500 ;; zepto) echo 2700 ;; *) echo 1800 ;; esac; }
CHAIN_LOCK="$DIR/logs/.sweep-chain.lock"
exec 7>"$CHAIN_LOCK"
WAIT_END=$((T - 1680)); W=$((WAIT_END - NOW)); [ "$W" -lt 0 ] && W=0
if ! flock -w "$W" 7; then
  LOG "sweep-chain lock still busy after ${W}s — cannot rescue before the batch (selfheal owns it post-10:00)"
  tg "⏳ KVM1 fallback: the VPS chain still holds the scrape lock at $(date +%H:%M) IST — cannot re-run$NEEDY before 10:00; the post-batch selfheal (~10:01) will ship them late."
  exit 0
fi

for P in $NEEDY; do
  if pgrep -f "run\.sh ${P}\$" >/dev/null 2>&1; then LOG "$P: already mid-run locally — skip"; continue; fi
  NOW="$(date +%s)"; D="$(est "$P")"
  if [ $((NOW + D)) -gt $((T - 300)) ]; then
    LOG "$P: too late for a defer-mode run (est ${D}s, batch at 10:00) — leaving to post-batch selfheal"
    tg "⚠️ KVM1 fallback: too late to re-run $P before the 10:00 batch — the post-batch selfheal will deliver it late."
    continue
  fi
  LOG "$P: local rescue (defer, est ${D}s)"
  if [ "$DRY" = "1" ]; then LOG "[DRYRUN] would run: DEFER_DELIVERY=1 SWEEP_ID=$SID COVERAGE_DAILY=1 ./run.sh $P"; continue; fi
  tg "🛠 KVM1 fallback: re-running $P on the VPS at store-open hours (defer into the 10:00 batch)."
  RC=0
  DEFER_DELIVERY="${SID:+1}" SWEEP_ID="$SID" COVERAGE_DAILY=1 \
    timeout $((D + 900)) ./run.sh "$P" >> logs/kvm1_watchdog_runs.log 2>&1 || RC=$?
  F="$(verdict_file "$P")"; V="none"; [ -n "$F" ] && V="$(verdict_of "$F")"
  LOG "$P: rescue rc=$RC verdict=$V"
  if [ "$V" = "OK" ]; then
    tg "✅ KVM1 fallback: $P re-run verdict OK — in today's 10:00 batch."
  else
    tg "⚠️ KVM1 fallback: $P re-run verdict $V (rc=$RC) — held back (gates not loosened); selfheal retries after the batch."
  fi
done
LOG "pass done"
exit 0
