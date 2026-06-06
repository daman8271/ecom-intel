#!/usr/bin/env bash
# VERIFY Phase 3 — wiring safety for the price-match integration.
# SANDBOXED: never touches real workbooks, never sends real Telegram (dead creds,
# same pattern as tools/cron/tests/run_sim.sh). Exercises the REAL shipped code:
#   - run.sh hook lines (extracted verbatim) with tool absent / tool crashing
#   - run_all.sh price-match block (extracted verbatim between its markers) in
#     DEFER (spool), PLAIN (immediate-send, dead creds), and builder-crash modes
#   - send_batch.py: price-match present in CANONICAL and attempted LAST
#   - run_all.sh SIM gate: block is skipped when SIM_MODE=1
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
PASS=0; FAIL=0
ok()   { echo "PASS  $1"; PASS=$((PASS+1)); }
bad()  { echo "FAIL  $1  -- ${2:-}"; FAIL=$((FAIL+1)); }

SB="$ROOT/tools/cron/send_batch.py"
BASE="$(mktemp -d /tmp/pmwiring-XXXXXX)"
trap 'rm -rf "$BASE"' EXIT

# a tiny real workbook to play the role of the platform report
SRC_X="$(ls -t "$ROOT"/platforms/bigbasket/Jivo-*.xlsx | head -1)"

# ============================================================ 1. run.sh hook
# Extract the EXACT hook lines from run.sh (the two lines after the Price Match
# comment block) and run them in a sandbox.
HOOK="$(sed -n '/Price Match sheet: live vs our reference/,/^$/p' "$ROOT/run.sh" | grep -E '^\[|^cp ')"
LINES=$(echo "$HOOK" | wc -l)
if [ "$LINES" -ge 2 ]; then ok "run.sh hook: extracted $LINES lines"; else bad "run.sh hook extraction" "$HOOK"; fi

mk_sandbox() { # $1 = name; creates $DIR layout with workbook; echoes dir
  local d="$BASE/$1"
  mkdir -p "$d/tools/pricematch" "$d/platforms/testplat" "$d/output" "$d/logs"
  cp "$SRC_X" "$d/platforms/testplat/Jivo-Test-Report.xlsx"
  echo "$d"
}

run_hook() { # $1=sandbox dir -> runs the verbatim hook lines with run.sh's vars bound
  local DIRV="$1"
  ( cd "$DIRV" && DIR="$DIRV" PDIR="$DIRV/platforms/testplat" P=testplat RUN_ID=verify \
    bash -c "set -uo pipefail
DIR=\"$DIRV\"; PDIR=\"$DIRV/platforms/testplat\"; P=testplat; RUN_ID=verify
$HOOK
exit 0" )
}

# --- 1a. tool ABSENT => byte-identical workbook, exit 0
D="$(mk_sandbox absent)"
H_PRE="$(sha256sum "$D/platforms/testplat/Jivo-Test-Report.xlsx" | cut -d' ' -f1)"
if run_hook "$D" >/dev/null 2>&1; then ok "hook(tool absent): exit 0"; else bad "hook(tool absent): exit 0" "rc=$?"; fi
H_POST="$(sha256sum "$D/platforms/testplat/Jivo-Test-Report.xlsx" | cut -d' ' -f1)"
[ "$H_PRE" = "$H_POST" ] && ok "hook(tool absent): workbook byte-identical" || bad "hook(tool absent): workbook byte-identical"
# the cp refresh must still mirror to output/ (same as predict block does)
cmp -s "$D/platforms/testplat/Jivo-Test-Report.xlsx" "$D/output/Jivo-Test-Report.xlsx" \
  && ok "hook(tool absent): output/ mirror identical" || bad "hook(tool absent): output/ mirror" "missing/different"

# --- 1b. tool PRESENT but CRASHING => run continues, workbook intact
D="$(mk_sandbox crash)"
printf 'import sys\nsys.exit(7)\n' > "$D/tools/pricematch/add_pricematch_sheet.py"
H_PRE="$(sha256sum "$D/platforms/testplat/Jivo-Test-Report.xlsx" | cut -d' ' -f1)"
if run_hook "$D" >/dev/null 2>&1; then ok "hook(tool crashes rc=7): run continues (exit 0)"; else bad "hook(tool crashes): run continues" "rc=$?"; fi
H_POST="$(sha256sum "$D/platforms/testplat/Jivo-Test-Report.xlsx" | cut -d' ' -f1)"
[ "$H_PRE" = "$H_POST" ] && ok "hook(tool crashes): workbook byte-identical" || bad "hook(tool crashes): workbook byte-identical"

# --- 1c. REAL appender, REAL engine, broken sku_map (engine throws at runtime)
D="$(mk_sandbox enginecrash)"
cp "$ROOT/tools/pricematch/add_pricematch_sheet.py" "$ROOT/tools/pricematch/pricematch_core.py" "$D/tools/pricematch/"
echo '{broken json' > "$D/tools/pricematch/sku_map.json"
echo '{broken json' > "$D/tools/pricematch/master_v2.json"
H_PRE="$(sha256sum "$D/platforms/testplat/Jivo-Test-Report.xlsx" | cut -d' ' -f1)"
if run_hook "$D" >/dev/null 2>&1; then ok "hook(engine runtime error): run continues"; else bad "hook(engine runtime error): run continues" "rc=$?"; fi
H_POST="$(sha256sum "$D/platforms/testplat/Jivo-Test-Report.xlsx" | cut -d' ' -f1)"
[ "$H_PRE" = "$H_POST" ] && ok "hook(engine runtime error): workbook byte-identical (no stub sheet!)" \
  || bad "hook(engine runtime error): workbook byte-identical" "appender wrote despite engine failure"

# ===================================================== 2. run_all.sh pm block
# Extract the price-match block verbatim: from its banner comment to the line
# before the batch-barrier banner.
BLK="$BASE/pm_block.sh"
awk '/---- PRICE-MATCH master workbook/,/---- Deferred-delivery batch barrier/' "$ROOT/run_all.sh" | head -n -2 > "$BLK.body"
{ echo '#!/usr/bin/env bash'; echo 'set -uo pipefail'; echo 'cd "$DIR"'; cat "$BLK.body"; echo 'echo BLOCK_DONE'; } > "$BLK"
grep -q 'build_pricematch.py' "$BLK" && ok "run_all block: extracted (builder ref present)" || bad "run_all block extraction"
bash -n "$BLK" && ok "run_all block: bash -n clean" || bad "run_all block: bash -n"

mk_blocksandbox() { # stub builder behavior via $1: ok|silent|crash — unique dir per call
  # NB: called via $(...) i.e. a subshell, so no parent-state counters here
  local d
  d="$(mktemp -d "$BASE/blk-$1-XXXXXX")"
  mkdir -p "$d/tools/pricematch" "$d/tools/cron" "$d/output" "$d/logs"
  case "$1" in
    ok)
      cp "$SRC_X" "$d/tools/pricematch/PM-fixture.xlsx"
      cat > "$d/tools/pricematch/build_pricematch.py" <<PYEOF
import json, os, sys
here = os.path.dirname(os.path.abspath(__file__))
x = os.path.join(here, "PM-fixture.xlsx")
side = {"date": "2026-06-06", "regime": "SVD",
        "summary_md": "*Jivo Price Match — master*\n2026-06-06 · SVD day\n85 below-ref · exposure ₹5,804\ntop: EV5L/EV2L/EL2L",
        "caption": "Jivo Price Match · 2026-06-06 · SVD day"}
with open(x + ".summary.json", "w") as f: json.dump(side, f)
print("builder noise line")   # builder may chat; run_all takes tail -1
print(x)
PYEOF
      ;;
    silent) printf 'import sys\nsys.exit(0)\n' > "$d/tools/pricematch/build_pricematch.py" ;;
    crash)  printf 'import sys\nsys.stderr.write("boom\\n")\nsys.exit(3)\n' > "$d/tools/pricematch/build_pricematch.py" ;;
  esac
  echo "$d"
}

# --- 2a. DEFER mode: spool entry written, schema complete
D="$(mk_blocksandbox ok)"
OUT="$(cd "$D" && DIR="$D" SIM_MODE=0 CHAIN_SKIPPED=0 DEFER_DELIVERY=1 SWEEP_ID=vtest \
      TELEGRAM_BOT_TOKEN= TELEGRAM_CHAT_ID= bash "$BLK" 2>&1)"; RC=$?
SPOOL="$D/output/.batch/vtest/price-match.json"
[ $RC -eq 0 ] && ok "defer: block exit 0" || bad "defer: block exit 0" "rc=$RC out=$OUT"
[ -f "$SPOOL" ] && ok "defer: spool price-match.json written" || bad "defer: spool written" "$OUT"
if [ -f "$SPOOL" ]; then
  python3 - "$SPOOL" <<'PYEOF' && ok "defer: spool schema v1 complete (platform/verdict/summary/xlsx/caption/ts)" || bad "defer: spool schema"
import json, os, sys
d = json.load(open(sys.argv[1]))
assert d["platform"] == "price-match", d
assert d["verdict"] == "OK"
assert d["summary"] and "Price Match" in d["summary"]
assert os.path.isfile(d["xlsx"]), d["xlsx"]
assert d["caption"] and isinstance(d["ts"], int)
PYEOF
  echo "$OUT" | grep -q "spooled for batch" && ok "defer: spool logged" || bad "defer: spool log line" "$OUT"
  echo "$OUT" | grep -qi "sendMessage" && bad "defer: no immediate send" "curl attempted in defer mode" || ok "defer: no immediate TG send attempted"
fi
# workbook copied to output/
[ -f "$D/output/PM-fixture.xlsx" ] && ok "defer: xlsx mirrored to output/" || bad "defer: xlsx mirror"

# --- 2b. PLAIN mode (no defer), dead/absent creds: graceful, no crash
D="$(mk_blocksandbox ok)"
OUT="$(cd "$D" && DIR="$D" SIM_MODE=0 CHAIN_SKIPPED=0 TELEGRAM_BOT_TOKEN= TELEGRAM_CHAT_ID= bash "$BLK" 2>&1)"; RC=$?
[ $RC -eq 0 ] && ok "plain: block exit 0" || bad "plain: block exit 0" "rc=$RC"
echo "$OUT" | grep -q "no Telegram creds" && ok "plain(no creds): fail-safe message, workbook kept" || bad "plain(no creds): fail-safe" "$OUT"
[ ! -e "$D/output/.batch" ] && ok "plain: no spool dir created" || bad "plain: no spool dir" "$(find "$D/output/.batch" 2>/dev/null | head -3; echo D=$D)"

# --- 2c. builder produces nothing => logged, block still exits 0
D="$(mk_blocksandbox silent)"
OUT="$(cd "$D" && DIR="$D" SIM_MODE=0 CHAIN_SKIPPED=0 DEFER_DELIVERY=1 SWEEP_ID=vtest bash "$BLK" 2>&1)"; RC=$?
[ $RC -eq 0 ] && ok "silent builder: block exit 0" || bad "silent builder: exit 0" "rc=$RC"
echo "$OUT" | grep -q "produced no xlsx" && ok "silent builder: honest log line" || bad "silent builder: log" "$OUT"
[ ! -f "$D/output/.batch/vtest/price-match.json" ] && ok "silent builder: no bogus spool entry" || bad "silent builder: bogus spool"

# --- 2d. builder crashes => same containment
D="$(mk_blocksandbox crash)"
OUT="$(cd "$D" && DIR="$D" SIM_MODE=0 CHAIN_SKIPPED=0 DEFER_DELIVERY=1 SWEEP_ID=vtest bash "$BLK" 2>&1)"; RC=$?
[ $RC -eq 0 ] && ok "crashing builder: block exit 0 (sweep survives)" || bad "crashing builder: exit 0" "rc=$RC"
[ ! -f "$D/output/.batch/vtest/price-match.json" ] && ok "crashing builder: no spool entry" || bad "crashing builder: spool leaked"

# --- 2e. SIM gate + CHAIN_SKIPPED gate (real run_all.sh source, static + dynamic)
grep -q 'SIM_MODE" != "1" ] && \[ "$CHAIN_SKIPPED" != "1"' "$ROOT/run_all.sh" \
  && ok "run_all: SIM + CHAIN_SKIPPED gates present on pm block" \
  || bad "run_all: gates" "guard line not found"
D="$(mk_blocksandbox ok)"
OUT="$(cd "$D" && DIR="$D" SIM_MODE=1 CHAIN_SKIPPED=0 DEFER_DELIVERY=1 SWEEP_ID=vtest bash "$BLK" 2>&1)"; RC=$?
if [ $RC -eq 0 ] && ! echo "$OUT" | grep -q "building master Price Match"; then
  ok "SIM_MODE=1: pm block fully skipped"
else
  bad "SIM_MODE=1: pm block skipped" "rc=$RC out=$OUT"
fi
[ ! -e "$D/output/.batch" ] && ok "SIM_MODE=1: no spool side-effects" || bad "SIM_MODE=1: spool leaked" "$(find "$D/output/.batch" 2>/dev/null | head -3; echo D=$D)"
OUT="$(cd "$D" && DIR="$D" SIM_MODE=0 CHAIN_SKIPPED=1 bash "$BLK" 2>&1)"
echo "$OUT" | grep -q "building master Price Match" && bad "CHAIN_SKIPPED=1: pm block skipped" "$OUT" || ok "CHAIN_SKIPPED=1: pm block skipped (stale-read guard)"

# ====================================================== 3. send_batch ordering
# Spool 3 entries (2 platforms + price-match), dead creds, deadline=now.
# price-match must be attempted LAST. Reuses run_sim.sh's env-precedence safety.
D="$BASE/sb"
mkdir -p "$D"
BATCH="$ROOT/output/.batch/verify-order-test"
rm -rf "$BATCH"; mkdir -p "$BATCH"
cp "$SRC_X" "$D/r1.xlsx"
for p in flipkart-minutes blinkit price-match; do
  python3 - "$BATCH/$p.json" "$p" "$D/r1.xlsx" <<'PYEOF'
import json, sys, time
json.dump({"platform": sys.argv[2], "verdict": "OK", "summary": "verify order test " + sys.argv[2],
           "xlsx": sys.argv[3], "caption": "t", "ts": int(time.time())}, open(sys.argv[1], "w"))
PYEOF
done
SECRETS_SIM="$D/secrets.env"; printf 'TELEGRAM_BOT_TOKEN="000000000:DEAD"\nTELEGRAM_CHAT_ID="-1"\n' > "$SECRETS_SIM"
SBLOG="$(cd "$ROOT" && SECRETS_FILE="$SECRETS_SIM" TELEGRAM_BOT_TOKEN="000000000:DEAD" TELEGRAM_CHAT_ID="-1" TG_DRY_RUN="${TG_DRY_RUN_FOR_TEST:-1}" \
        python3 tools/cron/send_batch.py verify-order-test "$(date +%s)" 2>&1)"; RC=$?
[ $RC -eq 0 ] && ok "send_batch: exit 0 on verify batch" || bad "send_batch: exit 0" "rc=$RC"
ORDER="$(echo "$SBLOG" | grep -oE '(flipkart-minutes|blinkit|price-match)' | awk '!seen[$0]++' | tr '\n' ' ')"
case "$ORDER" in
  *"flipkart-minutes blinkit price-match"*) ok "send_batch: price-match attempted LAST (order: $ORDER)" ;;
  *) bad "send_batch: order" "got: $ORDER | log: $(echo "$SBLOG" | head -5)" ;;
esac
echo "$SBLOG" | grep -q "price-match" && ok "send_batch: price-match entry consumed" || bad "send_batch: pm consumed" "$SBLOG"
rm -rf "$BATCH"

# barrier + lock invariants untouched (vs pre-pm commit 5e4cf496)
cd "$ROOT"
if git diff 5e4cf496..HEAD -- run_all.sh | grep -E '^-' | grep -vE '^---' | grep -q .; then
  bad "run_all.sh: pure-additive diff vs 5e4cf496" "deletions found"
else
  ok "run_all.sh: pure-additive diff vs 5e4cf496 (lock/barrier untouched)"
fi
if git diff 5e4cf496..HEAD -- run.sh | grep -E '^-' | grep -vE '^---' | grep -q .; then
  bad "run.sh: pure-additive diff" "deletions found"
else
  ok "run.sh: pure-additive diff vs 5e4cf496"
fi

echo
echo "== check_wiring: $((PASS+FAIL)) checks, $FAIL FAIL =="
exit $([ $FAIL -eq 0 ] && echo 0 || echo 1)
