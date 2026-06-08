#!/usr/bin/env bash
# tools/cron/safe_fixes/unhold_false_positive.sh <platform>
#
# SAFE-FIX #1 — auto-unhold a platform that was HELD by a KNOWN false-positive review
# flag, after PROVING with the committed review.py logic that the data is actually clean.
#
# Trigger (the agent picks this only when ALL hold):
#   - <platform>'s latest committed review verdict is SUSPECT/BROKEN (held), AND
#   - EVERY held reason is one of the two KNOWN false-positive classes:
#       shared_price_dup  (seller-duplicate / combo listings counted as distinct SKUs)
#       price_staleness   (stable prices on the realtime path WITH movers present)
#     (the exact two fixed 2026-06-08 — review-cal commit a4bce2db / unhold f8277636).
#
# What it does (deterministic, idempotent, self-verifying):
#   1. Re-run review.py on the SAME (unchanged) result.json with a synthetic -unhold
#      RUN_ID, using the now-committed identity-/mover-aware logic.
#   2. If the fresh verdict is OK with ZERO reasons -> the hold WAS a false positive.
#      Rebuild the Excel from that result.json and DELIVER:
#        - inside a deadline sweep (SWEEP_ID set) -> SPOOL into the batch (send_batch
#          ships it timely to stakeholders), else
#        - after-the-fact -> send the recovered workbook to the OWNER channel with a
#          clear "false-positive hold, re-verified OK" note (no unattended stale blast
#          to stakeholders).
#   3. ANY ambiguity (verdict not OK, new reasons appear, a non-FP reason was present,
#      result.json changed/unreadable, build failed) -> exit 1 => PROPOSE-ONLY.
#
# Blast radius: re-reads existing result.json, writes a reviews/*-unhold.json verdict,
# rebuilds ONE workbook, and either spools a batch file or sends ONE owner/stakeholder
# message. NO scrape. NO push. Re-runnable: a delivery marker prevents double-send.

SF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SF_DIR/_common.sh"

P="${1:?usage: unhold_false_positive.sh <platform>}"
PDIR="$REPO/platforms/$P"
[ -d "$PDIR" ] || ambiguous "no such platform dir: $PDIR"

RESULT="$PDIR/result.json"
[ -s "$RESULT" ] || ambiguous "$P: result.json missing/empty — nothing to re-verify"

log "BEGIN unhold check for $P"

# --- 1. The platform must currently be HELD for a KNOWN false-positive reason -------
LATEST="$(latest_review_file "$P")"
[ -n "$LATEST" ] || ambiguous "$P: no prior review verdict found — cannot confirm it is held"
PREV_VERDICT="$(verdict_of "$LATEST")"
log "$P latest committed verdict = $PREV_VERDICT ($(basename "$LATEST"))"

if [ "$PREV_VERDICT" = "OK" ]; then
  ambiguous "$P: latest verdict is already OK — not held, nothing to unhold"
fi

# Every held reason must be a KNOWN false-positive class. One stranger => propose-only.
mapfile -t REASONS < <(reasons_of "$LATEST")
[ "${#REASONS[@]}" -gt 0 ] || ambiguous "$P: held ($PREV_VERDICT) but no reasons recorded — unknown cause, propose-only"
for r in "${REASONS[@]}"; do
  if reason_is_known_fp "$r"; then
    log "  known-FP reason OK to attempt: ${r%%:*}"
  else
    ambiguous "$P: held reason is NOT a known false-positive class: '${r%%:*}' (full: $r)"
  fi
done

# --- Idempotency: don't re-deliver if we already unheld this result today ------------
RESULT_MTIME="$(date -r "$RESULT" '+%Y%m%d%H%M%S' 2>/dev/null || echo 0)"
MARKER="$DOCTOR_LOG_DIR/.unheld-$P-$RESULT_MTIME"
if [ -f "$MARKER" ]; then
  ok_done "$P: already unheld+delivered for this result.json (mtime $RESULT_MTIME) — idempotent no-op"
fi

# --- 2. Re-run review.py with the committed logic on the SAME data -------------------
UNHOLD_RID="$(date_tag)-doctor"
log "$P: re-running review.py with committed logic (RUN_ID=$UNHOLD_RID) ..."
( cd "$REPO" && python3 tools/review.py "$P" "$UNHOLD_RID" ) >>"$SAFE_FIX_LOG" 2>&1 || true
NEW_VERDICT_FILE="$REPO/reviews/$P-$UNHOLD_RID.json"
[ -s "$NEW_VERDICT_FILE" ] || ambiguous "$P: re-review produced no verdict file"

NEW_VERDICT="$(verdict_of "$NEW_VERDICT_FILE")"
mapfile -t NEW_REASONS < <(reasons_of "$NEW_VERDICT_FILE")
log "$P: re-review verdict = $NEW_VERDICT, reasons=${#NEW_REASONS[@]}"

if [ "$NEW_VERDICT" != "OK" ] || [ "${#NEW_REASONS[@]}" -ne 0 ]; then
  ambiguous "$P: re-review did NOT come back clean OK (verdict=$NEW_VERDICT, ${#NEW_REASONS[@]} reason(s)) — NOT a confirmed false positive; propose-only"
fi
log "$P: CONFIRMED false positive — clean OK on committed logic. Proceeding to rebuild + deliver."

# --- 3a. Rebuild the workbook from the existing result.json (best-effort chain) ------
log "$P: rebuilding Excel from existing result.json (no scrape) ..."
(
  cd "$PDIR"
  python3 build_excel.py
) >>"$SAFE_FIX_LOG" 2>&1 || ambiguous "$P: build_excel.py failed during rebuild"

XLSX="$(ls -t "$PDIR"/Jivo-*.xlsx 2>/dev/null | head -1)"
[ -n "$XLSX" ] && [ -s "$XLSX" ] || ambiguous "$P: no workbook produced by rebuild"

# Optional sheets — mirror run.sh, all best-effort (never abort the fix).
( cd "$REPO" && python3 tools/predict.py "$P" "$XLSX" ) >>"$SAFE_FIX_LOG" 2>&1 || true
[ -f "$REPO/tools/pricematch/add_pricematch_sheet.py" ] && \
  ( cd "$REPO" && python3 tools/pricematch/add_pricematch_sheet.py "$P" "$XLSX" ) >>"$SAFE_FIX_LOG" 2>&1 || true
[ -f "$REPO/tools/report_dashboard.py" ] && \
  ( cd "$REPO" && python3 tools/report_dashboard.py "$P" "$XLSX" ) >>"$SAFE_FIX_LOG" 2>&1 || true
mkdir -p "$REPO/output" && cp "$PDIR"/Jivo-*.xlsx "$REPO/output/" 2>/dev/null || true
XLSX="$(ls -t "$PDIR"/Jivo-*.xlsx 2>/dev/null | head -1)"
ROWS="$(python3 -c "import json;print(json.load(open('$NEW_VERDICT_FILE')).get('rows','?'))" 2>/dev/null || echo '?')"
log "$P: workbook rebuilt -> $(basename "$XLSX") (rows=$ROWS)"

# --- 3b. Deliver ---------------------------------------------------------------------
# In a deadline sweep -> spool for send_batch (timely, stakeholders, canonical order).
if [ "${DEFER_DELIVERY:-}" = "1" ] && [ -n "${SWEEP_ID:-}" ]; then
  BDIR="$REPO/output/.batch/${SWEEP_ID}"
  mkdir -p "$BDIR"
  python3 - "$P" "$XLSX" "$ROWS" "$BDIR/${P}.json" <<'PY' >>"$SAFE_FIX_LOG" 2>&1 || ambiguous "$P: batch spool write failed"
import json, sys, os
p, xlsx, rows, out = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
if not (xlsx and os.path.exists(xlsx)):
    raise SystemExit(f"spool: xlsx missing: {xlsx!r}")
cap = (f"Jivo × {p} — recovered report ({rows} rows). "
       "Was held by a FALSE-POSITIVE review flag; re-verified OK by the Ecom Doctor.")
tmp = out + ".tmp"
json.dump({"platform": p, "verdict": "OK", "summary": cap, "xlsx": xlsx,
           "caption": cap, "doctor_unhold": True}, open(tmp, "w"))
os.replace(tmp, out)
print("spooled", out)
PY
  touch "$MARKER"
  ok_done "$P: false-positive hold CLEARED; recovered report SPOOLED into batch ${SWEEP_ID} (send_batch will ship it timely)."
fi

# After-the-fact (not in a sweep): notify the OWNER with the recovered workbook. No
# unattended stale blast to stakeholders — the owner reviews + forwards if still useful.
[ -f "$REPO/secrets.env" ] && . "$REPO/secrets.env" 2>/dev/null || true
TG="${TELEGRAM_BOT_TOKEN:-}"
OWNER_CH="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
CAPTION="✅ Ecom Doctor: ${P} false-positive hold CLEARED.
Latest sweep held it (${PREV_VERDICT}: ${REASONS[0]%%:*}…) but the committed review logic re-verifies it OK (${ROWS} rows). Recovered workbook attached for your review/forward."

if is_dry; then
  log "$P: [DRY] would send recovered workbook to owner channel; marking delivered."
  touch "$MARKER"
  ok_done "$P: false-positive hold CLEARED (DRY — no real Telegram). Workbook at $XLSX"
fi

if [ -z "$TG" ] || [ -z "$OWNER_CH" ]; then
  log "$P: Telegram creds absent — workbook rebuilt + re-verified OK at $XLSX, but not sent."
  touch "$MARKER"
  ok_done "$P: false-positive hold CLEARED (no TG creds; workbook ready at $XLSX for manual send)."
fi

R="$(curl -s --max-time 120 -X POST "https://api.telegram.org/bot${TG}/sendDocument" \
      -F "chat_id=${OWNER_CH}" -F "caption=${CAPTION}" \
      -F "document=@${XLSX}" 2>>"$SAFE_FIX_LOG" || true)"
if echo "$R" | grep -q '"ok":true'; then
  touch "$MARKER"
  ok_done "$P: false-positive hold CLEARED; recovered workbook sent to owner channel."
else
  log "$P: owner Telegram send failed (resp: ${R:0:160}) — workbook ready at $XLSX"
  # Delivery failed but the diagnosis stands; do NOT mark delivered so a retry can send.
  ambiguous "$P: unhold verified OK but delivery FAILED — propose-only (manual send needed)"
fi
