#!/usr/bin/env bash
# Keep both residential Instamart collectors on the validated VPS canonical list.
set -uo pipefail

ROOT=/opt/ecom-intel
CANON="$ROOT/platforms/instamart/pincodes.json"
COLLECTOR="$ROOT/collectors/swiggy-instamart"
LOCAL="$COLLECTOR/pincodes/ecom-intel-363.json"
SYNC_TOOL="$COLLECTOR/pincodes/build-ecom-intel-list.py"

python3 "$SYNC_TOOL" --source "$CANON" --dest "$LOCAL" || exit 2

failures=0
deploy() {
  local host=$1 source=$2 dest=$3 dir tmp
  dir=${dest%/*}
  tmp="${dest}.tmp.$$"
  if ! ssh -o ConnectTimeout=10 "$host" "mkdir -p '$dir'"; then
    echo "[instamart-config] $host unavailable" >&2
    failures=$((failures + 1))
    return
  fi
  if scp -q "$source" "$host:$tmp" && ssh "$host" "mv '$tmp' '$dest'"; then
    echo "[instamart-config] synced $(basename "$source") to $host:$dest"
  else
    echo "[instamart-config] failed to deploy to $host" >&2
    ssh "$host" "rm -f '$tmp'" >/dev/null 2>&1 || true
    failures=$((failures + 1))
  fi
}

MACPRO_ROOT="/Users/danny./VPS-Migration/imported/ecom-intel/collectors/swiggy-instamart"
MACAIR_ROOT="/Users/damanpreetsingh/jivo-instamart-collector"
for spec in "macpro:$MACPRO_ROOT" "macair:$MACAIR_ROOT"; do
  host=${spec%%:*}
  remote_root=${spec#*:}
  deploy "$host" "$LOCAL" "$remote_root/pincodes/ecom-intel-363.json"
  deploy "$host" "$COLLECTOR/collector/scan.js" "$remote_root/collector/scan.js"
  deploy "$host" "$SYNC_TOOL" "$remote_root/pincodes/build-ecom-intel-list.py"
done

exit "$failures"
