#!/usr/bin/env bash
# record_duration.sh <platform> <seconds> <sweep_id>
#
# Appends one JSON line to tools/cron/durations.jsonl:
#   {"platform":"<p>","secs":<n>,"sweep":"<sweep_id>","ts":"<iso8601>"}
# Called by run_all.sh after each platform's pipeline (W2's hook) so
# predict_lead.py always has fresh runtime history.
#
# Contract: ATOMIC append (flock + single printf), and NEVER fails —
# any problem (bad args, unwritable disk) exits 0 silently so the sweep
# can't be hurt by its own bookkeeping.
set +e

P="${1:-}"
SECS="${2:-}"
SWEEP="${3:-}"

DIR="$(cd "$(dirname "$0")" && pwd)" || exit 0
# DURATIONS_FILE env override keeps W4's sim hermetic (never touches real history)
F="${DURATIONS_FILE:-$DIR/durations.jsonl}"

# validate: need a platform and an integer seconds value, else silently no-op
[ -n "$P" ] || exit 0
case "$SECS" in ''|*[!0-9]*) exit 0 ;; esac

# keep the JSON well-formed even if callers pass odd ids: strip the only
# JSON-hostile chars (" and \) from the string fields
P="${P//\\/}";     P="${P//\"/}"
SWEEP="${SWEEP//\\/}"; SWEEP="${SWEEP//\"/}"

TS="$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || echo unknown)"
LINE="{\"platform\":\"$P\",\"secs\":$SECS,\"sweep\":\"$SWEEP\",\"ts\":\"$TS\"}"

# atomic append: one printf of one line, serialized by flock when available
if command -v flock >/dev/null 2>&1; then
  (
    flock -w 10 9 2>/dev/null
    printf '%s\n' "$LINE" >> "$F"
  ) 9>>"$F.lock" 2>/dev/null || printf '%s\n' "$LINE" >> "$F" 2>/dev/null
else
  printf '%s\n' "$LINE" >> "$F" 2>/dev/null
fi

exit 0
