#!/usr/bin/env bash
# tools/cron/doctor.sh <scope>            scope = daily | weekly | monthly
#
# Ecom Doctor — the self-healing watchdog ORCHESTRATOR.
#
#   (a) run the deterministic collector  -> logs/doctor/<scope>-<date>.json
#   (b) overall==GREEN -> one-line "all clear" owner Telegram, exit.
#   (c) overall==YELLOW|RED -> invoke a BOUNDED headless Claude agent
#       (tools/cron/doctor_prompt.md + the vetted tools/cron/safe_fixes/ menu)
#       to diagnose & apply only VETTED-SAFE fixes, capture its output, then
#       send the owner a summary Telegram + the agent's written diagnosis.
#       ALWAYS alert on non-GREEN.
#
# HARD GUARDRAILS (baked in here + the scoped agent settings):
#   * ENABLE FLAG: runs only if ECOM_DOCTOR_ENABLE=1 (secrets.env). Kill switch = unset it.
#   * The headless agent NEVER pushes (scoped settings deny git push); doctor.sh never pushes.
#   * Single-flight: flock -n logs/.doctor.lock — two doctors never overlap.
#   * Fail-safe: ANY step failing still fires an owner alert ("doctor run errored").
#     A doctor crash can NEVER touch the live cron sweeps (separate process, exits 0).
#
# Dry-run / test overrides (used by W3's tools/cron/tests/doctor_dryrun.sh):
#   DOCTOR_DRY_RUN=1      -> log Telegram payloads instead of curl'ing them.
#   DOCTOR_AGENT_CMD=...  -> run this command (prompt on stdin) instead of `claude -p`.
#                           env it sees: DOCTOR_REPORT_JSON, DOCTOR_DIAGNOSIS_PATH, DOCTOR_SCOPE.
#   HEALTH_ROOT=...       -> point health_snapshot.py at a fixture repo (it honors this).
#   ECOM_DOCTOR_MODEL     -> agent model (default sonnet; weekly/monthly may set opus).
#   ECOM_DOCTOR_TIMEOUT   -> headless agent wall-clock budget seconds (default 1200).
#
# Never `set -e` around the working body: this script must reach its alert path no
# matter what fails. It returns 0 always.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"   # repo root
SCOPE="${1:-daily}"
case "$SCOPE" in daily|weekly|monthly) ;; *) SCOPE="daily" ;; esac

# --- load secrets (best-effort) ---------------------------------------------
[ -f "$DIR/secrets.env" ] && . "$DIR/secrets.env"

DOCTOR_LOG="$DIR/logs/doctor"
mkdir -p "$DOCTOR_LOG" 2>/dev/null
DATE_IST="$(TZ=Asia/Kolkata date '+%Y-%m-%d')"
STAMP() { TZ=Asia/Kolkata date '+%Y-%m-%d %H:%M:%S'; }

REPORT="$DOCTOR_LOG/${SCOPE}-${DATE_IST}.json"
AGENT_OUT="$DOCTOR_LOG/${SCOPE}-${DATE_IST}.out"
# W2's headless agent writes its human diagnosis here (per agent-2 contract):
DIAGNOSIS="$DOCTOR_LOG/diagnosis-${SCOPE}-${DATE_IST}.md"

log() { echo "[$(STAMP)] doctor[$SCOPE]: $*"; }

# ---------------------------------------------------------------------------
# Telegram helper — mirrors run.sh's pattern; honors DOCTOR_DRY_RUN.
#   tg_message "<text>"        -> owner sendMessage
#   tg_document "<path>" "<caption>" -> owner sendDocument (best-effort)
# Always best-effort: never fails the script.
# ---------------------------------------------------------------------------
tg_message() {
  local text="$1"
  local TG="${TELEGRAM_BOT_TOKEN:-}"
  local CH="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
  if [ "${DOCTOR_DRY_RUN:-}" = "1" ]; then
    log "DRY tg_message -> $text"
    return 0
  fi
  if [ -z "$TG" ] || [ -z "$CH" ]; then
    log "tg_message skipped (no TELEGRAM creds): $text"
    return 0
  fi
  local r
  r="$(curl -s --max-time 60 -X POST "https://api.telegram.org/bot${TG}/sendMessage" \
        --data-urlencode "chat_id=${CH}" \
        --data-urlencode "text=${text}" 2>/dev/null)"
  log "tg_message sent -> ${r:0:120}"
}

tg_document() {
  local path="$1" caption="$2"
  local TG="${TELEGRAM_BOT_TOKEN:-}"
  local CH="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
  [ -f "$path" ] || return 0
  if [ "${DOCTOR_DRY_RUN:-}" = "1" ]; then
    log "DRY tg_document -> $path ($caption)"
    return 0
  fi
  [ -z "$TG" ] || [ -z "$CH" ] && return 0
  curl -s --max-time 120 -X POST "https://api.telegram.org/bot${TG}/sendDocument" \
       -F "chat_id=${CH}" -F "document=@${path}" \
       --form-string "caption=${caption}" >/dev/null 2>&1
  log "tg_document sent -> $path"
}

# FAIL-SAFE DESIGN: we deliberately do NOT use `set -e` or an ERR trap. An ERR trap
# fires on benign non-zero returns (grep-no-match, a failing `[ -z ]` test, a curl
# hiccup) and would both spuriously alert AND abort early. Instead, every meaningful
# step is explicitly guarded (the health_snapshot run below, the agent rc, the
# always-runs owner alert in step 5). Bash-without-errexit simply continues past any
# benign failure to the alert + `exit 0` at the end, so a doctor crash can never
# abort or touch the live sweeps.

# ---------------------------------------------------------------------------
# (0) ENABLE flag — kill switch.
# ---------------------------------------------------------------------------
if [ "${ECOM_DOCTOR_ENABLE:-}" != "1" ]; then
  log "disabled (ECOM_DOCTOR_ENABLE != 1) — no-op exit"
  exit 0
fi

# ---------------------------------------------------------------------------
# (1) Single-flight lock — two doctors never overlap.
# ---------------------------------------------------------------------------
LOCK="$DIR/logs/.doctor.lock"
if command -v flock >/dev/null 2>&1; then
  exec 8>"$LOCK"
  if ! flock -n 8; then
    log "another doctor holds the lock ($LOCK) — exiting"
    exit 0
  fi
fi

# From here we run the body in a way that NEVER aborts on a single failure: each
# stage is guarded; a fatal surprise hits the ERR trap -> owner alert -> exit 0.
log "start (date=$DATE_IST scope=$SCOPE)"

# ---------------------------------------------------------------------------
# (2) Collect deterministic health -> REPORT.
# ---------------------------------------------------------------------------
if ! python3 "$DIR/tools/cron/health_snapshot.py" --scope "$SCOPE" --json > "$REPORT" 2>>"$DIR/logs/doctor.log"; then
  log "health_snapshot FAILED to run — alerting owner"
  tg_message "🩺❌ Ecom Doctor ($SCOPE) could not collect health on $DATE_IST (health_snapshot crashed). Live sweeps unaffected."
  exit 0
fi

OVERALL="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('overall','RED'))" "$REPORT" 2>/dev/null || echo RED)"
log "overall=$OVERALL  report=$REPORT"

# Human-readable issue summary (used in both GREEN and non-GREEN messages).
SUMMARY="$(python3 - "$REPORT" <<'PYEOF' 2>/dev/null || true
import json, sys
d = json.load(open(sys.argv[1]))
issues = d.get("issues", [])
if not issues:
    print("no issues — all platforms healthy.")
else:
    lines = []
    for i in issues[:12]:
        plat = i.get("platform") or "-"
        lines.append(f"• [{i.get('severity')}] {i.get('signal')} ({plat}): {i.get('detail')}")
    if len(issues) > 12:
        lines.append(f"… +{len(issues)-12} more")
    print("\n".join(lines))
PYEOF
)"

# ---------------------------------------------------------------------------
# (3) GREEN -> one-line all-clear, done.
# ---------------------------------------------------------------------------
if [ "$OVERALL" = "GREEN" ]; then
  tg_message "🩺✅ Ecom Doctor ($SCOPE) $DATE_IST: all clear — 8 platforms healthy, batches delivered, no held streaks."
  log "GREEN — all-clear sent, done"
  exit 0
fi

# ---------------------------------------------------------------------------
# (4) YELLOW/RED -> invoke the bounded headless agent, then summarize to owner.
# ---------------------------------------------------------------------------
log "non-GREEN ($OVERALL) -> invoking headless doctor agent"

MODEL="${ECOM_DOCTOR_MODEL:-sonnet}"
TIMEOUT_S="${ECOM_DOCTOR_TIMEOUT:-1200}"

# --- build the prompt: W2's playbook + the inlined report + the output contract.
PROMPT_FILE="$(mktemp /tmp/doctor-prompt.XXXXXX.md)"
{
  if [ -f "$DIR/tools/cron/doctor_prompt.md" ]; then
    cat "$DIR/tools/cron/doctor_prompt.md"
  else
    # Fallback so doctor.sh is independently runnable before W2 lands. Conservative:
    # diagnose + propose only; do not free-edit.
    cat <<'FALLBACK'
You are the Ecom Doctor headless agent. The doctor_prompt.md playbook is not yet
installed, so operate in DIAGNOSE + PROPOSE-ONLY mode: investigate each issue from
repo artifacts (reviews/, platforms/<p>/result.json, logs/, baselines/, data/),
classify it (FALSE-POSITIVE | REAL-DATA-ISSUE | INFRA | UNKNOWN), and write a
diagnosis with a proposed fix. Do NOT edit production code, do NOT push, do NOT run
full sweeps. Apply a fix ONLY by calling a script in tools/cron/safe_fixes/ if one
clearly applies.
FALLBACK
  fi
  echo
  echo "## HEALTH REPORT (JSON) — scope=$SCOPE date=$DATE_IST"
  echo '```json'
  cat "$REPORT"
  echo '```'
  echo
  echo "## OUTPUT CONTRACT"
  echo "Write your full diagnosis to: $DIAGNOSIS"
  echo "Per issue: root cause · classification · action taken (safe_fix id) or PROPOSE-ONLY (with a diff) · evidence · confidence."
  echo "Commit any APPLIED fix LOCALLY with prefix 'doctor:' (behind flock on $DIR/.gitcommit.lock). NEVER git push. NEVER run ./run_all.sh."
  echo "STOP after writing $DIAGNOSIS."
} > "$PROMPT_FILE"

AGENT_RC=0
if [ -n "${DOCTOR_AGENT_CMD:-}" ]; then
  # --- test/stub path: run the override command with the prompt on stdin.
  log "using DOCTOR_AGENT_CMD override (stub)"
  DOCTOR_REPORT_JSON="$REPORT" DOCTOR_DIAGNOSIS_PATH="$DIAGNOSIS" DOCTOR_SCOPE="$SCOPE" \
    bash -c "$DOCTOR_AGENT_CMD" < "$PROMPT_FILE" > "$AGENT_OUT" 2>&1
  AGENT_RC=$?
else
  # --- live path: isolated config dir + symlinked creds (mirrors cc-worker.sh) so
  #     there are no permission prompts, plus a SCOPED settings.json that denies push
  #     + full-sweep scrapes + destructive ops.
  CCFG="$DOCTOR_LOG/.ccfg"
  mkdir -p "$CCFG" 2>/dev/null
  ln -sf /root/.claude/.credentials.json "$CCFG/.credentials.json" 2>/dev/null || true
  if [ -f /root/.claude.json ] && [ ! -e "$CCFG/.claude.json" ]; then
    cp /root/.claude.json "$CCFG/.claude.json" 2>/dev/null || true
  fi
  # Scoped permissions: read/inspect + Edit/Write + a SAFE bash subset + safe_fixes;
  # DENY git push, full sweeps, destructive, and outbound curl/wget (doctor.sh owns alerts).
  cat > "$CCFG/settings.json" <<'SETTINGS'
{
  "permissions": {
    "defaultMode": "acceptEdits",
    "allow": [
      "Read", "Grep", "Glob", "Edit", "Write",
      "Bash(python3:*)", "Bash(node:*)", "Bash(ls:*)", "Bash(cat:*)", "Bash(grep:*)",
      "Bash(rg:*)", "Bash(head:*)", "Bash(tail:*)", "Bash(wc:*)", "Bash(jq:*)",
      "Bash(find:*)", "Bash(diff:*)", "Bash(sort:*)", "Bash(uniq:*)", "Bash(cut:*)",
      "Bash(echo:*)", "Bash(date)", "Bash(mkdir:*)", "Bash(cp:*)", "Bash(mv:*)",
      "Bash(touch:*)", "Bash(flock:*)", "Bash(test:*)", "Bash(sed:*)", "Bash(awk:*)",
      "Bash(git status:*)", "Bash(git diff:*)", "Bash(git add:*)", "Bash(git commit:*)",
      "Bash(git log:*)", "Bash(git stash:*)", "Bash(git restore:*)", "Bash(git show:*)",
      "Bash(./tools/cron/safe_fixes/:*)", "Bash(tools/cron/safe_fixes/:*)",
      "Bash(./run.sh:*)"
    ],
    "deny": [
      "Bash(git push:*)", "Bash(git push)", "Bash(./run_all.sh:*)", "Bash(run_all.sh:*)",
      "Bash(curl:*)", "Bash(wget:*)", "Bash(crontab:*)", "Bash(rm -rf:*)", "Bash(rm -fr:*)",
      "Bash(setup_cron.sh:*)", "Bash(./setup_cron.sh:*)", "Bash(sudo:*)"
    ]
  },
  "skipAutoPermissionPrompt": true,
  "includeCoAuthoredBy": false
}
SETTINGS

  log "invoking claude headless (model=$MODEL timeout=${TIMEOUT_S}s)"
  CLAUDE_CONFIG_DIR="$CCFG" timeout "$TIMEOUT_S" \
    claude -p "$(cat "$PROMPT_FILE")" \
      --model "$MODEL" \
      --output-format text \
      --add-dir "$DIR" \
      --settings "$CCFG/settings.json" \
      > "$AGENT_OUT" 2>&1
  AGENT_RC=$?
fi
rm -f "$PROMPT_FILE" 2>/dev/null

if [ "$AGENT_RC" -eq 124 ]; then
  log "agent TIMED OUT after ${TIMEOUT_S}s"
elif [ "$AGENT_RC" -ne 0 ]; then
  log "agent exited rc=$AGENT_RC (see $AGENT_OUT)"
else
  log "agent finished OK (see $AGENT_OUT)"
fi

# ---------------------------------------------------------------------------
# (5) ALWAYS alert the owner with the summary + the agent's diagnosis.
# ---------------------------------------------------------------------------
ICON="⚠️"; [ "$OVERALL" = "RED" ] && ICON="🔴"
HDR="🩺$ICON Ecom Doctor ($SCOPE) $DATE_IST — overall=$OVERALL"
if [ "$AGENT_RC" -eq 0 ] && [ -f "$DIAGNOSIS" ]; then
  TAIL="agent ran; diagnosis attached."
elif [ "$AGENT_RC" -eq 124 ]; then
  TAIL="agent TIMED OUT (${TIMEOUT_S}s) — diagnose manually."
else
  TAIL="agent rc=$AGENT_RC — no diagnosis written; investigate."
fi

tg_message "$HDR
$SUMMARY

$TAIL
report: $REPORT"

# attach the agent's written diagnosis if present, else its raw stdout tail
if [ -f "$DIAGNOSIS" ]; then
  tg_document "$DIAGNOSIS" "Ecom Doctor diagnosis — $SCOPE $DATE_IST"
elif [ -f "$AGENT_OUT" ]; then
  tg_document "$AGENT_OUT" "Ecom Doctor agent output — $SCOPE $DATE_IST"
fi

log "done (overall=$OVERALL agent_rc=$AGENT_RC)"
exit 0
