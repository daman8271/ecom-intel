#!/usr/bin/env bash
# Daily 25-city x 3-pincode Blinkit top-8 competitor run.
set -uo pipefail

ROOT=/opt/ecom-intel
cd "$ROOT" || exit 1
. tools/laptop/lib.sh

DATE_IST="${BLINKIT_TOP8_DATE:-$(TZ=Asia/Kolkata date +%F)}"
RUN_END="${BLINKIT_TOP8_RUN_END:-13:00}"
POLL_SECONDS="${BLINKIT_TOP8_POLL_SECONDS:-60}"
CONCURRENCY="${BLINKIT_TOP8_CONCURRENCY:-2}"
REPORT="$ROOT/output/Competitor-Price-Watch-Blinkit-${DATE_IST}.xlsx"
SENT="$ROOT/logs/blinkit-top8-wa-${DATE_IST}.sent"
MAIN_SENT="$ROOT/logs/blinkit-main-wa-${DATE_IST}.sent"
NOT_LISTED_SENT="$ROOT/logs/blinkit-not-listed-wa-${DATE_IST}.sent"
POINTER="$ROOT/shards/runs/ACTIVE-blinkit-top8"
LOCK="$ROOT/logs/.blinkit-top8-daily.lock"
STATE="$ROOT/logs/blinkit-top8-${DATE_IST}.state"
LOG_FILE="$ROOT/logs/blinkit-top8-${DATE_IST}.log"
MAC_BASE="/Users/danny./VPS-Migration"
MAC_PROJECT="$MAC_BASE/imported/ecom-intel"
VPS_REMOTE="root@187.127.129.132"
BRANDS="Jivo,Sano,Fortune,Saffola,Borges,Tata,Del Monte,Figaro,Sundrop,Gulab"
mkdir -p "$ROOT/logs" "$ROOT/shards/runs"

log() {
  printf '[%s] blinkit_top8: %s\n' "$(TZ=Asia/Kolkata date '+%F %T %Z')" "$*" | tee -a "$LOG_FILE"
}

tg() { (
  set +e
  [ -f "$ROOT/secrets.env" ] && . "$ROOT/secrets.env"
  chat="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "$chat" ] || exit 0
  curl -s --max-time 30 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=$chat" --data-urlencode "text=$1" >/dev/null
) || true; }

alert_once() {
  local key="$1" message="$2"
  touch "$STATE"
  grep -qxF "$key" "$STATE" 2>/dev/null && return 0
  printf '%s\n' "$key" >> "$STATE"
  log "ALERT $key: $message"
  tg "$message"
}

end_epoch() {
  TZ=Asia/Kolkata date -d "$DATE_IST $RUN_END" +%s
}

current_run_id() {
  local run_id=""
  if [ -f "$POINTER" ]; then
    run_id="$(head -1 "$POINTER" 2>/dev/null || true)"
  fi
  if [ -n "$run_id" ] && [ "${run_id#"${DATE_IST//-/}"-}" != "$run_id" ] \
     && [ -d "$ROOT/shards/runs/$run_id" ]; then
    printf '%s\n' "$run_id"
    return 0
  fi
  rm -f "$POINTER"
  return 1
}

write_runners() {
  local run_id="$1" run="$2" win_run_bs mac_run remote_run
  win_run_bs="$WIN_RUNS_BS\\$run_id"
  mac_run="$MAC_BASE/competitor-runs/$run_id"
  remote_run="$ROOT/shards/runs/$run_id"

  cat > "$run/mac.run.sh" <<EOF
#!/bin/bash
set -uo pipefail
BASE="$MAC_BASE"
PROJECT="$MAC_PROJECT"
RUN="$mac_run"
REMOTE="$VPS_REMOTE:$remote_run/"
CAPTURE="\$PROJECT/tools/competitor/data/blinkit_competitor_${DATE_IST}-TOP8-3PCITY-MAC.json"
LOCK_DIR="/tmp/com.danny.blinkit-top8.lock"
mkdir -p "\$RUN"
if ! mkdir "\$LOCK_DIR" 2>/dev/null; then
  printf '75\n' > "\$RUN/mac.run.rc"
  date > "\$RUN/mac.run.done"
  rsync -az "\$RUN/mac.run.rc" "\$RUN/mac.run.done" "\$REMOTE" || true
  exit 75
fi
trap 'rmdir "\$LOCK_DIR" 2>/dev/null || true' EXIT
. "\$BASE/bin/node22-env.sh"
cd "\$PROJECT/platforms/blinkit" || exit 1
export COMPETITOR_MODE=1
export COMPETITOR_DATE="${DATE_IST}-TOP8-3PCITY-MAC"
export COMPETITOR_BRANDS="$BRANDS"
export BLINKIT_AUTH_STATE_FILE="\$BASE/secrets/blinkit-auth-state.json"
export BLINKIT_REQUIRE_AUTH=1
export BLINKIT_OOS_PROBE=0
export BLINKIT_PDP_OOS_PROBE=0
export BLINKIT_PDP_PRICE_PROBE=0
export CONCURRENCY="$CONCURRENCY"
export PINCODES_FILE="\$RUN/pincodes.json"
export BLINKIT_PROGRESS_FILE="\$RUN/progress.json"
rm -f "\$CAPTURE"
node scrape.js >"\$RUN/mac.stdout.log" 2>"\$RUN/mac.run.log"
rc=\$?
printf '%s\n' "\$rc" > "\$RUN/mac.run.rc"
date > "\$RUN/mac.run.done"
[ -s "\$CAPTURE" ] && cp "\$CAPTURE" "\$RUN/mac.capture.json"
[ -s "\$RUN/progress.json" ] && cp "\$RUN/progress.json" "\$RUN/mac.progress.json"
for file in mac.run.rc mac.run.done mac.run.log mac.stdout.log mac.capture.json mac.progress.json; do
  [ -f "\$RUN/\$file" ] && rsync -az "\$RUN/\$file" "\$REMOTE\$file" || true
done
exit "\$rc"
EOF
  chmod +x "$run/mac.run.sh"

  cat > "$run/windows.run.cmd" <<EOF
@echo off
setlocal
set "RUN=$win_run_bs"
set "PROJECT=$WIN_ECOM_BS"
set "CAPTURE=%PROJECT%\tools\competitor\data\blinkit_competitor_${DATE_IST}-TOP8-3PCITY-WIN.json"
cd /d "%PROJECT%\platforms\blinkit"
set "COMPETITOR_MODE=1"
set "COMPETITOR_DATE=${DATE_IST}-TOP8-3PCITY-WIN"
set "COMPETITOR_BRANDS=$BRANDS"
set "BLINKIT_AUTH_STATE_FILE=$WIN_BASE_BS\secrets\blinkit-auth-state.json"
set "BLINKIT_REQUIRE_AUTH=1"
set "BLINKIT_OOS_PROBE=0"
set "BLINKIT_PDP_OOS_PROBE=0"
set "BLINKIT_PDP_PRICE_PROBE=0"
set "CONCURRENCY=$CONCURRENCY"
set "BLINKIT_CHROMIUM_EXECUTABLE=$WIN_CHROMIUM"
set "PINCODES_FILE=%RUN%\pincodes.json"
set "BLINKIT_PROGRESS_FILE=%RUN%\progress.json"
del /q "%CAPTURE%" 2>nul
node scrape.js 1>"%RUN%\windows.stdout.log" 2>"%RUN%\windows.run.log"
set "RC=%ERRORLEVEL%"
>"%RUN%\windows.run.rc" echo %RC%
>"%RUN%\windows.run.done" echo %DATE% %TIME%
if exist "%CAPTURE%" copy /y "%CAPTURE%" "%RUN%\windows.capture.json" >nul
if exist "%RUN%\progress.json" copy /y "%RUN%\progress.json" "%RUN%\windows.progress.json" >nul
scp -q -o BatchMode=yes -o ConnectTimeout=20 "%RUN%\windows.run.rc" "%RUN%\windows.run.done" vps-bridge:$remote_run/
if exist "%RUN%\windows.run.log" scp -q -o BatchMode=yes -o ConnectTimeout=20 "%RUN%\windows.run.log" "%RUN%\windows.stdout.log" vps-bridge:$remote_run/
if exist "%RUN%\windows.capture.json" scp -q -o BatchMode=yes -o ConnectTimeout=20 "%RUN%\windows.capture.json" vps-bridge:$remote_run/windows.capture.json
if exist "%RUN%\windows.progress.json" scp -q -o BatchMode=yes -o ConnectTimeout=20 "%RUN%\windows.progress.json" vps-bridge:$remote_run/windows.progress.json
exit /b %RC%
EOF
  sed -i 's/$/\r/' "$run/windows.run.cmd"
}

sync_and_launch() {
  local run_id="$1" run="$2" mac_run win_run_fs win_run_bs sync_failed=0
  mac_run="$MAC_BASE/competitor-runs/$run_id"
  win_run_fs="$WIN_RUNS_FS/$run_id"
  win_run_bs="$WIN_RUNS_BS\\$run_id"

  ssh -o BatchMode=yes -o ConnectTimeout=15 macpro \
    "mkdir -p '$mac_run' '$MAC_PROJECT/tools/competitor/data'; test -s '$MAC_BASE/secrets/blinkit-auth-state.json'" \
    >/dev/null 2>&1 || return 1
  rsync -az platforms/blinkit/scrape.js macpro:"$MAC_PROJECT/platforms/blinkit/scrape.js" || sync_failed=1
  rsync -az tools/competitor/category_queries.json tools/competitor/competitor_brands.json \
    macpro:"$MAC_PROJECT/tools/competitor/" || sync_failed=1
  rsync -az "$run/mac.pincodes.json" macpro:"$mac_run/pincodes.json" || sync_failed=1
  rsync -az "$run/mac.run.sh" macpro:"$mac_run/run.sh" || sync_failed=1

  laptop_mkdir "$win_run_fs" || sync_failed=1
  laptop_push platforms/blinkit/scrape.js "$WIN_ECOM_FS/platforms/blinkit/scrape.js" || sync_failed=1
  laptop_push tools/competitor/category_queries.json "$WIN_ECOM_FS/tools/competitor/category_queries.json" || sync_failed=1
  laptop_push tools/competitor/competitor_brands.json "$WIN_ECOM_FS/tools/competitor/competitor_brands.json" || sync_failed=1
  laptop_push secrets/blinkit-auth-state-laptop.json "$WIN_BASE_FS/secrets/blinkit-auth-state.json" || sync_failed=1
  laptop_push "$run/windows.pincodes.json" "$win_run_fs/pincodes.json" || sync_failed=1
  laptop_push "$run/windows.run.cmd" "$win_run_fs/windows.run.cmd" || sync_failed=1
  [ "$sync_failed" = "0" ] || return 1

  printf '%s\n' "$run_id" > "$POINTER"
  ssh -o BatchMode=yes -o ConnectTimeout=15 macpro \
    "nohup bash '$mac_run/run.sh' >'$mac_run/launcher.log' 2>&1 </dev/null &" \
    >/dev/null 2>&1 || return 1
  laptop_spawn_cmd "$win_run_bs\\windows.run.cmd" || return 1
  log "launched $run_id: Windows 38 pins + Mac Pro 37 pins, concurrency=$CONCURRENCY each"
  return 0
}

create_run() {
  local run_id run split_dir
  if ! timeout 30 ssh -o BatchMode=yes -o ConnectTimeout=10 macpro "exit 0" >/dev/null 2>&1; then
    alert_once "mac-unreachable" "[WARN] Blinkit top-8 competitor run cannot start: Mac Pro is unreachable. Windows remains available but the normal two-device run is waiting."
    return 1
  fi
  if ! laptop_up; then
    alert_once "windows-unreachable" "[WARN] Blinkit top-8 competitor run cannot start: Windows laptop is unreachable. Mac Air remains emergency-only."
    return 1
  fi
  [ -s secrets/blinkit-auth-state-laptop.json ] || {
    alert_once "windows-auth-missing" "[FAIL] Blinkit top-8 competitor run cannot start: Windows Blinkit auth state is missing."
    return 1
  }

  run_id="${DATE_IST//-/}-$(TZ=Asia/Kolkata date +%H%M%S)-blinkit-top8"
  run="$ROOT/shards/runs/$run_id"
  mkdir -p "$run"
  python3 tools/competitor/select_blinkit_top8_pincodes.py \
    --date "$DATE_IST" --output "$run/pincodes.all.json" \
    --audit "$run/selection-audit.json" >> "$LOG_FILE" 2>&1 || return 1
  for index in 0 1; do
    split_dir="$run/split-$index"
    python3 tools/shards/split_pincodes.py blinkit "$run/pincodes.all.json" "$split_dir" \
      --total 2 --index "$index" --run-id "$run_id" \
      --role "$([ "$index" = 0 ] && echo windows || echo macpro)" \
      >> "$LOG_FILE" 2>&1 || return 1
  done
  cp "$run/split-0/pincodes.0-of-2.json" "$run/windows.pincodes.json"
  cp "$run/split-1/pincodes.1-of-2.json" "$run/mac.pincodes.json"
  python3 - "$run/run.json" "$run_id" "$DATE_IST" "$CONCURRENCY" <<'PY'
import json, sys
path, run_id, date, concurrency = sys.argv[1:]
data = {
    "schema": "blinkit-top8-run-v1",
    "run_id": run_id,
    "date": date,
    "selection_source": "platforms/blinkit/result.json + tools/competitor/blinkit_top8_pincodes.json",
    "competitors": ["Fortune", "Saffola", "Borges", "Tata", "Del Monte", "Figaro", "Sundrop", "Gulab"],
    "workers": [
        {"id": "windows", "label": "Windows laptop", "concurrency": int(concurrency), "pincodes_file": "windows.pincodes.json", "progress_file": "windows.progress.json", "capture_file": "windows.capture.json"},
        {"id": "macpro", "label": "Mac Pro", "concurrency": int(concurrency), "pincodes_file": "mac.pincodes.json", "progress_file": "mac.progress.json", "capture_file": "mac.capture.json"},
    ],
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, ensure_ascii=False)
    handle.write("\n")
PY
  write_runners "$run_id" "$run"
  if ! sync_and_launch "$run_id" "$run"; then
    alert_once "launch-failed-$run_id" "[FAIL] Blinkit top-8 competitor device sync/launch failed for $DATE_IST; cron will retry."
    return 1
  fi
  CREATED_RUN_ID="$run_id"
}

pull_backstops() {
  local run_id="$1" run="$2" mac_run win_run_fs file
  mac_run="$MAC_BASE/competitor-runs/$run_id"
  win_run_fs="$WIN_RUNS_FS/$run_id"
  for file in windows.run.rc windows.run.done windows.run.log windows.stdout.log windows.capture.json windows.progress.json; do
    laptop_pull "$win_run_fs/$file" "$run/$file" || true
  done
  for file in mac.run.rc mac.run.done mac.run.log mac.stdout.log mac.capture.json mac.progress.json; do
    rsync -az macpro:"$mac_run/$file" "$run/$file" >/dev/null 2>&1 || true
  done
}

retry_failed_worker() {
  local worker="$1" run_id="$2" run="$3" rc count_file count win_run_bs mac_run
  [ -f "$run/$worker.run.rc" ] || return 0
  rc="$(tr -dc '0-9' < "$run/$worker.run.rc" | head -c 3)"
  [ -n "$rc" ] && [ "$rc" != "0" ] || return 0
  count_file="$run/$worker.retry.count"
  count="$(cat "$count_file" 2>/dev/null || echo 0)"
  if [ "$count" -ge 1 ]; then
    alert_once "$worker-failed-$run_id" "[FAIL] Blinkit top-8 competitor $worker worker failed twice for $DATE_IST (rc=$rc)."
    return 1
  fi
  printf '1\n' > "$count_file"
  rm -f "$run/$worker.run.rc" "$run/$worker.run.done" "$run/$worker.capture.json"
  log "retrying $worker worker once from its checkpoint (previous rc=$rc)"
  if [ "$worker" = "windows" ]; then
    win_run_bs="$WIN_RUNS_BS\\$run_id"
    laptop_spawn_cmd "$win_run_bs\\windows.run.cmd"
  else
    mac_run="$MAC_BASE/competitor-runs/$run_id"
    ssh -o BatchMode=yes -o ConnectTimeout=15 macpro \
      "nohup bash '$mac_run/run.sh' >'$mac_run/retry-launcher.log' 2>&1 </dev/null &" \
      >/dev/null 2>&1
  fi
}

finish_run() {
  local run_id="$1" run="$2"
  if ! python3 tools/competitor/build_blinkit_top8_daily.py \
      --date "$DATE_IST" --run-dir "$run" \
      >> "$LOG_FILE" 2>&1; then
    alert_once "quality-hold-$run_id" "[FAIL] Blinkit top-8 competitor report is held by coverage/auth/data-quality gates for $DATE_IST. See $LOG_FILE."
    return 1
  fi
  if ! tools/competitor/send_blinkit_top8_whatsapp.sh daily >> "$LOG_FILE" 2>&1; then
    alert_once "send-failed-$run_id" "[WARN] Blinkit top-8 workbook passed quality but Ecom-group delivery failed for $DATE_IST; retry cron remains active."
    return 1
  fi
  python3 tools/competitor/to_vault.py "$DATE_IST" >> "$LOG_FILE" 2>&1 || true
  "$ROOT/bin/advance_today_section.sh" competitors --date "$DATE_IST" \
    >> "$ROOT/bin/build_today.log" 2>&1 || true
  rm -f "$POINTER"
  log "complete: $REPORT sent to Ecom group"
  return 0
}

exec 9>"$LOCK"
if ! flock -n 9; then
  log "another top-8 orchestrator holds the lock; exiting"
  exit 0
fi
if [ -s "$SENT" ]; then
  log "already delivered for $DATE_IST"
  exit 0
fi
if [ ! -s "$MAIN_SENT" ] || [ ! -s "$NOT_LISTED_SENT" ]; then
  log "waiting: daily Blinkit main + not-listed delivery is not complete"
  exit 0
fi

RUN_ID="$(current_run_id || true)"
if [ -z "$RUN_ID" ]; then
  CREATED_RUN_ID=""
  create_run || exit 1
  RUN_ID="$CREATED_RUN_ID"
fi
RUN="$ROOT/shards/runs/$RUN_ID"
log "watching run $RUN_ID until $RUN_END IST"

while [ "$(date +%s)" -le "$(end_epoch)" ]; do
  pull_backstops "$RUN_ID" "$RUN"
  if [ -s "$RUN/windows.capture.json" ] && [ -s "$RUN/windows.progress.json" ] \
     && [ -s "$RUN/mac.capture.json" ] && [ -s "$RUN/mac.progress.json" ]; then
    finish_run "$RUN_ID" "$RUN" && exit 0
    exit 1
  fi
  retry_failed_worker windows "$RUN_ID" "$RUN" || true
  retry_failed_worker mac "$RUN_ID" "$RUN" || true
  sleep "$POLL_SECONDS"
done

alert_once "run-window-ended-$RUN_ID" "[FAIL] Blinkit top-8 competitor run did not finish by $RUN_END IST for $DATE_IST. Device artifacts remain resumable in $RUN."
exit 1
