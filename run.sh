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

# ---- Per-pincode coverage (Wave-1 QC: blinkit/zepto/flipkart-minutes). Opt-in via COVERAGE_FULL=1. ----
# When COVERAGE_FULL=1 and no explicit PINCODES_FILE is set, point the scraper at the
# full 25-city per-pincode config (pincodes.full25.json, 1,885 pins) instead of the
# anchor config. An operator may instead pass their own PINCODES_FILE (e.g. a zero-cities
# subset) — we honor it. Either way a relative PINCODES_FILE is normalized to an absolute
# path because the scraper runs with cwd=$PDIR. Flag unset = byte-for-byte unchanged
# (anchor pincodes.json). This NEVER touches pincodes.json (the rollback anchor).
if [ "$P" = "blinkit" ] || [ "$P" = "zepto" ] || [ "$P" = "flipkart-minutes" ]; then
  if [ -n "${PINCODES_FILE:-}" ]; then
    case "$PINCODES_FILE" in /*) ;; *) PINCODES_FILE="$DIR/$PINCODES_FILE";; esac
    export PINCODES_FILE
  elif [ "${COVERAGE_FULL:-0}" = "1" ] && [ -f "$PDIR/pincodes.full25.json" ]; then
    export PINCODES_FILE="$PDIR/pincodes.full25.json"
  fi
  [ -n "${PINCODES_FILE:-}" ] && echo "[$RUN_ID] $P PINCODES_FILE=$PINCODES_FILE"
fi
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

# ---- Price Match sheet: live vs our reference for today's regime (best-effort). ----
# Guarded: if the tool is absent this is a no-op and behavior is exactly as before.
[ -f "$DIR/tools/pricematch/add_pricematch_sheet.py" ] && python3 "$DIR/tools/pricematch/add_pricematch_sheet.py" "$P" "$(ls -t "$PDIR"/Jivo-*.xlsx | head -1)" 2>>"$DIR/logs/${P}-${RUN_ID}.log" || true

# ---- Leadership View: regenerate the FIRST sheet LAST (best-effort). ----
# MUST stay the final workbook-touching step: it redraws the chart-free durable
# dashboard so no earlier openpyxl round-trip / viewer quirk can blank page 1.
[ -f "$DIR/tools/report_dashboard.py" ] && python3 "$DIR/tools/report_dashboard.py" "$P" "$(ls -t "$PDIR"/Jivo-*.xlsx | head -1)" 2>>"$DIR/logs/${P}-${RUN_ID}.log" || true
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

# ---- AUTO-HEAL (Amazon canonical-collision) — reactive, identity-only. -------
# If an Amazon report is about to be HELD *solely* on the shared_price_dup
# canonical-collision flag, wake Claude to merge stub canonicals into their real
# product (rewrites identity only — NEVER a price), rebuild the report, and
# re-review. On success the verdict flips SUSPECT->OK right here, so the clean
# report ships on the normal OK path below and history.csv is appended clean.
# Scoped + best-effort: a no-op for non-Amazon / non-SUSPECT / any other reason,
# and can NEVER fail the run (set -e safe). See tools/autoheal_amazon.py + spec
# docs/superpowers/specs/2026-06-13-amazon-canonical-autoheal-design.md.
case "$P" in
  amazon-now|amazon|amazon-fresh)
    if [ "$VERDICT" = "SUSPECT" ] && [ -f "$DIR/tools/autoheal_amazon.py" ]; then
      echo "[$RUN_ID] $P SUSPECT -> auto-heal adjudication (Amazon canonical-collision)"
      python3 "$DIR/tools/autoheal_amazon.py" "$P" "$RUN_ID" >>"$DIR/logs/autoheal.log" 2>&1 || true
      # re-read the verdict the auto-heal's fresh review may have rewritten to OK
      VERDICT="$(python3 - "$DIR/reviews/${P}-${RUN_ID}.json" <<'PYEOF' 2>/dev/null || echo "$VERDICT"
import json, sys
print((json.load(open(sys.argv[1])).get("verdict") or "BROKEN").upper())
PYEOF
)"
      echo "[$RUN_ID] $P post-auto-heal verdict = $VERDICT"
    fi
    ;;
esac

# ---- Vault: append this run's COMPLETE rows to data/<P>/history.csv. ----
# Note generation is NOT done here: the whole Obsidian graph (complete run notes +
# SKU/city/pincode hubs + MOCs + rollups + index) is rebuilt once per sweep by
# tools/vault_build.py in run_all.sh, after all platforms finish. So we only persist
# the machine-readable rows here (--csv-only) — the vault is complete-by-construction
# and never holds a summarized note. (Drop --csv-only to also write a standalone note.)
echo "[$RUN_ID] appending history.csv ..."
python3 "$DIR/tools/vault_note.py" "$P" "$RUN_ID" --csv-only || echo "vault_note failed (non-fatal)" >&2

# ---- Coverage ledger (Wave-1 QC: blinkit/zepto/flipkart-minutes): classify every CONFIGURED pincode. ----
# Best-effort + gated on COVERAGE_FULL so default runs are unchanged. Derives an honest
# per-pincode status (price_captured / serviceable_no_jivo / not_serviceable) from the
# history rows this run just appended + the config that was actually scraped.
if { [ "$P" = "blinkit" ] || [ "$P" = "zepto" ] || [ "$P" = "flipkart-minutes" ]; } && [ "${COVERAGE_FULL:-0}" = "1" ]; then
  CFG_USED="${PINCODES_FILE:-$PDIR/pincodes.full25.json}"
  echo "[$RUN_ID] emitting coverage ledger from history (config=$CFG_USED) ..."
  python3 "$DIR/tools/coverage/emit_ledger_from_history.py" "$P" "$RUN_ID" "$(date +%F)" \
    "$DIR/data/$P/history.csv" "$CFG_USED" "$DIR/data/coverage/ledger.csv" "$PDIR/result.json" || true
fi

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
    # DEFER MODE (cron-deadline): the owner alert above already went out immediately
    # (owner wants problems early); additionally spool a held-marker so the sweep's
    # batch delivery (tools/cron/send_batch.py) can list this platform in its footer.
    # Entirely inert unless DEFER_DELIVERY=1 and SWEEP_ID are set by the caller.
    if [ "${DEFER_DELIVERY:-}" = "1" ] && [ -n "${SWEEP_ID:-}" ]; then
      BDIR="$DIR/output/.batch/${SWEEP_ID}"
      mkdir -p "$BDIR" 2>>"$TGLOG"
      if REASONS="$REASONS" python3 - "$P" "$VERDICT" "$BDIR/${P}.json" 2>>"$TGLOG" <<'SPOOLPY'
import json, os, sys, time
p, verdict, out = sys.argv[1], sys.argv[2], sys.argv[3]
tmp = out + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump({"platform": p, "verdict": verdict, "held": True,
               "reasons": os.environ.get("REASONS", ""),
               "ts": int(time.time())}, f, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, out)  # atomic: send_batch never sees a half-written file
SPOOLPY
      then
        echo "[$STAMP] $P held-marker spooled -> $BDIR/${P}.json" >> "$TGLOG"
      else
        echo "[$STAMP] $P held-marker spool write FAILED (owner alert already sent)" >> "$TGLOG"
      fi
    fi
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

      # ---- DEFER MODE (cron-deadline): spool instead of send ----------------------
      # When DEFER_DELIVERY=1 and SWEEP_ID are set by the caller (run_all.sh deadline
      # sweep), the OK report is NOT curled now; it's spooled to output/.batch/<sweep>/
      # so tools/cron/send_batch.py can deliver the whole sweep at the slot deadline.
      # SUMMARY above is computed EXACTLY as in immediate mode. Any spool failure falls
      # back to the immediate-send path below — a report is never lost. With the env
      # vars unset this block is a no-op and delivery is byte-for-byte today's.
      DEFERRED=0
      if [ "${DEFER_DELIVERY:-}" = "1" ] && [ -n "${SWEEP_ID:-}" ]; then
        BDIR="$DIR/output/.batch/${SWEEP_ID}"
        mkdir -p "$BDIR" 2>>"$TGLOG"
        if SUMMARY="$SUMMARY" XLSX="$XLSX" python3 - "$P" "$DISP" "$RDATE" "$BDIR/${P}.json" 2>>"$TGLOG" <<'SPOOLPY'
import json, os, sys, time
p, disp, rdate, out = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
xlsx = os.environ["XLSX"]
if not (xlsx and os.path.isfile(xlsx)):
    raise SystemExit(f"spool: xlsx missing: {xlsx!r}")
tmp = out + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump({"platform": p, "verdict": "OK",
               "summary": os.environ["SUMMARY"],
               "xlsx": os.path.abspath(xlsx),
               "caption": f"Jivo × {disp} · {rdate}",
               "ts": int(time.time())}, f, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, out)  # atomic: send_batch never sees a half-written file
SPOOLPY
        then
          DEFERRED=1
          echo "[$STAMP] $P OK spooled for batch -> $BDIR/${P}.json (sweep ${SWEEP_ID})" >> "$TGLOG"
        else
          echo "[$STAMP] $P spool write FAILED -> falling back to immediate send" >> "$TGLOG"
        fi
      fi

      if [ "$DEFERRED" != "1" ]; then
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
      fi
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
  git add vault data reviews baselines docs README.md REPORT.md CLAUDE.md >/dev/null 2>&1
  git add platforms/*/pincodes.full25.json >/dev/null 2>&1 || true
  if ! git diff --cached --quiet; then
    git commit -m "run: $P $RUN_ID" >/dev/null 2>&1
    git pull --rebase --autostash >/dev/null 2>&1
    git push >/dev/null 2>&1 || { git pull --rebase --autostash >/dev/null 2>&1; git push >/dev/null 2>&1; }
    echo "[$RUN_ID] $P committed + pushed."
  else
    echo "[$RUN_ID] $P nothing new to commit."
  fi
) || true
