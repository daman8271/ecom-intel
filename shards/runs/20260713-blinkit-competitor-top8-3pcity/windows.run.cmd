@echo off
setlocal
set "RUN=C:\scrape-worker\team-runs\20260713-blinkit-competitor-top8-3pcity"
set "PROJECT=C:\scrape-worker\ecom-intel"
cd /d "%PROJECT%\platforms\blinkit"
set "COMPETITOR_MODE=1"
set "COMPETITOR_DATE=2026-07-13-TOP8-3PCITY-WIN"
set "COMPETITOR_BRANDS=Jivo,Sano,Fortune,Saffola,Borges,Tata,Del Monte,Figaro,Sundrop,Gulab"
set "BLINKIT_AUTH_STATE_FILE=C:\scrape-worker\secrets\blinkit-auth-state.json"
set "BLINKIT_REQUIRE_AUTH=1"
set "BLINKIT_OOS_PROBE=0"
set "BLINKIT_PDP_OOS_PROBE=0"
set "BLINKIT_PDP_PRICE_PROBE=0"
set "CONCURRENCY=2"
set "BLINKIT_CHROMIUM_EXECUTABLE=C:\Users\prabh\AppData\Local\ms-playwright\chromium-1228\chrome-win64\chrome.exe"
set "PINCODES_FILE=%RUN%\pincodes.json"
set "BLINKIT_PROGRESS_FILE=%RUN%\progress.json"
del /q "%RUN%\progress.json" 2>nul
del /q "%PROJECT%\tools\competitor\data\blinkit_competitor_2026-07-13-TOP8-3PCITY-WIN.json" 2>nul
node scrape.js 1>"%RUN%\stdout.log" 2>"%RUN%\run.log"
set "RC=%ERRORLEVEL%"
if exist "%PROJECT%\tools\competitor\data\blinkit_competitor_2026-07-13-TOP8-3PCITY-WIN.json" copy /y "%PROJECT%\tools\competitor\data\blinkit_competitor_2026-07-13-TOP8-3PCITY-WIN.json" "%RUN%\capture.json" >nul
>"%RUN%\run.rc" echo %RC%
>"%RUN%\run.done" echo %DATE% %TIME%
scp -q -o BatchMode=yes -o ConnectTimeout=20 "%RUN%\run.rc" "%RUN%\run.done" "%RUN%\run.log" "%RUN%\stdout.log" vps-bridge:/opt/ecom-intel/shards/runs/20260713-blinkit-competitor-top8-3pcity/
if exist "%RUN%\capture.json" scp -q -o BatchMode=yes -o ConnectTimeout=20 "%RUN%\capture.json" vps-bridge:/opt/ecom-intel/shards/runs/20260713-blinkit-competitor-top8-3pcity/windows.capture.json
exit /b %RC%
