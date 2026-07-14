#!/usr/bin/env bash
# blinkit_direct_endpoint_guard.sh — agent-2 (fleet-blinkfix), 2026-07-15.
#
# VPS-side DEAD-ENDPOINT guard for the ecom-direct Blinkit model. The VPS is
# consume-only: `consume_direct_reports.sh` promotes Mac-built reports and alerts
# on an endpoint FAILURE RECEIPT — but if the Mac endpoint is DOWN all morning it
# never writes any receipt, so today there is NO alert for total silence (the
# 7/14-class "nobody scraped, nobody noticed until the deadline"). This guard
# closes that gap: past the cutoff, if there is NO Blinkit direct evidence for
# today (no ready package, no accepted receipt, no failure receipt, no promoted
# workbook), it ALERTS the owner ONCE.
#
# It is ALERT-ONLY by default. If (and only if) the owner opts in with
# BLINKIT_ALLOW_VPS_RESCUE=1 AND a resumable team run dir is present, it also
# invokes the flag-gated resumable VPS rescue as a last resort. Datacenter-direct
# scraping stays OFF by default (LEAD ruling 2026-07-15).
#
# Cron (owner applies — do NOT edit crontab here, HARD RULE #8). Proposed line:
#   0,15,30 10 * * * cd /opt/ecom-intel && ./tools/laptop/blinkit_direct_endpoint_guard.sh \
#     >> logs/blinkit-direct-endpoint-guard.log 2>&1   # alert if Blinkit direct endpoint silent by 10:00
set -uo pipefail
DIR="${ECOM_ROOT:-/opt/ecom-intel}"
cd "$DIR" || exit 1

TODAY="$(TZ=Asia/Kolkata date +%F)"
TODAY_C="$(TZ=Asia/Kolkata date +%Y%m%d)"
NOW="$(TZ=Asia/Kolkata date +%H%M)"
CUTOFF="${BLINKIT_ENDPOINT_GUARD_CUTOFF:-1000}"     # HHMM IST; alert only at/after this
INBOX="${BLINKIT_DIRECT_INBOX:-shards/mac-direct-ready}"
RECEIPTS="${BLINKIT_DIRECT_RECEIPTS:-logs/direct-report-receipts}"
FAILURES="${BLINKIT_DIRECT_FAILURES:-logs/direct-report-failures}"
STATE_DIR="${BLINKIT_ENDPOINT_GUARD_STATE:-logs/blinkit-direct-endpoint-guard}"
SECRETS_FILE="${BLINKIT_SECRETS_FILE:-$DIR/secrets.env}"
REPORT="output/Jivo-Blinkit-Live-Report-${TODAY}.xlsx"

LOG(){ echo "[$(TZ=Asia/Kolkata date '+%F %T')] blinkit_direct_endpoint_guard: $*"; }

# send_alert <message> — returns 0 ONLY on a confirmed owner delivery, so the
# caller writes the once-a-day marker only on success (a transient Telegram
# failure or missing creds must NOT suppress the next tick's retry).
# BLINKIT_GUARD_SEND_CMD overrides the transport for tests (its exit code wins).
send_alert(){
  if [ -n "${BLINKIT_GUARD_SEND_CMD:-}" ]; then
    BLINKIT_GUARD_MSG="$1" bash -c "$BLINKIT_GUARD_SEND_CMD"
    return $?
  fi
  ( set +e
    # shellcheck disable=SC1090
    [ -f "$SECRETS_FILE" ] && . "$SECRETS_FILE"
    owner_chat="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
    [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "$owner_chat" ] || exit 1
    resp="$(curl -s --max-time 30 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=$owner_chat" --data-urlencode "text=$1" 2>/dev/null)" || exit 1
    printf '%s' "$resp" | grep -q '"ok":true' || exit 1
    exit 0
  )
}

mkdir -p "$STATE_DIR"
exec 9>"logs/.blinkit-direct-endpoint-guard.lock"
flock -n 9 || exit 0

if [ "$((10#$NOW))" -lt "$((10#$CUTOFF))" ]; then
  LOG "now $NOW < cutoff $CUTOFF — too early, no check"
  exit 0
fi

# ---- gather Blinkit direct evidence for today -------------------------------
have_evidence() {
  # 1) promoted workbook already exists -> delivered
  [ -f "$REPORT" ] && { LOG "evidence: promoted workbook $REPORT"; return 0; }
  # 2) a ready package from the Mac endpoint for today
  local f
  for f in "$INBOX"/${TODAY_C}*/report.ready.json; do
    [ -f "$f" ] || continue
    if python3 - "$f" "$TODAY" <<'PY' 2>/dev/null
import json,sys
d=json.loads(open(sys.argv[1],encoding="utf-8-sig").read())
raise SystemExit(0 if (d.get("platform")=="blinkit" and d.get("date_ist")==sys.argv[2]) else 1)
PY
    then LOG "evidence: ready package $f"; return 0; fi
  done
  # 3) an accepted promotion receipt for today
  for f in "$RECEIPTS/$TODAY"/*.json; do
    [ -f "$f" ] || continue
    if python3 - "$f" <<'PY' 2>/dev/null
import json,sys
d=json.loads(open(sys.argv[1],encoding="utf-8").read())
raise SystemExit(0 if (d.get("status")=="accepted" and d.get("platform")=="blinkit") else 1)
PY
    then LOG "evidence: accepted receipt $f"; return 0; fi
  done
  # 4) an endpoint-failure receipt (endpoint reported its own failure -> the
  #    consumer already alerts; not silent, so we defer to it)
  for f in "$FAILURES/$TODAY"/*.json; do
    [ -f "$f" ] || continue
    if python3 - "$f" <<'PY' 2>/dev/null
import json,sys
d=json.loads(open(sys.argv[1],encoding="utf-8").read())
raise SystemExit(0 if d.get("platform")=="blinkit" else 1)
PY
    then LOG "evidence: endpoint-failure receipt $f (consumer owns that alert)"; return 0; fi
  done
  return 1
}

if have_evidence; then
  LOG "Blinkit direct endpoint evidence present for $TODAY — OK"
  exit 0
fi

LOG "NO Blinkit direct evidence for $TODAY at $NOW IST — endpoint appears SILENT/DOWN"

# ---- alert the owner once (marker written ONLY on confirmed delivery) --------
STATE="$STATE_DIR/${TODAY}.alerted"
MSG="[FAIL] Blinkit direct endpoint is SILENT: no report package, accepted receipt, failure receipt, or workbook for ${TODAY} by ${NOW} IST. The Mac endpoint may be down — nobody is scraping Blinkit. VPS is consume-only; no fallback started (set BLINKIT_ALLOW_VPS_RESCUE=1 to permit the flag-gated last-resort VPS rescue)."
if [ -s "$STATE" ]; then
  LOG "owner already alerted for $TODAY — not repeating"
elif send_alert "$MSG"; then
  printf 'silent-endpoint %s alerted\n' "$NOW" > "$STATE"
  LOG "owner alerted (once) for $TODAY"
else
  LOG "alert NOT delivered (transient send failure or missing creds) — marker NOT written, will retry next tick"
fi

# ---- optional flag-gated last-resort rescue ---------------------------------
if [ "${BLINKIT_ALLOW_VPS_RESCUE:-0}" != "1" ]; then
  LOG "VPS rescue OFF by owner policy (BLINKIT_ALLOW_VPS_RESCUE!=1) — alert-only"
  exit 0
fi
# find a resumable team run dir for today (shard-0 manifest present, no result yet)
RESUMABLE=""
for d in shards/runs/${TODAY_C}*-blinkit-team shards/runs/${TODAY_C}*blinkit*; do
  [ -f "$d/blinkit/shard-0-of-2/manifest.0-of-2.json" ] || continue
  [ -s "$d/blinkit/shard-0-of-2/result.json" ] && continue
  RESUMABLE="$(basename "$d")"; break
done
if [ -z "$RESUMABLE" ]; then
  LOG "opt-in rescue requested but NO resumable team run dir for $TODAY (cold start) — cannot resume; alert-only. Owner must launch a team run or full census."
  exit 0
fi
LOG "opt-in rescue: launching resumable VPS rescue for run $RESUMABLE (shard-0)"
nohup tools/laptop/blinkit_rescue_resume.sh "$RESUMABLE" 0 >> logs/blinkit_team.log 2>&1 </dev/null &
exit 0
