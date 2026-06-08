#!/usr/bin/env bash
# tools/cron/safe_fixes/clear_stale_lock.sh <lockfile>
#
# SAFE-FIX #3 — remove a PROVABLY-orphaned flock file.
#
# The pipeline serializes critical sections with flock targets (.gitpush.lock,
# .gitcommit.lock, .sweep-chain.lock, .<platform>.lock, durations.jsonl.lock, ...).
# With flock, a leftover file is normally HARMLESS — the kernel releases the lock when
# the holder dies. This fix exists for the rare case where the agent wants to assert a
# lock is free and tidy a stale artifact, and it does so SAFELY:
#
#   - We attempt a NON-BLOCKING flock on the file. If we GET it, no live process holds
#     it -> it is provably orphaned -> safe to remove. If we CANNOT get it, a live
#     process holds it -> REFUSE (exit 1 => propose-only). Never break an active lock.
#
# Guards: the path must be inside the repo and end in .lock; never a directory; never a
# tracked/committed file (locks are gitignored runtime artifacts).
#
# Idempotent: a missing lock file is treated as already-clear (exit 0).

SF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SF_DIR/_common.sh"

LOCK="${1:?usage: clear_stale_lock.sh <lockfile>}"

# Normalize to an absolute path and require it to live inside the repo.
case "$LOCK" in
  /*) ABS="$LOCK" ;;
  *)  ABS="$REPO/$LOCK" ;;
esac
ABS="$(cd "$(dirname "$ABS")" 2>/dev/null && pwd)/$(basename "$ABS")" 2>/dev/null || ambiguous "cannot resolve path: $LOCK"

case "$ABS" in
  "$REPO"/*) : ;;
  *) ambiguous "refusing: $ABS is outside the repo ($REPO)" ;;
esac
case "$ABS" in
  *.lock) : ;;
  *) ambiguous "refusing: $ABS does not end in .lock" ;;
esac
[ -d "$ABS" ] && ambiguous "refusing: $ABS is a directory, not a lock file"

if [ ! -e "$ABS" ]; then
  ok_done "lock already absent: $ABS (nothing to clear)"
fi

# Refuse to touch a git-tracked file (locks must be runtime-only / gitignored).
if ( cd "$REPO" && git ls-files --error-unmatch "$ABS" >/dev/null 2>&1 ); then
  ambiguous "refusing: $ABS is git-tracked — not a runtime lock"
fi

command -v flock >/dev/null 2>&1 || ambiguous "flock not available — cannot prove the lock is orphaned"

log "BEGIN stale-lock check: $ABS"

# Probe: can we take it non-blocking? If yes, no live holder.
if ( flock -n 8 ) 8<"$ABS"; then
  rm -f "$ABS" 2>/dev/null || ambiguous "lock is orphaned but rm failed: $ABS"
  ok_done "removed provably-orphaned lock (no live holder): $ABS"
else
  ambiguous "$ABS is HELD by a live process — refusing to break an active lock"
fi
