#!/usr/bin/env bash
set +e
cd '/Users/danny./VPS-Migration/imported/ecom-intel/platforms/bigbasket' || exit 10
mkdir -p '/Users/danny./VPS-Migration/imported/ecom-intel/platforms/bigbasket/team-runs/bb-soy-fix-20260706-01'
if [ ! -d node_modules/playwright-extra ]; then npm ci; fi
OUT_FILE='/Users/danny./VPS-Migration/imported/ecom-intel/platforms/bigbasket/team-runs/bb-soy-fix-20260706-01/macpro.json' \
PINCODES_FILE='/Users/danny./VPS-Migration/imported/ecom-intel/platforms/bigbasket/team-runs/bb-soy-fix-20260706-01/pincodes.macpro.json' \
BB_COOKIE_PATH='/Users/danny./VPS-Migration/imported/ecom-intel/platforms/bigbasket/secrets/bb_cookies.pincode.json' \
BB_QUERIES='jivo' \
BB_PINCODE_MIN_REQUIRED=1 \
BB_PINCODE_DELAY_MS='2500' \
BB_PINCODE_QUERY_DELAY_MS='2500' \
BB_PINCODE_WATCHDOG_MS='14400000' \
  node scrape_pincode_browser.js >'/Users/danny./VPS-Migration/imported/ecom-intel/platforms/bigbasket/team-runs/bb-soy-fix-20260706-01/macpro.stdout' 2>'/Users/danny./VPS-Migration/imported/ecom-intel/platforms/bigbasket/team-runs/bb-soy-fix-20260706-01/macpro.log'
rc=$?
printf '%s\n' "$rc" > '/Users/danny./VPS-Migration/imported/ecom-intel/platforms/bigbasket/team-runs/bb-soy-fix-20260706-01/macpro.rc'
date -u +%FT%TZ > '/Users/danny./VPS-Migration/imported/ecom-intel/platforms/bigbasket/team-runs/bb-soy-fix-20260706-01/macpro.done'
exit "$rc"
