@echo off
setlocal
set "RUN=C:\scrape-worker\team-runs\20260714-133503-blinkit-top8"
set "PROJECT=C:\scrape-worker\ecom-intel"
set "CAPTURE=%PROJECT%\tools\competitor\data\blinkit_competitor_2026-07-14-TOP8-3PCITY-WIN.json"
cd /d "%PROJECT%\platforms\blinkit"
set "COMPETITOR_MODE=1"
set "COMPETITOR_DATE=2026-07-14-TOP8-3PCITY-WIN"
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
del /q "%CAPTURE%" 2>nul
node scrape.js 1>"%RUN%\windows.stdout.log" 2>"%RUN%\windows.run.log"
set "RC=%ERRORLEVEL%"
>"%RUN%\windows.run.rc" echo %RC%
>"%RUN%\windows.run.done" echo %DATE% %TIME%
if exist "%CAPTURE%" copy /y "%CAPTURE%" "%RUN%\windows.capture.json" >nul
if exist "%RUN%\progress.json" copy /y "%RUN%\progress.json" "%RUN%\windows.progress.json" >nul
scp -q -o BatchMode=yes -o ConnectTimeout=20 "%RUN%\windows.run.rc" "%RUN%\windows.run.done" vps-bridge:/opt/ecom-intel/shards/runs/20260714-133503-blinkit-top8/
if exist "%RUN%\windows.run.log" scp -q -o BatchMode=yes -o ConnectTimeout=20 "%RUN%\windows.run.log" "%RUN%\windows.stdout.log" vps-bridge:/opt/ecom-intel/shards/runs/20260714-133503-blinkit-top8/
if exist "%RUN%\windows.capture.json" scp -q -o BatchMode=yes -o ConnectTimeout=20 "%RUN%\windows.capture.json" vps-bridge:/opt/ecom-intel/shards/runs/20260714-133503-blinkit-top8/windows.capture.json
if exist "%RUN%\windows.progress.json" scp -q -o BatchMode=yes -o ConnectTimeout=20 "%RUN%\windows.progress.json" vps-bridge:/opt/ecom-intel/shards/runs/20260714-133503-blinkit-top8/windows.progress.json
exit /b %RC%
