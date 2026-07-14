#!/usr/bin/env bash
# tools/selfheal.sh — ecom-intel self-healing routine.
#
# For each VPS-run platform, decide if its latest run is broken/degraded using
# THREE independent signals, then attempt ONE automatic recovery (re-run via
# ./run.sh <platform>), re-check, and escalate to Telegram if still broken.
#
# Detection signals (any one trips a heal):
#   1. VERDICT  — newest reviews/<platform>-<RUN_ID>.json has "verdict":"BROKEN".
#                 (SUSPECT is a data-quality flag, not a failure — a re-run won't
#                  fix it, so it is recorded in reviews/ + the vault note, NOT re-run.)
#   2. STALE    — platforms/<platform>/result.json is missing, or older than
#                 MAX_AGE_H, or not from today (no fresh result/Excel today).
#   3. COLLAPSE — summary.total_rows fell well below baselines/<platform>.json
#                 (rows <= baseline * COLLAPSE_FRAC), or is under MIN_ROWS.
#
# Recovery:  ./run.sh <platform> ONCE (RETRY_CAP=1), guarded by a per-platform
#            lock file so overlapping cron fires never double-run a scraper.
#            Off-box Mac/drop platforms such as Blinkit, BigBasket, and Swiggy
#            are intentionally excluded so the backstop cannot fall back to the
#            VPS/datacenter path.
# Escalate:  if STILL broken after the retry, send a Telegram alert (same
#            secrets.env TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID pattern as run.sh)
#            naming the platform + reason, and append to logs/health.log.
#
# Best-effort & idempotent: never crashes the box, never aborts mid-recovery,
# safe to run on its own cron as often as you like.

# NOTE: deliberately NOT using `set -e`. A self-heal routine must never abort
# half-way through a recovery just because one sub-step returned non-zero.
set -uo pipefail

export HOME="${HOME:-/root}"
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
DIR="$(cd "$(dirname "$0")/.." && pwd)"   # repo root (tools/ is one level down)
cd "$DIR" || exit 0
mkdir -p logs reviews baselines 2>/dev/null || true

# ---- config -----------------------------------------------------------------
PLATFORMS="${ECOM_PLATFORMS:-flipkart-minutes flipkart amazon amazon-fresh amazon-now}"  # off-box Mac/drop platforms are never VPS-healed
MIN_ROWS="${ECOM_MIN_ROWS:-20}"          # absolute floor; healthy runs return ~60-160
COLLAPSE_FRAC="${ECOM_COLLAPSE_FRAC:-0.5}" # rows <= baseline*this  => collapse
MAX_AGE_H="${ECOM_MAX_AGE_H:-15}"        # result.json older than this = stale
RETRY_CAP="${ECOM_RETRY_CAP:-1}"         # auto re-runs per platform per invocation
RUN_TIMEOUT="${ECOM_RUN_TIMEOUT:-2400}"  # seconds; default hard cap on a single ./run.sh recovery.
                                         # Platform overrides below keep daily rescue parity with
                                         # the deadline sweep without letting every small platform
                                         # inherit a multi-hour timeout.
HEALTH_LOG="$DIR/logs/health.log"
LOCKDIR="$DIR/logs"                       # lock files live here (logs/ is gitignored)
TODAY="$(date +%Y-%m-%d)"

log() { echo "[$(date '+%F %T')] $*" >> "$HEALTH_LOG"; }

# ---- Telegram alert (best-effort; never fails the routine) ------------------
tg_alert() {
  # $1 = message text
  (
    set +e
    [ -f "$DIR/secrets.env" ] && . "$DIR/secrets.env"
    local TG="${TELEGRAM_BOT_TOKEN:-}" CH="${TELEGRAM_CHAT_ID:-}"
    [ -n "$TG" ] && [ -n "$CH" ] || { log "TG: creds missing, alert skipped"; return 0; }
    local R
    R="$(curl -s --max-time 60 -X POST "https://api.telegram.org/bot${TG}/sendMessage" \
            --data-urlencode "chat_id=${CH}" \
            --data-urlencode "text=$1" 2>/dev/null)"
    log "TG sendMessage -> ${R:0:200}"
  ) || true
}

# ---- read newest review verdict for a platform ------------------------------
# echoes "VERDICT ROWS" (e.g. "BROKEN 4"); blanks if no review file present.
read_verdict() {
  local P="$1"
  local f
  # RUN_ID = date +%Y-%m-%d-%H%M (always starts with a 4-digit year), so lexical
  # sort == chronological; newest last. Anchor the glob on the year digit so a
  # shared prefix never bleeds across platforms — e.g. "flipkart-2026-..." must
  # NOT also match "flipkart-minutes-2026-...".
  f="$(ls -1 "$DIR/reviews/${P}-"[0-9][0-9][0-9][0-9]-*.json 2>/dev/null | sort | tail -1)"
  [ -n "$f" ] && [ -f "$f" ] || return 0
  python3 - "$f" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    v = str(d.get("verdict", "")).upper()
    r = d.get("rows", "")
    print(f"{v} {r}")
except Exception:
    pass
PY
}

# ---- baseline expected rows for a platform ----------------------------------
# Reads baselines/<platform>.json; tolerates several plausible shapes.
# echoes an integer (0 if unknown).
baseline_rows() {
  local P="$1"
  local f="$DIR/baselines/${P}.json"
  [ -f "$f" ] || { echo 0; return 0; }
  python3 - "$f" <<'PY' 2>/dev/null || echo 0
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    if isinstance(d, (int, float)):
        print(int(d)); raise SystemExit
    cand = None
    for k in ("rows","total_rows","baseline_rows","expected_rows","median_rows","min_rows"):
        if isinstance(d, dict) and k in d and isinstance(d[k], (int, float)):
            cand = d[k]; break
    if cand is None and isinstance(d, dict):
        s = d.get("summary")
        if isinstance(s, dict):
            for k in ("total_rows","rows"):
                if isinstance(s.get(k), (int, float)):
                    cand = s[k]; break
    print(int(cand) if cand is not None else 0)
except Exception:
    print(0)
PY
}

# ---- result.json row count for a platform (0 if missing/unparseable) --------
result_rows() {
  local P="$1"
  local f="$DIR/platforms/$P/result.json"
  [ -f "$f" ] || { echo 0; return 0; }
  python3 - "$f" <<'PY' 2>/dev/null || echo 0
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    s = d.get("summary", {}) or {}
    r = s.get("total_rows")
    if not isinstance(r, (int, float)):
        rows = d.get("allRows") or [x for p in d.get("perPin", []) for x in p.get("rows", [])]
        r = len(rows)
    print(int(r))
except Exception:
    print(0)
PY
}

# ---- age of result.json in hours (9999 if missing) --------------------------
result_age_h() {
  local f="$DIR/platforms/$1/result.json"
  [ -f "$f" ] || { echo 9999; return 0; }
  local m
  m="$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)"
  echo "$(( ( $(date +%s) - m ) / 3600 ))"
}

# ---- does this platform have a fresh artifact from TODAY? -------------------
# checks result.json mtime date AND today's Excel in output/.
fresh_today() {
  local P="$1"
  local f="$DIR/platforms/$P/result.json"
  if [ -f "$f" ]; then
    local d
    d="$(date -d "@$(stat -c %Y "$f" 2>/dev/null || echo 0)" +%Y-%m-%d 2>/dev/null || echo "")"
    [ "$d" = "$TODAY" ] && return 0
  fi
  # fall back to an Excel dated today in output/
  ls "$DIR/output/"*"${TODAY}.xlsx" >/dev/null 2>&1 && return 0
  return 1
}

# ---- evaluate a platform's health; echo "OK" or a human reason --------------
# usage: assess <platform>  -> prints "OK" or "<reason>"
assess() {
  local P="$1"
  local rows age base verdict vrows reason=""

  rows="$(result_rows "$P")";    rows="${rows:-0}"
  age="$(result_age_h "$P")";    age="${age:-9999}"
  base="$(baseline_rows "$P")";  base="${base:-0}"

  # signal 1: review verdict. Only BROKEN triggers an auto re-run; SUSPECT is a
  # data-quality flag (truncated names, scale change, etc.) that a re-run won't
  # fix, so it is left to the recorded verdict + vault note, not a wasted re-run.
  read -r verdict vrows < <(read_verdict "$P"); verdict="${verdict:-}"; vrows="${vrows:-}"
  if [ "$verdict" = "BROKEN" ]; then
    reason="verdict=$verdict (review rows=${vrows:-?})"
  fi

  # signal 2: staleness
  if ! fresh_today "$P"; then
    reason="${reason:+$reason; }stale (no fresh result/Excel today, age=${age}h)"
  elif [ "${age}" -gt "$MAX_AGE_H" ] 2>/dev/null; then
    reason="${reason:+$reason; }stale (age=${age}h > ${MAX_AGE_H}h)"
  fi

  # signal 3: row collapse / floor
  if [ "${rows}" -lt "$MIN_ROWS" ] 2>/dev/null; then
    reason="${reason:+$reason; }rows=$rows < floor $MIN_ROWS"
  elif [ "${base}" -gt 0 ] 2>/dev/null; then
    # collapse if rows <= base*COLLAPSE_FRAC  (integer math via python for the frac)
    local thr
    thr="$(python3 -c "print(int($base*$COLLAPSE_FRAC))" 2>/dev/null || echo 0)"
    if [ "${rows}" -le "${thr}" ] 2>/dev/null && [ "${thr}" -gt 0 ]; then
      reason="${reason:+$reason; }collapse rows=$rows <= ${thr} (baseline=$base)"
    fi
  fi

  if [ -n "$reason" ]; then echo "$reason"; else echo "OK"; fi
}

# ---- recover one platform: re-run ./run.sh once, under a lock ---------------
# returns 0 if a re-run was attempted, 1 if skipped (lock held).
recover() {
  local P="$1"
  case "$P" in
    blinkit|zepto|bigbasket|swiggy-instamart)
      log "$P: REFUSED local recovery; platform is off-box-only"
      return 1
      ;;
  esac
  local run_timeout="$RUN_TIMEOUT"
  local daily_env=0
  case "$P" in
    flipkart-minutes|amazon-fresh|amazon-now)
      daily_env=1
      ;;
  esac
  case "$P" in
    amazon-fresh) run_timeout="${ECOM_AMAZON_FRESH_RUN_TIMEOUT:-7800}" ;;
    amazon-now) run_timeout="${ECOM_AMAZON_NOW_RUN_TIMEOUT:-7800}" ;;
  esac
  local lock="$LOCKDIR/.heal-${P}.lock"
  # Non-blocking lock: if another fire is already healing this platform, skip.
  exec {LFD}>"$lock" 2>/dev/null || { log "$P: cannot open lock $lock; skipping recover"; return 1; }
  if ! flock -n "$LFD"; then
    log "$P: lock held by another run; skipping recover (no double-run)"
    eval "exec ${LFD}>&-" 2>/dev/null || true
    return 1
  fi
  log "$P: lock acquired; re-running ./run.sh $P (retry cap=$RETRY_CAP timeout=${run_timeout}s daily_env=$daily_env)"
  local attempt=0 ok=1
  while [ "$attempt" -lt "$RETRY_CAP" ]; do
    attempt=$((attempt+1))
    log "$P: recovery attempt $attempt/$RETRY_CAP -> ./run.sh $P"
    if [ "$daily_env" = "1" ]; then
      timeout "$run_timeout" env COVERAGE_DAILY=1 ./run.sh "$P" >> "$DIR/logs/cron.log" 2>&1
    else
      timeout "$run_timeout" ./run.sh "$P" >> "$DIR/logs/cron.log" 2>&1
    fi
    rc=$?
    log "$P: ./run.sh exited rc=$rc"
    [ "$rc" -eq 0 ] && { ok=0; break; }
  done
  # release lock
  flock -u "$LFD" 2>/dev/null || true
  eval "exec ${LFD}>&-" 2>/dev/null || true
  return 0
}

# =============================================================================
main() {
  log "selfheal start (platforms: $PLATFORMS)"
  local healed=0 still_broken=0
  for P in $PLATFORMS; do
    local reason
    reason="$(assess "$P")"
    if [ "$reason" = "OK" ]; then
      log "$P OK"
      continue
    fi

    log "$P DEGRADED -> $reason"

    # attempt recovery (lock-guarded)
    if ! recover "$P"; then
      # skipped because lock was held by a concurrent fire — leave it to that run
      continue
    fi
    healed=$((healed+1))

    # re-assess after the re-run
    local reason2
    reason2="$(assess "$P")"
    if [ "$reason2" = "OK" ]; then
      log "$P RECOVERED after re-run"
    else
      still_broken=$((still_broken+1))
      log "$P STILL BROKEN after re-run -> $reason2"
      tg_alert "⚠️ ecom-intel self-heal: *$P* still broken after auto re-run.
Reason: $reason2
First seen: $reason
Host: $(hostname 2>/dev/null || echo vps) · $(date '+%F %H:%M IST')
Manual attention needed (likely captcha / IP block / selector change)."
    fi
  done
  log "selfheal done (degraded+healed=$healed, still_broken=$still_broken)"
}

main "$@"
exit 0
