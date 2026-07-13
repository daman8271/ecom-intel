@echo off
setlocal
set "TEST_DIR=C:\scrape-worker\ecom-intel\platforms\blinkit\device-tests\20260714-023251"
cd /d "%TEST_DIR%"
del /q result.json progress.json run.rc started_at.txt finished_at.txt 2>nul
powershell -NoProfile -Command "(Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')" > started_at.txt
set "BLINKIT_AUTH_STATE_FILE=C:\scrape-worker\secrets\blinkit-auth-state.json"
set "BLINKIT_REQUIRE_AUTH=1"
set "BLINKIT_OOS_PROBE=1"
set "BLINKIT_PDP_OOS_PROBE=1"
set "BLINKIT_PDP_PRICE_PROBE=1"
set "CONCURRENCY=1"
set "BLINKIT_CHROMIUM_EXECUTABLE=C:\Users\prabh\AppData\Local\ms-playwright\chromium-1228\chrome-win64\chrome.exe"
set "PINCODES_FILE=%TEST_DIR%\pincodes.json"
set "OUT_FILE=%TEST_DIR%\result.json"
set "BLINKIT_PROGRESS_FILE=%TEST_DIR%\progress.json"
node "%TEST_DIR%\scrape.js" 1>stdout.log 2>stderr.log
set "RC=%ERRORLEVEL%"
echo %RC%>run.rc
powershell -NoProfile -Command "(Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')" > finished_at.txt
exit /b %RC%
