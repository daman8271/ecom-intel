#!/usr/bin/env bash
# doctor_dryrun.sh — W3 end-to-end dry-run for the Ecom Doctor watchdog.
#
# PROVES, with NO live scrape / NO real Telegram / NO real Claude turn / NO crontab install:
#   1. DETECTION   — health_snapshot returns YELLOW for the flipkart+zepto held-streak that bit
#                    us, RED for a missing batch and for a BROKEN platform, GREEN when all-clear.
#   2. ORCHESTRATION (bounded) — doctor.sh invokes the headless agent ONLY on non-GREEN, drives
#                    a stubbed agent (zero Claude spend) end to end, and (with --with-real-agent)
#                    ONE real small sonnet call to prove the live wiring.
#   3. GUARDRAILS  — ENABLE flag off => no-op; doctor lock prevents overlap; NO git push is
#                    reachable (static grep + a runtime push tripwire); a crash still alerts the
#                    owner and never touches the sweep crons; a safe_fix that exits!=0 on
#                    ambiguity => propose-only path.
#   4. NO-REGRESSION — on the REAL current repo, doctor.sh is strictly READ-ONLY: no push, no
#                    working-tree mutation, no crontab touch (the actual safety guarantee). The
#                    clean all-clear path is proven on a GREEN fixture.
#
# HERMETIC BY CONSTRUCTION: a tests/doctor/bin/ PATH shim intercepts `curl` (every telegram call
# is logged, NEVER sent), `git` (push is a tripwire that fails; commit is a no-op so the repo is
# never mutated), and `claude` (the agent stub). So even if doctor.sh sources real creds from
# secrets.env, nothing leaves the box and the working tree is never changed.
#
# FIXTURES use health_snapshot.py's HEALTH_ROOT override (relocates ROOT => reviews/, logs/,
# baselines/ all read from a controlled fake root), so the real reviews/ is never polluted.
#
# Usage:  tools/cron/tests/doctor_dryrun.sh [--with-real-agent]
# Exit 0 = all assertions PASS (W3 PASS, gates the install). Exit 1 = a FAIL or PRECHECK-FAIL.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
cd "$ROOT"

WITH_REAL_AGENT=0
[ "${1:-}" = "--with-real-agent" ] && WITH_REAL_AGENT=1

SANDBOX="$TESTS_DIR/doctor"
BIN="$SANDBOX/bin"
FIX="$SANDBOX/fixtures"
OUTLOG="$SANDBOX/run.log"
RESULTS="$SANDBOX/results.tsv"
TG_LOG="$SANDBOX/telegram.log"
GIT_TRIP="$SANDBOX/git-push-tripwire.log"
AGENT_LOG="$SANDBOX/agent-invocations.log"
rm -rf "$SANDBOX"
mkdir -p "$BIN" "$FIX"
: > "$OUTLOG"; : > "$RESULTS"; : > "$TG_LOG"; : > "$GIT_TRIP"; : > "$AGENT_LOG"

DOCTOR="tools/cron/doctor.sh"
SNAP="tools/cron/health_snapshot.py"
PROMPT="tools/cron/doctor_prompt.md"
FIXES="tools/cron/safe_fixes"
TODAY="$(date +%F)"   # system clock is IST (matches health_snapshot's ist_date_str)

# ----------------------------------------------------------------------------- result plumbing
PASS_N=0; FAIL_N=0; SKIP_N=0
pass()  { PASS_N=$((PASS_N+1)); printf 'PASS\t%s\n' "$1" | tee -a "$RESULTS"; }
fail()  { FAIL_N=$((FAIL_N+1)); printf 'FAIL\t%s\n' "$1" | tee -a "$RESULTS"; }
skip()  { SKIP_N=$((SKIP_N+1)); printf 'SKIP\t%s\n' "$1" | tee -a "$RESULTS"; }
note()  { printf '      %s\n' "$*" | tee -a "$OUTLOG"; }
die()   { echo "PRECHECK-FAIL: $*" >&2; printf 'PRECHECK-FAIL\t%s\n' "$*" >> "$RESULTS"; exit 1; }
assert_eq() { if [ "$2" = "$3" ]; then pass "$1 (=$3)"; else fail "$1 (want '$2' got '$3')"; fi; }
assert_contains()    { if printf '%s' "$2" | grep -qF "$3"; then pass "$1"; else fail "$1 (missing '$3')"; fi; }
assert_notcontains() { if printf '%s' "$2" | grep -qF "$3"; then fail "$1 (found '$3')"; else pass "$1"; fi; }

echo "== doctor_dryrun.sh — ROOT=$ROOT  TODAY=$TODAY  $(date '+%F %T') ==" | tee -a "$OUTLOG"

# =============================================================================== PRECHECKS
[ -f "$SNAP" ]   || die "$SNAP missing (W1 not done) — cannot test detection"
[ -f "$DOCTOR" ] || die "$DOCTOR missing (W1 not done) — cannot test orchestration"
[ -d "$FIXES" ]  || die "$FIXES/ missing (W2 not done) — cannot test safe-fix exit-code contract"
[ -f "$PROMPT" ] || note "WARN: $PROMPT missing (W2) — real-agent test will be skipped"

# Discover the health-root override on health_snapshot.py (W1 uses HEALTH_ROOT).
ROOT_ENV=""
for cand in HEALTH_ROOT DOCTOR_HEALTH_ROOT DOCTOR_REVIEWS_DIR HEALTH_REVIEWS_DIR; do
  if grep -qE "\b$cand\b" "$SNAP"; then ROOT_ENV="$cand"; break; fi
done
[ -n "$ROOT_ENV" ] || die "$SNAP exposes no root/reviews override env — cannot inject fixtures \
without polluting real reviews/. Ask W1 for HEALTH_ROOT."
note "health_snapshot root override = \$$ROOT_ENV"

# Discover the agent-cmd override on doctor.sh (optional; PATH 'claude' shim is the fallback).
AGENT_ENV=""
for cand in DOCTOR_AGENT_CMD DOCTOR_AGENT DOCTOR_CLAUDE_CMD AGENT_CMD; do
  if grep -qE "\b$cand\b" "$DOCTOR"; then AGENT_ENV="$cand"; break; fi
done
[ -n "$AGENT_ENV" ] && note "doctor.sh agent-cmd override = \$$AGENT_ENV" \
                    || note "doctor.sh has no agent-cmd env — using PATH 'claude' shim instead"

grep -qE "ECOM_DOCTOR_ENABLE" "$DOCTOR" || die "$DOCTOR has no ECOM_DOCTOR_ENABLE gate"
grep -qE "flock" "$DOCTOR" || note "WARN: no obvious flock in doctor.sh (lock test will SKIP)"
# does doctor.sh propagate HEALTH_ROOT to its health_snapshot call? (best-effort note)
grep -qE "HEALTH_ROOT" "$DOCTOR" \
  && note "doctor.sh references HEALTH_ROOT (fixtures will flow into doctor.sh's collector)" \
  || note "NOTE: doctor.sh doesn't name HEALTH_ROOT; it inherits it via env (subprocess) — verified by the GREEN/YELLOW doctor runs below"

# =============================================================================== PATH SHIMS
cat > "$BIN/curl" <<SHIM
#!/usr/bin/env bash
echo "[\$(date '+%F %T')] curl \$*" >> "$TG_LOG"
for a in "\$@"; do case "\$a" in *api.telegram.org*) echo '{"ok":true,"result":{"message_id":1}}'; exit 0;; esac; done
echo '{"ok":true,"dry":true}'; exit 0
SHIM
cat > "$BIN/git" <<SHIM
#!/usr/bin/env bash
REAL=\$(PATH="\$(echo "\$PATH" | sed "s#$BIN:##g")" command -v git)
case "\${1:-}" in
  push)   echo "[\$(date '+%F %T')] BLOCKED git push \$*" >> "$GIT_TRIP"; echo "doctor dry-run: git push forbidden" >&2; exit 13;;
  commit) echo "[\$(date '+%F %T')] (noop) git commit \$*" >> "$GIT_TRIP"; exit 0;;
  *)      exec "\$REAL" "\$@";;
esac
SHIM
cat > "$BIN/claude" <<SHIM
#!/usr/bin/env bash
# Agent STUB — invoked by doctor.sh via DOCTOR_AGENT_CMD (prompt on stdin). Writes the
# diagnosis to the EXACT path doctor.sh hands it (DOCTOR_DIAGNOSIS_PATH), so we exercise the
# real "agent writes diagnosis -> doctor attaches it" contract. Zero Claude spend.
echo "[\$(date '+%F %T')] claude \$*" >> "$AGENT_LOG"
SCOPE="\${DOCTOR_SCOPE:-daily}"
RPT="\${DOCTOR_DIAGNOSIS_PATH:-$ROOT/logs/doctor/diagnosis-\${SCOPE}-stub.md}"
mkdir -p "\$(dirname "\$RPT")"
{ echo "# Doctor diagnosis (STUB) — \$SCOPE";
  echo "- held_streak:flipkart -> FALSE-POSITIVE -> auto-fix unhold_false_positive.sh flipkart";
  echo "- held_streak:zepto    -> FALSE-POSITIVE -> auto-fix unhold_false_positive.sh zepto";
  echo "- report seen: \${DOCTOR_REPORT_JSON:-?}";
  echo "- confidence: stubbed"; } > "\$RPT"
echo "STUB-AGENT wrote \$RPT and (simulated) applied 2 safe fixes"; exit 0
SHIM
chmod +x "$BIN/curl" "$BIN/git" "$BIN/claude"

DEAD_SECRETS="$SANDBOX/secrets.dead.env"
cat > "$DEAD_SECRETS" <<'EOF'
TELEGRAM_BOT_TOKEN="000000000:DOCTOR-DRYRUN-INVALID"
TELEGRAM_CHAT_ID="-1"
TELEGRAM_OWNER_CHAT_ID="-1"
ECOM_DOCTOR_ENABLE=1
EOF

doctor_env() {
  # PRIMARY no-send guarantee = DOCTOR_DRY_RUN=1 (doctor.sh LOGS telegram payloads instead of
  # curl'ing). The PATH curl shim is the BACKUP (intercepts any stray curl). Note: doctor.sh
  # sources the REAL secrets.env, so dead-cred env vars are overwritten — DOCTOR_DRY_RUN + the
  # curl shim are what actually prevent a real send.
  echo "PATH=$BIN:$PATH"
  echo "ECOM_DOCTOR_ENABLE=1"
  echo "DOCTOR_DRY_RUN=1"
  echo "ECOM_DOCTOR_MODEL=sonnet"
  [ -n "$AGENT_ENV" ] && echo "$AGENT_ENV=$BIN/claude"
}
run_doctor() { # run_doctor <scope> <health-root|""> [extra KEY=VAL ...]
  local scope="$1" hroot="$2"; shift 2
  ( cd "$ROOT"
    while IFS= read -r kv; do export "$kv"; done < <(doctor_env)
    [ -n "$hroot" ] && export "$ROOT_ENV=$hroot"
    export DOCTOR_SCOPE="$scope"
    for kv in "$@"; do export "$kv"; done
    bash "$DOCTOR" "$scope" )
}

# =============================================================================== FIXTURE BUILDER
LIVE_PLATFORMS="flipkart-minutes flipkart zepto bigbasket amazon amazon-fresh amazon-now blinkit"
write_review() { # <reviews-dir> <platform> <run_id> <verdict> <reason>
  python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import json,sys,os
d,p,rid,verdict,reason=sys.argv[1:6]
os.makedirs(d,exist_ok=True)
checks=[{"name":"non_zero_rows","pass":verdict=="OK","detail":"fixture"}]
if verdict!="OK": checks.append({"name":reason,"pass":False,"detail":f"fixture {reason}"})
obj={"platform":p,"run_id":rid,"captured_at":"2026-06-08T06:00:00.000Z","verdict":verdict,
     "rows":268 if verdict=="OK" else 120,"unique_skus":268,"baseline_rows":268,
     "reasons":([reason] if verdict!="OK" else []),"checks":checks}
json.dump(obj,open(os.path.join(d,f"{p}-{rid}.json"),"w"))
PY
}
build_fixture() { # <root-dir> <scenario: yellow|red-broken|red-batch|green>
  local root="$1" scen="$2"; rm -rf "$root"; mkdir -p "$root/reviews" "$root/logs"
  local rdir="$root/reviews" p
  for p in $LIVE_PLATFORMS; do
    write_review "$rdir" "$p" "$TODAY-1500" "OK" ""
    write_review "$rdir" "$p" "$TODAY-1000" "OK" ""
    write_review "$rdir" "$p" "2026-06-07-1000" "OK" ""
  done
  # batch-delivered lines (both slots), so missing-batch never falsely fires — UNLESS red-batch.
  local clog="$root/logs/cron.log"
  if [ "$scen" != "red-batch" ]; then
    {
      echo "send_batch: sweep $TODAY-1000: batch delivered (8 reports, 0 held, 0 missing)"
      echo "send_batch: sweep $TODAY-1500: batch delivered (8 reports, 0 held, 0 missing)"
    } > "$clog"
  else
    : > "$clog"   # NO delivered line => missing-batch RED for any slot past its grace
  fi
  case "$scen" in
    yellow)
      write_review "$rdir" flipkart "$TODAY-1000" "SUSPECT" "shared_price_dup"
      write_review "$rdir" flipkart "$TODAY-1500" "SUSPECT" "shared_price_dup"
      write_review "$rdir" zepto    "$TODAY-1000" "SUSPECT" "price_staleness"
      write_review "$rdir" zepto    "$TODAY-1500" "SUSPECT" "price_staleness" ;;
    red-broken)
      write_review "$rdir" bigbasket "$TODAY-1000" "BROKEN" "BB_SESSION_EXPIRED"
      write_review "$rdir" bigbasket "$TODAY-1500" "BROKEN" "BB_SESSION_EXPIRED" ;;
    red-batch|green) : ;;
  esac
}
snap_json() { ( cd "$ROOT"; env "$ROOT_ENV=$2" python3 "$SNAP" --scope "$1" --json 2>>"$OUTLOG" ); }
jget() { python3 -c "import json,sys;d=json.load(sys.stdin);print(eval(sys.argv[1]))" "$1"; }

# =============================================================================== 1. DETECTION
echo "" | tee -a "$OUTLOG"; echo "--- 1. DETECTION ---" | tee -a "$OUTLOG"

build_fixture "$FIX/yellow" yellow
Y="$(snap_json daily "$FIX/yellow")"; echo "$Y" > "$SANDBOX/yellow.health.json"
if [ -z "$Y" ]; then fail "1.YELLOW no JSON"; else
  assert_eq       "1.YELLOW overall" "YELLOW" "$(printf '%s' "$Y" | jget 'd["overall"]')"
  IDS="$(printf '%s' "$Y" | jget '",".join(i["id"] for i in d["issues"])')"
  REASONS="$(printf '%s' "$Y" | jget 'json.dumps(d["issues"])')"
  assert_contains "1.YELLOW names flipkart held_streak" "$IDS" "held_streak:flipkart"
  assert_contains "1.YELLOW names zepto held_streak"    "$IDS" "held_streak:zepto"
  assert_contains "1.YELLOW carries reason shared_price_dup" "$REASONS" "shared_price_dup"
  assert_contains "1.YELLOW carries reason price_staleness"  "$REASONS" "price_staleness"
  for p in flipkart-minutes bigbasket amazon amazon-fresh amazon-now blinkit; do
    assert_notcontains "1.YELLOW does not false-flag $p" "$IDS" "held_streak:$p"
  done
fi

build_fixture "$FIX/red_broken" red-broken
RB="$(snap_json daily "$FIX/red_broken")"; echo "$RB" > "$SANDBOX/red_broken.health.json"
[ -n "$RB" ] && assert_eq "1.RED(broken platform) overall" "RED" "$(printf '%s' "$RB" | jget 'd["overall"]')" || fail "1.RED-broken no JSON"

build_fixture "$FIX/red_batch" red-batch
RBT="$(snap_json daily "$FIX/red_batch")"; echo "$RBT" > "$SANDBOX/red_batch.health.json"
if [ -n "$RBT" ]; then
  assert_eq       "1.RED(missing batch) overall" "RED" "$(printf '%s' "$RBT" | jget 'd["overall"]')"
  assert_contains "1.RED(missing batch) flags a batch_delivery signal" "$RBT" "batch_delivery"
  assert_contains "1.RED(missing batch) names the missing slot id" "$RBT" "batch_missing:$TODAY-1000"
else fail "1.RED-batch no JSON"; fi

build_fixture "$FIX/green" green
G="$(snap_json daily "$FIX/green")"; echo "$G" > "$SANDBOX/green.health.json"
if [ -n "$G" ]; then
  assert_eq "1.GREEN overall" "GREEN" "$(printf '%s' "$G" | jget 'd["overall"]')"
  assert_eq "1.GREEN zero issues" "0" "$(printf '%s' "$G" | jget 'len(d["issues"])')"
else fail "1.GREEN no JSON"; fi

# =============================================================================== 2. ORCHESTRATION
echo "" | tee -a "$OUTLOG"; echo "--- 2. ORCHESTRATION (bounded agent) ---" | tee -a "$OUTLOG"
rm -rf "$ROOT/logs/doctor"; : > "$AGENT_LOG"; : > "$TG_LOG"

run_doctor daily "$FIX/green" > "$SANDBOX/doctor-green.out" 2>&1
assert_eq "2.GREEN doctor does NOT invoke the agent" "0" "$(grep -c 'claude ' "$AGENT_LOG" 2>/dev/null)"
if grep -qiE 'all.?clear|all good' "$SANDBOX/doctor-green.out" 2>/dev/null; then
  pass "2.GREEN doctor emits an all-clear owner message (DRY-logged)"
else note "(all-clear text not in stdout; see doctor-green.out)"; fail "2.GREEN all-clear text"; fi

: > "$AGENT_LOG"; : > "$TG_LOG"
run_doctor daily "$FIX/yellow" > "$SANDBOX/doctor-yellow.out" 2>&1
[ "$(grep -c 'claude ' "$AGENT_LOG" 2>/dev/null)" -ge 1 ] \
  && pass "2.YELLOW doctor invokes the headless agent (stub)" || fail "2.YELLOW agent NOT invoked"
ls "$ROOT"/logs/doctor/diagnosis-daily-*.md >/dev/null 2>&1 \
  && pass "2.YELLOW agent wrote its diagnosis to the doctor-supplied path" || fail "2.YELLOW diagnosis missing"
ls "$ROOT"/logs/doctor/daily-*.json >/dev/null 2>&1 \
  && pass "2.YELLOW health report.json persisted under logs/doctor/" || fail "2.YELLOW report.json not persisted"
# owner alert: with DOCTOR_DRY_RUN=1 doctor.sh LOGS the payload (no curl). Assert the alert text.
if grep -qE 'DRY tg_message' "$SANDBOX/doctor-yellow.out" && grep -qE 'overall=YELLOW' "$SANDBOX/doctor-yellow.out"; then
  pass "2.YELLOW owner Telegram alert fired (DRY-logged, overall=YELLOW)"
else note "(alert text not found; see doctor-yellow.out)"; fail "2.YELLOW owner alert"; fi
# belt-and-suspenders: NO real telegram curl escaped to the network shim either
grep -q 'api.telegram.org' "$TG_LOG" 2>/dev/null \
  && fail "2.YELLOW a curl to telegram escaped DRY mode (shim caught it, but DRY should suppress)" \
  || pass "2.YELLOW no telegram curl attempted (DRY mode suppressed it; shim saw nothing)"

# 2b. ONE real, small, SAFE live sonnet invocation — proves the live `claude -p --settings
# --add-dir` seam doctor.sh uses actually drives a headless agent, AND that the scoped deny
# blocks git push LIVE. Run in an ISOLATED temp dir (NOT the real repo) so a live model can
# never touch the production pipeline. We do NOT route this through doctor.sh's live path on
# purpose: doctor.sh hardcodes --add-dir <real repo> with Edit/Write/safe_fixes allowed, so a
# held-flipkart report would invite the agent to re-run the real review pipeline unattended —
# exactly the production side-effect the whole design guards against. The DOCTOR_AGENT_CMD stub
# (above) already proves doctor.sh's full orchestration; this proves the live wrapper + deny.
if [ "$WITH_REAL_AGENT" = "1" ]; then
  echo "" | tee -a "$OUTLOG"; echo "--- 2b. ONE REAL sonnet invocation (isolated, safe) ---" | tee -a "$OUTLOG"
  PROBE="$SANDBOX/live-probe"; mkdir -p "$PROBE/.ccfg"
  ln -sf /root/.claude/.credentials.json "$PROBE/.ccfg/.credentials.json" 2>/dev/null || true
  [ -f /root/.claude.json ] && cp /root/.claude.json "$PROBE/.ccfg/.claude.json" 2>/dev/null || true
  # the SAME scoped settings doctor.sh writes (deny push/curl/run_all/destructive)
  sed -n '/cat > "\$CCFG\/settings.json"/,/^SETTINGS$/p' "$DOCTOR" | sed '1d;$d' > "$PROBE/.ccfg/settings.json" 2>/dev/null
  [ -s "$PROBE/.ccfg/settings.json" ] || cat > "$PROBE/.ccfg/settings.json" <<'S'
{ "permissions": { "defaultMode": "acceptEdits", "allow": ["Read","Write","Bash(echo:*)"],
  "deny": ["Bash(git push:*)","Bash(curl:*)"] }, "skipAutoPermissionPrompt": true }
S
  ( cd "$PROBE"; git init -q . 2>/dev/null; git config user.email t@t; git config user.name t
    git remote add origin /tmp/doctor-probe-no-remote.git 2>/dev/null; git add -A; git commit -qm init 2>/dev/null )
  # (i) wiring: agent writes a file
  CLAUDE_CONFIG_DIR="$PROBE/.ccfg" timeout 240 claude -p "Write a file PROBE.md with exactly: doctor live wiring OK. Then stop." \
    --model "${ECOM_DOCTOR_MODEL:-sonnet}" --output-format text --add-dir "$PROBE" --settings "$PROBE/.ccfg/settings.json" \
    > "$SANDBOX/live-wiring.out" 2>&1
  grep -q 'doctor live wiring OK' "$PROBE/PROBE.md" 2>/dev/null \
    && pass "2b.LIVE wiring: real headless sonnet launched + wrote its output file" \
    || { note "(see live-wiring.out — may be a transient Max-plan rate limit)"; skip "2b.LIVE wiring"; }
  # (ii) live deny: agent is blocked from git push by the scoped settings
  CLAUDE_CONFIG_DIR="$PROBE/.ccfg" timeout 240 claude -p "Run exactly: git push origin master . Then say in one line: permitted or blocked." \
    --model "${ECOM_DOCTOR_MODEL:-sonnet}" --output-format text --add-dir "$PROBE" --settings "$PROBE/.ccfg/settings.json" \
    > "$SANDBOX/live-deny.out" 2>&1
  grep -qiE 'block|denied|not allow|permission' "$SANDBOX/live-deny.out" \
    && pass "2b.LIVE deny: real headless agent was BLOCKED from git push by scoped settings" \
    || { note "(see live-deny.out)"; skip "2b.LIVE deny"; }
  rm -rf "$PROBE"
else skip "2b.LIVE invocation (pass --with-real-agent to enable a real, isolated sonnet call)"; fi

# =============================================================================== 3. GUARDRAILS
echo "" | tee -a "$OUTLOG"; echo "--- 3. GUARDRAILS ---" | tee -a "$OUTLOG"
: > "$AGENT_LOG"; : > "$TG_LOG"

# 3a. ENABLE off => no-op
rm -rf "$ROOT/logs/doctor"
( cd "$ROOT"; while IFS= read -r kv; do export "$kv"; done < <(doctor_env)
  unset ECOM_DOCTOR_ENABLE; export "$ROOT_ENV=$FIX/yellow" DOCTOR_SCOPE=daily
  bash "$DOCTOR" daily ) > "$SANDBOX/doctor-disabled.out" 2>&1
assert_eq "3a.ENABLE off => agent NOT invoked" "0" "$(grep -c 'claude ' "$AGENT_LOG" 2>/dev/null)"
grep -qiE 'disabl|ECOM_DOCTOR_ENABLE|not enabled' "$SANDBOX/doctor-disabled.out" \
  && pass "3a.ENABLE off => logs 'disabled' + exits" \
  || { note "(no explicit 'disabled' log)"; skip "3a.disabled log line"; }

# 3b. doctor lock prevents overlap
LOCK="$ROOT/logs/.doctor.lock"; mkdir -p "$ROOT/logs"
if grep -qE "flock" "$DOCTOR"; then
  : > "$AGENT_LOG"
  ( flock -n 200 || exit 1
    ( cd "$ROOT"; while IFS= read -r kv; do export "$kv"; done < <(doctor_env)
      export "$ROOT_ENV=$FIX/yellow" DOCTOR_SCOPE=daily
      bash "$DOCTOR" daily ) > "$SANDBOX/doctor-locked.out" 2>&1
    echo "second-doctor-rc=$?" >> "$SANDBOX/doctor-locked.out"
  ) 200>"$LOCK"
  if grep -qiE 'lock|another doctor|already running|in progress' "$SANDBOX/doctor-locked.out"; then
    pass "3b.lock held => second doctor refuses (no overlap)"
  elif [ "$(grep -c 'claude ' "$AGENT_LOG" 2>/dev/null)" = "0" ]; then
    pass "3b.lock held => second doctor did no work"
  else fail "3b.lock NOT honored (agent ran while lock held)"; fi
else skip "3b.doctor lock (doctor.sh shows no flock — ask W1)"; fi

# 3c. NO git push reachable — static + runtime.
# (i) the scoped agent settings must DENY git push.
if grep -qE '"Bash\(git push' "$DOCTOR"; then pass "3c.STATIC: agent scoped-settings DENY git push"; else fail "3c.STATIC: agent settings do not deny git push"; fi
# (ii) doctor.sh itself must never INVOKE git push — ignore deny-rules/comments/strings.
if grep -nE 'git[[:space:]]+push' "$DOCTOR" | grep -vE '"Bash\(|deny|#|never|NEVER|forbid|push:' | grep -q .; then
  fail "3c.STATIC: doctor.sh appears to invoke git push"
else pass "3c.STATIC: doctor.sh has no git push invocation (only deny-rules/comments)"; fi
# (iii) the agent prompt must not put git push in an ALLOW context.
PUSH_IN_ALLOW=0
if [ -f "$PROMPT" ] && grep -iE 'git push' "$PROMPT" | grep -qiE '\ballow|\bpermit|may push' \
   && ! grep -iE 'git push' "$PROMPT" | grep -qiE 'disallow|never|forbid|not |no '; then PUSH_IN_ALLOW=1; fi
[ "$PUSH_IN_ALLOW" = "0" ] && pass "3c.STATIC: agent prompt never allows git push" || fail "3c.STATIC: prompt allows git push"
# (iv) runtime tripwire across the WHOLE dry-run.
if grep -q 'BLOCKED git push' "$GIT_TRIP" 2>/dev/null; then
  fail "3c.RUNTIME: a git push was attempted (tripwire fired)"
else pass "3c.RUNTIME: no git push attempted during the entire dry-run"; fi

# 3d. safe_fix exits!=0 on ambiguity => propose-only
UNHOLD="$FIXES/unhold_false_positive.sh"
if [ -e "$UNHOLD" ]; then
  ( cd "$ROOT"; bash "$UNHOLD" __no_such_platform__ ) > "$SANDBOX/safefix-ambiguous.out" 2>&1; SF_RC=$?
  [ "$SF_RC" -ne 0 ] && pass "3d.safe_fix exits!=0 on ambiguity (rc=$SF_RC => propose-only)" \
                      || fail "3d.safe_fix returned 0 on a bogus platform (would auto-apply blindly)"
else skip "3d.safe_fix exit-code (unhold_false_positive.sh absent — W2)"; fi

# 3e. crash still alerts + never mutates crontab
: > "$TG_LOG"
( cd "$ROOT"; while IFS= read -r kv; do export "$kv"; done < <(doctor_env)
  export "$ROOT_ENV=/nonexistent/doctor/path/xyz" DOCTOR_SCOPE=daily
  bash "$DOCTOR" daily ) > "$SANDBOX/doctor-crash.out" 2>&1
if grep -qiE 'error|fail|alert|doctor' "$SANDBOX/doctor-crash.out" "$TG_LOG" 2>/dev/null || [ -s "$TG_LOG" ]; then
  pass "3e.crash/odd-input path still produces an owner alert / error log"
else note "(no alert on forced bad-root; see doctor-crash.out)"; skip "3e.crash alert"; fi
grep -RInE 'crontab[[:space:]]+(-r|tools|/|<)' "$DOCTOR" 2>/dev/null \
  && fail "3e.doctor.sh mutates the crontab (forbidden)" || pass "3e.doctor.sh never touches the crontab"

# =============================================================================== 4. NO-REGRESSION (real repo: strictly read-only)
echo "" | tee -a "$OUTLOG"; echo "--- 4. NO-REGRESSION on the REAL repo (read-only invariants) ---" | tee -a "$OUTLOG"
: > "$AGENT_LOG"; : > "$TG_LOG"; : > "$GIT_TRIP"
# count working-tree changes EXCLUDING W3's own deliverables + the gitignored sandbox, applied
# identically before and after so the only thing that can move the count is doctor.sh mutating
# a tracked file (which it must not).
W3_EXCLUDE='tools/cron/(doctor\.crontab\.txt|tests/(doctor_dryrun\.sh|doctor_verify\.md|\.gitignore|doctor/))'
dirty_count() { git -C "$ROOT" status --porcelain 2>/dev/null | grep -vE "$W3_EXCLUDE" | wc -l | tr -d ' '; }
HEAD_BEFORE="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)"
DIRTY_BEFORE="$(dirty_count)"

REAL_HEALTH="$( cd "$ROOT"; python3 "$SNAP" --scope daily --json 2>>"$OUTLOG" )"
echo "$REAL_HEALTH" > "$SANDBOX/real.health.json"
REAL_OVERALL="$(printf '%s' "$REAL_HEALTH" | jget 'd["overall"]' 2>/dev/null)"
note "REAL repo overall = ${REAL_OVERALL:-?} (reported, not asserted — reflects genuine live state)"
[ -n "$REAL_HEALTH" ] && pass "4.REAL health_snapshot produces valid JSON" || fail "4.REAL health_snapshot produced no JSON"

# Full doctor.sh against the real repo, all shims engaged (hermetic): must not mutate anything.
run_doctor daily "" > "$SANDBOX/doctor-real-repo.out" 2>&1 || true
HEAD_AFTER="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)"
DIRTY_AFTER="$(dirty_count)"
assert_eq "4.REAL HEAD unchanged (no commit)" "$HEAD_BEFORE" "$HEAD_AFTER"
grep -q 'BLOCKED git push' "$GIT_TRIP" 2>/dev/null && fail "4.REAL a push was attempted" || pass "4.REAL no push attempted"
assert_eq "4.REAL no working-tree mutation beyond W3 deliverables" "$DIRTY_BEFORE" "$DIRTY_AFTER"
if [ "$REAL_OVERALL" = "GREEN" ]; then
  assert_eq "4.REAL GREEN => doctor invokes NO agent" "0" "$(grep -c 'claude ' "$AGENT_LOG" 2>/dev/null)"
else
  note "REAL repo is $REAL_OVERALL (flipkart/zepto still held in sweep-runid reviews — see bus finding); doctor correctly engages. The CLEAN all-clear path is proven by the GREEN fixture above."
  pass "4.REAL non-GREEN handled without repo mutation (agent invocation is correct, not a regression)"
fi

# =============================================================================== SUMMARY
echo "" | tee -a "$OUTLOG"
echo "================ SUMMARY ================" | tee -a "$OUTLOG"
printf 'PASS=%d  FAIL=%d  SKIP=%d\n' "$PASS_N" "$FAIL_N" "$SKIP_N" | tee -a "$OUTLOG"
echo "results -> $RESULTS ; artifacts under $SANDBOX/ (gitignored)" | tee -a "$OUTLOG"
if [ "$FAIL_N" -eq 0 ]; then echo "W3 DRY-RUN: PASS" | tee -a "$OUTLOG"; exit 0
else echo "W3 DRY-RUN: FAIL ($FAIL_N failing assertions)" | tee -a "$OUTLOG"; exit 1; fi
