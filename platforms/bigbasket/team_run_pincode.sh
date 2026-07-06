#!/usr/bin/env bash
# BigBasket logged-in pincode team runner.
#
# Runs weighted shards on:
#   - this VPS
#   - Mac Pro over ssh alias "macpro"
#   - KVM1 over ssh alias "kvm1"
#
# Every worker runs in tmux, so closing the launching shell does not kill the
# scrape. Re-run this script with "status", "collect", "merge", or "build" and
# the same run id to recover/finish a run.
set -euo pipefail

ROOT="${BB_TEAM_ROOT:-/opt/ecom-intel}"
PDIR="$ROOT/platforms/bigbasket"
PINS_FILE="${BB_TEAM_PINS_FILE:-$PDIR/pincodes_jivo.json}"
SHARD_ROOT="${BB_TEAM_SHARD_ROOT:-$ROOT/shards/bigbasket}"
PRIVATE_OUT="${BB_TEAM_PRIVATE_OUT:-$ROOT/output/private-no-group}"

MAC_HOST="${BB_TEAM_MAC_HOST:-macpro}"
KVM_HOST="${BB_TEAM_KVM_HOST:-kvm1}"
MAC_BASE="${BB_TEAM_MAC_BASE:-/Users/danny./VPS-Migration/imported/ecom-intel/platforms/bigbasket}"
KVM_BASE="${BB_TEAM_KVM_BASE:-/opt/ecom-intel/platforms/bigbasket}"

VPS_WEIGHT="${BB_TEAM_VPS_WEIGHT:-5}"
MAC_WEIGHT="${BB_TEAM_MAC_WEIGHT:-4}"
KVM_WEIGHT="${BB_TEAM_KVM_WEIGHT:-1}"
WAIT_TIMEOUT_S="${BB_TEAM_WAIT_TIMEOUT_S:-14400}"
POLL_S="${BB_TEAM_POLL_S:-30}"

BB_QUERIES_DEFAULT="${BB_QUERIES:-jivo}"
PIN_DELAY_MS="${BB_PINCODE_DELAY_MS:-3500}"
QUERY_DELAY_MS="${BB_PINCODE_QUERY_DELAY_MS:-3500}"
WATCHDOG_MS="${BB_PINCODE_WATCHDOG_MS:-14400000}"

usage() {
  cat <<EOF
Usage:
  $0 run [run-id]       Launch, wait, collect, merge, and build
  $0 launch [run-id]    Launch detached workers only
  $0 status <run-id>    Show worker state
  $0 collect <run-id>   Pull remote worker outputs to VPS
  $0 merge <run-id>     Merge shard JSON into result_pincode.json
  $0 build <run-id>     Build private no-group workbook

Weights default to VPS=$VPS_WEIGHT Mac=$MAC_WEIGHT KVM1=$KVM_WEIGHT.
Override with BB_TEAM_VPS_WEIGHT, BB_TEAM_MAC_WEIGHT, BB_TEAM_KVM_WEIGHT.
EOF
}

cmd="${1:-run}"
run_id="${2:-bb-team-$(date +%Y%m%d-%H%M%S)}"
run_dir="$SHARD_ROOT/$run_id"
session_prefix="bb_${run_id//[^A-Za-z0-9_]/_}"

remote_sh() {
  local host="$1" script="$2"
  ssh "$host" "bash -lc $(printf '%q' "$script")"
}

worker_base() {
  case "$1" in
    vps) printf '%s\n' "$PDIR" ;;
    macpro) printf '%s\n' "$MAC_BASE" ;;
    kvm1) printf '%s\n' "$KVM_BASE" ;;
    *) return 1 ;;
  esac
}

worker_host() {
  case "$1" in
    vps) printf '%s\n' "local" ;;
    macpro) printf '%s\n' "$MAC_HOST" ;;
    kvm1) printf '%s\n' "$KVM_HOST" ;;
    *) return 1 ;;
  esac
}

make_shards() {
  mkdir -p "$run_dir"
  printf '%s\n' "$run_id" > "$SHARD_ROOT/ACTIVE_TEAM_RUN"
  python3 - "$PINS_FILE" "$run_dir" "$VPS_WEIGHT" "$MAC_WEIGHT" "$KVM_WEIGHT" "$run_id" <<'PY'
import json, os, sys, datetime
pins_file, run_dir = sys.argv[1:3]
weights = {"vps": int(sys.argv[3]), "macpro": int(sys.argv[4]), "kvm1": int(sys.argv[5])}
run_id = sys.argv[6]
pins = json.load(open(pins_file))
cycle = []
for name in ("vps", "macpro", "kvm1"):
    cycle.extend([name] * max(0, weights[name]))
if not cycle:
    raise SystemExit("all worker weights are zero")
shards = {name: [] for name in ("vps", "macpro", "kvm1")}
for i, pin in enumerate(pins):
    shards[cycle[i % len(cycle)]].append(pin)
workers = []
for name, rows in shards.items():
    path = os.path.join(run_dir, f"pincodes.{name}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(rows, f, indent=2)
        f.write("\n")
    workers.append({"name": name, "weight": weights[name], "pins": len(rows), "result": f"{name}.json"})
manifest = {
    "run_id": run_id,
    "created_at": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "pins_total": len(pins),
    "weights": weights,
    "workers": workers,
}
with open(os.path.join(run_dir, "manifest.json"), "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
print(json.dumps(manifest, indent=2))
PY
}

sync_worker() {
  local name="$1" host base
  host="$(worker_host "$name")"
  base="$(worker_base "$name")"
  if [ "$name" = "vps" ]; then
    mkdir -p "$base/secrets" "$run_dir"
    return 0
  fi

  rsync -az \
    --exclude node_modules \
    --exclude secrets \
    --exclude mac-drops \
    --exclude team-runs \
    --exclude '*.xlsx' \
    "$PDIR/" "$host:$base/"
  rsync -az "$PDIR/secrets/bb_cookies.pincode.json" "$host:$base/secrets/bb_cookies.pincode.json"
  rsync -az "$PDIR/secrets/bb_cookies.json" "$host:$base/secrets/bb_cookies.json" 2>/dev/null || true
  rsync -az "$PDIR/secrets/bb.storageState.json" "$host:$base/secrets/bb.storageState.json" 2>/dev/null || true
  remote_sh "$host" "
    set -e
    mkdir -p '$base/secrets' '$base/team-runs/$run_id'
    chmod 600 '$base'/secrets/*.json 2>/dev/null || true
    cd '$base'
    if [ ! -d node_modules/playwright-extra ]; then npm ci; fi
  "
}

push_shard() {
  local name="$1" host base
  host="$(worker_host "$name")"
  base="$(worker_base "$name")"
  if [ "$name" = "vps" ]; then
    return 0
  fi
  remote_sh "$host" "mkdir -p '$base/team-runs/$run_id'"
  rsync -az "$run_dir/pincodes.$name.json" "$host:$base/team-runs/$run_id/pincodes.$name.json"
}

launch_worker() {
  local name="$1" host base remote_run session launch_cmd
  host="$(worker_host "$name")"
  base="$(worker_base "$name")"
  session="${session_prefix}_${name}"

  if [ "$name" = "vps" ]; then
    remote_run="$run_dir"
  else
    remote_run="$base/team-runs/$run_id"
  fi

  launch_cmd="
    set +e
    cd '$base' || exit 10
    mkdir -p '$remote_run'
    if [ ! -d node_modules/playwright-extra ]; then npm ci; fi
    OUT_FILE='$remote_run/$name.json' \
    PINCODES_FILE='$remote_run/pincodes.$name.json' \
    BB_COOKIE_PATH='$base/secrets/bb_cookies.pincode.json' \
    BB_QUERIES='$BB_QUERIES_DEFAULT' \
    BB_PINCODE_MIN_REQUIRED=1 \
    BB_PINCODE_DELAY_MS='$PIN_DELAY_MS' \
    BB_PINCODE_QUERY_DELAY_MS='$QUERY_DELAY_MS' \
    BB_PINCODE_WATCHDOG_MS='$WATCHDOG_MS' \
      node scrape_pincode_browser.js >'$remote_run/$name.stdout' 2>'$remote_run/$name.log'
    rc=\$?
    echo \$rc > '$remote_run/$name.rc'
    date -u +%FT%TZ > '$remote_run/$name.done'
    exit \$rc
  "

  if [ "$name" = "vps" ]; then
    tmux kill-session -t "$session" 2>/dev/null || true
    tmux new-session -d -s "$session" "bash -lc $(printf '%q' "$launch_cmd")"
  else
    remote_sh "$host" "
      tmux kill-session -t '$session' 2>/dev/null || true
      tmux new-session -d -s '$session' \"bash -lc $(printf '%q' "$launch_cmd")\"
    "
  fi
}

launch_all() {
  make_shards
  for name in vps macpro kvm1; do
    sync_worker "$name"
    push_shard "$name"
    launch_worker "$name"
  done
  echo "[bb-team] launched $run_id in tmux sessions: ${session_prefix}_vps, ${session_prefix}_macpro, ${session_prefix}_kvm1"
}

collect_all() {
  mkdir -p "$run_dir"
  local worker host base remote_run
  for worker in macpro kvm1; do
    host="$(worker_host "$worker")"
    base="$(worker_base "$worker")"
    remote_run="$base/team-runs/$run_id"
    rsync -az "$host:$remote_run/$worker.json" "$run_dir/$worker.json" 2>/dev/null || true
    rsync -az "$host:$remote_run/$worker.log" "$run_dir/$worker.log" 2>/dev/null || true
    rsync -az "$host:$remote_run/$worker.stdout" "$run_dir/$worker.stdout" 2>/dev/null || true
    rsync -az "$host:$remote_run/$worker.rc" "$run_dir/$worker.rc" 2>/dev/null || true
    rsync -az "$host:$remote_run/$worker.done" "$run_dir/$worker.done" 2>/dev/null || true
  done
}

worker_status() {
  local name="$1" host base remote_run session tmux_state done_state rc_state pins_state
  host="$(worker_host "$name")"
  base="$(worker_base "$name")"
  session="${session_prefix}_${name}"
  if [ "$name" = "vps" ]; then
    remote_run="$run_dir"
    tmux_state="$(tmux has-session -t "$session" 2>/dev/null && echo running || echo not-running)"
    done_state="$([ -f "$remote_run/$name.done" ] && cat "$remote_run/$name.done" || true)"
    rc_state="$([ -f "$remote_run/$name.rc" ] && cat "$remote_run/$name.rc" || true)"
    pins_state="$([ -f "$remote_run/$name.json" ] && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); per=d.get("perPin") or []; print(str(len(per))+" pins, "+str(sum(len(p.get("rows") or []) for p in per))+" rows")' "$remote_run/$name.json" || true)"
  else
    remote_run="$base/team-runs/$run_id"
    tmux_state="$(remote_sh "$host" "tmux has-session -t '$session' 2>/dev/null && echo running || echo not-running" || true)"
    done_state="$([ -f "$run_dir/$name.done" ] && cat "$run_dir/$name.done" || true)"
    rc_state="$([ -f "$run_dir/$name.rc" ] && cat "$run_dir/$name.rc" || true)"
    pins_state="$([ -f "$run_dir/$name.json" ] && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); per=d.get("perPin") or []; print(str(len(per))+" pins, "+str(sum(len(p.get("rows") or []) for p in per))+" rows")' "$run_dir/$name.json" || true)"
  fi
  printf '%-6s %-12s rc=%-4s done=%-20s %s\n' "$name" "$tmux_state" "${rc_state:-}" "${done_state:-}" "${pins_state:-no-json-yet}"
}

status_all() {
  echo "[bb-team] run_id=$run_id run_dir=$run_dir"
  collect_all >/dev/null 2>&1 || true
  [ -f "$run_dir/manifest.json" ] && python3 - "$run_dir/manifest.json" <<'PY'
import json, sys
d=json.load(open(sys.argv[1]))
print("weights", d.get("weights"), "pins", {w["name"]: w["pins"] for w in d.get("workers", [])})
PY
  for name in vps macpro kvm1; do worker_status "$name"; done
}

all_done() {
  collect_all >/dev/null 2>&1 || true
  for name in vps macpro kvm1; do
    [ -f "$run_dir/$name.done" ] || return 1
  done
  return 0
}

wait_all() {
  local deadline now
  deadline=$(( $(date +%s) + WAIT_TIMEOUT_S ))
  while ! all_done; do
    now="$(date +%s)"
    if [ "$now" -ge "$deadline" ]; then
      echo "[bb-team] timeout waiting for workers; run status with: $0 status $run_id" >&2
      return 1
    fi
    status_all
    sleep "$POLL_S"
  done
  collect_all
  status_all
}

merge_run() {
  mkdir -p "$run_dir"
  python3 "$PDIR/merge_team_pincode.py" \
    --run-dir "$run_dir" \
    --manifest "$run_dir/manifest.json" \
    --pins "$PINS_FILE" \
    --output "$run_dir/merged-result_pincode.cleaned.json"
  cp -f "$run_dir/merged-result_pincode.cleaned.json" "$PDIR/result_pincode.json"
}

build_run() {
  cd "$PDIR"
  BB_ALLOW_PARTIAL_PINCODE_REPORT=1 python3 build_excel_pincode.py
  mkdir -p "$PRIVATE_OUT"
  local xlsx
  xlsx="$(ls -t "$PDIR"/Jivo-BigBasket-Pincode-Report-*.xlsx | head -1)"
  cp -f "$xlsx" "$PRIVATE_OUT/$(basename "$xlsx")"
  rm -f "$ROOT/output/$(basename "$xlsx")"
  echo "[bb-team] private workbook: $PRIVATE_OUT/$(basename "$xlsx")"
}

case "$cmd" in
  run)
    launch_all
    wait_all
    merge_run
    build_run
    ;;
  launch)
    launch_all
    ;;
  status)
    status_all
    ;;
  collect)
    collect_all
    status_all
    ;;
  merge)
    collect_all
    merge_run
    ;;
  build)
    build_run
    ;;
  *)
    usage
    exit 2
    ;;
esac
