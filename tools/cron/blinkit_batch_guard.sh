#!/usr/bin/env bash
# blinkit_batch_guard.sh — owner rule updated 2026-07-14: the Blinkit report MUST
# reach the Ecom group by 11:00 IST. Root cause of the daily misses: the
# Mac launchd scrape fired 03:45 IST when many Blinkit dark stores are closed,
# so drops resolved ~258-261 stores and ingest's store-collapse guard (correctly)
# refused them; accepted runs have all been daytime runs (~300+ stores).
#
# Cron runs this at 07:20 (early pass) and 08:45 (pass arg "late"). If today's
# workbook is not in output/ and the Mac wrapper isn't already running, trigger
# a fresh Mac scrape over ssh. If the Mac is unreachable, launch the strict
# VPS+KVM1 authenticated shard fallback. Never loosens the store floor — a
# refused drop stays refused; we just re-run at store-open hours and ingest
# through the same fail-closed gates.
set -u
DIR=/opt/ecom-intel
cd "$DIR" || exit 0
. tools/laptop/lib.sh
TODAY="$(date +%F)"
REPORT="output/Jivo-Blinkit-Live-Report-${TODAY}.xlsx"
WRAPPER="/Users/danny./VPS-Migration/scripts/run_blinkit_mac_to_vps.sh"
PASS="${1:-early}"
DELIVERY_DEADLINE="${BLINKIT_DELIVERY_DEADLINE:-11:00}"
LOG(){ echo "[$(date '+%F %T')] blinkit_guard($PASS): $*"; }

mac_blinkit_running(){
  ssh -o BatchMode=yes -o ConnectTimeout=15 macpro "pgrep -f run_blinkit_mac_to_vps.sh >/dev/null" 2>/dev/null
}

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

case "$PASS" in
  drycheck|status)
    latest_drop="$(ls -t platforms/blinkit/mac-drops/blinkit-"${TODAY//-/}"*.json platforms/blinkit/mac-drops/blinkit-"${TODAY//-/}"T*.json 2>/dev/null | head -1 || true)"
    if mac_blinkit_running; then
      LOG "report missing; Mac scrape running; latest_drop=$(basename "${latest_drop:-none}")"
    else
      LOG "report missing; Mac scrape not running; latest_drop=$(basename "${latest_drop:-none}")"
    fi
    exit 0
    ;;
esac

# Device-team split (laptop worker #4, 2026-07-13): while today's team run is
# active the Mac only scrapes shard-0 and no mac-drops file appears — that is
# NOT a miss. blinkit_team_watch.sh (cron */10 06-11) owns pull/merge/rescue;
# the late pass reclaims control only when the team machinery is provably idle.
TEAM_PTR="shards/runs/ACTIVE-blinkit-team"
if [ -f "$TEAM_PTR" ]; then
  TEAM_ID="$(head -1 "$TEAM_PTR" 2>/dev/null || true)"
  if [ -n "$TEAM_ID" ] && [ "${TEAM_ID#"$(date +%Y%m%d)"-}" != "$TEAM_ID" ]; then
    if [ "$PASS" = "late" ]; then
      if mac_blinkit_running \
         || pgrep -f "run_platform_shard.sh blinkit|blinkit_team_merge.sh|platforms/blinkit/ingest.sh" >/dev/null 2>&1 \
         || laptop_file_fresh "$WIN_RUNS_FS/$TEAM_ID/run.progress.json" 900 \
         || [ -s "shards/runs/$TEAM_ID/blinkit/shard-0-of-2/result.json" ] \
         || [ -s "shards/runs/$TEAM_ID/blinkit/shard-1-of-2/result.json" ]; then
        LOG "team run $TEAM_ID still in flight at late pass — standing by (team watch owns rescue)"
        exit 0
      fi
      LOG "team run $TEAM_ID stalled with nothing running — clearing pointer, falling back to legacy guard logic"
      tg "⚠️ Blinkit guard 08:45: device-team run $TEAM_ID stalled; falling back to a full legacy re-run."
      rm -f "$TEAM_PTR"
    else
      LOG "team run $TEAM_ID active (Mac shard-0 + laptop shard-1) — standing by"
      exit 0
    fi
  else
    rm -f "$TEAM_PTR"   # stale pointer from a previous day
  fi
fi

attempt_held_drop_repair(){
  local before after
  before="$(ls -t platforms/blinkit/mac-drops/blinkit-"${TODAY//-/}"*.json platforms/blinkit/mac-drops/blinkit-"${TODAY//-/}"T*.json 2>/dev/null | head -1 || true)"
  [ -n "$before" ] || return 1
  LOG "today's Mac drop exists but report missing -> trying targeted repair before rerun ($(basename "$before"))"
  "$DIR/tools/cron/blinkit_repair_held_mac_drop.sh" >> logs/blinkit_guard.log 2>&1 || true
  if [ -f "$REPORT" ]; then
    LOG "targeted repair produced report — triggering direct WhatsApp sweep"
    "$DIR/tools/cron/blinkit_whatsapp_delivery_sweep.sh" "guard-$PASS-repair" >> logs/blinkit_guard.log 2>&1 || true
    return 0
  fi
  after="$(ls -t platforms/blinkit/mac-drops/blinkit-"${TODAY//-/}"*.json platforms/blinkit/mac-drops/blinkit-"${TODAY//-/}"T*.json 2>/dev/null | head -1 || true)"
  LOG "targeted repair did not produce report (latest_drop=$(basename "${after:-none}"))"
  return 1
}

# Mac Pro known-offline sentinel: skip the doomed ssh re-run and fall back —
# laptop-first (residential worker #4, goal #81 step 7), then the strict
# VPS+KVM1 path if the laptop cannot engage. If the marker is stale and the Mac
# is reachable again, remove it and fall through to the normal Mac path.
if [ -f "$DIR/logs/.mac-offline" ]; then
  if ssh -o BatchMode=yes -o ConnectTimeout=15 macpro "true" 2>/dev/null; then
    LOG "Mac offline marker is stale; Mac reachable again -> removing marker"
    rm -f "$DIR/logs/.mac-offline"
  else
    LOG "Mac flagged offline (logs/.mac-offline) -> laptop-first fallback (worker #4 residential), then VPS+KVM1"
    if "$DIR/tools/laptop/blinkit_macdown_fallback.sh" "$PASS" >> logs/blinkit_guard.log 2>&1; then
      LOG "laptop+VPS mac-down fallback engaged (team watch owns merge/rescue)"
    elif "$DIR/tools/cron/blinkit_vps_kvm_fallback.sh" "$PASS" >> logs/blinkit_guard.log 2>&1; then
      LOG "VPS+KVM1 fallback completed"
    else
      LOG "VPS+KVM1 fallback FAILED"
      tg "[FAIL] Blinkit guard: VPS+KVM1 fallback failed for ${TODAY}; report was not delivered."
    fi
    exit 0
  fi
fi

if mac_blinkit_running; then
  LOG "Mac scrape already running — not double-triggering"
  [ "$PASS" = "late" ] && tg "⏳ Blinkit guard 08:45: scrape still running — watching against the ${DELIVERY_DEADLINE} Ecom-group deadline."
  exit 0
fi

if attempt_held_drop_repair; then
  exit 0
fi

LOG "no report for $TODAY and no scrape running -> triggering Mac re-run"
if ssh -o BatchMode=yes -o ConnectTimeout=15 macpro "nohup $WRAPPER >/tmp/blinkit-guard-rerun.log 2>&1 & disown" 2>/dev/null; then
  LOG "trigger sent"
  if [ "$PASS" = "late" ]; then
    tg "🛠 Blinkit guard 08:45: no drop for ${TODAY} — triggered a fresh Mac scrape (LATE pass; targeting the ${DELIVERY_DEADLINE} Ecom-group deadline)"
  else
    tg "🛠 Blinkit guard 07:20: no accepted drop for ${TODAY} — triggered a fresh Mac scrape; targeting delivery before ${DELIVERY_DEADLINE} IST"
  fi
else
  LOG "trigger FAILED (ssh unreachable?)"
  tg "[WARN] Blinkit guard: no drop for ${TODAY} and could NOT reach the Mac Pro - trying laptop-first fallback, then VPS+KVM1."
  if "$DIR/tools/laptop/blinkit_macdown_fallback.sh" "$PASS" >> logs/blinkit_guard.log 2>&1; then
    LOG "laptop+VPS mac-down fallback engaged (team watch owns merge/rescue)"
  elif "$DIR/tools/cron/blinkit_vps_kvm_fallback.sh" "$PASS" >> logs/blinkit_guard.log 2>&1; then
    LOG "VPS+KVM1 fallback completed"
  else
    LOG "VPS+KVM1 fallback FAILED"
    tg "[FAIL] Blinkit guard: VPS+KVM1 fallback failed for ${TODAY}; report was not delivered."
  fi
fi
