#!/usr/bin/env bash
set +e
cd '/opt/ecom-intel/platforms/bigbasket' || exit 10
mkdir -p '/opt/ecom-intel/platforms/bigbasket/team-runs/bb-recover-vpskvm-20260708'
if [ ! -d node_modules/playwright-extra ]; then npm ci; fi
OUT_FILE='/opt/ecom-intel/platforms/bigbasket/team-runs/bb-recover-vpskvm-20260708/macpro.json' \
PINCODES_FILE='/opt/ecom-intel/platforms/bigbasket/team-runs/bb-recover-vpskvm-20260708/pincodes.macpro.json' \
BB_COOKIE_PATH='/opt/ecom-intel/platforms/bigbasket/secrets/bb_cookies.pincode.json' \
BB_QUERIES='jivo' \
BB_PINCODE_MIN_REQUIRED=1 \
BB_PINCODE_DELAY_MS='3500' \
BB_PINCODE_QUERY_DELAY_MS='3500' \
BB_PINCODE_WATCHDOG_MS='14400000' \
  node scrape_pincode_browser.js >'/opt/ecom-intel/platforms/bigbasket/team-runs/bb-recover-vpskvm-20260708/macpro.stdout' 2>'/opt/ecom-intel/platforms/bigbasket/team-runs/bb-recover-vpskvm-20260708/macpro.log'
rc=$?
printf '%s\n' "$rc" > '/opt/ecom-intel/platforms/bigbasket/team-runs/bb-recover-vpskvm-20260708/macpro.rc'
date -u +%FT%TZ > '/opt/ecom-intel/platforms/bigbasket/team-runs/bb-recover-vpskvm-20260708/macpro.done'
exit "$rc"
