@echo off
cd /d "C:\Users\prabh\bb"
set "OUT_FILE=C:\Users\prabh\bb\team-runs\bb-team-20260714-030001\laptop.json"
set "PINCODES_FILE=C:\Users\prabh\bb\team-runs\bb-team-20260714-030001\pincodes.laptop.json"
set "BB_COOKIE_PATH=C:\Users\prabh\bb\secrets\bb_cookies.pincode.json"
set "BB_QUERIES=jivo"
set "BB_PINCODE_MIN_REQUIRED=1"
set "BB_PINCODE_DELAY_MS=3500"
set "BB_PINCODE_QUERY_DELAY_MS=3500"
set "BB_PINCODE_WATCHDOG_MS=21600000"
node scrape_pincode_browser.js 1>"C:\Users\prabh\bb\team-runs\bb-team-20260714-030001\laptop.stdout" 2>"C:\Users\prabh\bb\team-runs\bb-team-20260714-030001\laptop.log"
set "RC=%ERRORLEVEL%"
>"C:\Users\prabh\bb\team-runs\bb-team-20260714-030001\laptop.rc" echo %RC%
>"C:\Users\prabh\bb\team-runs\bb-team-20260714-030001\laptop.done" echo %DATE% %TIME%
exit /b %RC%
