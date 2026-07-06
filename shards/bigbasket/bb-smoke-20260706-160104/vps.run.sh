#!/usr/bin/env bash
set +e
cd '/opt/ecom-intel/platforms/bigbasket' || exit 10
mkdir -p '/opt/ecom-intel/shards/bigbasket/bb-smoke-20260706-160104'
if [ ! -d node_modules/playwright-extra ]; then npm ci; fi
OUT_FILE='/opt/ecom-intel/shards/bigbasket/bb-smoke-20260706-160104/vps.json' \
PINCODES_FILE='/opt/ecom-intel/shards/bigbasket/bb-smoke-20260706-160104/pincodes.vps.json' \
BB_COOKIE_PATH='/opt/ecom-intel/platforms/bigbasket/secrets/bb_cookies.pincode.json' \
BB_QUERIES='jivo' \
BB_PINCODE_MIN_REQUIRED=1 \
BB_PINCODE_DELAY_MS='500' \
BB_PINCODE_QUERY_DELAY_MS='500' \
BB_PINCODE_WATCHDOG_MS='900000' \
  node scrape_pincode_browser.js >'/opt/ecom-intel/shards/bigbasket/bb-smoke-20260706-160104/vps.stdout' 2>'/opt/ecom-intel/shards/bigbasket/bb-smoke-20260706-160104/vps.log'
rc=$?
printf '%s\n' "$rc" > '/opt/ecom-intel/shards/bigbasket/bb-smoke-20260706-160104/vps.rc'
date -u +%FT%TZ > '/opt/ecom-intel/shards/bigbasket/bb-smoke-20260706-160104/vps.done'
exit "$rc"
