@echo off
setlocal
set "RUN=C:\scrape-worker\team-runs\20260713-blinkit-competitor-top8-3pcity"
set "PROJECT=C:\scrape-worker\ecom-intel"
cd /d "%PROJECT%\platforms\blinkit"
set "COMPETITOR_MODE=1"
set "COMPETITOR_DATE=2026-07-13-TOP8-3PCITY-RETRY2"
set "COMPETITOR_BRANDS=Jivo,Sano,Fortune,Saffola,Borges,Tata,Del Monte,Figaro,Sundrop,Gulab"
set "BLINKIT_AUTH_STATE_FILE=C:\scrape-worker\secrets\blinkit-auth-state.json"
set "BLINKIT_REQUIRE_AUTH=1"
set "BLINKIT_OOS_PROBE=0"
set "BLINKIT_PDP_OOS_PROBE=0"
set "BLINKIT_PDP_PRICE_PROBE=0"
set "CONCURRENCY=2"
set "BLINKIT_CHROMIUM_EXECUTABLE=C:\Users\prabh\AppData\Local\ms-playwright\chromium-1228\chrome-win64\chrome.exe"
set "PINCODES_FILE=%RUN%\pincodes.retry2.json"
set "BLINKIT_PROGRESS_FILE=%RUN%\retry2.progress.json"
del /q "%RUN%\retry2.progress.json" 2>nul
del /q "%PROJECT%\tools\competitor\data\blinkit_competitor_2026-07-13-TOP8-3PCITY-RETRY2.json" 2>nul
node scrape.js 1>"%RUN%\retry2.stdout.log" 2>"%RUN%\retry2.run.log"
set "RC=%ERRORLEVEL%"
if exist "%PROJECT%\tools\competitor\data\blinkit_competitor_2026-07-13-TOP8-3PCITY-RETRY2.json" copy /y "%PROJECT%\tools\competitor\data\blinkit_competitor_2026-07-13-TOP8-3PCITY-RETRY2.json" "%RUN%\retry2.capture.json" >nul
>"%RUN%\retry2.run.rc" echo %RC%
>"%RUN%\retry2.run.done" echo %DATE% %TIME%
scp -q -o BatchMode=yes -o ConnectTimeout=20 "%RUN%\retry2.run.rc" "%RUN%\retry2.run.done" "%RUN%\retry2.run.log" "%RUN%\retry2.stdout.log" vps-bridge:/opt/ecom-intel/shards/runs/20260713-blinkit-competitor-top8-3pcity/
if exist "%RUN%\retry2.capture.json" scp -q -o BatchMode=yes -o ConnectTimeout=20 "%RUN%\retry2.capture.json" vps-bridge:/opt/ecom-intel/shards/runs/20260713-blinkit-competitor-top8-3pcity/retry2.capture.json
if exist "%RUN%\retry2.progress.json" scp -q -o BatchMode=yes -o ConnectTimeout=20 "%RUN%\retry2.progress.json" vps-bridge:/opt/ecom-intel/shards/runs/20260713-blinkit-competitor-top8-3pcity/retry2.progress.json
exit /b %RC%
