#!/usr/bin/env bash
# zepto_drop_rescue.sh — rescue a stranded Zepto Mac-drop.
#
# WHY: on 2026-07-11 the Mac Pro dropped zepto-20260711-072002.json at 07:20 but
# tools/cron/macpro_zepto_ingest.sh gave up after waiting 2400s on a stuck local
# run.sh, and NOTHING retried it — the drop sat un-ingested ~4h until a manual
# rescue at ~3:05 PM. This hourly rescuer closes that gap: if today's Zepto report
# is still missing but a today drop exists, it re-invokes the ingest wrapper (with
# an ABSOLUTE drop path — a relative path fails inside run.sh with "drop
# missing/empty"). Delivery always delegates to the locked 10:30 dispatcher,
# whose SHA/messageId receipts make late retries idempotent.
#
# Cron (installed 2026-07-11):
#   20 10-14 * * * cd /opt/ecom-intel && ./tools/cron/zepto_drop_rescue.sh \
#       >> logs/zepto_drop_rescue.log 2>&1   # zepto stranded-drop rescuer (2026-07-11)
#
# Scrape-side failures (no drop at all) are the zepto_macpro_guard's job, not ours.
set -u
DIR=/opt/ecom-intel
cd "$DIR" || exit 0
mkdir -p logs
D="$(date +%F)"
DC="$(date +%Y%m%d)"
LOG(){ echo "[$(date '+%F %T')] zepto_drop_rescue: $*"; }

REPORT="output/Jivo-Zepto-Live-Report-${D}.xlsx"
FAIL_MARK="logs/.zepto-rescue-failed-${D}.sent"

# ---------- Telegram alert (mirror the other guards) ----------
tg(){ ( set +e
  [ -f "$DIR/secrets.env" ] && . "$DIR/secrets.env"
  CH="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "$CH" ] || exit 0
  curl -s --max-time 30 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CH}" --data-urlencode "text=$1" >/dev/null ) || true; }

deliver_if_due(){
  local now
  now="$(TZ=Asia/Kolkata date +%H%M)"
  if [ "$((10#$now))" -lt 1030 ]; then
    LOG "report ready before 10:30; consolidated batch owns delivery"
    return 0
  fi
  LOG "delegating late delivery to the locked, receipt-based batch dispatcher"
  MAILER_SKIP_EMAIL=1 MAILER_SKIP_WAIT=1 ./tools/mailer/mail_price_data.sh am \
    || { tg "⚠️ Zepto report exists for ${D}, but idempotent Ecom batch retry failed. See logs/mailer.log."; return 1; }
}

# A built report may still need a receipt-safe late delivery retry.
if [ -f "$REPORT" ]; then
  deliver_if_due
  exit $?
fi

# Newest today drop (Mac Pro dead-drop). None -> scrape-side problem, not ours.
DROP="$(ls -t platforms/zepto/mac-drops/zepto-${DC}-*.json 2>/dev/null | head -1)"
[ -n "$DROP" ] || exit 0
ABS_DROP="$DIR/${DROP#./}"

# ---------- from here we have real work: single-flight ----------
exec 9>"logs/.zepto_drop_rescue.lock"
if ! flock -n 9; then LOG "another rescue run holds the lock — exit"; exit 0; fi

# Re-check under the lock: a concurrent run (or the normal ingest) may have just built it.
[ -f "$REPORT" ] && { LOG "report appeared while acquiring lock — nothing to do"; exit 0; }

LOG "Zepto report missing but drop present ($DROP) -> ingesting via macpro_zepto_ingest.sh (absolute path)"
RC=0
./tools/cron/macpro_zepto_ingest.sh "$ABS_DROP" >> logs/zepto_drop_rescue.log 2>&1 || RC=$?

if [ ! -f "$REPORT" ]; then
  LOG "ingest finished rc=$RC but report still absent — rescue FAILED"
  if [ ! -f "$FAIL_MARK" ]; then
    tg "❌ Zepto stranded-drop rescue FAILED (rc=$RC). Drop=${ABS_DROP}. See logs/zepto_drop_rescue.log and logs/run-zepto.out. Zepto is NOT in today's group batch."
    touch "$FAIL_MARK"
  else
    LOG "fail alert already sent today — suppressed"
  fi
  exit 1
fi

LOG "ingest OK — Zepto report now present: $REPORT"
deliver_if_due
