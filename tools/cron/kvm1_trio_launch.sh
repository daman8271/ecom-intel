#!/usr/bin/env bash
# kvm1_trio_launch.sh — VPS cron 07:30 IST: fire the KVM1 store-open trio.
#
# Phase 2 split (2026-07-07). Launch is DETACHED on KVM1 (setsid + nohup), so an
# ssh drop after launch cannot kill the trio; the runner has its own flock and a
# per-day done-marker, so the 07:40 IST KVM1-local backup cron and any manual
# re-trigger are safe no-ops. If the launch itself fails (box down / ssh dead),
# alert the owner — tools/cron/kvm1_watchdog.sh (08:10/08:40/09:05) owns the
# local-rescue fallback, and the flipkart_batch_guard keeps its own fallback.
set -uo pipefail
DIR=/opt/ecom-intel
cd "$DIR" || exit 1
mkdir -p logs
LOG(){ echo "[$(date '+%F %T')] kvm1_launch: $*"; }
tg(){ ( set +e
  [ -f "$DIR/secrets.env" ] && . "$DIR/secrets.env"
  CH="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "$CH" ] || exit 0
  curl -s --max-time 30 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CH}" \
    --data-urlencode "text=$1" >/dev/null ) || true; }

# today's pending sweep id (best-effort; the ingest self-discovers when empty)
SID=""
TODAY="$(date +%F)"
for l in output/.batch/launched-"$TODAY"-*; do
  [ -e "$l" ] || continue
  s="${l##*/launched-}"
  [ -e "output/.batch/sent-$s" ] && continue
  SID="$s"
done

for i in 1 2 3; do
  if timeout 60 ssh -o BatchMode=yes -o ConnectTimeout=15 kvm1 \
      "setsid nohup env SWEEP_ID='$SID' /opt/ecom-intel/bin/kvm1_run_trio.sh >> /opt/ecom-intel/logs/trio.log 2>&1 & echo LAUNCHED-\$!"; then
    LOG "trio launched on KVM1 (attempt $i, sweep=${SID:-auto})"
    exit 0
  fi
  LOG "launch attempt $i failed; retrying in 45s"
  sleep 45
done

LOG "KVM1 UNREACHABLE — trio NOT launched"
: > logs/.kvm1_launch_failed-"$TODAY"
tg "🛑 KVM1 trio launch FAILED at $(date +%H:%M) IST — box unreachable from the VPS. Backup: KVM1's own 07:40 cron (if the box is alive) or the 08:10/08:40 watchdog will re-run flipkart-minutes/flipkart/zepto on the VPS."
exit 1
