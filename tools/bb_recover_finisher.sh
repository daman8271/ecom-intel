#!/usr/bin/env bash
# Detached finisher for the Mac-down BigBasket VPS+KVM1 recovery run (2026-07-08).
# The scrape workers already run in their own tmux sessions (they survive a session
# close); the ORCHESTRATOR that waits->collects->merges->builds->delivers was tied to
# the Claude session. This runs that tail inside its own tmux session so it survives.
# Single-flight via flock. MAC shard is physically on KVM1 (BB_TEAM_MAC_HOST=kvm1).
set -uo pipefail
cd /opt/ecom-intel || exit 1
export BB_TEAM_MAC_HOST=kvm1
export BB_TEAM_MAC_BASE=/opt/ecom-intel/platforms/bigbasket
RUNID=bb-recover-vpskvm-20260708
RUNDIR=shards/bigbasket/$RUNID
LOG=logs/bb-recover-finisher.log
SCRIPT=./platforms/bigbasket/team_run_pincode.sh
say(){ echo "[$(TZ=Asia/Kolkata date '+%F %T')] finisher: $*" >>"$LOG"; }

exec 9>logs/.bb-finisher.lock
flock -n 9 || { say "another finisher holds the lock; exiting"; exit 0; }

say "start; waiting for vps/macpro(kvm1)/kvm1 workers to finish"
for i in $(seq 1 240); do          # up to 2h
  "$SCRIPT" collect "$RUNID" >>"$LOG" 2>&1 || true
  if [ -f "$RUNDIR/vps.done" ] && [ -f "$RUNDIR/macpro.done" ] && [ -f "$RUNDIR/kvm1.done" ]; then
    say "all 3 workers done after ~$((i*30))s"
    break
  fi
  sleep 30
done

say "collect+merge"
if "$SCRIPT" merge "$RUNID" >>"$LOG" 2>&1; then say "merge OK"; else say "merge FAILED"; fi
say "build + deliver"
if "$SCRIPT" build "$RUNID" >>"$LOG" 2>&1; then say "build OK"; else say "build FAILED"; fi

python3 -c 'import json;d=json.load(open("platforms/bigbasket/result_pincode.json"));per=d.get("perPin") or [];print("result_pincode.json pins:",len(per))' >>"$LOG" 2>&1 || true
say "done"
