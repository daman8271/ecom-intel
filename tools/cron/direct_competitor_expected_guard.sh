#!/usr/bin/env bash
# Alert when an expected direct competitor workflow produced no terminal evidence.
set -uo pipefail

ROOT="${DIRECT_COMPETITOR_ROOT:-/opt/ecom-intel}"
cd "$ROOT" || exit 1
DATE_IST="${DIRECT_COMPETITOR_DATE:-$(TZ=Asia/Kolkata date +%F)}"
PROMOTION_ROOT="${DIRECT_COMPETITOR_PROMOTION_ROOT:-$ROOT/logs/direct-competitor-report-receipts}"
FAILURE_ROOT="${DIRECT_COMPETITOR_FAILURE_ROOT:-$ROOT/logs/direct-competitor-report-failures}"
STATE_ROOT="${DIRECT_COMPETITOR_GUARD_STATE_ROOT:-$ROOT/logs/direct-competitor-expected}"
LOCK="${DIRECT_COMPETITOR_GUARD_LOCK:-$ROOT/logs/.direct-competitor-expected.lock}"
SECRETS_FILE="${DIRECT_COMPETITOR_SECRETS_FILE:-$ROOT/secrets.env}"

mkdir -p "$STATE_ROOT" "$(dirname "$LOCK")"
exec 9>"$LOCK"
flock -n 9 || exit 0

has_terminal_evidence() {
  python3 - "$PROMOTION_ROOT" "$FAILURE_ROOT" "$DATE_IST" "$1" "$2" <<'PY'
import json
import sys
from pathlib import Path

promotion_root, failure_root, date_ist, platform, workflow = sys.argv[1:]
for path in (Path(promotion_root) / date_ist).glob("*.json"):
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        continue
    if all((
        value.get("schema") == "jivo-direct-competitor-promotion-receipt-v1",
        value.get("status") == "accepted",
        value.get("date_ist") == date_ist,
        value.get("platform") == platform,
        value.get("workflow_kind") == workflow,
    )):
        raise SystemExit(0)
for path in (Path(failure_root) / date_ist).glob("*.json"):
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        continue
    if all((
        value.get("schema") == "jivo-direct-competitor-failure-accepted-v1",
        value.get("date_ist") == date_ist,
        value.get("platform") == platform,
        value.get("workflow_kind") == workflow,
    )):
        raise SystemExit(0)
raise SystemExit(1)
PY
}

alert_once() {
  local platform="$1" workflow="$2"
  local state="$STATE_ROOT/${DATE_IST}.${workflow}.alerted"
  [ ! -s "$state" ] || return 0
  printf '%s\n' "missing-terminal-evidence" >"$state"
  (
    set +e
    # shellcheck disable=SC1090
    [ -f "$SECRETS_FILE" ] && . "$SECRETS_FILE"
    owner_chat="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
    [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "$owner_chat" ] || exit 0
    message="[FAIL] ${platform} direct competitor workflow (${workflow}) has no accepted report or endpoint-failure receipt for ${DATE_IST}. No VPS/KVM fallback was started."
    curl -s --max-time 30 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      --data-urlencode "chat_id=$owner_chat" --data-urlencode "text=$message" >/dev/null
  ) || true
}

MISSING=0
for spec in "zepto:zepto-competitor" "blinkit:blinkit-top8"; do
  platform="${spec%%:*}"
  workflow="${spec#*:}"
  if has_terminal_evidence "$platform" "$workflow"; then
    echo "[direct_competitor_expected] ${workflow}: terminal evidence present"
  else
    echo "[direct_competitor_expected] ${workflow}: missing terminal evidence"
    alert_once "$platform" "$workflow"
    MISSING=1
  fi
done
exit "$MISSING"
