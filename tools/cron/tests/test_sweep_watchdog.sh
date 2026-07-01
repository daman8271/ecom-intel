#!/usr/bin/env bash
# test_sweep_watchdog.sh — behavioural test for the noon-sweep catch-up watchdog.
# Runs the real script in DRYRUN (no sweep launched, no Telegram) with a faked
# "now", asserts the decision in each scenario, and never touches production state
# beyond a throwaway launched-marker it cleans up.
set -uo pipefail
cd "$(cd "$(dirname "$0")/../../.." && pwd)"   # -> repo root
WD=tools/cron/sweep_watchdog.sh
LOG=logs/sweep_watchdog.log
TODAY="$(date +%F)"
MARK="output/.batch/launched-${TODAY}-1200"
pass=0; fail=0

epoch(){ date -d "$TODAY $1" +%s; }   # today at HH:MM -> epoch
run(){ # $1=now HH:MM ; extra env in $2 -> returns last-line-of-log via $VERDICT
  local nowhm="$1"; local extra="${2:-}"
  : > "$LOG"
  env $extra WATCHDOG_DRYRUN=1 WATCHDOG_NOW_OVERRIDE="$(epoch "$nowhm")" bash "$WD" 12:00 >/dev/null 2>&1
  VERDICT="$(tail -n 3 "$LOG" | tr '\n' '|')"
}
check(){ # $1=label $2=needle
  if printf '%s' "$VERDICT" | grep -q "$2"; then echo "PASS: $1"; pass=$((pass+1));
  else echo "FAIL: $1"; echo "   log tail: $VERDICT"; fail=$((fail+1)); fi
}

rm -f "$MARK"

# 1) before 00:35 grace -> must NOT launch (primary owns it)
run 00:20; check "00:20 before-grace -> no launch" "before 00:35 grace"
[ -e "$MARK" ] && { echo "FAIL: 00:20 wrote a marker"; fail=$((fail+1)); rm -f "$MARK"; }

# 2) 01:00, not armed, plenty of time -> catch-up launch
rm -f "$MARK"
run 01:00; check "01:00 unarmed -> catch-up launch" "would LAUNCH"
rm -f "$MARK"

# 3) marker present -> already armed, no launch
: > "$MARK"
run 01:00; check "marker present -> already armed" "already armed"
rm -f "$MARK"

# 4) 10:00, not armed, too late -> best-effort launch still happens (alarm path)
rm -f "$MARK"
run 10:00; check "10:00 unarmed -> best-effort launch (too-late path)" "would LAUNCH"
rm -f "$MARK"

# 5) sent- dir present -> armed (simulate delivered), no launch
sentdir="output/.batch/sent-${TODAY}-1200"; had_sent=0; [ -d "$sentdir" ] && had_sent=1
mkdir -p "$sentdir"
run 01:00; check "delivered (sent- dir) -> already armed" "already armed"
[ "$had_sent" = 0 ] && rmdir "$sentdir" 2>/dev/null || true

rm -f "$MARK"
echo "-----"
echo "watchdog tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
