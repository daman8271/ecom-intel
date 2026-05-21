#!/usr/bin/env bash
# Usage: ./run.sh <platform>   e.g. ./run.sh blinkit
set -euo pipefail
P="${1:?usage: ./run.sh <platform>  (blinkit|zepto|flipkart-minutes|amazon-now|flipkart|amazon)}"
DIR="$(cd "$(dirname "$0")" && pwd)"
PDIR="$DIR/platforms/$P"
[ -d "$PDIR" ] || { echo "no such platform: $P"; exit 1; }
mkdir -p "$DIR/output" "$DIR/logs"
RUN_ID="$(date +%Y-%m-%d-%H%M)"

cd "$PDIR"
echo "[$RUN_ID] scraping $P ..."
node scrape.js 2> "$DIR/logs/${P}-${RUN_ID}.log"
echo "[$RUN_ID] building excel ..."
python3 build_excel.py
cp Jivo-*.xlsx "$DIR/output/" 2>/dev/null || true

# ---- Predictions sheet: append to the workbook before delivery (best-effort). ----
echo "[$RUN_ID] adding predictions sheet ..."
python3 "$DIR/tools/predict.py" "$P" "$(ls -t "$PDIR"/Jivo-*.xlsx | head -1)" 2>>"$DIR/logs/${P}-${RUN_ID}.log" || true
cp "$PDIR"/Jivo-*.xlsx "$DIR/output/" 2>/dev/null || true

# ---- Review: deterministic checks + optional cheap LLM. Never fail the run. ----
# Writes reviews/<P>-<RUN_ID>.json (verdict OK|SUSPECT|BROKEN). The :30 cron
# healthcheck reads that verdict to self-heal. exit!=0 here just means BROKEN.
echo "[$RUN_ID] reviewing $P ..."
python3 "$DIR/tools/review.py" "$P" "$RUN_ID" || true

# ---- Vault: Obsidian memory note + daily/weekly/monthly rollups + ML history ----
echo "[$RUN_ID] writing vault note ..."
python3 "$DIR/tools/vault_note.py" "$P" "$RUN_ID" || echo "vault_note failed (non-fatal)" >&2
python3 "$DIR/tools/vault_rollup.py" daily   || true
python3 "$DIR/tools/vault_rollup.py" weekly  || true
python3 "$DIR/tools/vault_rollup.py" monthly || true

# ---- Telegram delivery (best-effort; MUST NOT fail the run) ----
# Runs in a subshell with errexit off and a trailing `|| true`, so any
# network/API/parse failure is logged to logs/telegram.log and ignored.
(
  set +e
  [ -f "$DIR/secrets.env" ] && . "$DIR/secrets.env"
  TG="${TELEGRAM_BOT_TOKEN:-}"
  CH="${TELEGRAM_CHAT_ID:-}"
  TGLOG="$DIR/logs/telegram.log"
  if [ -n "$TG" ] && [ -n "$CH" ]; then
    STAMP="$(date '+%Y-%m-%d %H:%M:%S')"
    # the Excel just built sits in $PDIR; newest by mtime is this run's file
    XLSX="$(ls -t "$PDIR"/Jivo-*.xlsx 2>/dev/null | head -1)"
    if [ -n "$XLSX" ] && [ -f "$XLSX" ]; then
      BASE="$(basename "$XLSX")"                              # Jivo-Blinkit-Live-Report-2026-05-21.xlsx
      DISP="${BASE#Jivo-}"; DISP="${DISP%-Live-Report-*}"     # Blinkit
      RDATE="${BASE##*-Live-Report-}"; RDATE="${RDATE%.xlsx}" # 2026-05-21

      # Build a short Markdown summary FROM result.json (deterministic, no LLM).
      SUMMARY="$(python3 - "$DISP" "$RDATE" "$PDIR/result.json" 2>>"$TGLOG" <<'PYEOF'
import json, sys, datetime
disp, rdate, path = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(path))
s = d.get("summary", {})
rows = d.get("allRows") or [r for p in d.get("perPin", []) for r in p.get("rows", [])]

def esc(t):  # escape legacy-Markdown control chars in dynamic text
    t = str(t)
    for ch in ('_', '*', '`', '['):
        t = t.replace(ch, '\\' + ch)
    return t

pin_with = s.get("pincodes_with_jivo", "?")
pin_tot  = s.get("pincodes_total", "?")
skus     = s.get("unique_skus") or len({r.get("canonical") for r in rows})
nrows    = s.get("total_rows") or len(rows)

# captured_at (UTC ISO) -> IST display
when = rdate
cap = s.get("captured_at")
try:
    dt = datetime.datetime.fromisoformat(str(cap).replace("Z", "+00:00"))
    ist = dt.astimezone(datetime.timezone(datetime.timedelta(hours=5, minutes=30)))
    when = ist.strftime("%Y-%m-%d %H:%M IST")
except Exception:
    pass

lines = [f"*Jivo × {esc(disp)}*  \U0001F4CA",
         esc(when),
         "",
         f"Coverage: {pin_with}/{pin_tot} pincodes with Jivo",
         f"SKUs: {skus} unique · {nrows} rows"]

# headline 1: cheapest in-stock SKU by per-litre price
instock = [r for r in rows if r.get("in_stock") and (r.get("per_litre") or 0) > 0]
if instock:
    c = min(instock, key=lambda r: r["per_litre"])
    name = c.get("sku_raw") or c.get("canonical") or "?"
    lines.append(f"\n\U0001F4B0 Cheapest: {esc(name)} — ₹{int(round(c['per_litre']))}/L ({esc(c.get('city'))})")

# headline 2: biggest discount
disc = [r for r in rows if (r.get("discount_pct") or 0) > 0]
if disc:
    t = max(disc, key=lambda r: r["discount_pct"])
    name = t.get("sku_raw") or t.get("canonical") or "?"
    lines.append(f"\U0001F3F7️ Top discount: {esc(name)} — {int(round(t['discount_pct']))}% off ({esc(t.get('city'))})")

print("\n".join(lines))
PYEOF
)"
      [ -n "$SUMMARY" ] || SUMMARY="*Jivo ${DISP}* - ${RDATE}
Report attached."

      # a) short markdown summary
      R1="$(curl -s --max-time 60 -X POST "https://api.telegram.org/bot${TG}/sendMessage" \
              --data-urlencode "chat_id=${CH}" \
              --data-urlencode "parse_mode=Markdown" \
              --data-urlencode "text=${SUMMARY}")"
      echo "[$STAMP] $P sendMessage  -> $R1" >> "$TGLOG"

      # b) the Excel report
      R2="$(curl -s --max-time 120 -X POST "https://api.telegram.org/bot${TG}/sendDocument" \
              -F "chat_id=${CH}" \
              -F "document=@${XLSX}" \
              -F "caption=Jivo × ${DISP} · ${RDATE}")"
      echo "[$STAMP] $P sendDocument -> $R2" >> "$TGLOG"
    else
      echo "[$(date '+%F %T')] $P: no Excel file found, telegram delivery skipped" >> "$TGLOG"
    fi
  fi
) || true

echo "[$RUN_ID] $P done. Excel -> $DIR/output/  | log -> $DIR/logs/${P}-${RUN_ID}.log"
tail -1 "$DIR/logs/${P}-${RUN_ID}.log" || true

# ---- Persist this run to git: the memory vault + history + verdicts. Never fail. ----
# Excel/logs/result.json are gitignored on purpose; only the Markdown vault, the
# machine-readable history, and the review verdicts/baselines are committed.
(
  set +e
  cd "$DIR"
  git add vault data reviews baselines >/dev/null 2>&1
  if ! git diff --cached --quiet; then
    git commit -m "run: $P $RUN_ID" >/dev/null 2>&1
    git pull --rebase --autostash >/dev/null 2>&1
    git push >/dev/null 2>&1 || { git pull --rebase --autostash >/dev/null 2>&1; git push >/dev/null 2>&1; }
    echo "[$RUN_ID] $P committed + pushed."
  else
    echo "[$RUN_ID] $P nothing new to commit."
  fi
) || true
