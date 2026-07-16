#!/usr/bin/env bash
# Promote only final Mac-reviewed competitor packages; never capture or merge.
set -uo pipefail

ROOT="${DIRECT_COMPETITOR_ROOT:-/opt/ecom-intel}"
CONSUMER="${DIRECT_COMPETITOR_CONSUMER:-$ROOT/tools/cron/direct_competitor_consumer.py}"
LOG="${DIRECT_COMPETITOR_CONSUMER_LOG:-$ROOT/logs/direct-competitor-consumer.log}"
LOCK="${DIRECT_COMPETITOR_CONSUMER_LOCK:-$ROOT/logs/.direct-competitor-consumer.lock}"
cd "$ROOT" || exit 1
mkdir -p "$(dirname "$LOG")" "$(dirname "$LOCK")"

exec 9>"$LOCK"
flock -n 9 || exit 0

if [ -f "$ROOT/secrets.env" ]; then
  # shellcheck disable=SC1091
  . "$ROOT/secrets.env"
fi

TODAY="${DIRECT_COMPETITOR_TODAY:-$(TZ=Asia/Kolkata date +%F)}"
DATES=("$TODAY")
HOUR="${DIRECT_COMPETITOR_HOUR:-$(TZ=Asia/Kolkata date +%H)}"
if [ "$((10#$HOUR))" -lt 3 ]; then
  DATES+=("${DIRECT_COMPETITOR_YESTERDAY:-$(TZ=Asia/Kolkata date -d yesterday +%F)}")
fi
TOTAL_RC=0

marker_is_current() {
  python3 - "$1" "$2" "$3" <<'PY'
import json
import sys

marker, source_sha, package_sha = sys.argv[1:]
try:
    value = json.load(open(marker, encoding="utf-8"))
except (OSError, ValueError, json.JSONDecodeError):
    raise SystemExit(1)
checks = (
    value.get("status") == "alerted",
    value.get("source_receipt_sha256") == source_sha,
    not package_sha or value.get("package_state_sha256") == package_sha,
    isinstance(value.get("telegram_message_id"), (str, int))
    and bool(str(value["telegram_message_id"]).strip()),
)
raise SystemExit(0 if all(checks) else 1)
PY
}

record_confirmed_alert() {
  local marker="$1" category="$2" source_sha="$3" package_sha="$4" response="$5"
  python3 - "$marker" "$category" "$source_sha" "$package_sha" "$response" <<'PY'
import datetime
import json
import os
import re
import sys

marker, category, source_sha, package_sha, raw = sys.argv[1:]
if not re.fullmatch(r"[0-9a-f]{64}", source_sha) \
   or package_sha and not re.fullmatch(r"[0-9a-f]{64}", package_sha):
    raise SystemExit("consumer alert provenance hash is invalid")
try:
    response = json.loads(raw)
except json.JSONDecodeError:
    raise SystemExit("Telegram response was not JSON")
result = response.get("result")
message_id = result.get("message_id") if isinstance(result, dict) else None
if response.get("ok") is not True or message_id is None or not str(message_id).strip():
    raise SystemExit("Telegram response did not confirm ok/message_id")
value = {
    "schema": "jivo-direct-competitor-alert-marker-v1",
    "status": "alerted",
    "category": category,
    "source_receipt_sha256": source_sha,
    "telegram_message_id": str(message_id),
    "alerted_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
if package_sha:
    value["package_state_sha256"] = package_sha
os.makedirs(os.path.dirname(marker) or ".", exist_ok=True)
temporary = marker + ".tmp"
with open(temporary, "w", encoding="utf-8") as handle:
    json.dump(value, handle, indent=2, sort_keys=True)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
os.replace(temporary, marker)
PY
}

alert_once() {
  local marker="$1" category="$2" source_sha="$3" package_sha="$4" message="$5" response
  if [ -s "$marker" ] && marker_is_current "$marker" "$source_sha" "$package_sha"; then
    return 0
  fi
  rm -f "$marker"
  if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
    printf '%s alert pending; Telegram credentials are unavailable: %s\n' \
      "$(date '+%F %T')" "$marker" >> "$LOG"
    return 1
  fi
  response="$(curl -sS --max-time 30 -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=$message")" || {
      printf '%s alert pending; Telegram request failed: %s\n' \
        "$(date '+%F %T')" "$marker" >> "$LOG"
      return 1
    }
  if ! record_confirmed_alert "$marker" "$category" "$source_sha" "$package_sha" "$response"; then
    printf '%s alert pending; Telegram did not confirm ok: %s\n' \
      "$(date '+%F %T')" "$marker" >> "$LOG"
    return 1
  fi
  printf '%s Telegram alert confirmed and marked: %s\n' \
    "$(date '+%F %T')" "$marker" >> "$LOG"
}

alert_records() {
  python3 - "$1" <<'PY'
import base64
import json
import sys

value = json.loads(sys.argv[1])
records = []
for item in value.get("rejection_alerts", []):
    if not isinstance(item, dict):
        raise SystemExit("consumer rejection alert is not an object")
    kind = str(item.get("kind") or "package")
    records.append({
        "category": f"rejection-{kind}",
        "marker": item.get("alert_marker"),
        "source": item.get("source_receipt_sha256"),
        "package": item.get("package_state_sha256") or "",
        "message": (
            "[FAIL] Direct Mac competitor input rejected: "
            f"{item.get('run_id', 'unknown')} kind={kind} reason={item.get('error', 'unknown')}. "
            "No VPS/KVM fallback was started."
        ),
    })
for item in value.get("endpoint_failures", []):
    if not isinstance(item, dict):
        raise SystemExit("consumer endpoint failure alert is not an object")
    records.append({
        "category": "endpoint-failure",
        "marker": item.get("alert_marker"),
        "source": item.get("source_receipt_sha256"),
        "package": "",
        "message": (
            "[FAIL] Direct competitor endpoint failure recorded: "
            f"{item.get('platform', 'unknown')} {item.get('run_id', 'unknown')} "
            f"phase={item.get('phase', 'unknown')} reason={item.get('reason', 'unknown')}. "
            "No VPS/KVM fallback was started."
        ),
    })
for record in records:
    if not all(isinstance(record[key], str) and record[key] for key in ("category", "marker", "source", "message")):
        raise SystemExit("consumer alert record is incomplete")
    encoded = [
        base64.b64encode((record[key] or "-").encode("utf-8")).decode("ascii")
        for key in ("marker", "category", "source", "package", "message")
    ]
    print("\t".join(encoded))
PY
}

decode64() {
  printf '%s' "$1" | base64 --decode
}

for REPORT_DATE in "${DATES[@]}"; do
  OUTPUT="$(python3 "$CONSUMER" --date "$REPORT_DATE" \
    2> >(tee -a "$LOG" >&2))"
  RC=$?
  printf '%s %s\n' "$(date '+%F %T')" "$OUTPUT" >> "$LOG"
  if [ "$RC" -ne 0 ]; then
    TOTAL_RC=1
  fi
  RECORDS="$(alert_records "$OUTPUT")" || { TOTAL_RC=1; continue; }
  if [ -n "$RECORDS" ]; then
    while IFS=$'\t' read -r marker64 category64 source64 package64 message64; do
      MARKER="$(decode64 "$marker64")" || { TOTAL_RC=1; continue; }
      CATEGORY="$(decode64 "$category64")" || { TOTAL_RC=1; continue; }
      SOURCE_SHA="$(decode64 "$source64")" || { TOTAL_RC=1; continue; }
      PACKAGE_SHA="$(decode64 "$package64")" || { TOTAL_RC=1; continue; }
      [ "$PACKAGE_SHA" != "-" ] || PACKAGE_SHA=""
      MESSAGE="$(decode64 "$message64")" || { TOTAL_RC=1; continue; }
      alert_once "$MARKER" "$CATEGORY" "$SOURCE_SHA" "$PACKAGE_SHA" "$MESSAGE" || TOTAL_RC=1
    done <<< "$RECORDS"
  fi
done

exit "$TOTAL_RC"
