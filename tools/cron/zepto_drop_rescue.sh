#!/usr/bin/env bash
# zepto_drop_rescue.sh — rescue a stranded Zepto Mac-drop.
#
# WHY: on 2026-07-11 the Mac Pro dropped zepto-20260711-072002.json at 07:20 but
# tools/cron/macpro_zepto_ingest.sh gave up after waiting 2400s on a stuck local
# run.sh, and NOTHING retried it — the drop sat un-ingested ~4h until a manual
# rescue at ~3:05 PM. This hourly rescuer closes that gap: if today's Zepto report
# is still missing but a today drop exists, it re-invokes the ingest wrapper (with
# an ABSOLUTE drop path — a relative path fails inside run.sh with "drop
# missing/empty"). If the ingest lands AFTER the 10:00 batch already posted (so the
# group never got Zepto), it posts just the Zepto workbook to the Ecom-team group
# once, guarded by a per-day marker.
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
WA_GROUP="120363047864912511@g.us"
LATE_MARK="logs/zepto-late-wa-${D}.sent"
FAIL_MARK="logs/.zepto-rescue-failed-${D}.sent"

# Report already built today -> nothing to rescue.
[ -f "$REPORT" ] && exit 0

# Newest today drop (Mac Pro dead-drop). None -> scrape-side problem, not ours.
DROP="$(ls -t platforms/zepto/mac-drops/zepto-${DC}-*.json 2>/dev/null | head -1)"
[ -n "$DROP" ] || exit 0
ABS_DROP="$DIR/${DROP#./}"

# ---------- from here we have real work: single-flight ----------
exec 9>"logs/.zepto_drop_rescue.lock"
if ! flock -n 9; then LOG "another rescue run holds the lock — exit"; exit 0; fi

# Re-check under the lock: a concurrent run (or the normal ingest) may have just built it.
[ -f "$REPORT" ] && { LOG "report appeared while acquiring lock — nothing to do"; exit 0; }

# ---------- Telegram alert (mirror the other guards) ----------
tg(){ ( set +e
  [ -f "$DIR/secrets.env" ] && . "$DIR/secrets.env"
  CH="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "$CH" ] || exit 0
  curl -s --max-time 30 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CH}" --data-urlencode "text=$1" >/dev/null ) || true; }

# Did today's 10:00 batch already post to the Ecom group? (same awk as
# morning_report_guard.sh batch_posted(): look for the "posted N reports" line
# AFTER today's mailer-start marker.)
batch_posted(){
  awk -v d="$D" '$0 ~ ("mailer start slot=.* date=" d) {f=1}
       f && / reports to Ecom team group/ {found=1}
       END {exit found?0:1}' logs/mailer.log 2>/dev/null
}

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

# Report exists now. If the 10:00 batch already went to the group WITHOUT Zepto,
# post just the Zepto workbook late (once, marker-guarded). If the batch hasn't
# posted yet, the normal batch will carry Zepto — don't double-post.
if [ -f "$LATE_MARK" ]; then
  LOG "late-WA marker already present — Zepto already posted late; done"
  exit 0
fi

if batch_posted; then
  LOG "10:00 batch already posted without Zepto -> posting Zepto workbook late to the Ecom group"
  # Best-effort: make sure the gateway is up (mirror the mailer's approach).
  if ! curl -s --max-time 5 http://127.0.0.1:3001/health 2>/dev/null | grep -q '"connected"'; then
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/0}"
    export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/0/bus}"
    systemctl --user reset-failed hermes-gateway-wa-test.service 2>/dev/null || true
    systemctl --user start        hermes-gateway-wa-test.service 2>/dev/null || true
    for _ in $(seq 1 30); do
      curl -s --max-time 3 http://127.0.0.1:3001/health 2>/dev/null | grep -q '"connected"' && break
      sleep 1
    done
  fi
  B="$(python3 -c 'import json,os,sys; p=os.path.abspath(sys.argv[1]); print(json.dumps({"chatId": sys.argv[2], "filePath": p, "mediaType": "document", "fileName": os.path.basename(p)}))' "$REPORT" "$WA_GROUP")"
  R="$(curl -s --max-time 120 -X POST http://127.0.0.1:3001/send-media -H 'Content-Type: application/json' -d "$B")"
  LOG "WhatsApp late Zepto doc $(basename "$REPORT"): $R"
  if echo "$R" | grep -q '"success":true'; then
    printf '%s %s %s\n' "$(date '+%F %T')" "$WA_GROUP" "$(basename "$REPORT")" > "$LATE_MARK"
    tg "✅ Zepto was stranded (drop un-ingested past the 10:00 batch); rescued and posted LATE to the Ecom team group for ${D}."
  else
    LOG "late Zepto WhatsApp post FAILED — leaving marker unset so the next hourly tick retries"
    tg "⚠️ Zepto stranded-drop was rescued and ingested, but the LATE WhatsApp post to the Ecom group failed for ${D}. Will retry hourly. Check the gateway (logs/wa_gateway_heartbeat.log)."
    exit 1
  fi
else
  LOG "10:00 batch not yet posted — the normal batch will carry Zepto; no separate post"
  tg "✅ Zepto stranded drop was rescued and ingested for ${D}; today's batch hasn't posted yet, so the normal batch will carry it."
fi
exit 0
