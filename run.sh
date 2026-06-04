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
# amazon-now runs the v2 scraper (scrape.ctnow.js) against the GENUINE Amazon Now
# storefront (almBrandId=ctnow). The old scrape.js targeted i=nowstore — the legacy
# Prime-Now/marketplace SEARCH — which silently published marketplace prices as "Now"
# (0 real minute ETAs, ~8% catalog); it is frozen. See ROOTCAUSE-AmazonNow-2026-06-01.md.
SCRAPER="scrape.js"
[ "$P" = "amazon-now" ] && SCRAPER="scrape.ctnow.js"
echo "[$RUN_ID] scraping $P ($SCRAPER) ..."
# amazon-fresh and amazon-now now run on SEPARATE, INDEPENDENT Amazon accounts
# (fresh=259-8681039, now=520-2840772), each with its OWN account-global delivery
# location — verified independent 2026-06-04 — so they no longer collide and may run
# CONCURRENTLY. We still take a PER-PLATFORM lock (.<platform>.lock) so a platform can't
# overlap its OWN previous run (e.g. two run_all windows stacking), which would corrupt
# that one account's location. Cross-platform they are fully parallel. Safety net: both
# scrapers drop any row whose resolved location != requested pincode, so even an
# unexpected collision yields reduced coverage, never wrong prices.
if { [ "$P" = "amazon-fresh" ] || [ "$P" = "amazon-now" ]; } && command -v flock >/dev/null 2>&1; then
  (
    flock -w 2700 8 || { echo "[$RUN_ID] $P: per-account lock not acquired in 45m; skipping this window"; exit 75; }
    echo "[$RUN_ID] $P: per-account lock (.${P}.lock) acquired; scraping ..."
    node "$SCRAPER" 2> "$DIR/logs/${P}-${RUN_ID}.log"
  ) 8>"$DIR/.${P}.lock"
else
  node "$SCRAPER" 2> "$DIR/logs/${P}-${RUN_ID}.log"
fi
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

# Read the verdict the review just wrote (reviews/<P>-<RUN_ID>.json). This GATES the
# stakeholder Telegram delivery below: we publish the polished report ONLY on a clean OK
# run, so a BROKEN/SUSPECT run (contamination, padding, combo inflation, block, staleness)
# can never reach Jivo's stakeholders. Default to BROKEN if the verdict is unreadable —
# fail closed, never ship on uncertainty.
VERDICT="$(python3 - "$DIR/reviews/${P}-${RUN_ID}.json" <<'PYEOF' 2>/dev/null || echo BROKEN
import json, sys
try:
    print((json.load(open(sys.argv[1])).get("verdict") or "BROKEN").upper())
except Exception:
    print("BROKEN")
PYEOF
)"
echo "[$RUN_ID] $P review verdict = $VERDICT"

# ---- Vault: append this run's COMPLETE rows to data/<P>/history.csv. ----
# Note generation is NOT done here: the whole Obsidian graph (complete run notes +
# SKU/city/pincode hubs + MOCs + rollups + index) is rebuilt once per sweep by
# tools/vault_build.py in run_all.sh, after all platforms finish. So we only persist
# the machine-readable rows here (--csv-only) — the vault is complete-by-construction
# and never holds a summarized note. (Drop --csv-only to also write a standalone note.)
echo "[$RUN_ID] appending history.csv ..."
python3 "$DIR/tools/vault_note.py" "$P" "$RUN_ID" --csv-only || echo "vault_note failed (non-fatal)" >&2

# ---- Telegram delivery (best-effort; MUST NOT fail the run) ----
# Runs in a subshell with errexit off and a trailing `|| true`, so any
# network/API/parse failure is logged to logs/telegram.log and ignored.
(
  set +e
  [ -f "$DIR/secrets.env" ] && . "$DIR/secrets.env"
  TG="${TELEGRAM_BOT_TOKEN:-}"
  CH="${TELEGRAM_CHAT_ID:-}"
  # Optional separate owner/alert channel for held-back (non-OK) runs; falls back to the
  # main chat if not configured, so the alert is never lost.
  OWNER_CH="${TELEGRAM_OWNER_CHAT_ID:-$CH}"
  TGLOG="$DIR/logs/telegram.log"

  # ---- VERDICT GATE ----------------------------------------------------------
  # Only an OK verdict ships the polished report+Excel to stakeholders. A SUSPECT/BROKEN
  # run is HELD BACK and the owner gets a short alert instead (never the garbage report).
  if [ "$VERDICT" != "OK" ] && [ -n "$TG" ] && [ -n "$OWNER_CH" ]; then
    STAMP="$(date '+%Y-%m-%d %H:%M:%S')"
    REASONS="$(python3 - "$DIR/reviews/${P}-${RUN_ID}.json" <<'PYEOF' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    rs = d.get("reasons") or []
    print("; ".join(rs[:4]) if rs else "(no reason recorded)")
except Exception:
    print("(verdict file unreadable)")
PYEOF
)"
    ALERT="⚠️ Jivo × ${P} — run ${RUN_ID} verdict=${VERDICT}. HELD BACK from stakeholder delivery (not shipped).
${REASONS}"
    RA="$(curl -s --max-time 60 -X POST "https://api.telegram.org/bot${TG}/sendMessage" \
            --data-urlencode "chat_id=${OWNER_CH}" \
            --data-urlencode "text=${ALERT}")"
    echo "[$STAMP] $P HELD ($VERDICT) owner-alert -> $RA" >> "$TGLOG"
  elif [ "$VERDICT" = "OK" ] && [ -n "$TG" ] && [ -n "$CH" ]; then
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
  # Serialize the whole git critical section across concurrent run.sh instances
  # (run_all.sh launches platforms in parallel). flock holds the lock for this
  # subshell's lifetime; if flock is missing it no-ops and we degrade to the old
  # racy-but-retrying behavior rather than failing the run.
  exec 9>"$DIR/.gitpush.lock"
  command -v flock >/dev/null 2>&1 && flock 9
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
