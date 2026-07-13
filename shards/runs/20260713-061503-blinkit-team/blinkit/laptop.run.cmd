@echo off
cd /d "C:\scrape-worker\ecom-intel\platforms\blinkit"
set "BLINKIT_AUTH_STATE_FILE=C:\scrape-worker\secrets\blinkit-auth-state.json"
set "BLINKIT_REQUIRE_AUTH=1"
set "BLINKIT_OOS_PROBE=1"
set "BLINKIT_PDP_OOS_PROBE=1"
set "BLINKIT_PDP_PRICE_PROBE=1"
set "CONCURRENCY=2"
set "BLINKIT_CHROMIUM_EXECUTABLE=C:\Users\prabh\AppData\Local\ms-playwright\chromium-1228\chrome-win64\chrome.exe"
set "PINCODES_FILE=C:\scrape-worker\team-runs\20260713-061503-blinkit-team\pincodes.json"
set "OUT_FILE=C:\scrape-worker\team-runs\20260713-061503-blinkit-team\result.json"
set "BLINKIT_PROGRESS_FILE=C:\scrape-worker\team-runs\20260713-061503-blinkit-team\run.progress.json"
node scrape.js 1>"C:\scrape-worker\team-runs\20260713-061503-blinkit-team\run.stdout" 2>"C:\scrape-worker\team-runs\20260713-061503-blinkit-team\run.log"
set "RC=%ERRORLEVEL%"
>"C:\scrape-worker\team-runs\20260713-061503-blinkit-team\run.rc" echo %RC%
>"C:\scrape-worker\team-runs\20260713-061503-blinkit-team\run.done" echo %DATE% %TIME%
scp -q -o BatchMode=yes -o ConnectTimeout=20 "C:\scrape-worker\team-runs\20260713-061503-blinkit-team\run.rc" "C:\scrape-worker\team-runs\20260713-061503-blinkit-team\run.done" vps-bridge:/opt/ecom-intel/shards/runs/20260713-061503-blinkit-team/blinkit/shard-1-of-2/
if exist "C:\scrape-worker\team-runs\20260713-061503-blinkit-team\result.json" scp -q -o BatchMode=yes -o ConnectTimeout=20 "C:\scrape-worker\team-runs\20260713-061503-blinkit-team\result.json" vps-bridge:/opt/ecom-intel/shards/runs/20260713-061503-blinkit-team/blinkit/shard-1-of-2/result.json
scp -q -o BatchMode=yes -o ConnectTimeout=20 "C:\scrape-worker\team-runs\20260713-061503-blinkit-team\run.log" vps-bridge:/opt/ecom-intel/shards/runs/20260713-061503-blinkit-team/blinkit/shard-1-of-2/laptop.run.log
ssh -o BatchMode=yes -o ConnectTimeout=20 vps-bridge "cd /opt/ecom-intel && nohup tools/laptop/blinkit_team_merge.sh '20260713-061503-blinkit-team' >> logs/blinkit_team.log 2>&1 </dev/null &"
exit /b %RC%
