#!/usr/bin/env bash
# tools/guardian_daily.sh — SCHEDULED DAILY DEEP-DIVE (the auto-heal system's
# standing watch). Runs the full 11-bug-class audit (tools/guardian.py) over every
# LIVE platform, writes a dated health report, and ALERTS the owner on any NEW bug
# class that wasn't present yesterday — so a regression can never slip in silently.
#
# Read-only by design: this is a DETECT pass (no scraping, no re-runs). The inline
# guardian hook in run_all.sh owns the SELF-HEAL; this daily pass owns the standing
# diagnosis + trend. It CALLS tools/guardian.py (which CALLS tools/review.py); it
# never reimplements any check.
#
# Wiring: one crontab line (see setup at bottom of autoheal.fix.md). Best-effort &
# idempotent — never crashes the box, always exits 0.
set -uo pipefail
export HOME="${HOME:-/root}"
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR" || exit 0
mkdir -p logs reviews/guardian 2>/dev/null || true

PLATFORMS="${ECOM_PLATFORMS:-blinkit  flipkart-minutes flipkart amazon zepto amazon-fresh amazon-now bigbasket}"
TODAY="$(date +%Y-%m-%d)"
YDAY="$(date -d 'yesterday' +%Y-%m-%d 2>/dev/null || echo '')"
REPORT="$DIR/reviews/guardian/health-${TODAY}.md"
LOG="$DIR/logs/guardian.log"

log() { echo "[$(date '+%F %T')] guardian_daily: $*" >> "$LOG"; }
log "START daily deep-dive ($TODAY)"

# 1) Evaluate every platform in DETECT mode (force a fresh review.py verdict, but
#    --no-baseline so the diagnostic pass never touches the rolling baselines; no heal).
#    guardian.py writes reviews/guardian/<p>-latest.json for each.
for P in $PLATFORMS; do
  python3 tools/guardian.py "$P" --review --no-baseline --run-id "daily-${TODAY}" \
    >/dev/null 2>>"$LOG" || true
done

# 2) Build the dated health report + detect NEW bug classes vs yesterday, in Python.
#    The block prints exactly one line ("ALERT|..." or "OK|...") on stdout, captured
#    into RESULT below as the single source of truth for the Telegram decision.
RESULT="$(python3 - "$TODAY" "$YDAY" "$REPORT" $PLATFORMS <<'PY' 2>>"$LOG"
import json, os, sys
today, yday, report = sys.argv[1], sys.argv[2], sys.argv[3]
platforms = sys.argv[4:]
ROOT = os.getcwd()
GDIR = os.path.join(ROOT, "reviews", "guardian")

def load(p):
    fp = os.path.join(GDIR, f"{p}-latest.json")
    try:
        with open(fp) as f: return json.load(f)
    except Exception: return None

# failing (class -> name) per platform today
def failed_classes(v):
    out = set()
    for c in (v or {}).get("deep_checks", []) or []:
        if not c.get("pass"):
            out.add((c.get("class"), c.get("name")))
    return out

rows, all_new, broken, suspect = [], [], [], []
state_today = {}
for p in platforms:
    v = load(p)
    if not v:
        rows.append((p, "NO-DATA", "", ""))
        continue
    verdict = v.get("verdict", "?")
    fc = failed_classes(v)
    state_today[p] = sorted(f"{c}:{n}" for c, n in fc)
    if verdict == "BROKEN": broken.append(p)
    elif verdict == "SUSPECT": suspect.append(p)
    rows.append((p, verdict, v.get("review_verdict") or "-",
                 v.get("diagnosis", "")))

# compare to yesterday's saved state (a tiny json sidecar)
prev_fp = os.path.join(GDIR, f"state-{yday}.json") if yday else None
prev = {}
if prev_fp and os.path.isfile(prev_fp):
    try:
        with open(prev_fp) as f: prev = json.load(f)
    except Exception: prev = {}
for p in platforms:
    new = set(state_today.get(p, [])) - set(prev.get(p, []))
    for n in sorted(new):
        all_new.append((p, n))

# save today's state for tomorrow's comparison
try:
    with open(os.path.join(GDIR, f"state-{today}.json"), "w") as f:
        json.dump(state_today, f, indent=2)
except Exception: pass

# write the markdown report
lines = [f"# ecom-intel — Guardian daily health report ({today})", ""]
lines.append(f"- BROKEN: {', '.join(broken) or 'none'}")
lines.append(f"- SUSPECT: {', '.join(suspect) or 'none'}")
lines.append(f"- NEW bug classes vs {yday or '(none)'}: "
             f"{', '.join(f'{p}[{n}]' for p, n in all_new) or 'none'}")
lines += ["", "| platform | guardian | review.py | diagnosis |",
          "|---|---|---|---|"]
for p, verdict, rv, diag in rows:
    diag = (diag or "").replace("|", "\\|")[:180]
    lines.append(f"| {p} | {verdict} | {rv} | {diag} |")
lines.append("")
try:
    with open(report, "w") as f: f.write("\n".join(lines))
except Exception as e:
    print(f"report write failed: {e}")

# emit a one-line alert payload to stdout for the shell to Telegram (only if needed)
if broken or all_new:
    parts = []
    if broken: parts.append("BROKEN: " + ", ".join(broken))
    if all_new:
        parts.append("NEW bug classes: " +
                     ", ".join(f"{p}[{n}]" for p, n in all_new))
    print("ALERT|" + " | ".join(parts))
else:
    print("OK|all platforms healthy")
PY
)"

log "report -> $REPORT ; result=$RESULT"

# 3) Telegram alert ONLY when something is broken or a NEW class appeared.
if [[ "$RESULT" == ALERT\|* ]]; then
  PAYLOAD="${RESULT#ALERT|}"
  ( set +e
    [ -f "$DIR/secrets.env" ] && . "$DIR/secrets.env"
    TG="${TELEGRAM_BOT_TOKEN:-}"; CH="${TELEGRAM_CHAT_ID:-}"
    if [ -n "$TG" ] && [ -n "$CH" ]; then
      curl -s --max-time 60 -X POST "https://api.telegram.org/bot${TG}/sendMessage" \
        --data-urlencode "chat_id=${CH}" \
        --data-urlencode "text=🩺 ecom-intel guardian daily ($TODAY)
$PAYLOAD

Full report: reviews/guardian/health-${TODAY}.md" >/dev/null 2>&1 \
        && log "TG daily alert sent" || log "TG daily alert failed (ignored)"
    else
      log "TG creds missing; daily alert skipped"
    fi ) || true
fi

log "DONE daily deep-dive"
exit 0
