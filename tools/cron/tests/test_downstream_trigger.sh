#!/usr/bin/env bash
# test_downstream_trigger.sh — proves the NEW event-driven downstream trigger in
# deadline_sweep.sh fires the competitor runner exactly when it should. The real
# trigger has never run in production (added 2026-07-01 goal #35; today's sweep
# never launched), so this validates the guard logic against a stubbed runner in a
# throwaway sandbox — no scraping, no data-bank writes.
#
# Mirrors the guard predicate from tools/cron/deadline_sweep.sh (competitor block
# + price-scraper/reconcile blocks): fire iff
#   SWEEP_DOWNSTREAM==1 && SLOT==12:00 && no PLATFORMS_OVERRIDE && no RUNNER_OVERRIDE
#   && RUN_ALL_RC==0 && runner is executable
set -uo pipefail
SBX="$(mktemp -d "${TMPDIR:-/tmp}/downstream_test.XXXXXX")"
trap 'rm -rf "$SBX"' EXIT
mkdir -p "$SBX/tools/competitor" "$SBX/bin" "$SBX/logs"
FIRED="$SBX/fired.marker"
# stub runner: records that it was invoked
cat > "$SBX/tools/competitor/run_daily.sh" <<EOF
#!/usr/bin/env bash
echo "STUB competitor run_daily fired" >> "$FIRED"
EOF
cat > "$SBX/bin/advance_today_section.sh" <<EOF
#!/usr/bin/env bash
echo "STUB advance \$1" >> "$FIRED"
EOF
chmod +x "$SBX/tools/competitor/run_daily.sh" "$SBX/bin/advance_today_section.sh"

# the exact guard + invocation from deadline_sweep.sh, run in the sandbox
fire_downstream(){ ( cd "$SBX"
  SLOT="$1"; RUN_ALL_RC="$2"
  if [ "${SWEEP_DOWNSTREAM:-1}" = "1" ] && [ "$SLOT" = "12:00" ] \
     && [ -z "${PLATFORMS_OVERRIDE:-}" ] && [ -z "${RUNNER_OVERRIDE:-}" ] \
     && [ "$RUN_ALL_RC" = "0" ] && [ -x ./tools/competitor/run_daily.sh ]; then
    ./bin/advance_today_section.sh price-scraper   # price-scraper FIRST (goal #52)
    ./tools/competitor/run_daily.sh                # then competitor
  fi ) ; }

pass=0; fail=0
check(){ # $1 label ; $2 expect(fire|no) ; $3 slot ; $4 rc ; $5.. env KEY=VAL
  local label="$1" expect="$2" slot="$3" rc="$4"; shift 4
  : > "$FIRED"
  # run in a subshell so env assignments ($@) don't leak; fire_downstream's own
  # inner subshell inherits them + still sees $SBX/$FIRED from this parent shell.
  ( for kv in "$@"; do export "$kv"; done; fire_downstream "$slot" "$rc" ) >/dev/null 2>&1
  local got=no; [ -s "$FIRED" ] && got=fire
  if [ "$got" = "$expect" ]; then echo "PASS: $label (expected $expect)"; pass=$((pass+1))
  else echo "FAIL: $label (expected $expect, got $got)"; fail=$((fail+1)); fi
}

check "normal noon sweep, rc=0 -> fires competitor"        fire 12:00 0
check "sweep failed (rc=1) -> does NOT fire"                no   12:00 1
check "wrong slot (15:00) -> does NOT fire"                 no   15:00 0
check "test-mode RUNNER_OVERRIDE set -> does NOT fire"      no   12:00 0 RUNNER_OVERRIDE=/bin/true
check "test-mode PLATFORMS_OVERRIDE set -> does NOT fire"   no   12:00 0 PLATFORMS_OVERRIDE=zepto
check "kill switch SWEEP_DOWNSTREAM=0 -> does NOT fire"     no   12:00 0 SWEEP_DOWNSTREAM=0

# prove ORDER: price-scraper advance is recorded BEFORE competitor
: > "$FIRED"; fire_downstream 12:00 0 >/dev/null 2>&1
order_ok=no
if [ "$(sed -n '1p' "$FIRED")" = "STUB advance price-scraper" ] \
   && grep -q "STUB competitor run_daily fired" "$FIRED"; then order_ok=yes; fi
if [ "$order_ok" = yes ]; then echo "PASS: price-scraper advances BEFORE competitor"; pass=$((pass+1))
else echo "FAIL: ordering (price-scraper should precede competitor)"; fail=$((fail+1)); fi

echo "-----"; echo "downstream trigger tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
