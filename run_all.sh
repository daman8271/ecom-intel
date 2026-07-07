#!/usr/bin/env bash
# run_all.sh — one cron-triggered sweep: scrape every LIVE platform SERIALLY (one at a time;
#  REMOVED from the chain 2026-06-06 — WAF-dead, rebuild pending),
# then run the self-heal pass.
#
# SERIAL (not parallel) — accuracy over speed. Launching all 9 at once STARVED each scraper
# (CPU/network contention -> thin, partial data the hardened review.py correctly rejects) and
# made the 3 Amazon storefronts thrash their one shared account/server-side location. One
# platform at a time: each gets full resources, re-resolves its store cleanly (full coverage),
# and the Amazon trio can never overlap. Slower wall-clock (~1-1.5h), but correct + complete —
# a 2x/day window (10:00 + 15:00, 5h apart) has the headroom. Each ./run.sh is self-contained
# (scrape -> excel -> predict -> review -> vault -> telegram[verdict-gated] -> git push);
# per-platform stdout goes to logs/run-<p>.out.
#
# NOTE (2026-06-28): the pipeline is now 1×/day — a SINGLE 12:00-noon sweep. The "2x/day /
# 10:00+15:00 / 12:00+15:00" framing in some comments below is retained as historical rationale
# for the .sweep-chain.lock overlap guard, which now rarely engages (no afternoon sweep) but is
# kept as an inert backstop.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
echo "[$(date '+%F %T')] run_all: START (serial — accuracy first)"
# Order: quick/light platforms first so their clean reports land early; the Amazon trio runs
# consecutively (serial guarantees no shared-account overlap). Blinkit is no longer in this
# VPS chain; it runs off-box on the Mac Pro/residential IP and feeds the batch through
# platforms/blinkit/ingest.sh.
#
# Overrides (for the cron-deadline simulation harness ONLY — both UNSET in production, which
# leaves the loop byte-for-byte identical to before):
#   PLATFORMS_OVERRIDE — space-separated platform list replacing the default 9
#   RUNNER_OVERRIDE    — command run instead of ./run.sh (word-split on purpose: may carry args)
# PHASE 2 SPLIT (owner-approved 2026-07-07): flipkart + zepto now scrape OFF-BOX on
# KVM1 at store-open hours (~07:30 IST; tools/cron/kvm1_trio_launch.sh fires the box,
# bin/kvm1_run_trio.sh there scrapes serially and dead-drops results back through
# tools/cron/kvm1_ingest.sh -> run.sh SCRAPE_RESULT_DROP -> the same review gates +
# batch spool). flipkart-minutes STAYS in this chain (its logged-in Flipkart API is
# DC-bound: from KVM1's IP the northern pincodes 302 to another DC and return 0 rows
# — smoke-tested 2026-07-07). It runs FIRST (fast, ~2m, store-open hours), then the
# Amazon family serially on this ONE IP so the Amazon tarpit is never poked from
# multiple addresses. Fallbacks if KVM1 dies: tools/cron/kvm1_watchdog.sh +
# flipkart_batch_guard.sh re-run the missing platforms locally (this box still can).
PLATFORMS="${PLATFORMS_OVERRIDE:-flipkart-minutes amazon amazon-fresh amazon-now}"  # kvm1: flipkart zepto · macpro: blinkit bigbasket swiggy (ingest.sh feeders)
RUNNER="${RUNNER_OVERRIDE:-./run.sh}"
# SIM MODE hard gate (LEAD ruling): ANY override set => this is the simulation harness, NOT a
# production sweep. Skip everything that touches live platforms or shared state: the per-platform
# guardian.py (undefined on fake platforms), healthcheck.sh -> selfheal (would RE-RUN REAL
# platforms on staleness/BROKEN = live scrapes), vault_build.py, and the final git block.
# The send_batch barrier still runs — it is exactly what the sim exercises.
SIM_MODE=0
if [ -n "${PLATFORMS_OVERRIDE:-}" ] || [ -n "${RUNNER_OVERRIDE:-}" ]; then
  SIM_MODE=1
  echo "[$(date '+%F %T')] run_all: SIM MODE (override set) — guardian/healthcheck/vault/git SKIPPED"
fi
# ---- SWEEP-CHAIN LOCK (W2 mitigation, LEAD-approved 2026-06-06) --------------
# Historically the deadline slots 12:00 + 15:00 were only 3h apart (now a single
# 10:00 slot, 2026-07-03): an overrunning prior chain
# (in-chain guardian heal re-runs are not priced into the p90 lead) could still
# be scraping when this sweep's chain starts — two serial chains co-running
# defeats the whole serial design. One mechanism guards both that and the
# post-batch selfheal backstop (gated below on the SAME lock): the PLATFORM
# LOOP ONLY runs under a BLOCKING flock on logs/.sweep-chain.lock, released
# before the batch barrier (the deadline sleep must never hold the chain mutex).
# Manual ./run_all.sh takes it too (manual-vs-cron protection); SIM MODE takes
# it as well (harmless — fake platforms still shouldn't co-run a real chain).
# If the lock can't be had in 9000s (2h30m — a full healthy chain + slack), we
# NEVER scrape concurrently: log + owner-alert + SKIP the chain; send_batch
# still ships an honest (empty/partial) batch at the deadline. No flock binary /
# unopenable lockfile degrades to the old unlocked behavior rather than failing.
SWEEP_CHAIN_LOCK="$DIR/logs/.sweep-chain.lock"
mkdir -p "$DIR/logs" 2>/dev/null || true
HAVE_CHAIN_LOCK=0
CHAIN_SKIPPED=0
if command -v flock >/dev/null 2>&1; then
  if exec 7>"$SWEEP_CHAIN_LOCK" 2>/dev/null; then
    HAVE_CHAIN_LOCK=1
    if ! flock -n 7; then
      echo "[$(date '+%F %T')] run_all: waiting for prior sweep chain (logs/.sweep-chain.lock held)"
      if ! flock -w 9000 7; then
        CHAIN_SKIPPED=1
        echo "[$(date '+%F %T')] run_all: sweep-chain lock NOT acquired in 9000s -> SKIPPING the chain (never scrape concurrently)"
        ( # owner alert — same secrets.env pattern as run.sh; best-effort, never fails the sweep
          set +e
          [ -f "$DIR/secrets.env" ] && . "$DIR/secrets.env"
          TG="${TELEGRAM_BOT_TOKEN:-}"; OC="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
          [ -n "$TG" ] && [ -n "$OC" ] && curl -s --max-time 60 -X POST "https://api.telegram.org/bot${TG}/sendMessage" \
            --data-urlencode "chat_id=${OC}" \
            --data-urlencode "text=⚠️ ecom-intel run_all: sweep-chain lock busy >2h30m — chain SKIPPED for sweep ${SWEEP_ID:-manual} (a prior sweep is still scraping). The batch will be empty/partial; investigate the stuck chain." >/dev/null
        ) || true
      fi
    fi
  else
    echo "[$(date '+%F %T')] run_all: cannot open $SWEEP_CHAIN_LOCK — degrading to unlocked (old behavior)"
  fi
fi

if [ "$CHAIN_SKIPPED" != "1" ]; then
for P in $PLATFORMS; do
  echo "[$(date '+%F %T')] run_all: running $P (serial)"
  # AUTO-HEAL HOOK: after this platform's pipeline, the guardian re-evaluates the fresh
  # result.json (CALLs tools/review.py for the shared checks + its independent 11-bug-class deep
  # checks). On BROKEN -> QUARANTINE (keep last-good, nothing published — Telegram is already
  # verdict-gated) + bounded --heal retry + owner alert. Best-effort `|| true` so a guardian
  # hiccup can never fail the sweep. In SIM MODE the guardian is skipped (fake platforms).
  P_START="$(date +%s)"
  if [ "$SIM_MODE" = "1" ]; then
    ( $RUNNER "$P" ) >> "logs/run-${P}.out" 2>&1
  else
    # Guardian only after a CLEAN pipeline exit (2026-06-10): a failed run.sh (e.g. scrape
    # FATAL) leaves the PREVIOUS run's result.json on disk, and evaluating that re-blesses
    # STALE data into the last-good snapshot (bit amazon-now 2026-06-10: false session-expiry
    # abort + a 21.5h-old result.json — under guardian's 24h freshness bar, so it passed).
    # Staleness/recovery after a failed scrape belongs to the healthcheck/selfheal backstop.
    (
      if $RUNNER "$P"; then
        python3 tools/guardian.py "$P" --heal || true
      else
        rc=$?
        echo "[$(date '+%F %T')] run_all: $P pipeline FAILED (rc=$rc) -> inline guardian SKIPPED (stale result.json must not refresh last-good; healthcheck backstop owns recovery)"
      fi
    ) >> "logs/run-${P}.out" 2>&1
  fi
  P_END="$(date +%s)"
  # Duration ledger for the deadline scheduler (W1's tools/cron). Best-effort, only if the
  # recorder exists; sweep_id falls back to "adhoc" on manual runs without SWEEP_ID.
  if [ -f tools/cron/record_duration.sh ]; then
    bash tools/cron/record_duration.sh "$P" "$((P_END - P_START))" "${SWEEP_ID:-adhoc}" || true
  fi
done
fi  # end CHAIN_SKIPPED guard
# Release the sweep-chain lock BEFORE the batch barrier: the deadline sleep in
# send_batch.py (up to ~55m) must never hold the chain mutex — the next sweep's
# chain only has to wait for SCRAPING, never for a barrier.
if [ "$HAVE_CHAIN_LOCK" = "1" ]; then
  exec 7>&- 2>/dev/null || true
fi
if [ "$CHAIN_SKIPPED" = "1" ]; then
  echo "[$(date '+%F %T')] run_all: chain was SKIPPED (sweep-chain lock busy) -> straight to barrier"
else
  echo "[$(date '+%F %T')] run_all: all platforms done -> self-heal pass"
fi

# ---- PRICE-MATCH master workbook (SHEETS-B) ----------------------------------
# BigBasket national workbook — scraped off-box and ingested into output/.
# The pincode workbook is private/direct-only and must not be spooled into the
# Ecom group batch, even if a stale copy appears in output/.
if [ "$SIM_MODE" != "1" ] && [ "$CHAIN_SKIPPED" != "1" ] && [ "${DEFER_DELIVERY:-}" = "1" ] && [ -n "${SWEEP_ID:-}" ]; then
  BB_RPT="$DIR/output/Jivo-Bigbasket-Live-Report-$(date +%F).xlsx"
  BB_SUM="$DIR/platforms/bigbasket/result.json"
  BB_KIND="national"
  if [ -n "$BB_RPT" ] && [ -f "$BB_RPT" ]; then
    BBDIR="$DIR/output/.batch/${SWEEP_ID}"; mkdir -p "$BBDIR" 2>>logs/telegram.log
    BB_RPT="$BB_RPT" BB_SUM="$BB_SUM" BB_KIND="$BB_KIND" python3 - "$BBDIR/bigbasket.json" 2>>logs/telegram.log <<'BBSPOOL'
import json, os, sys, time
out = sys.argv[1]; xlsx = os.path.abspath(os.environ["BB_RPT"])
s = {}
try:
    s = json.load(open(os.environ["BB_SUM"]))["summary"]
except Exception:
    pass
date = (s.get("captured_at", "") or "")[:10] or time.strftime("%Y-%m-%d")
kind = os.environ.get("BB_KIND", "Mac browser")
summ = (f"*BigBasket — {kind}*\n{date}\n"
        f"{s.get('pincodes_with_jivo','?')}/{s.get('pincodes_total','?')} pincodes carry Jivo · "
        f"{s.get('unique_skus','?')} SKUs · {s.get('total_rows','?')} datapoints")
tmp = out + ".tmp"
json.dump({"platform": "bigbasket", "verdict": "OK", "summary": summ, "xlsx": xlsx,
           "caption": f"Jivo x BigBasket · {date}", "ts": int(time.time())},
          open(tmp, "w"), ensure_ascii=False)
os.replace(tmp, out)
BBSPOOL
    echo "[$(date '+%F %T')] run_all: bigbasket ($BB_KIND) spooled for batch -> $BBDIR/bigbasket.json (sweep ${SWEEP_ID})"
  else
    echo "[$(date '+%F %T')] run_all: bigbasket report not in output/ — skipped (Mac drop late/absent)"
  fi
fi

# Swiggy Instamart — scraped OFF-BOX on a residential IP (Mac launchd @02:30 IST; this
# VPS datacenter IP is WAF-blocked on Swiggy's search endpoint) and dropped+ingested into
# output/ by ~04:00. Spool the day's report into THIS sweep's batch so it lands WITH the
# other platforms in BOTH the 12:00 and 15:00 batches (no scrape here). Skipped if absent.
if [ "$SIM_MODE" != "1" ] && [ "$CHAIN_SKIPPED" != "1" ] && [ "${DEFER_DELIVERY:-}" = "1" ] && [ -n "${SWEEP_ID:-}" ]; then
  SI_RPT="$DIR/output/Jivo-SwiggyInstamart-Live-Report-$(date +%F).xlsx"   # today's, by date
  if [ -n "$SI_RPT" ] && [ -f "$SI_RPT" ]; then
    SIDIR="$DIR/output/.batch/${SWEEP_ID}"; mkdir -p "$SIDIR" 2>>logs/telegram.log
    SI_RPT="$SI_RPT" SI_SUM="$DIR/platforms/swiggy-instamart/result.json" python3 - "$SIDIR/swiggy-instamart.json" 2>>logs/telegram.log <<'SISPOOL'
import json, os, sys, time
out = sys.argv[1]; xlsx = os.path.abspath(os.environ["SI_RPT"])
s = {}
try:
    s = json.load(open(os.environ["SI_SUM"]))["summary"]
except Exception:
    pass
date = (s.get("captured_at", "") or "")[:10] or time.strftime("%Y-%m-%d")
summ = (f"*Swiggy Instamart — residential-IP collector*\n{date}\n"
        f"{s.get('pincodes_with_jivo','?')}/{s.get('pincodes_total','?')} pincodes carry Jivo · "
        f"{s.get('unique_skus','?')} SKUs · {s.get('total_rows','?')} datapoints")
tmp = out + ".tmp"
json.dump({"platform": "swiggy-instamart", "verdict": "OK", "summary": summ, "xlsx": xlsx,
           "caption": f"Jivo x Swiggy Instamart · {date}", "ts": int(time.time())},
          open(tmp, "w"), ensure_ascii=False)
os.replace(tmp, out)
SISPOOL
    echo "[$(date '+%F %T')] run_all: swiggy-instamart spooled for batch -> $SIDIR/swiggy-instamart.json (sweep ${SWEEP_ID})"
  else
    echo "[$(date '+%F %T')] run_all: swiggy-instamart report not in output/ — skipped (residential drop late/absent)"
  fi
fi

# Blinkit — scraped OFF-BOX on the Mac Pro/residential IP and dropped+ingested into
# output/. It used to be the slowest platform in the VPS serial chain; keep it out of
# that chain, but spool the vetted Mac workbook into this deadline batch if present.
if [ "$SIM_MODE" != "1" ] && [ "$CHAIN_SKIPPED" != "1" ] && [ "${DEFER_DELIVERY:-}" = "1" ] && [ -n "${SWEEP_ID:-}" ]; then
  BI_RPT="$DIR/output/Jivo-Blinkit-Live-Report-$(date +%F).xlsx"
  if [ -n "$BI_RPT" ] && [ -f "$BI_RPT" ]; then
    BI_SENT="$DIR/logs/blinkit-main-wa-$(date +%F).sent"
    if [ -f "$BI_SENT" ]; then
      echo "[$(date '+%F %T')] run_all: blinkit already sent direct WhatsApp ($BI_SENT) — skipped batch spool for $BI_RPT"
    elif ! BLINKIT_MONITOR_DRYRUN=1 \
         BLINKIT_MONITOR_EXIT_CODE=1 \
         BLINKIT_MONITOR_DATE="$(date +%F)" \
         BLINKIT_MONITOR_REPORT="$BI_RPT" \
         ./tools/cron/blinkit_quality_monitor.sh pre-batch; then
      echo "[$(date '+%F %T')] run_all: blinkit quality gate failed — skipped batch spool for $BI_RPT"
      (
        set +e
        [ -f "$DIR/secrets.env" ] && . "$DIR/secrets.env"
        TG="${TELEGRAM_BOT_TOKEN:-}"; OC="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
        [ -n "$TG" ] && [ -n "$OC" ] && curl -s --max-time 60 -X POST "https://api.telegram.org/bot${TG}/sendMessage" \
          --data-urlencode "chat_id=${OC}" \
          --data-urlencode "text=⚠️ Blinkit held back from ${SWEEP_ID:-deadline} batch: quality gate failed for $(basename "$BI_RPT"). It was not spooled for send_batch/WhatsApp." >/dev/null
      ) || true
    else
    BIDIR="$DIR/output/.batch/${SWEEP_ID}"; mkdir -p "$BIDIR" 2>>logs/telegram.log
    BI_RPT="$BI_RPT" BI_SUM="$DIR/platforms/blinkit/result.json" python3 - "$BIDIR/blinkit.json" 2>>logs/telegram.log <<'BISPOOL'
import json, os, sys, time
out = sys.argv[1]; xlsx = os.path.abspath(os.environ["BI_RPT"])
s = {}
try:
    s = json.load(open(os.environ["BI_SUM"], encoding="utf-8"))["summary"]
except Exception:
    pass
date = (s.get("captured_at", "") or "")[:10] or time.strftime("%Y-%m-%d")
summ = (f"*Blinkit — Mac Pro residential-IP collector*\n{date}\n"
        f"{s.get('pincodes_with_jivo','?')}/{s.get('pincodes_total','?')} pincodes carry Jivo · "
        f"{s.get('unique_skus','?')} SKUs · {s.get('total_rows','?')} datapoints")
tmp = out + ".tmp"
json.dump({"platform": "blinkit", "verdict": "OK", "summary": summ, "xlsx": xlsx,
           "caption": f"Jivo x Blinkit · {date}", "ts": int(time.time())},
          open(tmp, "w"), ensure_ascii=False)
os.replace(tmp, out)
BISPOOL
    echo "[$(date '+%F %T')] run_all: blinkit spooled for batch -> $BIDIR/blinkit.json (sweep ${SWEEP_ID})"
    fi
  else
    echo "[$(date '+%F %T')] run_all: blinkit report not in output/ — skipped (Mac drop late/absent)"
  fi
fi

# One standalone violations workbook per sweep: every platform x every SKU vs the
# day's regime reference (tools/pricematch/build_pricematch.py; Ecom Head first
# sheet). Built AFTER the platform loop (freshest result.json for all platforms,
# chain lock already released) and BEFORE the batch barrier so it joins the same
# deadline batch — send_batch.py ships it LAST (most visible message in the chat).
# Best-effort everywhere (|| true): a builder/send failure can never touch the
# sweep. SIM MODE skips it (fake platforms must never feed a real-data workbook);
# a CHAIN_SKIPPED sweep skips it too (another chain is actively rewriting the
# result.json files this builder would read). Plain run without defer env = build
# + immediate Telegram send, same pattern run.sh uses.
if [ "$SIM_MODE" != "1" ] && [ "$CHAIN_SKIPPED" != "1" ] && [ -f tools/pricematch/build_pricematch.py ]; then
  echo "[$(date '+%F %T')] run_all: building master Price Match workbook"
  (
    set +e
    PM_SRC="$(python3 tools/pricematch/build_pricematch.py 2>>logs/pricematch.log | tail -1)"
    if [ -z "$PM_SRC" ] || [ ! -f "$PM_SRC" ]; then
      echo "[$(date '+%F %T')] run_all: price-match build produced no xlsx (see logs/pricematch.log)"
      exit 0
    fi
    PM_SUM="${PM_SRC}.summary.json"            # sidecar written by the builder
    PM_XLSX="$PM_SRC"
    if cp -f "$PM_SRC" "$DIR/output/" 2>>logs/pricematch.log; then
      PM_XLSX="$DIR/output/$(basename "$PM_SRC")"
    fi
    TGLOG="$DIR/logs/telegram.log"
    PM_SENT=0
    # DEFER MODE (cron-deadline): spool for send_batch.py instead of curling now.
    # Same spool schema v1 + atomic-replace pattern as run.sh. Any spool failure
    # falls through to the immediate-send path below — the report is never lost.
    if [ "${DEFER_DELIVERY:-}" = "1" ] && [ -n "${SWEEP_ID:-}" ]; then
      BDIR="$DIR/output/.batch/${SWEEP_ID}"
      mkdir -p "$BDIR" 2>>"$TGLOG"
      if PM_XLSX="$PM_XLSX" PM_SUM="$PM_SUM" python3 - "$BDIR/price-match.json" 2>>"$TGLOG" <<'SPOOLPY'
import json, os, sys, time
out = sys.argv[1]
xlsx = os.environ["PM_XLSX"]
if not (xlsx and os.path.isfile(xlsx)):
    raise SystemExit(f"pm spool: xlsx missing: {xlsx!r}")
try:
    with open(os.environ["PM_SUM"], encoding="utf-8") as fh:
        side = json.load(fh)
except Exception:
    side = {}
date = side.get("date") or time.strftime("%Y-%m-%d")
regime = side.get("regime") or "?"
tmp = out + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump({"platform": "price-match", "verdict": "OK",
               "summary": side.get("summary_md")
                          or f"*Jivo Price Match — master*\n{date} · {regime} day\nReport attached.",
               "xlsx": os.path.abspath(xlsx),
               "caption": side.get("caption") or f"Jivo Price Match · {date} · {regime} day",
               "ts": int(time.time())}, f, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, out)  # atomic: send_batch never sees a half-written file
SPOOLPY
      then
        PM_SENT=1
        echo "[$(date '+%F %T')] run_all: price-match spooled for batch -> $BDIR/price-match.json (sweep ${SWEEP_ID})" | tee -a "$TGLOG"
      else
        echo "[$(date '+%F %T')] run_all: price-match spool write FAILED -> falling back to immediate send" | tee -a "$TGLOG"
      fi
    fi
    # IMMEDIATE SEND (plain run, or spool fallback) — same TG pattern as run.sh.
    if [ "$PM_SENT" != "1" ]; then
      [ -f "$DIR/secrets.env" ] && . "$DIR/secrets.env"
      TG="${TELEGRAM_BOT_TOKEN:-}"
      CH="${TELEGRAM_CHAT_ID:-}"
      if [ -n "$TG" ] && [ -n "$CH" ]; then
        STAMP="$(date '+%Y-%m-%d %H:%M:%S')"
        SUMMARY="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1], encoding="utf-8")).get("summary_md",""))' "$PM_SUM" 2>>"$TGLOG")"
        CAPTION="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1], encoding="utf-8")).get("caption",""))' "$PM_SUM" 2>>"$TGLOG")"
        [ -n "$SUMMARY" ] || SUMMARY="*Jivo Price Match — master*
Report attached."
        [ -n "$CAPTION" ] || CAPTION="Jivo Price Match"
        R1="$(curl -s --max-time 60 -X POST "https://api.telegram.org/bot${TG}/sendMessage" \
                --data-urlencode "chat_id=${CH}" \
                --data-urlencode "parse_mode=Markdown" \
                --data-urlencode "text=${SUMMARY}")"
        echo "[$STAMP] price-match sendMessage  -> $R1" >> "$TGLOG"
        R2="$(curl -s --max-time 120 -X POST "https://api.telegram.org/bot${TG}/sendDocument" \
                -F "chat_id=${CH}" \
                -F "document=@${PM_XLSX}" \
                -F "caption=${CAPTION}")"
        echo "[$STAMP] price-match sendDocument -> $R2" >> "$TGLOG"
      else
        echo "[$(date '+%F %T')] run_all: price-match built but no Telegram creds — workbook at $PM_XLSX" | tee -a "$TGLOG"
      fi
    fi
  ) || true
fi

# ---- Deferred-delivery batch barrier (cron-deadline mode) ----
# When the deadline sweep set DEFER_DELIVERY=1, each platform's OK report was spooled to
# output/.batch/$SWEEP_ID/ instead of being curled (run.sh). send_batch.py sleeps until the
# slot deadline, then delivers the whole sweep in one batch. Best-effort: a batch failure
# never blocks the self-heal/vault steps below. Inert when the env vars are unset.
if [ "${DEFER_DELIVERY:-}" = "1" ] && [ -n "${SWEEP_ID:-}" ] && [ -n "${SWEEP_DEADLINE:-}" ] && [ -f tools/cron/send_batch.py ]; then
  echo "[$(date '+%F %T')] run_all: batch barrier -> send_batch.py $SWEEP_ID (deadline epoch $SWEEP_DEADLINE)"
  python3 tools/cron/send_batch.py "$SWEEP_ID" "$SWEEP_DEADLINE" || true
fi
# SIM MODE hard gate: everything below (selfheal, vault rebuild, git) is production-only.
if [ "$SIM_MODE" != "1" ]; then

# Backstop: the legacy self-heal pass still runs (it owns the staleness / row-collapse
# signals the inline guardian leaves to it). It runs AFTER the wait above, so the
# inline guardians have finished; it shares the same per-platform .heal-<p>.lock, so
# it can never run concurrently with a guardian heal (e.g. an overlapping daily pass).
# A platform the guardian already healed-but-left-BROKEN may get one more recovery
# attempt here — bounded and harmless (a deliberate second safety net).
# DEFER ENV STRIPPED (W4 report-loss fix): this backstop runs AFTER send_batch.py has
# delivered + retired the spool dir. If a selfheal re-run came back OK with the defer env
# still set, run.sh would SPOOL the healed report into the dead batch dir and it would
# never be delivered. Empty values fail run.sh's `= "1"` guard -> the healed report ships
# immediately, exactly like today. (The in-loop guardian heals keep the env on purpose —
# they run BEFORE send_batch, so their healed reports correctly join the batch.)
# W2 SWEEP-CHAIN GATE on the backstop (same logs/.sweep-chain.lock as the loop):
# with 12:00 + 15:00 slots 3h apart, this tail runs ~12:00:16 — mid-way through
# the 15:00 sweep's chain. A heal re-run here (`timeout 2400 ./run.sh <p>`) would
# scrape CONCURRENTLY with that chain (only amazon-fresh/now have a heal-vs-chain
# lock; every other platform has none). flock -n: another sweep's chain holds the
# lock => SKIP — zero coverage loss, the next sweep's own backstop runs with
# nothing else active and assesses ALL platforms. While the backstop DOES run, we
# hold the lock, so any heal re-run is itself mutually exclusive with a chain.
BACKSTOP_DONE=0
if command -v flock >/dev/null 2>&1; then
  {
    if flock -n 6 2>/dev/null; then
      BACKSTOP_DONE=1
      DEFER_DELIVERY= SWEEP_ID= ./healthcheck.sh || true
    else
      BACKSTOP_DONE=1
      echo "[$(date '+%F %T')] run_all: selfheal backstop SKIPPED — another sweep chain is active (logs/.sweep-chain.lock busy)"
    fi
  } 6>"$SWEEP_CHAIN_LOCK" 2>/dev/null
fi
if [ "$BACKSTOP_DONE" != "1" ]; then
  # no flock binary / unopenable lockfile -> old unlocked behavior
  DEFER_DELIVERY= SWEEP_ID= ./healthcheck.sh || true
fi

# ---- Rebuild the COMPLETE Obsidian memory graph from the full price history. ----
# vault_build.py regenerates EVERY run note (complete: every observation as a fenced ```csv
# block) plus the SKU / city / pincode entity hubs, the two MOCs, the daily/weekly/monthly
# rollups, the home index and the .obsidian graph config — all densely cross-linked by
# real-basename [[wikilinks]] (NOT aliases, which Obsidian does not resolve). Deterministic +
# idempotent (stdlib only). Runs ONCE here after the parallel sweep — never per-platform — so
# the whole-graph rebuild can't race the concurrent run.sh instances. Then persist to git
# (same flock on .gitpush.lock as run.sh). Never fails the sweep.
echo "[$(date '+%F %T')] run_all: rebuilding Obsidian memory graph"
# vault_build.py rebuilds + prunes orphans + runs the integrity gate (basename uniqueness AND
# every body [[wikilink]] resolves), returning nonzero on any violation. The commit/push below
# is GATED on that exit code: a broken graph is NEVER committed or pushed (last good vault is
# preserved in git) and the owner is alerted. This still never aborts the sweep.
if python3 tools/vault_build.py; then VB_RC=0; else VB_RC=$?; fi
if [ "$VB_RC" != "0" ]; then
  echo "[$(date '+%F %T')] run_all: vault_build FAILED (rc=$VB_RC) — memory graph NOT committed/pushed; last good vault preserved" >&2
  ( # owner alert — same secrets.env pattern as the chain-skip alert above; never fails the sweep
    set +e
    [ -f "$DIR/secrets.env" ] && . "$DIR/secrets.env"
    TG="${TELEGRAM_BOT_TOKEN:-}"; OC="${TELEGRAM_OWNER_CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"
    [ -n "$TG" ] && [ -n "$OC" ] && curl -s --max-time 60 -X POST "https://api.telegram.org/bot${TG}/sendMessage" \
      --data-urlencode "chat_id=${OC}" \
      --data-urlencode "text=🛑 ecom-intel vault_build FAILED (rc=${VB_RC}: basename collision or broken-link integrity check) for sweep ${SWEEP_ID:-manual} — the memory graph was NOT committed or pushed; the last good vault is preserved in git. See logs/cron.log." >/dev/null
  ) || true
fi
if [ "$VB_RC" = "0" ]; then
(
  set +e
  cd "$DIR"
  exec 9>"$DIR/.gitpush.lock"
  command -v flock >/dev/null 2>&1 && flock 9
  git add vault data reviews baselines docs README.md REPORT.md CLAUDE.md >/dev/null 2>&1
  git add platforms/*/pincodes.full25.json >/dev/null 2>&1 || true
  if ! git diff --cached --quiet; then
    git commit -m "vault: rebuild memory graph $(date '+%F-%H%M')" >/dev/null 2>&1
    git pull --rebase --autostash >/dev/null 2>&1
    git push >/dev/null 2>&1 || { git pull --rebase --autostash >/dev/null 2>&1; git push >/dev/null 2>&1; }
    echo "[$(date '+%F %T')] run_all: vault graph committed + pushed."
  else
    echo "[$(date '+%F %T')] run_all: vault graph unchanged."
  fi
) || true
fi

fi  # end SIM MODE gate

echo "[$(date '+%F %T')] run_all: DONE"
