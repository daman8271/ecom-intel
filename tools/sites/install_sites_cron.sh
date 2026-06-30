#!/usr/bin/env bash
# Site refresh is EVENT-DRIVEN (goal #40, 2026-07-01): it is triggered by the
# SITE-REFRESH-HOOK at the tail of tools/cron/deadline_sweep.sh, which fires the
# instant the noon sweep lands today's data (rc=0) — right after the competitor +
# data-bank downstream chain. There is NO standalone timed cron (no clock to tune;
# it auto-slides if the sweep runs late, and never fires if the sweep failed).
#
# This script just VERIFIES that wiring and removes any stale standalone timer.
set -euo pipefail
cd "$(cd "$(dirname "$0")/../.." && pwd)"
if grep -q 'SITE-REFRESH-HOOK' tools/cron/deadline_sweep.sh; then
  echo "OK: event-driven SITE-REFRESH-HOOK present in tools/cron/deadline_sweep.sh"
else
  echo "WARN: SITE-REFRESH-HOOK MISSING from deadline_sweep.sh — the refresh will NOT auto-fire. Re-add the hook."
fi
if crontab -l 2>/dev/null | grep -q '# ecom-sites'; then
  crontab -l | grep -v '# ecom-sites' | crontab -
  echo "removed stale standalone '# ecom-sites' timer (superseded by the hook)"
else
  echo "OK: no standalone timer present (event-driven only)"
fi
