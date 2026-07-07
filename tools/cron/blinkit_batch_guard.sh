#!/usr/bin/env bash
# blinkit_batch_guard.sh — owner rule 2026-07-07: the Blinkit report MUST be in
# the 10:00 batch / 10:30 Ecom-group post. Root cause of the daily misses: the
# Mac launchd scrape fired 03:45 IST when many Blinkit dark stores are closed,
# so drops resolved ~258-261 stores and ingest's store-collapse guard (correctly)
# refused them; accepted runs have all been daytime runs (~300+ stores).
#
# Cron runs this at 06:35 (early pass) and 08:45 (pass arg "late"). If today's
# workbook is not in output/ and the Mac wrapper isn't already running, trigger
# a fresh Mac scrape over ssh. If the Mac is unreachable, launch the strict
# VPS+KVM1 authenticated shard fallback. Never loosens the store floor — a
# refused drop stays refused; we just re-run at store-open hours and ingest
# through the same fail-closed gates.
set -u
DIR=/opt/ecom-intel
cd "$DIR" || exit 0
TODAY="$(date +%F)"
REPORT="output/Jivo-Blinkit-Live-Report-${TODAY}.xlsx"
WRAPPER="/Users/danny./VPS-Migration/scripts/run_blinkit_mac_to_vps.sh"
PASS="${1:-early}"
LOG(){ echo "[$(date '+%F %T')] blinkit_guard($PASS): $*"; }

tg(){ ( set +e
  [ -f "$DIR/secrets.env" ] && . "$DIR/secrets.env"
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] || exit 0
  curl -s --max-time 30 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=$1" >/dev/null ) || true; }

if [ -f "$REPORT" ]; then
  LOG "today's report present — OK"
  exit 0
fi

# Mac Pro known-offline sentinel: skip the doomed ssh re-run and go straight to
# the strict VPS+KVM1 fallback. If the marker is stale and the Mac is reachable
# again, remove it and fall through to the normal Mac path.
if [ -f "$DIR/logs/.mac-offline" ]; then
  if ssh -o BatchMode=yes -o ConnectTimeout=15 macpro "true" 2>/dev/null; then
    LOG "Mac offline marker is stale; Mac reachable again -> removing marker"
    rm -f "$DIR/logs/.mac-offline"
  else
    LOG "Mac flagged offline (logs/.mac-offline) -> launching VPS+KVM1 fallback"
    if "$DIR/tools/cron/blinkit_vps_kvm_fallback.sh" "$PASS" >> logs/blinkit_guard.log 2>&1; then
      LOG "VPS+KVM1 fallback completed"
    else
      LOG "VPS+KVM1 fallback FAILED"
      tg "[FAIL] Blinkit guard: VPS+KVM1 fallback failed for ${TODAY}; report was not delivered."
    fi
    exit 0
  fi
fi

if ssh -o BatchMode=yes -o ConnectTimeout=15 macpro "pgrep -f run_blinkit_mac_to_vps.sh >/dev/null" 2>/dev/null; then
  LOG "Mac scrape already running — not double-triggering"
  [ "$PASS" = "late" ] && tg "⏳ Blinkit guard 08:45: scrape still running — report may land close to the 10:00 batch. Watching."
  exit 0
fi

LOG "no report for $TODAY and no scrape running -> triggering Mac re-run"
if ssh -o BatchMode=yes -o ConnectTimeout=15 macpro "nohup $WRAPPER >/tmp/blinkit-guard-rerun.log 2>&1 & disown" 2>/dev/null; then
  LOG "trigger sent"
  if [ "$PASS" = "late" ]; then
    tg "🛠 Blinkit guard 08:45: no drop for ${TODAY} — triggered a fresh Mac scrape (LATE pass; ~1h50m run may miss the 10:00 batch, will still post when done)"
  else
    tg "🛠 Blinkit guard 06:35: no accepted drop for ${TODAY} — triggered a fresh Mac scrape; should land ~08:30, in time for the 10:00 batch"
  fi
else
  LOG "trigger FAILED (ssh unreachable?)"
  tg "[WARN] Blinkit guard: no drop for ${TODAY} and could NOT reach the Mac Pro - launching VPS+KVM1 authenticated fallback."
  if "$DIR/tools/cron/blinkit_vps_kvm_fallback.sh" "$PASS" >> logs/blinkit_guard.log 2>&1; then
    LOG "VPS+KVM1 fallback completed"
  else
    LOG "VPS+KVM1 fallback FAILED"
    tg "[FAIL] Blinkit guard: VPS+KVM1 fallback failed for ${TODAY}; report was not delivered."
  fi
fi
