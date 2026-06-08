#!/usr/bin/env bash
# tools/cron/safe_fixes/restart_helper.sh <name>
#
# SAFE-FIX #4 — restart a DEAD known background helper.
#
# The ecom-intel pipeline is cron-driven: there are NO resident services in the normal
# scrape/review/deliver path (each sweep is a fresh process tree). The only optional
# resident helper is the WhatsApp OUTBOUND bridge, and even that is DISABLED by default
# (outbound-only; WA_BOT_ENABLE gates inbound). So by design this fix is almost always a
# no-op that returns exit 1 (=> propose-only) rather than inventing something to restart.
#
# It restarts ONLY:
#   - a helper whose name is in the explicit ALLOW-LIST below, AND
#   - that is enabled by its own env gate, AND
#   - that is currently NOT running (provably dead).
# Anything else (unknown name, already running, disabled, restart failed) -> exit 1.
#
# Dry/testing: DOCTOR_DRY=1 logs the intended restart without launching anything.

SF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SF_DIR/_common.sh"

NAME="${1:?usage: restart_helper.sh <name>   (known helpers: wa-bridge)}"
log "BEGIN restart_helper check: $NAME"

# is_running <pgrep-pattern> : 0 if at least one matching process is alive.
is_running() { pgrep -f "$1" >/dev/null 2>&1; }

case "$NAME" in
  wa-bridge|whatsapp|wa)
    # The WhatsApp OUTBOUND watcher. Gated by WA_BOT_ENABLE (default OFF). We only act if
    # it is explicitly enabled AND dead.
    if [ "${WA_BOT_ENABLE:-0}" != "1" ]; then
      ambiguous "wa-bridge is DISABLED (WA_BOT_ENABLE!=1, outbound-only mode) — nothing to restart"
    fi
    PATTERN="tools/whatsapp/watch.js"
    if is_running "$PATTERN"; then
      ok_done "wa-bridge already running — no restart needed (idempotent)"
    fi
    if is_dry; then
      ok_done "wa-bridge dead; [DRY] would relaunch tools/whatsapp/watch.sh (no launch performed)"
    fi
    log "wa-bridge dead — relaunching tools/whatsapp/watch.sh in the background ..."
    ( cd "$REPO" && nohup bash tools/whatsapp/watch.sh >>"$REPO/logs/wa-watch.log" 2>&1 & ) || \
      ambiguous "wa-bridge relaunch failed"
    sleep 2
    if is_running "$PATTERN"; then
      ok_done "wa-bridge restarted (was dead)."
    else
      ambiguous "wa-bridge relaunch did not come up — propose-only (manual check)"
    fi
    ;;
  *)
    ambiguous "unknown helper '$NAME' — not in the allow-list (known: wa-bridge). Propose-only."
    ;;
esac
