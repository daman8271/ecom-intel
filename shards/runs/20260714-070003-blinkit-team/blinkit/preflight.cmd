@echo off
cd /d "C:\scrape-worker\ecom-intel\platforms\blinkit"
set "BLINKIT_AUTH_STATE_FILE=C:\scrape-worker\secrets\blinkit-auth-state.json"
set "BLINKIT_REQUIRE_AUTH=1"
set "BLINKIT_OOS_PROBE=0"
set "BLINKIT_PDP_OOS_PROBE=0"
set "BLINKIT_PDP_PRICE_PROBE=0"
set "CONCURRENCY=1"
set "BLINKIT_CHROMIUM_EXECUTABLE=C:\Users\prabh\AppData\Local\ms-playwright\chromium-1228\chrome-win64\chrome.exe"
set "PINCODES_FILE=C:\scrape-worker\team-runs\20260714-070003-blinkit-team\preflight-pincodes.json"
set "OUT_FILE=C:\scrape-worker\team-runs\20260714-070003-blinkit-team\preflight.json"
set "BLINKIT_PROGRESS_FILE=C:\scrape-worker\team-runs\20260714-070003-blinkit-team\preflight.progress.json"
node scrape.js 1>"C:\scrape-worker\team-runs\20260714-070003-blinkit-team\preflight.stdout" 2>"C:\scrape-worker\team-runs\20260714-070003-blinkit-team\preflight.log"
exit /b %ERRORLEVEL%
