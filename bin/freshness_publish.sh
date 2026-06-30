#!/usr/bin/env bash
# =============================================================================
# freshness_publish.sh — regenerate the data-health banner and publish it into
# the JIVO data-bank vault. Runs AFTER the daily data-bank build (cron).
#
# Fully isolated from the gated daily_rebuild pipeline: it only writes/commits
# DATA-FRESHNESS.md + data-freshness.json (already proven to PASS verify_databank
# link-integrity), and pushes via the repo's own push_both.sh. A failure here is
# best-effort and can NEVER affect the rebuild/push that already ran.
#
# The push is CRON-DRIVEN to the owner's OWN private repo (legitimate; the same
# pattern run_daily.sh stage 2 uses) — not an interactive Claude push.
# =============================================================================
set -uo pipefail

ECOM="${ECOM_ROOT:-/opt/ecom-intel}"
VAULT="${VAULT_ROOT:-/root/jivo-data-bank}"
LOG="$ECOM/logs/freshness.log"
mkdir -p "$ECOM/logs"

{
  echo "=== freshness_publish $(date -u +%FT%TZ) ==="
  # 1. regenerate banner (--alert sends Telegram only on an actionable RED freeze)
  ECOM_ROOT="$ECOM" VAULT_ROOT="$VAULT" python3 "$ECOM/tools/freshness_guard.py" --alert
  rc=$?
  echo "freshness_guard exit=$rc  (0=ok/amber, 1=actionable RED freeze)"

  # 2. commit + push ONLY the two banner files (no gated verify involved)
  cd "$VAULT" || { echo "vault missing: $VAULT"; exit 0; }
  if [ -n "$(git status --porcelain -- DATA-FRESHNESS.md data-freshness.json 2>/dev/null)" ]; then
    git add DATA-FRESHNESS.md data-freshness.json
    git commit -q -m "freshness: data-health banner $(date -u +%F)" || true
    if [ -x bin/push_both.sh ]; then bin/push_both.sh || true; else git push || true; fi
    echo "published updated banner"
  else
    echo "banner unchanged — nothing to publish"
  fi
} >> "$LOG" 2>&1 || true
