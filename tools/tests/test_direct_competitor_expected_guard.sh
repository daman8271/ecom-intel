#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$ROOT/tools/cron/direct_competitor_expected_guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
DATE=2099-01-02
PROMOTIONS="$TMP/promotions"
FAILURES="$TMP/failures"
STATE="$TMP/state"
CALLS="$TMP/curl.calls"
MOCK_BIN="$TMP/bin"
mkdir -p "$PROMOTIONS/$DATE" "$FAILURES/$DATE" "$MOCK_BIN" "$TMP/root"
cat >"$TMP/secrets.env" <<'EOF'
TELEGRAM_BOT_TOKEN=test-token
TELEGRAM_OWNER_CHAT_ID=test-chat
EOF
cat >"$MOCK_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DIRECT_COMPETITOR_TEST_CALLS"
printf '%s\n' '{"ok":true}'
EOF
chmod +x "$MOCK_BIN/curl"

run_guard() {
  PATH="$MOCK_BIN:$PATH" \
    DIRECT_COMPETITOR_ROOT="$TMP/root" \
    DIRECT_COMPETITOR_DATE="$DATE" \
    DIRECT_COMPETITOR_PROMOTION_ROOT="$PROMOTIONS" \
    DIRECT_COMPETITOR_FAILURE_ROOT="$FAILURES" \
    DIRECT_COMPETITOR_GUARD_STATE_ROOT="$STATE" \
    DIRECT_COMPETITOR_GUARD_LOCK="$TMP/guard.lock" \
    DIRECT_COMPETITOR_SECRETS_FILE="$TMP/secrets.env" \
    DIRECT_COMPETITOR_TEST_CALLS="$CALLS" \
    "$GUARD"
}

set +e
run_guard
FIRST_RC=$?
set -e
[ "$FIRST_RC" -eq 1 ]
[ "$(wc -l <"$CALLS")" -eq 2 ]

set +e
run_guard
SECOND_RC=$?
set -e
[ "$SECOND_RC" -eq 1 ]
[ "$(wc -l <"$CALLS")" -eq 2 ]

cat >"$PROMOTIONS/$DATE/zepto.json" <<EOF
{"schema":"jivo-direct-competitor-promotion-receipt-v1","status":"accepted","date_ist":"$DATE","platform":"zepto","workflow_kind":"zepto-competitor"}
EOF
cat >"$FAILURES/$DATE/blinkit.json" <<EOF
{"schema":"jivo-direct-competitor-failure-accepted-v1","date_ist":"$DATE","platform":"blinkit","workflow_kind":"blinkit-top8"}
EOF
run_guard
[ "$(wc -l <"$CALLS")" -eq 2 ]

printf 'direct competitor expected guard tests passed\n'
