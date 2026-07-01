#!/usr/bin/env bash
# recover_today_after_manual.sh — finish the noon post-run chain after manual scrapes.
#
# Waits for active platform `run.sh` jobs to finish, then performs the same durable
# tail work the 12:00 deadline sweep normally does: rebuild ecom vault, run the
# downstream competitor/data-bank chain, refresh the ecom-app vault, and build
# the verbatim today/ snapshot.
set -uo pipefail

ROOT="/opt/ecom-intel"
DATE_IST="${1:-$(TZ=Asia/Kolkata date +%F)}"
MAX_WAIT_SECONDS="${MAX_WAIT_SECONDS:-43200}"
LOG="$ROOT/logs/recover_today_after_manual-${DATE_IST}-$(TZ=Asia/Kolkata date +%H%M%S).log"
mkdir -p "$ROOT/logs"

log() { printf '[%s] %s\n' "$(TZ=Asia/Kolkata date '+%F %T %Z')" "$*" | tee -a "$LOG"; }

active_platform_runs() {
  pgrep -af 'bash ./run\.sh (blinkit|flipkart|amazon|amazon-fresh|amazon-now|zepto|flipkart-minutes)$' \
    | awk '{print $1 " " substr($0, index($0,$2))}' || true
}

verify_postbuild() {
  local fail=0 f repo

  log "verifying source markdown and today/ manifests"
  for f in \
    "$ROOT/vault/daily/${DATE_IST}.md" \
    "$ROOT/vault/competitor/daily/Competitor-${DATE_IST}.md" \
    "$ROOT/today/daily/${DATE_IST}.md" \
    "$ROOT/today/competitor/daily/Competitor-${DATE_IST}.md" \
    "/root/jivo-data-bank/today/price-scraper/daily/${DATE_IST}.md" \
    "/root/jivo-data-bank/today/competitors/competitor/daily/Competitor-${DATE_IST}.md"
  do
    if [ -s "$f" ]; then
      log "verify OK: $f"
    else
      log "verify MISSING: $f"
      fail=1
    fi
  done

  if git -C /root/jivo-intel log --grep="^daily ${DATE_IST}\$" -1 --format=%H 2>/dev/null | grep -q .; then
    log "verify OK: /root/jivo-intel has daily ${DATE_IST} commit"
  else
    log "verify MISSING: /root/jivo-intel daily ${DATE_IST} commit"
    fail=1
  fi

  for repo in "$ROOT" /root/jivo-factory-intel /root/jivo-intel /root/jivo-data-bank; do
    f="$repo/today/_manifest.json"
    if [ -s "$f" ] && grep -q "\"date\": \"${DATE_IST}\"" "$f"; then
      log "verify OK: $f date=$DATE_IST"
    else
      log "verify MISSING/HOLD: $f date is not $DATE_IST"
      fail=1
    fi
  done

  if [ "$fail" -eq 0 ]; then
    log "VERIFY PASS: today/ snapshot is complete for $DATE_IST"
  else
    log "VERIFY HOLD: today/ snapshot is not complete for $DATE_IST"
  fi
  return "$fail"
}

git_commit_push_ecom() {
  (
    set +e
    cd "$ROOT" || exit 0
    exec 9>"$ROOT/.gitpush.lock"
    command -v flock >/dev/null 2>&1 && flock 9
    git add vault data reviews baselines docs README.md REPORT.md CLAUDE.md >/dev/null 2>&1
    git add platforms/*/pincodes.full25.json >/dev/null 2>&1 || true
    if git diff --cached --quiet; then
      log "ecom git: nothing new to commit"
    else
      git commit -m "vault: manual recovery ${DATE_IST}" >/dev/null 2>&1
      git pull --rebase --autostash >/dev/null 2>&1
      git push >/dev/null 2>&1 || { git pull --rebase --autostash >/dev/null 2>&1; git push >/dev/null 2>&1; }
      log "ecom git: committed + pushed"
    fi
  ) || true
}

log "START date=$DATE_IST max_wait_seconds=$MAX_WAIT_SECONDS"

deadline=$(( $(date +%s) + MAX_WAIT_SECONDS ))
while true; do
  runs="$(active_platform_runs)"
  if [ -z "$runs" ]; then
    break
  fi
  if [ "$(date +%s)" -gt "$deadline" ]; then
    log "ABORT: platform runs still active after ${MAX_WAIT_SECONDS}s:"
    printf '%s\n' "$runs" | tee -a "$LOG"
    exit 1
  fi
  log "waiting for platform runs:"
  printf '%s\n' "$runs" | tee -a "$LOG"
  sleep 60
done

cd "$ROOT" || exit 1

log "rebuilding ecom vault from finished platform history"
if python3 tools/vault_build.py >>"$LOG" 2>&1; then
  log "ecom vault_build OK"
  git_commit_push_ecom
else
  rc=$?
  log "ecom vault_build FAILED rc=$rc; today/ snapshot will not be trustworthy"
  exit "$rc"
fi

if [ -x "$ROOT/tools/competitor/run_daily.sh" ]; then
  log "running downstream competitor + data-bank chain"
  if "$ROOT/tools/competitor/run_daily.sh" >>"$LOG" 2>&1; then
    log "downstream competitor + data-bank chain OK"
  else
    log "downstream competitor + data-bank chain returned non-zero; continuing to readiness check"
  fi
else
  log "SKIP: tools/competitor/run_daily.sh missing/not executable"
fi

if [ -x /root/jivo-intel/bin/run_daily.sh ]; then
  log "refreshing ecom-app source vault for $DATE_IST"
  if /root/jivo-intel/bin/run_daily.sh --date "$DATE_IST" >>"$LOG" 2>&1; then
    log "ecom-app run_daily returned"
  else
    log "ecom-app run_daily returned non-zero; build_today readiness gate may still hold"
  fi
else
  log "SKIP: /root/jivo-intel/bin/run_daily.sh missing/not executable"
fi

log "calling build_today.sh"
"$ROOT/bin/build_today.sh" --date "$DATE_IST" >>"$LOG" 2>&1 || true

if [ -f "$ROOT/today/_manifest.json" ] && grep -q "\"date\": \"${DATE_IST}\"" "$ROOT/today/_manifest.json"; then
  log "DONE: ecom today/ manifest is $DATE_IST"
else
  log "DONE with HOLD: today/ did not advance to $DATE_IST; see build_today readiness messages above"
fi

verify_postbuild || true
