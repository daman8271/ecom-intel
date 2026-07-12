# tools/laptop/lib.sh — shared helpers for the Windows laptop scrape worker
# (worker #4, host "Victus", ssh alias `laptop`, reverse tunnel 127.0.0.1:22024).
#
# Owner ruling 2026-07-12: the laptop is a FIRST-CLASS daily worker that shards
# the pincode universe with the Mac Pro — never a fallback-only device.
#
# Windows facts this lib encodes (proven in platforms/bigbasket/team_run_pincode.sh):
#   - default ssh shell is PowerShell, npm PS-wrapper is execution-policy-blocked;
#   - detached work must be spawned via WMI Win32_Process Create so it survives
#     ssh/tunnel drops (children of sshd die with the session);
#   - transport is scp (no rsync on Windows), forward slashes work for scp,
#     cmd.exe needs backslashes;
#   - the laptop reaches the VPS back as `vps-bridge` (its own key).
# Source from /opt/ecom-intel scripts:  . tools/laptop/lib.sh

LAPTOP_HOST="${LAPTOP_HOST:-laptop}"
WIN_BASE_FS="C:/scrape-worker"
WIN_BASE_BS='C:\scrape-worker'
WIN_ECOM_FS="$WIN_BASE_FS/ecom-intel"
WIN_ECOM_BS="$WIN_BASE_BS\\ecom-intel"
WIN_RUNS_FS="$WIN_BASE_FS/team-runs"
WIN_RUNS_BS="$WIN_BASE_BS\\team-runs"
WIN_CHROMIUM='C:\Users\prabh\AppData\Local\ms-playwright\chromium-1228\chrome-win64\chrome.exe'

laptop_up() {
  timeout 30 ssh -o BatchMode=yes -o ConnectTimeout=10 "$LAPTOP_HOST" "exit 0" >/dev/null 2>&1
}

# laptop_ps '<powershell>' — run PowerShell on the laptop (plain quoting; for
# anything with nested quotes use /root/bin/lap.sh instead).
laptop_ps() {
  timeout 60 ssh -o BatchMode=yes -o ConnectTimeout=15 "$LAPTOP_HOST" "$1" 2>/dev/null
}

# laptop_mkdir <C:/fs/path>
laptop_mkdir() {
  laptop_ps "New-Item -ItemType Directory -Force -Path '$1' | Out-Null; exit 0"
}

# laptop_push <local> <C:/fs/path>
laptop_push() {
  timeout 120 scp -q -o BatchMode=yes "$1" "$LAPTOP_HOST:$2"
}

# laptop_pull <C:/fs/path> <local>   (best-effort; caller checks the file)
laptop_pull() {
  timeout 120 scp -q -o BatchMode=yes "$LAPTOP_HOST:$1" "$2" 2>/dev/null
}

# laptop_spawn_cmd 'C:\bs\path\runner.cmd' — detached via WMI, survives ssh drop.
laptop_spawn_cmd() {
  timeout 45 ssh -o BatchMode=yes -o ConnectTimeout=15 "$LAPTOP_HOST" \
    "Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='cmd /c \"$1\"'} | Out-Null; exit 0"
}

# laptop_node_running <grep-pattern> — 0 iff a node.exe on the laptop matches.
laptop_node_running() {
  laptop_ps "Get-CimInstance Win32_Process | Where-Object {\$_.Name -eq 'node.exe'} | Select-Object -ExpandProperty CommandLine" \
    | grep -q "$1"
}

# laptop_file_fresh <C:/fs/path> <max_age_seconds> — 0 iff the file exists on
# the laptop and was written within the window (liveness probe for a shard:
# node CommandLines are ambiguous, progress-file mtime is not).
laptop_file_fresh() {
  local out
  out="$(laptop_ps "if (Test-Path '$1') { ((Get-Date) - (Get-Item '$1').LastWriteTime).TotalSeconds -lt $2 } else { 'False' }" | tr -d '\r' | tail -1)"
  [ "$out" = "True" ]
}

# Active-team-run pointer helpers. Pointer file holds one line: <RUN_ID>, where
# RUN_ID starts with today's %Y%m%d when current.
team_ptr_path() { printf '%s/shards/runs/ACTIVE-%s-team' "${DIR:-/opt/ecom-intel}" "$1"; }

# read_active <platform> — prints today's RUN_ID (rc 0) or nothing (rc 1).
# Silently removes a stale (non-today) pointer.
read_active() {
  local ptr id
  ptr="$(team_ptr_path "$1")"
  [ -f "$ptr" ] || return 1
  id="$(head -1 "$ptr" 2>/dev/null || true)"
  if [ -n "$id" ] && [ "${id#"$(date +%Y%m%d)"-}" != "$id" ]; then
    printf '%s\n' "$id"
    return 0
  fi
  rm -f "$ptr"
  return 1
}

clear_active() {
  local ptr id
  ptr="$(team_ptr_path "$1")"
  [ -f "$ptr" ] || return 0
  id="$(head -1 "$ptr" 2>/dev/null || true)"
  if [ -z "${2:-}" ] || [ "$id" = "$2" ]; then rm -f "$ptr"; fi
}

team_tg() { ( set +e
  [ -f "${DIR:-/opt/ecom-intel}/secrets.env" ] && . "${DIR:-/opt/ecom-intel}/secrets.env"
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] || exit 0
  curl -s --max-time 30 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=$1" >/dev/null ) || true; }
