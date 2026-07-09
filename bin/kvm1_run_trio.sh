#!/usr/bin/env bash
# kvm1_run_trio.sh — KVM1 store-open serial duo: flipkart -> zepto.
#
# Phase 2 split (owner-approved 2026-07-07): the VPS keeps flipkart-minutes (its
# logged-in Flipkart API is DC-BOUND — from this box's IP northern pincodes 302
# to another DC and return 0 rows; smoke-tested 2026-07-07) + the Amazon family +
# all orchestration/ingest/batch; THIS box scrapes flipkart + zepto at store-open
# hours (~07:30 IST start) from its own IP and dead-drops each result.json back
# to the VPS, exactly like the Mac Pro blinkit/swiggy feeders:
#     scrape (PINCODES_FILE/OUT_FILE) -> rsync drop -> ssh vps kvm1_ingest.sh
# The VPS-side ingest (tools/cron/kvm1_ingest.sh) replays the normal run.sh
# pipeline on the drop (excel -> enrichers -> review verdict gate -> history/
# coverage -> defer-spool into the pending 10:00 batch). Nothing here loosens
# any review gate — a BROKEN drop is held on the VPS like any local run.
#
# Launch: primary = VPS cron 07:30 IST (tools/cron/kvm1_trio_launch.sh via ssh
# nohup); backup = local cron 07:40 IST (CRON_TZ=Asia/Kolkata — THIS BOX RUNS
# UTC). flock makes the second launcher a no-op. Watchdog on the VPS
# (tools/cron/kvm1_watchdog.sh) rescues platforms locally if this box dies.
#
# Env: SWEEP_ID (optional, forwarded to the ingest; ingest self-discovers the
#      pending batch when absent), TRIO_PLATFORMS (test override).
set -uo pipefail
export TZ=Asia/Kolkata
ROOT=/opt/ecom-intel
cd "$ROOT" || exit 1
mkdir -p logs runs
DATE="$(date +%F)"
LOG(){ echo "[$(date '+%F %T IST')] trio: $*"; }

# ---- telegram (best-effort, owner channel; same secrets.env pattern as VPS) --
tg(){ ( set +e
  [ -f "$ROOT/secrets.env" ] && . "$ROOT/secrets.env"
  CH="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "$CH" ] || exit 0
  curl -s --max-time 30 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CH}" \
    --data-urlencode "text=$1" >/dev/null ) || true; }

# Blinkit has priority on this box. Its fallback shard may still be running when
# the 07:30 Flipkart/Zepto trio launch fires; do not contend for Playwright.
blinkit_active(){
  pgrep -f 'run_platform_shard.sh blinkit' >/dev/null 2>&1 && return 0
  local cwd
  for p in /proc/[0-9]*/cwd; do
    cwd="$(readlink "$p" 2>/dev/null || true)"
    case "$cwd" in
      */platforms/blinkit|*/work/blinkit) return 0 ;;
    esac
  done
  return 1
}

if [ "${TRIO_ALLOW_DURING_BLINKIT:-0}" != "1" ] && blinkit_active; then
  LOG "Blinkit fallback shard active on KVM1 — deferring Flipkart/Zepto trio"
  tg "[WARN] KVM1 trio deferred on $DATE: Blinkit fallback shard is active and has priority. VPS watchdog will retry/rescue Flipkart/Zepto later."
  exit 0
fi

# ---- single-flight: one trio at a time (backup cron + VPS trigger overlap) ---
exec 9>"$ROOT/logs/.trio.lock"
if ! flock -n 9; then LOG "another trio run holds logs/.trio.lock — exit"; exit 0; fi

# one full pass per day: a re-trigger after a completed day is a no-op
DONE_MARK="$ROOT/logs/trio-done-$DATE"
if [ -f "$DONE_MARK" ] && [ "${TRIO_FORCE:-0}" != "1" ]; then
  LOG "trio already completed today ($DONE_MARK) — exit (TRIO_FORCE=1 to re-run)"
  exit 0
fi

PLATFORMS="${TRIO_PLATFORMS:-flipkart zepto}"
LOG "START (serial: $PLATFORMS) sweep=${SWEEP_ID:-auto}"
STATUS=""

# housekeeping: drop run artifacts/logs older than 10 days (box has 48GB)
find "$ROOT/runs" -maxdepth 1 -type f -mtime +10 -delete 2>/dev/null || true
find "$ROOT/logs" -maxdepth 1 -type f \( -name "*.log" -o -name "trio-*" \) -mtime +10 -delete 2>/dev/null || true

scrape_timeout(){ case "$1" in
  flipkart-minutes) echo 1500 ;;   # ~2m normal; generous for the browser-fallback path
  flipkart)         echo 2700 ;;   # ~25m normal
  zepto)            echo "${ZEPTO_TRIO_TIMEOUT_SECS:-7200}" ;;   # checkpointed; 429-heavy days need >75m
  *)                echo 3600 ;; esac; }

push_and_ingest(){ # $1 platform  $2 result-file  -> 0 on ingest triggered
  local p="$1" out="$2" drop rc i
  drop="/opt/ecom-intel/platforms/$p/kvm1-drops/$(basename "$out")"
  for i in 1 2 3; do
    if timeout 120 ssh -o BatchMode=yes vps "mkdir -p '/opt/ecom-intel/platforms/$p/kvm1-drops'" \
       && timeout 300 rsync -az "$out" "vps:$drop"; then
      LOG "$p: drop pushed -> vps:$drop (attempt $i)"
      if timeout 1800 ssh -o BatchMode=yes vps \
           "cd /opt/ecom-intel && SWEEP_ID='${SWEEP_ID:-}' ./tools/cron/kvm1_ingest.sh '$p' '$drop' >> logs/kvm1-ingest.log 2>&1"; then
        LOG "$p: VPS ingest OK"
        return 0
      else
        rc=$?
        LOG "$p: VPS ingest returned rc=$rc (attempt $i) — see vps logs/kvm1-ingest.log"
        # ingest failures are not retried blindly (the drop is already on the VPS;
        # a re-run could double-append history). One retry only for ssh-drop (rc=255).
        [ "$rc" -ne 255 ] && return "$rc"
      fi
    else
      LOG "$p: push attempt $i failed; retrying in 60s"
    fi
    sleep 60
  done
  return 1
}

for P in $PLATFORMS; do
  PDIR="$ROOT/platforms/$P"
  OUT="$ROOT/runs/${P}-${DATE}.result.json"
  PLOG="$ROOT/logs/${P}-${DATE}.log"
  rm -f "$OUT"
  T0=$(date +%s)
  LOG "$P: scraping (timeout $(scrape_timeout "$P")s, log $PLOG)"
  RC=0
  case "$P" in
    flipkart)  # national listing set — scrape.js reads skus.master.tsv + its own pincodes.json.
               # NOTE: flipkart's scrape.js does NOT honor OUT_FILE (verified 2026-07-07);
               # it writes $PDIR/result.json — copy that out afterwards.
      rm -f "$PDIR/result.json"
      ( cd "$PDIR" && timeout "$(scrape_timeout "$P")" node scrape.js ) >>"$PLOG" 2>&1 || RC=$?
      [ -s "$PDIR/result.json" ] && cp "$PDIR/result.json" "$OUT" ;;
    *)         # per-pincode platforms use the DAILY price-tracking config (COVERAGE_DAILY parity)
      ( cd "$PDIR" && PINCODES_FILE="$PDIR/pincodes.daily.json" OUT_FILE="$OUT" \
          timeout "$(scrape_timeout "$P")" node scrape.js ) >>"$PLOG" 2>&1 || RC=$? ;;
  esac
  T1=$(date +%s)
  if [ "$RC" -ne 0 ] || [ ! -s "$OUT" ]; then
    LOG "$P: scrape FAILED rc=$RC after $((T1-T0))s (out=$([ -s "$OUT" ] && echo present || echo missing))"
    : > "$ROOT/logs/trio-fail-${P}-${DATE}"
    STATUS="$STATUS $P:FAIL(rc=$RC)"
    tg "⚠️ KVM1 trio: $P scrape FAILED (rc=$RC, $((T1-T0))s) on $DATE. The VPS watchdog/guard will rescue it locally; see kvm1 $PLOG"
    continue
  fi
  LOG "$P: scrape OK in $((T1-T0))s -> $OUT"
  if push_and_ingest "$P" "$OUT"; then
    STATUS="$STATUS $P:OK($((T1-T0))s)"
  else
    : > "$ROOT/logs/trio-fail-${P}-${DATE}"
    STATUS="$STATUS $P:PUSH-FAIL"
    tg "⚠️ KVM1 trio: $P scraped OK but push/ingest to the VPS FAILED on $DATE — result saved at kvm1:$OUT; VPS watchdog will rescue."
  fi
done

LOG "DONE:$STATUS"
case "$STATUS" in
  *FAIL*)
    FAIL_MARK="$ROOT/logs/trio-fail-$DATE"
    echo "$STATUS" > "$FAIL_MARK"
    rm -f "$DONE_MARK"
    LOG "failures recorded at $FAIL_MARK; no done-marker written so watchdog/manual force can resume"
    ;;  # failures already alerted individually
  *)
    echo "$STATUS" > "$DONE_MARK"
    LOG "all platforms clean"
    ;;
esac
exit 0
