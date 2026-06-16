#!/usr/bin/env bash
# setup_cron.sh — install the ecom-intel cron schedule (idempotent).
#
# NEW schedule: each LIVE platform runs 3x/day in three IST windows —
#   morning 09:xx, midday 12:xx, evening 16:xx (user: 9am / 12pm / 4pm IST).
# Platforms are STAGGERED a few minutes apart inside each window so four
# Chromium scrapers don't launch the same second on one VPS:
#   blinkit :00 · flipkart-minutes :04 · flipkart :08 · amazon :12
# The self-heal/healthcheck runs at :30 of each window — AFTER the batch — so it
# catches and fixes a failure in the same session.
#
# Idempotent: every ecom-intel line carries the "# ecom-intel" tag-comment; this
# script removes ONLY tagged lines and reinstalls them, never touching other
# crontab entries.
#
# NOTE: this script is runnable but the live crontab is applied by the
# orchestrator after end-to-end testing. Run with --print (or DRY_RUN=1) to just
# preview the block without modifying crontab.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

# Make cron times mean IST.
timedatectl set-timezone Asia/Kolkata 2>/dev/null || true

# LIVE platforms in the parallel sweep. amazon-fresh went live 2026-05-30 (logged-in
# session, i=freshstore — the rich Fresh catalog; see platforms/amazon-fresh/SKILL.md).
# amazon-now joined the cron 2026-05-31: it shares amazon-fresh's account + server-side
# delivery location, so run.sh serializes exactly this pair behind a shared
# .amazon-account.lock (they never scrape at the same time). The plain `amazon` scraper is
# guest /dp and does NOT set account location, so it's safe alongside both.
# (run_all.sh holds the authoritative list; this is a doc mirror.)
PLATFORMS="blinkit flipkart-minutes flipkart amazon zepto amazon-fresh amazon-now"  # bigbasket national scrape retired 2026-06-16 -> pincode-wise QC pull runs as its own 08:00 job

# Per-platform minute offset within each window (stagger to avoid concurrent Chromium).
declare -A OFFSET=( [blinkit]=0 [flipkart-minutes]=4 [flipkart]=8 [amazon]=12 )

# Run windows (hours, IST): 9am, 12pm, 4pm.
HOURS="9 12 16"

# Self-heal runs at :30 of each window — after the staggered batch finishes.
HEAL_MIN=30
TAG="# ecom-intel"

# Build the exact block we want installed.
# One sweep per window: run_all.sh scrapes every live platform IN PARALLEL then
# self-heals (amazon-fresh + amazon-now are the only serialized pair — a shared
# .amazon-account.lock in run.sh keeps them from co-scraping). No staggered
# per-platform cron lines — one run_all.sh per window.
build_block() {
  for H in $HOURS; do
    echo "0 $H * * * cd $DIR && ./run_all.sh >> logs/cron.log 2>&1   $TAG"
  done
  # AUTO-HEAL daily deep-dive: the full 11-bug-class audit over every platform ->
  # dated health report (reviews/guardian/health-<date>.md) + Telegram alert on any
  # NEW bug class. Read-only (no scraping). Runs at 18:00 IST, after the day's last
  # sweep, so it reports on fresh data. See tools/guardian_daily.sh.
  echo "0 18 * * * cd $DIR && ./tools/guardian_daily.sh >> logs/guardian.log 2>&1   $TAG guardian-daily"
}

BLOCK="$(build_block)"

# --print / DRY_RUN: preview only, do not touch crontab.
if [ "${1:-}" = "--print" ] || [ "${DRY_RUN:-0}" = "1" ]; then
  echo "# ecom-intel crontab block (preview — NOT installed):"
  echo "$BLOCK"
  exit 0
fi

# Install: strip old ecom-intel lines, append the fresh block, preserve the rest.
TMP="$(mktemp)"
crontab -l 2>/dev/null | grep -vF "$TAG" > "$TMP" || true
printf '%s\n' "$BLOCK" >> "$TMP"
crontab "$TMP"
rm -f "$TMP"

echo "cron installed (IST):"
crontab -l
