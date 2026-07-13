#!/usr/bin/env bash
set +e
cd '/opt/ecom-intel/platforms/bigbasket' || exit 10
mkdir -p '/opt/ecom-intel/platforms/bigbasket/team-runs/bb-team-20260714-030001'
if [ ! -d node_modules/playwright-extra ]; then npm ci; fi
OUT_FILE='/opt/ecom-intel/platforms/bigbasket/team-runs/bb-team-20260714-030001/kvm1.json' \
PINCODES_FILE='/opt/ecom-intel/platforms/bigbasket/team-runs/bb-team-20260714-030001/pincodes.kvm1.json' \
BB_COOKIE_PATH='/opt/ecom-intel/platforms/bigbasket/secrets/bb_cookies.pincode.json' \
BB_QUERIES='jivo' \
BB_PINCODE_MIN_REQUIRED=1 \
BB_PINCODE_DELAY_MS='3500' \
BB_PINCODE_QUERY_DELAY_MS='3500' \
BB_PINCODE_WATCHDOG_MS='21600000' \
  node scrape_pincode_browser.js >'/opt/ecom-intel/platforms/bigbasket/team-runs/bb-team-20260714-030001/kvm1.stdout' 2>'/opt/ecom-intel/platforms/bigbasket/team-runs/bb-team-20260714-030001/kvm1.log'
rc=$?
printf '%s\n' "$rc" > '/opt/ecom-intel/platforms/bigbasket/team-runs/bb-team-20260714-030001/kvm1.rc'
date -u +%FT%TZ > '/opt/ecom-intel/platforms/bigbasket/team-runs/bb-team-20260714-030001/kvm1.done'
exit "$rc"
