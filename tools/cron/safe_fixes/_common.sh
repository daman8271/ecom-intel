#!/usr/bin/env bash
# tools/cron/safe_fixes/_common.sh — shared helpers for the doctor's vetted safe-fix menu.
#
# Sourced by every safe_fixes/*.sh. NOT a fix itself. Provides repo-root resolution,
# structured logging, the "exit on any doubt" contract, and the KNOWN-false-positive
# classification used by unhold_false_positive.sh.
#
# Contract every safe-fix script inherits (see MENU.md):
#   deterministic · idempotent · self-verifying · logs what it did ·
#   exit != 0 on ANY ambiguity  => the doctor agent falls back to PROPOSE-ONLY.
#
# Dry hooks (used by W3's doctor_dryrun.sh and by the agent in a dry context):
#   DOCTOR_DRY=1        -> never send a real Telegram / never push; log "would ..." instead.
#   RUNNER_OVERRIDE     -> command run instead of ./run.sh (rerun_platform stub).
#   DOCTOR_NOW          -> override the wall clock stamp (epoch or 'YYYY-mm-dd-HHMM') for tests.

set -euo pipefail

# Repo root = three levels up from this file (tools/cron/safe_fixes/ -> repo).
SF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SF_DIR/../../.." && pwd)"
DOCTOR_LOG_DIR="$REPO/logs/doctor"
SAFE_FIX_LOG="$DOCTOR_LOG_DIR/safe_fixes.log"
mkdir -p "$DOCTOR_LOG_DIR" 2>/dev/null || true

# Name of the running fix script, for log lines.
SF_NAME="$(basename "${BASH_SOURCE[1]:-safe_fix}")"

now_stamp()  { date '+%F %T'; }
date_tag()   { date '+%Y-%m-%d'; }
run_id_tag() { date '+%Y-%m-%d-%H%M'; }

# log <msg...> : timestamped line to both stdout and the safe-fix log.
log() {
  local line
  line="[$(now_stamp)] [$SF_NAME] $*"
  echo "$line"
  echo "$line" >> "$SAFE_FIX_LOG" 2>/dev/null || true
}

# ambiguous <reason...> : the single, loud failure path. ANY doubt -> exit 1 so the
# agent stays PROPOSE-ONLY. Never destructive on the way out.
ambiguous() {
  log "AMBIGUOUS -> propose-only (exit 1): $*"
  exit 1
}

# ok_done <msg...> : success terminator.
ok_done() {
  log "DONE: $*"
  exit 0
}

is_dry() { [ "${DOCTOR_DRY:-0}" = "1" ]; }

# --- review verdict helpers -------------------------------------------------

# latest_review_file <platform> : path of the most-recent REAL review verdict json
# (excludes the doctor's own -unhold/-doctor/-probe synthetic verdicts). Empty if none.
latest_review_file() {
  local p="$1"
  ls -t "$REPO"/reviews/"$p"-*.json 2>/dev/null \
    | grep -Ev -- '-(unhold|doctor|probe|w2probe)\.json$' \
    | head -1
}

# verdict_of <review.json> : prints OK|SUSPECT|BROKEN (BROKEN if unreadable — fail closed).
verdict_of() {
  python3 - "$1" <<'PY' 2>/dev/null || echo BROKEN
import json, sys
try:
    print((json.load(open(sys.argv[1])).get("verdict") or "BROKEN").upper())
except Exception:
    print("BROKEN")
PY
}

# reasons_of <review.json> : prints one held-reason per line (empty if OK / none).
reasons_of() {
  python3 - "$1" <<'PY' 2>/dev/null || true
import json, sys
try:
    for r in (json.load(open(sys.argv[1])).get("reasons") or []):
        print(r)
except Exception:
    pass
PY
}

# The ONLY two held-reason classes the doctor is allowed to auto-unhold. These are the
# exact two false positives proven on 2026-06-08 (flipkart shared_price_dup all-same
# product / seller dupes; zepto price_staleness with movers present + realtime path).
# Both are now FIXED in the committed review.py — so a fresh re-run on the SAME data
# returns OK. The prefix gate below is the guard that we only ever auto-unhold these.
KNOWN_FP_PREFIXES="shared_price_dup price_staleness"

# reason_is_known_fp <reason-line> : 0 if its "name:" prefix is in KNOWN_FP_PREFIXES.
reason_is_known_fp() {
  local prefix="${1%%:*}"
  prefix="$(echo "$prefix" | tr -d '[:space:]')"
  local k
  for k in $KNOWN_FP_PREFIXES; do
    [ "$prefix" = "$k" ] && return 0
  done
  return 1
}
