#!/usr/bin/env bash
# BigBasket logged-in pincode team runner.
#
# Runs weighted shards on:
#   - this VPS
#   - Mac Pro over ssh alias "macpro"
#   - KVM1 over ssh alias "kvm1"
#   - Windows laptop over ssh alias "laptop" (native Windows: PowerShell shell,
#     scp not rsync, WMI-detached cmd runner not tmux; owner rule: NO WSL)
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
DIRECT_JID_FILE="${BB_TEAM_DIRECT_JID_FILE:-$ROOT/secrets/bigbasket-direct-jid}"
GROUP_JID_FILE="${BB_TEAM_GROUP_JID_FILE:-$ROOT/secrets/whatsapp-target.json}"
GW_HEALTH="${BB_TEAM_WA_HEALTH:-http://127.0.0.1:3001/health}"
GW_SEND="${BB_TEAM_WA_SEND:-http://127.0.0.1:3001/send}"
GW_SEND_MEDIA="${BB_TEAM_WA_SEND_MEDIA:-http://127.0.0.1:3001/send-media}"

MAC_HOST="${BB_TEAM_MAC_HOST:-macpro}"
KVM_HOST="${BB_TEAM_KVM_HOST:-kvm1}"
LAPTOP_HOST="${BB_TEAM_LAPTOP_HOST:-laptop}"
MAC_BASE="${BB_TEAM_MAC_BASE:-/Users/danny./VPS-Migration/imported/ecom-intel/platforms/bigbasket}"
KVM_BASE="${BB_TEAM_KVM_BASE:-/opt/ecom-intel/platforms/bigbasket}"
# Windows worker: native PowerShell + node, no WSL/bash/tmux/rsync (owner rule).
# Forward slashes work in PowerShell paths; scp needs the same form.
LAPTOP_BASE="${BB_TEAM_LAPTOP_BASE:-C:/Users/prabh/bb}"

VPS_WEIGHT="${BB_TEAM_VPS_WEIGHT:-3}"
MAC_WEIGHT="${BB_TEAM_MAC_WEIGHT:-3}"
KVM_WEIGHT="${BB_TEAM_KVM_WEIGHT:-1}"
# Laptop weight 3 = balanced with VPS/Mac (≈494 pins each, KVM1 ≈165) — the
# wall-clock-optimal split, since the slowest shard sets the night's length.
# BB_TEAM_LAPTOP_WEIGHT=7 would give the laptop a literal half (~822 pins) but
# makes it the long pole and risks the 6h cap + the laptop's 07:00 Blinkit
# shard. Override via env on the cron line if literal-half is ever wanted.
LAPTOP_WEIGHT="${BB_TEAM_LAPTOP_WEIGHT:-3}"
WAIT_TIMEOUT_S="${BB_TEAM_WAIT_TIMEOUT_S:-21600}"
POLL_S="${BB_TEAM_POLL_S:-30}"

BB_QUERIES_DEFAULT="${BB_QUERIES:-jivo}"
PIN_DELAY_MS="${BB_PINCODE_DELAY_MS:-3500}"
QUERY_DELAY_MS="${BB_PINCODE_QUERY_DELAY_MS:-3500}"
WATCHDOG_MS="${BB_PINCODE_WATCHDOG_MS:-21600000}"

usage() {
  cat <<EOF
Usage:
  $0 run [run-id]       Launch, wait, collect, merge, and build
  $0 launch [run-id]    Launch detached workers only
  $0 status <run-id>    Show worker state
  $0 collect <run-id>   Pull remote worker outputs to VPS
  $0 merge <run-id>     Merge shard JSON into result_pincode.json
  $0 build <run-id>     Build workbook for the Ecom batch/group
  $0 deliver [xlsx]     Retry Ecom WhatsApp group delivery for a built workbook

Weights default to VPS=$VPS_WEIGHT Mac=$MAC_WEIGHT KVM1=$KVM_WEIGHT Laptop=$LAPTOP_WEIGHT.
Override with BB_TEAM_VPS_WEIGHT, BB_TEAM_MAC_WEIGHT, BB_TEAM_KVM_WEIGHT, BB_TEAM_LAPTOP_WEIGHT.
Optional secondary direct delivery reads BB_TEAM_DIRECT_JID or $DIRECT_JID_FILE.
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

resolve_direct_jid() {
  if [ -n "${BB_TEAM_DIRECT_JID:-}" ]; then
    printf '%s\n' "$BB_TEAM_DIRECT_JID"
    return 0
  fi
  if [ -f "$DIRECT_JID_FILE" ]; then
    tr -d '[:space:]' < "$DIRECT_JID_FILE"
    printf '\n'
  fi
}

resolve_group_jid() {
  [ -f "$GROUP_JID_FILE" ] || return 1
  python3 - "$GROUP_JID_FILE" <<'PY'
import json, sys

try:
    jid = str(json.load(open(sys.argv[1], encoding="utf-8")).get("jid", "")).strip()
except Exception:
    raise SystemExit(1)
if not jid.endswith("@g.us"):
    raise SystemExit(1)
print(jid)
PY
}

ensure_gateway() {
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/0}"
  export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/0/bus}"
  if curl -s --max-time 5 "$GW_HEALTH" 2>/dev/null | grep -q '"connected"'; then
    return 0
  fi
  systemctl --user reset-failed hermes-gateway-wa-test.service 2>/dev/null || true
  systemctl --user start hermes-gateway-wa-test.service 2>/dev/null || true
  for _ in $(seq 1 30); do
    if curl -s --max-time 3 "$GW_HEALTH" 2>/dev/null | grep -q '"connected"'; then
      return 0
    fi
    sleep 1
  done
  return 1
}

send_group() {
  local workbook="$1" jid report_date marker header body response
  [ -f "$workbook" ] || {
    echo "[bb-team] Ecom group delivery failed: workbook missing: $workbook" >&2
    return 1
  }
  report_date="$(basename "$workbook" | sed -nE 's/.*([0-9]{4}-[0-9]{2}-[0-9]{2})\.xlsx$/\1/p')"
  report_date="${report_date:-$(date +%F)}"
  marker="$ROOT/logs/bigbasket-pincode-wa-${report_date}.sent"
  if [ -f "$marker" ]; then
    echo "[bb-team] Ecom group delivery already marked sent: $marker"
    return 0
  fi
  jid="$(resolve_group_jid || true)"
  if [ -z "$jid" ]; then
    echo "[bb-team] Ecom group delivery failed: missing/invalid group target in $GROUP_JID_FILE" >&2
    return 1
  fi
  if [ "${BB_TEAM_WA_DRYRUN:-0}" = "1" ]; then
    echo "[bb-team] [dryrun] would send $(basename "$workbook") to configured Ecom group"
    return 0
  fi
  if ! ensure_gateway; then
    echo "[bb-team] Ecom group delivery failed: gateway not connected" >&2
    return 1
  fi

  header="$(printf 'Jivo x BigBasket pincode-wise - %s\nReport attached.' "$report_date")"
  body="$(python3 - "$jid" "$header" <<'PY'
import json, sys
print(json.dumps({"chatId": sys.argv[1], "message": sys.argv[2]}))
PY
)"
  response="$(curl -s --max-time 60 -X POST "$GW_SEND" -H 'Content-Type: application/json' -d "$body" || true)"
  echo "$response" | grep -q '"success":true' || {
    echo "[bb-team] Ecom group header send failed: $response" >&2
    return 1
  }

  body="$(python3 - "$jid" "$workbook" <<'PY'
import json, os, sys
jid, path = sys.argv[1], os.path.abspath(sys.argv[2])
print(json.dumps({
    "chatId": jid,
    "filePath": path,
    "mediaType": "document",
    "fileName": os.path.basename(path),
}))
PY
)"
  response="$(curl -s --max-time 120 -X POST "$GW_SEND_MEDIA" -H 'Content-Type: application/json' -d "$body" || true)"
  echo "$response" | grep -q '"success":true' || {
    echo "[bb-team] Ecom group workbook send failed: $response" >&2
    return 1
  }
  mkdir -p "$ROOT/logs"
  touch "$marker"
  echo "[bb-team] Ecom group workbook sent; marker: $marker"
}

send_direct() {
  local workbook="$1" jid body response
  jid="$(resolve_direct_jid || true)"
  if [ -z "$jid" ]; then
    echo "[bb-team] direct WhatsApp skipped: no BB_TEAM_DIRECT_JID or $DIRECT_JID_FILE"
    return 0
  fi
  if [[ "$jid" != *@s.whatsapp.net ]]; then
    echo "[bb-team] direct WhatsApp skipped: invalid JID '$jid'" >&2
    return 1
  fi
  if ! ensure_gateway; then
    echo "[bb-team] direct WhatsApp failed: gateway not connected" >&2
    return 1
  fi
  body="$(python3 - "$jid" "$workbook" <<'PY'
import json, os, sys
jid, path = sys.argv[1], os.path.abspath(sys.argv[2])
print(json.dumps({
    "chatId": jid,
    "filePath": path,
    "mediaType": "document",
    "fileName": os.path.basename(path),
}))
PY
)"
  response="$(curl -s --max-time 120 -X POST "$GW_SEND_MEDIA" -H 'Content-Type: application/json' -d "$body" || true)"
  echo "[bb-team] direct WhatsApp response: $response"
  echo "$response" | grep -q '"success":true'
}

worker_base() {
  case "$1" in
    vps) printf '%s\n' "$PDIR" ;;
    macpro) printf '%s\n' "$MAC_BASE" ;;
    kvm1) printf '%s\n' "$KVM_BASE" ;;
    laptop) printf '%s\n' "$LAPTOP_BASE" ;;
    *) return 1 ;;
  esac
}

worker_host() {
  case "$1" in
    vps) printf '%s\n' "local" ;;
    macpro) printf '%s\n' "$MAC_HOST" ;;
    kvm1) printf '%s\n' "$KVM_HOST" ;;
    laptop) printf '%s\n' "$LAPTOP_HOST" ;;
    *) return 1 ;;
  esac
}

worker_alive() {
  local name="$1" host
  [ "$name" = "vps" ] && return 0
  host="$(worker_host "$name")"
  # "exit 0" is valid in both POSIX shells and PowerShell (laptop lands in PS).
  timeout 30 ssh -o ConnectTimeout=10 -o BatchMode=yes "$host" "exit 0" >/dev/null 2>&1
}

# Zero out the weight of any unreachable remote so its pins are rerouted to
# live workers instead of the whole run dying at sync/launch (2026-07-12
# incident: Mac Pro tunnel down at 3 AM -> set -e killed the run, no report).
# When a worker is down, remaining live workers split the list evenly.
preflight_weights() {
  local name dead=0
  for name in macpro kvm1 laptop; do
    if ! worker_alive "$name"; then
      echo "[bb-team] WARNING: $name unreachable at launch; rerouting its pins to live workers" >&2
      case "$name" in
        macpro) MAC_WEIGHT=0 ;;
        kvm1) KVM_WEIGHT=0 ;;
        laptop) LAPTOP_WEIGHT=0 ;;
      esac
      dead=1
    fi
  done
  if [ "$dead" = "1" ]; then
    [ "$VPS_WEIGHT" -gt 0 ] && VPS_WEIGHT=1
    [ "$MAC_WEIGHT" -gt 0 ] && MAC_WEIGHT=1
    [ "$KVM_WEIGHT" -gt 0 ] && KVM_WEIGHT=1
    [ "$LAPTOP_WEIGHT" -gt 0 ] && LAPTOP_WEIGHT=1
    echo "[bb-team] effective weights after preflight: vps=$VPS_WEIGHT macpro=$MAC_WEIGHT kvm1=$KVM_WEIGHT laptop=$LAPTOP_WEIGHT" >&2
  fi
}

# Workers actually participating in this run (from the manifest); falls back
# to all three for pre-manifest calls.
manifest_workers() {
  if [ -f "$run_dir/manifest.json" ]; then
    python3 -c 'import json,sys
for w in json.load(open(sys.argv[1]))["workers"]:
    print(w["name"])' "$run_dir/manifest.json"
  else
    printf 'vps\nmacpro\nkvm1\nlaptop\n'
  fi
}

mark_worker_skipped() {
  local name="$1"
  echo "99" > "$run_dir/$name.rc"
  date -u +%FT%TZ > "$run_dir/$name.done"
  touch "$run_dir/.allow-missing"
  echo "[bb-team] WARNING: $name skipped mid-launch; its pins will be reported as missing" >&2
}

make_shards() {
  mkdir -p "$run_dir"
  printf '%s\n' "$run_id" > "$SHARD_ROOT/ACTIVE_TEAM_RUN"
  python3 - "$PINS_FILE" "$run_dir" "$VPS_WEIGHT" "$MAC_WEIGHT" "$KVM_WEIGHT" "$LAPTOP_WEIGHT" "$run_id" <<'PY'
import json, os, sys, datetime
pins_file, run_dir = sys.argv[1:3]
weights = {"vps": int(sys.argv[3]), "macpro": int(sys.argv[4]), "kvm1": int(sys.argv[5]), "laptop": int(sys.argv[6])}
run_id = sys.argv[7]
pins = json.load(open(pins_file))
cycle = []
for name in ("vps", "macpro", "kvm1", "laptop"):
    cycle.extend([name] * max(0, weights[name]))
if not cycle:
    raise SystemExit("all worker weights are zero")
shards = {name: [] for name in ("vps", "macpro", "kvm1", "laptop") if weights[name] > 0}
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

  if [ "$name" = "laptop" ]; then
    ssh "$host" "New-Item -ItemType Directory -Force -Path '$base/secrets','$base/team-runs/$run_id' | Out-Null; exit 0"
    scp -q "$PDIR/scrape_pincode_browser.js" "$PDIR/scrape.js" "$PDIR/import_cookies.js" \
      "$PDIR/package.json" "$PDIR/package-lock.json" "$host:$base/"
    scp -q "$PDIR/secrets/bb_cookies.pincode.json" "$host:$base/secrets/"
    ssh "$host" "cd '$base'; if (-not (Test-Path node_modules/playwright-extra)) { npm.cmd ci --no-audit --no-fund | Out-Null }; exit 0"
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
  if [ "$name" = "laptop" ]; then
    ssh "$host" "New-Item -ItemType Directory -Force -Path '$base/team-runs/$run_id' | Out-Null; exit 0"
    scp -q "$run_dir/pincodes.$name.json" "$host:$base/team-runs/$run_id/pincodes.$name.json"
    return 0
  fi
  remote_sh "$host" "mkdir -p '$base/team-runs/$run_id'"
  rsync -az "$run_dir/pincodes.$name.json" "$host:$base/team-runs/$run_id/pincodes.$name.json"
}

launch_worker() {
  local name="$1" host base remote_run session local_runner remote_runner
  host="$(worker_host "$name")"
  base="$(worker_base "$name")"
  session="${session_prefix}_${name}"

  if [ "$name" = "vps" ]; then
    remote_run="$run_dir"
  else
    remote_run="$base/team-runs/$run_id"
  fi

  if [ "$name" = "laptop" ]; then
    # Native Windows: plain cmd batch runner (no PowerShell script policy
    # involved), launched detached via WMI so it survives ssh disconnect
    # (no tmux on Windows). Backslash paths for cmd.exe.
    local base_w="${base//\//\\}" run_w="${remote_run//\//\\}"
    local_runner="$run_dir/$name.run.cmd"
    cat > "$local_runner" <<EOF
@echo off
cd /d "$base_w"
set "OUT_FILE=$run_w\\$name.json"
set "PINCODES_FILE=$run_w\\pincodes.$name.json"
set "BB_COOKIE_PATH=$base_w\\secrets\\bb_cookies.pincode.json"
set "BB_QUERIES=$BB_QUERIES_DEFAULT"
set "BB_PINCODE_MIN_REQUIRED=1"
set "BB_PINCODE_DELAY_MS=$PIN_DELAY_MS"
set "BB_PINCODE_QUERY_DELAY_MS=$QUERY_DELAY_MS"
set "BB_PINCODE_WATCHDOG_MS=$WATCHDOG_MS"
node scrape_pincode_browser.js 1>"$run_w\\$name.stdout" 2>"$run_w\\$name.log"
set "RC=%ERRORLEVEL%"
>"$run_w\\$name.rc" echo %RC%
>"$run_w\\$name.done" echo %DATE% %TIME%
exit /b %RC%
EOF
    sed -i 's/$/\r/' "$local_runner"
    scp -q "$local_runner" "$host:$remote_run/$name.run.cmd"
    ssh "$host" "Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='cmd /c \"$run_w\\$name.run.cmd\"'} | Out-Null; exit 0"
    return 0
  fi

  local_runner="$run_dir/$name.run.sh"
  remote_runner="$remote_run/$name.run.sh"
  cat > "$local_runner" <<EOF
#!/usr/bin/env bash
set +e
cd '$base' || exit 10
mkdir -p '$remote_run'
if [ ! -d node_modules/playwright-extra ]; then npm ci; fi
OUT_FILE='$remote_run/$name.json' \\
PINCODES_FILE='$remote_run/pincodes.$name.json' \\
BB_COOKIE_PATH='$base/secrets/bb_cookies.pincode.json' \\
BB_QUERIES='$BB_QUERIES_DEFAULT' \\
BB_PINCODE_MIN_REQUIRED=1 \\
BB_PINCODE_DELAY_MS='$PIN_DELAY_MS' \\
BB_PINCODE_QUERY_DELAY_MS='$QUERY_DELAY_MS' \\
BB_PINCODE_WATCHDOG_MS='$WATCHDOG_MS' \\
  node scrape_pincode_browser.js >'$remote_run/$name.stdout' 2>'$remote_run/$name.log'
rc=\$?
printf '%s\\n' "\$rc" > '$remote_run/$name.rc'
date -u +%FT%TZ > '$remote_run/$name.done'
exit "\$rc"
EOF
  chmod +x "$local_runner"

  if [ "$name" = "vps" ]; then
    tmux kill-session -t "$session" 2>/dev/null || true
    tmux new-session -d -s "$session" "bash '$local_runner'"
  else
    remote_sh "$host" "mkdir -p '$remote_run'"
    rsync -az "$local_runner" "$host:$remote_runner"
    remote_sh "$host" "
      tmux kill-session -t '$session' 2>/dev/null || true
      tmux new-session -d -s '$session' \"bash '$remote_runner'\"
    "
  fi
}

launch_all() {
  preflight_weights
  make_shards
  local name
  for name in $(manifest_workers); do
    if [ "$name" = "vps" ]; then
      sync_worker "$name"
      push_shard "$name"
      launch_worker "$name"
    elif ! { sync_worker "$name" && push_shard "$name" && launch_worker "$name"; }; then
      mark_worker_skipped "$name"
    fi
  done
  echo "[bb-team] launched $run_id workers: $(manifest_workers | tr '\n' ' ')(tmux prefix ${session_prefix}_)"
}

collect_all() {
  mkdir -p "$run_dir"
  local worker host base remote_run
  for worker in $(manifest_workers); do
    [ "$worker" = "vps" ] && continue
    host="$(worker_host "$worker")"
    base="$(worker_base "$worker")"
    remote_run="$base/team-runs/$run_id"
    if [ "$worker" = "laptop" ]; then
      local ext
      # Do not read laptop.json while Node is checkpointing it. Windows OpenSSH
      # holds the source without delete sharing, which can make the scraper's
      # atomic rename fail with EPERM. The done marker is written after Node exits.
      for ext in rc done; do
        scp -q "$host:$remote_run/$worker.$ext" "$run_dir/$worker.$ext" 2>/dev/null || true
      done
      if [ -f "$run_dir/$worker.done" ]; then
        for ext in json log stdout; do
          scp -q "$host:$remote_run/$worker.$ext" "$run_dir/$worker.$ext" 2>/dev/null || true
        done
      fi
      continue
    fi
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
  elif [ "$name" = "laptop" ]; then
    remote_run="$base/team-runs/$run_id"
    tmux_state="$([ -f "$run_dir/$name.done" ] && echo not-running || echo running?)"
    done_state="$([ -f "$run_dir/$name.done" ] && tr -d '\r' < "$run_dir/$name.done" || true)"
    rc_state="$([ -f "$run_dir/$name.rc" ] && tr -d '\r' < "$run_dir/$name.rc" || true)"
    pins_state="$([ -f "$run_dir/$name.json" ] && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); per=d.get("perPin") or []; print(str(len(per))+" pins, "+str(sum(len(p.get("rows") or []) for p in per))+" rows")' "$run_dir/$name.json" || true)"
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
  for name in $(manifest_workers); do worker_status "$name"; done
}

all_done() {
  collect_all >/dev/null 2>&1 || true
  for name in $(manifest_workers); do
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
      echo "[bb-team] TIMEOUT after ${WAIT_TIMEOUT_S}s; merging completed shards as a PARTIAL report" >&2
      touch "$run_dir/.allow-missing"
      break
    fi
    status_all
    sleep "$POLL_S"
  done
  collect_all
  status_all
}

merge_run() {
  mkdir -p "$run_dir"
  local allow_missing=""
  [ -f "$run_dir/.allow-missing" ] && allow_missing="--allow-missing"
  python3 "$PDIR/merge_team_pincode.py" \
    --run-dir "$run_dir" \
    --manifest "$run_dir/manifest.json" \
    --pins "$PINS_FILE" \
    --output "$run_dir/merged-result_pincode.cleaned.json" \
    $allow_missing
  cp -f "$run_dir/merged-result_pincode.cleaned.json" "$PDIR/result_pincode.json"
}

build_run() {
  cd "$PDIR"
  BB_ALLOW_PARTIAL_PINCODE_REPORT=1 python3 build_excel_pincode.py
  mkdir -p "$ROOT/output" "$PRIVATE_OUT"
  local xlsx base public_xlsx private_xlsx
  xlsx="$(ls -t "$PDIR"/Jivo-BigBasket-Pincode-Report-*.xlsx | head -1)"
  base="$(basename "$xlsx")"
  public_xlsx="$ROOT/output/$base"
  private_xlsx="$PRIVATE_OUT/$base"
  cp -f "$xlsx" "$public_xlsx"
  echo "[bb-team] queued for the 10:30 Ecom batch: $public_xlsx"
  cp -f "$xlsx" "$private_xlsx"
  echo "[bb-team] secondary private copy: $private_xlsx"
  if [ "${BB_TEAM_SEND_DIRECT:-0}" = "1" ]; then
    send_direct "$public_xlsx" || echo "[bb-team] direct WhatsApp send failed; Ecom batch/group workbook kept"
  else
    echo "[bb-team] early direct delivery disabled; workbook will leave in the 10:30 Ecom batch"
  fi
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
  deliver)
    workbook="${2:-$ROOT/output/Jivo-BigBasket-Pincode-Report-$(date +%F).xlsx}"
    send_group "$workbook"
    ;;
  *)
    usage
    exit 2
    ;;
esac
