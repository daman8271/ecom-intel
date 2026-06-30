#!/usr/bin/env bash
# Idempotent installer for the daily Jivo-ecom-sites refresh+deploy cron.
# Runs at 12:30 IST — after the noon coverage batch lands (~12:00) and the
# coverage_12h ledger sync (12:00). Touches only the "# ecom-sites" line.
set -euo pipefail
LINE='30 12 * * * /opt/ecom-intel/tools/sites/refresh_sites.sh >> /opt/ecom-intel/logs/sites_refresh.cron.log 2>&1   # ecom-sites refresh+deploy'
tmp=$(mktemp)
crontab -l 2>/dev/null | grep -v '# ecom-sites' > "$tmp" || true
echo "$LINE" >> "$tmp"
crontab "$tmp"
rm -f "$tmp"
echo "installed:"
crontab -l | grep '# ecom-sites'
