#!/usr/bin/env bash
# morning_report_guard.sh — owner rule 2026-07-08 (goal #2 this session):
# BigBasket NATIONAL + BigBasket PINCODE + BLINKIT must reach the morning
# group/batch path. Root cause of the 2026-07-08 triple miss: the Mac Pro was powered off
# all night, so (a) run_all never got the Mac `bigbasket.json` drop -> BB national
# was "skipped (Mac drop late/absent)" from the 10:00 batch; (b) the 3 AM pincode
# team run lost its Mac shard (ssh 127.0.0.1:22022 refused) and delivered degraded/
# late; (c) no Mac Blinkit scrape -> the VPS+KVM1 fallback was (correctly) refused by
# the auth-verified / freshness gates. All three failed SILENTLY.
#
# This guard is the belt-and-suspenders safety net (owner picked "watchdog +
# auto-catchup"). It NEVER loosens any data-quality gate — it only re-runs the same
# fail-closed scrape/ingest paths and always alerts the owner.
#
#   early  (~08:40 IST, before the 10:00 batch send): make sure BB national is
#          SPOOLED INTO today's pending batch. Handles two failure modes:
#            - Mac drop present but run_all checked before it landed  -> just spool it.
#            - Mac drop absent (Mac down)                              -> VPS national
#              scrape (scrape.js) -> ingest.sh --deliver (session/rows gate + spool).
#   check  (~10:35 IST, after the 10:00 batch + 10:30 Blinkit deadline): verify all
#          three routed today, send the owner a completeness summary on Telegram +
#          WhatsApp, auto-catch-up BB pincode (Mac shard re-routed to KVM1) if missing,
#          and alert (Mac-only) for a missing Blinkit.
#
# Reuses: platforms/bigbasket/{scrape.js,ingest.sh,team_run_pincode.sh},
#         tools/cron/spool_into_batch.sh, secrets.env (Telegram), :3001 WhatsApp gw.
# GUARD_DRYRUN=1 => detect + alert only, run NO scrape/re-run (used to self-test).
set -u
DIR=/opt/ecom-intel
cd "$DIR" || exit 0
TODAY="$(date +%F)"
PASS="${1:-check}"
DRY="${GUARD_DRYRUN:-0}"
LOG(){ echo "[$(date '+%F %T')] morning_guard($PASS): $*"; }

# ---------- alert channels (reuse the exact patterns the other guards use) ----------
tg(){ ( set +e
  [ -f "$DIR/secrets.env" ] && . "$DIR/secrets.env"
  CH="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "$CH" ] || exit 0
  curl -s --max-time 30 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CH}" --data-urlencode "text=$1" >/dev/null ) || true; }

wa(){ ( set +e   # owner self-chat via the local WhatsApp gateway (memory: 918899011758)
  curl -s --max-time 5 http://127.0.0.1:3001/health 2>/dev/null | grep -q '"connected"' || exit 0
  PAY="$(python3 -c 'import json,sys; print(json.dumps({"chatId":"918899011758@s.whatsapp.net","message":sys.argv[1]}))' "$1")"
  curl -s --max-time 20 -X POST http://127.0.0.1:3001/send -H 'Content-Type: application/json' -d "$PAY" >/dev/null ) || true; }

TAG="${GUARD_TAG:-}"
alert(){ LOG "ALERT: $1"; tg "${TAG}$1"; wa "${TAG}$1"; }

# ---------- detection ----------
NAT_RPT="output/Jivo-Bigbasket-Live-Report-${TODAY}.xlsx"
PIN_RPT="output/Jivo-BigBasket-Pincode-Report-${TODAY}.xlsx"
NAT_MARK="logs/.national-guard-spooled-${TODAY}"

national_spooled(){    # did BB national make today's batch (run_all's spool OR ours)?
  grep -q "bigbasket.*spooled for batch.*${TODAY}" logs/cron.log 2>/dev/null && return 0
  [ -f "$NAT_MARK" ] && return 0
  return 1
}
pincode_routed(){ [ -f "$PIN_RPT" ]; }  # output/ copy is the group/batch handoff
blinkit_sent(){ [ -f "logs/blinkit-main-wa-${TODAY}.sent" ]; }

# ======================================================================= EARLY
if [ "$PASS" = "early" ]; then
  if national_spooled; then
    LOG "BB national already spooled into today's batch — OK"
    exit 0
  fi
  # A sent batch means we're past the window; fall through to a build for the record + alert.
  if [ -f "$NAT_RPT" ]; then
    LOG "BB national report present but not yet spooled -> spooling into pending batch (run_all timing race)"
    if [ "$DRY" = "1" ]; then LOG "[dryrun] would spool $NAT_RPT"; exit 0; fi
    if ./tools/cron/spool_into_batch.sh bigbasket "BigBasket" "$DIR/$NAT_RPT" >>logs/morning_report_guard.log 2>&1; then
      touch "$NAT_MARK"; alert "🛠 Morning guard: BB national was built but hadn't been spooled — added it to the 10:00 batch for ${TODAY}."
    else
      alert "[WARN] Morning guard: BB national present but spool_into_batch failed for ${TODAY} — check logs."
    fi
    exit 0
  fi
  # No national report at all -> Mac drop absent (Mac down). Run the VPS catch-up scrape.
  LOG "BB national report absent (Mac drop missing) -> VPS national catch-up scrape"
  if [ "$DRY" = "1" ]; then LOG "[dryrun] would run: node scrape.js -> ingest.sh --deliver"; alert "🛠 [dryrun] Morning guard would VPS-catch-up BB national for ${TODAY}."; exit 0; fi
  OUT="/tmp/bb-national-catchup-${TODAY}.json"
  ( cd "$DIR/platforms/bigbasket" && OUT_FILE="$OUT" node scrape.js ) >>logs/bigbasket-national-catchup.log 2>&1
  if [ -f "$OUT" ] && ./platforms/bigbasket/ingest.sh "$OUT" --deliver >>logs/bigbasket-national-catchup.log 2>&1; then
    touch "$NAT_MARK"
    alert "✅ Morning guard: Mac drop was absent — ran the VPS BigBasket-national catch-up and spooled it into the 10:00 batch for ${TODAY}."
  else
    alert "[FAIL] Morning guard: BB national VPS catch-up failed for ${TODAY} (scrape/session gate). It will NOT be in the 10:00 batch — needs a look."
  fi
  exit 0
fi

# ======================================================================= CHECK
# Completeness summary + auto-catch-up for anything still missing after the batch.
NAT_OK=0; PIN_OK=0; BLK_OK=0
national_spooled && NAT_OK=1
pincode_routed   && PIN_OK=1
blinkit_sent     && BLK_OK=1

emoji(){ [ "$1" = "1" ] && echo "✅" || echo "❌"; }
SUMMARY="Morning report check ${TODAY}:
$(emoji $NAT_OK) BigBasket national (10:00 batch)
$(emoji $PIN_OK) BigBasket pincode-wise (Ecom group/batch)
$(emoji $BLK_OK) Blinkit (Ecom group)"

# --- auto-catch-up: BB pincode (Mac shard re-routed to KVM1), single-flight ---
if [ "$PIN_OK" != "1" ]; then
  if [ "$DRY" = "1" ]; then
    LOG "[dryrun] would launch KVM-rerouted pincode re-run"
    SUMMARY="$SUMMARY
↳ [dryrun] would re-run BB pincode via KVM1 for Ecom group/batch output."
  elif pgrep -f 'team_run_pincode.sh (run|collect|merge|build)' >/dev/null 2>&1 || [ -f logs/.bb-finisher.lock ]; then
    LOG "pincode job already running — not double-triggering"
    SUMMARY="$SUMMARY
↳ BB pincode re-run already in progress."
  else
    LOG "BB pincode missing from output/ -> launching KVM-rerouted team re-run in tmux"
    RUNID="bb-guard-$(date +%Y%m%d-%H%M%S)"
    /usr/bin/tmux new-session -d -s "$RUNID" \
      "cd $DIR && BB_TEAM_MAC_HOST=kvm1 flock -n logs/.bigbasket-team.lock ./platforms/bigbasket/team_run_pincode.sh run >> logs/bigbasket-team-pincode.log 2>&1" 2>/dev/null \
      && SUMMARY="$SUMMARY
↳ Re-running BB pincode now (Mac→KVM1); expect Ecom group/batch output ~1:30 PM." \
      || SUMMARY="$SUMMARY
↳ [WARN] could not launch BB pincode re-run — check logs."
  fi
fi

# --- Blinkit is Mac-only: cannot be validly reproduced on the VPS -> alert only ---
if [ "$BLK_OK" != "1" ]; then
  SUMMARY="$SUMMARY
↳ Blinkit needs the Mac (residential auth). If the Mac is down it can't be recovered on the VPS — power the Mac on."
fi

if [ "$NAT_OK" = "1" ] && [ "$PIN_OK" = "1" ] && [ "$BLK_OK" = "1" ]; then
  LOG "all three routed — OK"
  alert "✅ All 3 morning reports routed for ${TODAY} (BB national, BB pincode, Blinkit)."
else
  alert "⚠️ $SUMMARY"
fi
exit 0
