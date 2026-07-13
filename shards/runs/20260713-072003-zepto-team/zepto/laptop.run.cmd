@echo off
cd /d "C:\scrape-worker\ecom-intel\platforms\zepto"
set "CONCURRENCY=3"
set "ZEPTO_SEED_VARIANTS=1"
set "PINCODES_FILE=C:\scrape-worker\team-runs\20260713-072003-zepto-team\pincodes.json"
set "OUT_FILE=C:\scrape-worker\team-runs\20260713-072003-zepto-team\result.json"
node scrape.js 1>"C:\scrape-worker\team-runs\20260713-072003-zepto-team\run.stdout" 2>"C:\scrape-worker\team-runs\20260713-072003-zepto-team\run.log"
set "RC=%ERRORLEVEL%"
>"C:\scrape-worker\team-runs\20260713-072003-zepto-team\run.rc" echo %RC%
>"C:\scrape-worker\team-runs\20260713-072003-zepto-team\run.done" echo %DATE% %TIME%
scp -q -o BatchMode=yes -o ConnectTimeout=20 "C:\scrape-worker\team-runs\20260713-072003-zepto-team\run.rc" "C:\scrape-worker\team-runs\20260713-072003-zepto-team\run.done" vps-bridge:/opt/ecom-intel/shards/runs/20260713-072003-zepto-team/zepto/shard-1-of-2/
if exist "C:\scrape-worker\team-runs\20260713-072003-zepto-team\result.json" scp -q -o BatchMode=yes -o ConnectTimeout=20 "C:\scrape-worker\team-runs\20260713-072003-zepto-team\result.json" vps-bridge:/opt/ecom-intel/shards/runs/20260713-072003-zepto-team/zepto/shard-1-of-2/result.json
scp -q -o BatchMode=yes -o ConnectTimeout=20 "C:\scrape-worker\team-runs\20260713-072003-zepto-team\run.log" vps-bridge:/opt/ecom-intel/shards/runs/20260713-072003-zepto-team/zepto/shard-1-of-2/laptop.run.log
ssh -o BatchMode=yes -o ConnectTimeout=20 vps-bridge "cd /opt/ecom-intel && nohup tools/laptop/zepto_team_merge.sh '20260713-072003-zepto-team' >> logs/zepto_team.log 2>&1 </dev/null &"
exit /b %RC%
