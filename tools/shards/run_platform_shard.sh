#!/usr/bin/env bash
# Run one platform pincode shard in an isolated work directory.
#
# Usage:
#   tools/shards/run_platform_shard.sh <platform> <pincodes.json> <shard_total> <shard_index> [run_id]
#
# This never writes live platforms/<p>/result.json. It writes under:
#   ${SHARD_BASE:-<repo>/shards/runs}/<run_id>/<platform>/shard-<i>-of-<n>/
set -euo pipefail

PLATFORM="${1:?usage: run_platform_shard.sh <platform> <pincodes.json> <total> <index> [run_id]}"
SOURCE_CONFIG="${2:?usage: run_platform_shard.sh <platform> <pincodes.json> <total> <index> [run_id]}"
SHARD_TOTAL="${3:?usage: run_platform_shard.sh <platform> <pincodes.json> <total> <index> [run_id]}"
SHARD_INDEX="${4:?usage: run_platform_shard.sh <platform> <pincodes.json> <total> <index> [run_id]}"
RUN_ID="${5:-$(date +%Y%m%d-%H%M%S)}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${ECOM_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
PDIR="$ROOT/platforms/$PLATFORM"
[ -d "$PDIR" ] || { echo "no such platform dir: $PDIR" >&2; exit 2; }

case "$PLATFORM" in
  blinkit|zepto|flipkart-minutes) ;;
  *) echo "platform $PLATFORM is not enabled for safe shard running yet" >&2; exit 2 ;;
esac

if [ -f "/Users/danny./VPS-Migration/bin/node22-env.sh" ]; then
  # Mac worker runtime.
  # shellcheck disable=SC1091
  . "/Users/danny./VPS-Migration/bin/node22-env.sh"
fi

case "$SOURCE_CONFIG" in
  /*) ;;
  *) SOURCE_CONFIG="$ROOT/$SOURCE_CONFIG" ;;
esac
[ -f "$SOURCE_CONFIG" ] || { echo "missing pincode config: $SOURCE_CONFIG" >&2; exit 2; }

BASE="${SHARD_BASE:-$ROOT/shards/runs}"
RUN_DIR="$BASE/$RUN_ID/$PLATFORM/shard-${SHARD_INDEX}-of-${SHARD_TOTAL}"
WORK="$RUN_DIR/work/$PLATFORM"
LOG_DIR="$RUN_DIR/logs"
mkdir -p "$RUN_DIR" "$WORK" "$LOG_DIR"

python3 "$ROOT/tools/shards/split_pincodes.py" "$PLATFORM" "$SOURCE_CONFIG" "$RUN_DIR" \
  --total "$SHARD_TOTAL" --index "$SHARD_INDEX" --run-id "$RUN_ID" --role "${SHARD_ROLE:-worker}" \
  > "$RUN_DIR/split.log"

SHARD_CONFIG="$RUN_DIR/pincodes.${SHARD_INDEX}-of-${SHARD_TOTAL}.json"
MANIFEST="$RUN_DIR/manifest.${SHARD_INDEX}-of-${SHARD_TOTAL}.json"
RESULT="$RUN_DIR/result.json"

rsync -a --delete \
  --exclude='.git/' \
  --exclude='.progress.*.json' \
  --exclude='result*.json' \
  --exclude='Jivo-*.xlsx' \
  --exclude='__pycache__/' \
  --exclude='*.pyc' \
  "$PDIR/" "$WORK/"

cd "$WORK"
if [ ! -d node_modules ] && [ -f package-lock.json ]; then
  npm ci >> "$LOG_DIR/npm.log" 2>&1
fi

SCRAPER="scrape.js"
[ "$PLATFORM" = "flipkart-minutes" ] && SCRAPER="scrape.js"

if [ "$PLATFORM" = "blinkit" ]; then
  if [ -z "${BLINKIT_AUTH_STATE_FILE:-}" ]; then
    for candidate in \
      "$ROOT/secrets/blinkit-auth-state.json" \
      "/Users/danny./VPS-Migration/secrets/blinkit-auth-state.json"
    do
      if [ -s "$candidate" ]; then
        BLINKIT_AUTH_STATE_FILE="$candidate"
        break
      fi
    done
  fi
  if [ -z "${BLINKIT_AUTH_STATE_FILE:-}" ] || [ ! -s "$BLINKIT_AUTH_STATE_FILE" ]; then
    echo "missing Blinkit auth state; set BLINKIT_AUTH_STATE_FILE or install secrets/blinkit-auth-state.json" >&2
    exit 3
  fi
  export BLINKIT_AUTH_STATE_FILE
  export BLINKIT_REQUIRE_AUTH="${BLINKIT_REQUIRE_AUTH:-1}"
fi

ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

echo "[$(ts)] shard START platform=$PLATFORM run_id=$RUN_ID shard=$SHARD_INDEX/$SHARD_TOTAL config=$SHARD_CONFIG"
PINCODES_FILE="$SHARD_CONFIG" OUT_FILE="$RESULT" node "$SCRAPER" \
  > "$LOG_DIR/stdout.log" 2> "$LOG_DIR/stderr.log"
echo "[$(ts)] shard DONE result=$RESULT manifest=$MANIFEST"

python3 - "$MANIFEST" "$RESULT" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
r = json.load(open(sys.argv[2]))
pins = {str(x.get("pincode")) for x in r.get("perPin", [])}
expected = set(map(str, m["shard_pincodes"]))
if pins != expected:
    raise SystemExit(f"result pincode set mismatch missing={sorted(expected-pins)[:10]} extra={sorted(pins-expected)[:10]}")
print(json.dumps({"ok": True, "summary": r.get("summary", {}), "pincodes": len(pins)}, indent=2))
PY

if [ -n "${SYNC_DEST:-}" ]; then
  DEST_PATH="$SYNC_DEST/$RUN_ID/$PLATFORM/shard-${SHARD_INDEX}-of-${SHARD_TOTAL}"
  case "$SYNC_DEST" in
    *:*)
      REMOTE_HOST="${SYNC_DEST%%:*}"
      REMOTE_BASE="${SYNC_DEST#*:}"
      ssh -o BatchMode=yes "$REMOTE_HOST" "mkdir -p '$REMOTE_BASE/$RUN_ID/$PLATFORM/shard-${SHARD_INDEX}-of-${SHARD_TOTAL}'"
      ;;
    *)
      mkdir -p "$DEST_PATH"
      ;;
  esac
  rsync -az --partial "$RUN_DIR/" "$SYNC_DEST/$RUN_ID/$PLATFORM/shard-${SHARD_INDEX}-of-${SHARD_TOTAL}/"
  echo "[$(ts)] synced shard to $SYNC_DEST/$RUN_ID/$PLATFORM/shard-${SHARD_INDEX}-of-${SHARD_TOTAL}/"
fi
