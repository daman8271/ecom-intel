#!/usr/bin/env bash
# Installs the ecom-intel cron jobs robustly (writes from a file, no paste-wrap bugs).
# Re-runnable: it replaces only the ecom-intel lines, preserves any others.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
timedatectl set-timezone Asia/Kolkata 2>/dev/null || true

# Edit this list as platforms go live:
PLATFORMS="blinkit flipkart-minutes"

TMP="$(mktemp)"
crontab -l 2>/dev/null | grep -v 'ecom-intel' > "$TMP" || true
{
  for P in $PLATFORMS; do
    echo "0 9 * * * cd $DIR && ./run.sh $P >> logs/cron.log 2>&1   # ecom-intel"
    echo "0 19 * * * cd $DIR && ./run.sh $P >> logs/cron.log 2>&1   # ecom-intel"
  done
  echo "30 9 * * * cd $DIR && ./healthcheck.sh >> logs/health.log 2>&1   # ecom-intel"
} >> "$TMP"
crontab "$TMP"
rm -f "$TMP"
echo "cron installed:"
crontab -l
