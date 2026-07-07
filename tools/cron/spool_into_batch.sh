#!/usr/bin/env bash
# Register a late-built (Mac-drop / residential-collector) report into the pending
# deadline batch so send_batch.py delivers it with the sweep at the slot deadline
# instead of counting it "missing" (owner-approved 2026-07-05: BB/Swiggy built ~3 AM
# were absent from the 10:00 Telegram batch because only run.sh spooled entries).
#
#   Usage: spool_into_batch.sh <platform> <display-name> <xlsx-path>
#
# Pending batch = output/.batch/launched-<sweep-id> with no matching sent-<sweep-id>.
# No pending batch, batch already sent, or missing xlsx => silent no-op (rc=0), so
# immediate-send days and manual ingests behave exactly as before.
set -euo pipefail
ROOT=/opt/ecom-intel
P="${1:?usage: spool_into_batch.sh <platform> <display-name> <xlsx>}"
DISP="${2:?display name}"
XLSX="${3:?xlsx path}"
BROOT="$ROOT/output/.batch"

[ -f "$XLSX" ] || exit 0
TODAY="$(date +%F)"

if [ "$P" = "blinkit" ]; then
  if [ -f "$ROOT/logs/blinkit-main-wa-${TODAY}.sent" ]; then
    echo "[spool_into_batch] blinkit already sent direct WhatsApp for ${TODAY}; not spooling $XLSX"
    exit 0
  fi
  BLINKIT_MONITOR_DRYRUN=1 \
  BLINKIT_MONITOR_EXIT_CODE=1 \
  BLINKIT_MONITOR_DATE="$TODAY" \
  BLINKIT_MONITOR_REPORT="$XLSX" \
  "$ROOT/tools/cron/blinkit_quality_monitor.sh" pre-spool >/dev/null || {
    echo "[spool_into_batch] blinkit quality gate failed; not spooling $XLSX" >&2
    exit 0
  }
fi

PENDING=""
for l in "$BROOT"/launched-"$TODAY"-*; do
  [ -e "$l" ] || continue
  sid="${l##*/launched-}"
  [ -e "$BROOT/sent-$sid" ] && continue
  PENDING="$sid"   # same-day only: stale launched-* markers from dropped ticks must not attract spools
done
[ -n "$PENDING" ] || exit 0

BDIR="$BROOT/$PENDING"
mkdir -p "$BDIR"
python3 - "$P" "$DISP" "$BDIR/${P}.json" "$XLSX" <<'PY'
import json, os, re, sys, time
p, disp, out, xlsx = sys.argv[1:5]
m = re.search(r"(\d{4}-\d{2}-\d{2})", os.path.basename(xlsx))
rdate = m.group(1) if m else time.strftime("%Y-%m-%d")
tmp = out + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump({"platform": p, "verdict": "OK",
               "summary": f"*Jivo × {disp}* · {rdate}\nReport attached.",
               "xlsx": os.path.abspath(xlsx),
               "caption": f"Jivo × {disp} · {rdate}",
               "ts": int(time.time())}, f, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, out)  # atomic: send_batch never sees a half-written file
PY
echo "[spool_into_batch] $P spooled into pending batch $PENDING"
