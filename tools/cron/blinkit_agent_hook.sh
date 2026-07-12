#!/usr/bin/env bash
# Blinkit production agent hook.
#
# Deterministic actions own production behavior. A read-only Codex escalation is
# invoked only when the run is late, held, or otherwise unresolved.
set -u

ROOT=/opt/ecom-intel
cd "$ROOT" || exit 1

PHASE="${1:-poll}"
DATE_IST="${BLINKIT_AGENT_DATE:-$(TZ=Asia/Kolkata date +%F)}"
LOG_DIR="$ROOT/logs/blinkit-agent"
LOG="$LOG_DIR/hook-${DATE_IST}.log"
LOCK="$ROOT/logs/.blinkit-agent-hook.lock"
mkdir -p "$LOG_DIR" "$ROOT/logs"

log() {
  printf '[%s] blinkit_agent_hook(%s): %s\n' "$(TZ=Asia/Kolkata date '+%F %T %Z')" "$PHASE" "$*" | tee -a "$LOG"
}

tg() { (
  set +e
  [ -f "$ROOT/secrets.env" ] && . "$ROOT/secrets.env"
  CH="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "$CH" ] || exit 0
  curl -s --max-time 30 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=$CH" \
    --data-urlencode "text=$1" >/dev/null
) || true; }

exec 9>"$LOCK"
if ! flock -n 9; then
  log "another hook holds $LOCK; exiting"
  exit 0
fi

hhmm_now() {
  TZ=Asia/Kolkata date +%H%M
}

after_hhmm() {
  local want="${1/:/}"
  [ "$((10#$(hhmm_now)))" -ge "$((10#$want))" ]
}

snapshot_file() {
  local stamp
  stamp="$(TZ=Asia/Kolkata date +%H%M%S)"
  printf '%s/snapshot-%s-%s-%s.json' "$LOG_DIR" "$DATE_IST" "$stamp" "$PHASE"
}

json_get() {
  python3 - "$1" "$2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
cur = d
for part in sys.argv[2].split("."):
    if isinstance(cur, dict):
        cur = cur.get(part)
    else:
        cur = None
        break
print("" if cur is None else cur)
PY
}

run_quality_and_send() {
  log "reports present; running quality gate and direct WhatsApp send helpers"
  BLINKIT_MONITOR_DRYRUN=1 BLINKIT_MONITOR_EXIT_CODE=1 BLINKIT_MONITOR_DATE="$DATE_IST" \
    "$ROOT/tools/cron/blinkit_quality_monitor.sh" "agent-$PHASE" >>"$LOG" 2>&1 || {
      log "quality gate held the current reports"
      return 1
    }
  BLINKIT_MAIN_WA_DATE="$DATE_IST" "$ROOT/tools/whatsapp/send_blinkit_main_direct.sh" "agent-$PHASE" >>"$LOG" 2>&1 || true
  BLINKIT_NOT_LISTED_DATE="$DATE_IST" "$ROOT/tools/whatsapp/send_blinkit_not_listed_direct.sh" "agent-$PHASE" >>"$LOG" 2>&1 || true
  return 0
}

delivery_complete() {
  [ -s "$ROOT/logs/blinkit-main-wa-${DATE_IST}.sent" ] && [ -s "$ROOT/logs/blinkit-not-listed-wa-${DATE_IST}.sent" ]
}

repair_held_mac_drop() {
  log "attempting deterministic held Mac-drop repair"
  "$ROOT/tools/cron/blinkit_repair_held_mac_drop.sh" >>"$LOG" 2>&1
  local rc=$?
  log "held Mac-drop repair finished rc=$rc"
  return "$rc"
}

invoke_readonly_codex() {
  local snap="$1" key="$2" throttle now last prompt out codex_bin
  throttle="$LOG_DIR/llm-${DATE_IST}-${key}.stamp"
  [ "${BLINKIT_AGENT_LLM_ENABLE:-1}" = "1" ] || { log "read-only Codex escalation disabled"; return 0; }
  now="$(date +%s)"
  last="$(stat -c %Y "$throttle" 2>/dev/null || echo 0)"
  if [ "$((now - last))" -lt "${BLINKIT_AGENT_LLM_THROTTLE_S:-2700}" ]; then
    log "read-only Codex escalation throttled for key=$key"
    return 0
  fi
  touch "$throttle"

  prompt="$LOG_DIR/prompt-${DATE_IST}-${key}-$(TZ=Asia/Kolkata date +%H%M%S).md"
  out="$LOG_DIR/codex-${DATE_IST}-${key}-$(TZ=Asia/Kolkata date +%H%M%S).out"
  {
    cat "$ROOT/tools/cron/blinkit_agent_prompt.md"
    echo
    echo "## Snapshot JSON"
    echo '```json'
    cat "$snap"
    echo '```'
    echo
    echo "Phase: $PHASE"
    echo "Date: $DATE_IST"
  } > "$prompt"

  codex_bin="${CODEX_BIN:-$(command -v codex || echo /root/.local/bin/codex)}"
  log "invoking read-only Codex escalation key=$key bin=$codex_bin"
  timeout "${BLINKIT_AGENT_LLM_TIMEOUT_S:-900}" \
    "$codex_bin" exec -C "$ROOT" --sandbox read-only --ephemeral --color never -c 'approval_policy="never"' - <"$prompt" \
    >"$out" 2>&1
  rc=$?
  log "read-only Codex escalation finished rc=$rc out=$out"
  if [ "$rc" -eq 0 ]; then
    tg "[Blinkit agent] ${DATE_IST} ${key}: Codex diagnosis written to $out"
  else
    tg "[Blinkit agent] ${DATE_IST} ${key}: Codex escalation failed rc=$rc; deterministic watchdog continues. Output: $out"
  fi
}

snap="$(snapshot_file)"
if ! "$ROOT/tools/cron/blinkit_agent_snapshot.py" --date "$DATE_IST" > "$snap"; then
  log "snapshot failed"
  tg "[Blinkit agent] snapshot failed for $DATE_IST"
  exit 0
fi

state="$(json_get "$snap" state)"
expected="$(json_get "$snap" expected_pincodes)"
log "state=$state expected_pincodes=$expected snapshot=$snap"

if [ "$PHASE" = "mac-start" ] && [ "${BLINKIT_AGENT_LLM_LIVE_START:-1}" = "1" ]; then
  log "Mac production start received; waking read-only Codex monitor with the fresh snapshot"
  invoke_readonly_codex "$snap" "live-start"
  exit 0
fi

case "$state" in
  complete)
    log "complete; both workbook files and WhatsApp markers exist"
    exit 0
    ;;
  accepted_pending_send)
    run_quality_and_send || invoke_readonly_codex "$snap" "quality-held"
    delivery_complete && log "delivery complete after hook send"
    exit 0
    ;;
  quality_hold)
    log "quality hold detected; running deterministic targeted repair before LLM escalation"
    if repair_held_mac_drop; then
      "$ROOT/tools/cron/blinkit_whatsapp_delivery_sweep.sh" "agent-repair" >>"$LOG" 2>&1 || true
    else
      invoke_readonly_codex "$snap" "quality-hold"
    fi
    exit 0
    ;;
  missing_after_1000)
    log "report missing after 10:00"
    repair_held_mac_drop || true
    if [ -f "$ROOT/output/Jivo-Blinkit-Live-Report-${DATE_IST}.xlsx" ]; then
      "$ROOT/tools/cron/blinkit_whatsapp_delivery_sweep.sh" "agent-repair" >>"$LOG" 2>&1 || true
      exit 0
    fi
    "$ROOT/tools/cron/blinkit_batch_guard.sh" "agent-$PHASE" >>"$LOG" 2>&1 || true
    "$ROOT/tools/cron/blinkit_whatsapp_delivery_sweep.sh" "agent-$PHASE" >>"$LOG" 2>&1 || true
    invoke_readonly_codex "$snap" "missing-after-1000"
    exit 0
    ;;
  running)
    if after_hhmm "10:00"; then
      log "run still active after 10:00; keeping delivery sweep live"
      "$ROOT/tools/cron/blinkit_whatsapp_delivery_sweep.sh" "agent-running" >>"$LOG" 2>&1 || true
    fi
    exit 0
    ;;
  waiting|*)
    if after_hhmm "06:35"; then
      log "waiting after start window; triggering guard idempotently"
      "$ROOT/tools/cron/blinkit_batch_guard.sh" "agent-$PHASE" >>"$LOG" 2>&1 || true
    fi
    if after_hhmm "09:00"; then
      "$ROOT/tools/cron/blinkit_whatsapp_delivery_sweep.sh" "agent-$PHASE" >>"$LOG" 2>&1 || true
    fi
    exit 0
    ;;
esac
