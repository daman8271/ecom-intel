#!/usr/bin/env bash
set +e
cd '/opt/ecom-intel/platforms/bigbasket' || exit 10
mkdir -p '/opt/ecom-intel/shards/bigbasket/bb-team-20260710-030001'
if [ ! -d node_modules/playwright-extra ]; then npm ci; fi
OUT_FILE='/opt/ecom-intel/shards/bigbasket/bb-team-20260710-030001/vps.json' \
PINCODES_FILE='/opt/ecom-intel/shards/bigbasket/bb-team-20260710-030001/pincodes.vps.json' \
BB_COOKIE_PATH='/opt/ecom-intel/platforms/bigbasket/secrets/bb_cookies.pincode.json' \
BB_QUERIES='jivo' \
BB_PINCODE_MIN_REQUIRED=1 \
BB_PINCODE_DELAY_MS='3500' \
BB_PINCODE_QUERY_DELAY_MS='3500' \
BB_PINCODE_WATCHDOG_MS='14400000' \
  node scrape_pincode_browser.js >'/opt/ecom-intel/shards/bigbasket/bb-team-20260710-030001/vps.stdout' 2>'/opt/ecom-intel/shards/bigbasket/bb-team-20260710-030001/vps.log'
rc=$?
printf '%s\n' "$rc" > '/opt/ecom-intel/shards/bigbasket/bb-team-20260710-030001/vps.rc'
date -u +%FT%TZ > '/opt/ecom-intel/shards/bigbasket/bb-team-20260710-030001/vps.done'
exit "$rc"
