@echo off
setlocal
set "RUN=C:\scrape-worker\team-runs\20260713-blinkit-competitor-top8-3pcity"
set "PROJECT=C:\scrape-worker\ecom-intel"
cd /d "%PROJECT%\platforms\blinkit"
set "COMPETITOR_MODE=1"
set "COMPETITOR_DATE=2026-07-13-TOP8-3PCITY-RETRY"
set "COMPETITOR_BRANDS=Jivo,Sano,Fortune,Saffola,Borges,Tata,Del Monte,Figaro,Sundrop,Gulab"
set "BLINKIT_AUTH_STATE_FILE=C:\scrape-worker\secrets\blinkit-auth-state.json"
set "BLINKIT_REQUIRE_AUTH=1"
set "BLINKIT_OOS_PROBE=0"
set "BLINKIT_PDP_OOS_PROBE=0"
set "BLINKIT_PDP_PRICE_PROBE=0"
set "CONCURRENCY=2"
set "BLINKIT_CHROMIUM_EXECUTABLE=C:\Users\prabh\AppData\Local\ms-playwright\chromium-1228\chrome-win64\chrome.exe"
set "PINCODES_FILE=%RUN%\pincodes.retry.json"
set "BLINKIT_PROGRESS_FILE=%RUN%\retry.progress.json"
del /q "%RUN%\retry.progress.json" 2>nul
del /q "%PROJECT%\tools\competitor\data\blinkit_competitor_2026-07-13-TOP8-3PCITY-RETRY.json" 2>nul
node scrape.js 1>"%RUN%\retry.stdout.log" 2>"%RUN%\retry.run.log"
set "RC=%ERRORLEVEL%"
if exist "%PROJECT%\tools\competitor\data\blinkit_competitor_2026-07-13-TOP8-3PCITY-RETRY.json" copy /y "%PROJECT%\tools\competitor\data\blinkit_competitor_2026-07-13-TOP8-3PCITY-RETRY.json" "%RUN%\retry.capture.json" >nul
>"%RUN%\retry.run.rc" echo %RC%
>"%RUN%\retry.run.done" echo %DATE% %TIME%
scp -q -o BatchMode=yes -o ConnectTimeout=20 "%RUN%\retry.run.rc" "%RUN%\retry.run.done" "%RUN%\retry.run.log" "%RUN%\retry.stdout.log" vps-bridge:/opt/ecom-intel/shards/runs/20260713-blinkit-competitor-top8-3pcity/
if exist "%RUN%\retry.capture.json" scp -q -o BatchMode=yes -o ConnectTimeout=20 "%RUN%\retry.capture.json" vps-bridge:/opt/ecom-intel/shards/runs/20260713-blinkit-competitor-top8-3pcity/retry.capture.json
if exist "%RUN%\retry.progress.json" scp -q -o BatchMode=yes -o ConnectTimeout=20 "%RUN%\retry.progress.json" vps-bridge:/opt/ecom-intel/shards/runs/20260713-blinkit-competitor-top8-3pcity/retry.progress.json
exit /b %RC%
