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

# LIVE platforms only — NO amazon-now (gated). zepto went live 2026-05-29 via the
# Zepto BFF API gateway (no proxy); see platforms/zepto/SKILL.md. instamart also runs
# via run_all.sh. (run_all.sh holds the authoritative list; this is a doc mirror.)
PLATFORMS="blinkit instamart flipkart-minutes flipkart amazon zepto"

# Per-platform minute offset within each window (stagger to avoid concurrent Chromium).
declare -A OFFSET=( [blinkit]=0 [flipkart-minutes]=4 [flipkart]=8 [amazon]=12 )

# Run windows (hours, IST): 9am, 12pm, 4pm.
HOURS="9 12 16"

# Self-heal runs at :30 of each window — after the staggered batch finishes.
HEAL_MIN=30
TAG="# ecom-intel"

# Build the exact block we want installed.
# One sweep per window: run_all.sh scrapes every live platform SEQUENTIALLY then
# self-heals (see run_all.sh for why sequential at ~796-pincode scale). No more
# staggered per-platform lines — the sweep is serialized inside run_all.sh.
build_block() {
  for H in $HOURS; do
    echo "0 $H * * * cd $DIR && ./run_all.sh >> logs/cron.log 2>&1   $TAG"
  done
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
