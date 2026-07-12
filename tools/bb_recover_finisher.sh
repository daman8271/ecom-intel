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

# Manifest-driven so a 4-worker run (incl. the Windows laptop, 2026-07-13)
# waits on exactly the workers that actually participated.
workers_done() {
  python3 - "$RUNDIR" <<'PY'
import json, os, sys
rd = sys.argv[1]
try:
    names = [w["name"] for w in json.load(open(os.path.join(rd, "manifest.json")))["workers"]]
except Exception:
    names = ["vps", "macpro", "kvm1"]
sys.exit(0 if all(os.path.exists(os.path.join(rd, f"{n}.done")) for n in names) else 1)
PY
}

say "start; waiting for the manifest's workers to finish"
for i in $(seq 1 240); do          # up to 2h
  "$SCRIPT" collect "$RUNID" >>"$LOG" 2>&1 || true
  if workers_done; then
    say "all manifest workers done after ~$((i*30))s"
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
