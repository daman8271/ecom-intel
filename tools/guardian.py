#!/usr/bin/env python3
"""tools/guardian.py — ecom-intel AUTO-HEAL guardian.

The owner's mandate: *nothing breaks silently again*. After a platform scrape (or
on a daily cron) the guardian re-evaluates the fresh result.json, and on FAIL it:

  1. QUARANTINEs   — does NOT publish (no Telegram, no baseline update) and keeps
                     the last-good snapshot (platforms/<p>/result.last-good.json) so
                     the bad run never becomes "the data".
  2. SELF-HEALs    — bounded re-runs of ./run.sh <platform> (cap 2, each logged),
                     re-evaluating after each.
  3. ALERTs        — if still failing, Telegram-alerts the owner with the SPECIFIC
                     diagnosis and marks the run BROKEN.

It does this by combining TWO independent verdicts:

  A. tools/review.py        — the SHARED hardened pipeline checks (geo-consistency,
                              priced-row-floor, per_litre, dup, staleness, ...). The
                              guardian CALLS review.py (subprocess); it never
                              reimplements review's logic. (pipeline session owns it.)
  B. the 11-bug-class deep  — an INDEPENDENT second opinion implemented here, mapped
     checks                   1:1 to the audit's 11 production bug classes. This makes
                              the guardian self-sufficient: it catches contamination /
                              padding / combo bugs even if review.py has not yet been
                              hardened, and gives a second vote when it has.

Combined verdict = the WORST of {review.py, deep-checks}. BROKEN => quarantine+heal.

FAILURE-PROOF by construction: every stage is wrapped; a guardian crash must never
abort a cron sweep. Exit code is advisory (0 OK / 1 SUSPECT / 2 BROKEN); callers in
run_all.sh `|| true` it.

Usage:
    tools/guardian.py <platform> [--review] [--heal] [--run-id ID]
                                 [--result PATH] [--no-baseline] [--json]

    --review       force a fresh `review.py <p> <run_id>` instead of reading the
                   newest existing reviews/<p>-*.json (used by the daily deep-dive
                   and the test harness; the run_all.sh hook reads the verdict that
                   run.sh already produced, to avoid a duplicate baseline update).
    --heal         on BROKEN, run the bounded self-heal (re-run ./run.sh). Off by
                   default so a bare evaluation never triggers a heavy re-scrape.
    --run-id ID    RUN_ID to label the review/verdict (default: derived).
    --result PATH  evaluate an explicit result.json (for tests / quarantined copies).
    --no-baseline  when forcing --review, restore baselines/<p>.json afterwards so a
                   diagnostic/test review can never pollute the rolling baseline.
    --json         print the full combined verdict as JSON to stdout.
"""

import csv
import datetime
import json
import os
import shutil
import subprocess
import sys
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLATFORMS_DIR = os.path.join(ROOT, "platforms")
REVIEWS_DIR = os.path.join(ROOT, "reviews")
GUARDIAN_DIR = os.path.join(REVIEWS_DIR, "guardian")
BASELINES_DIR = os.path.join(ROOT, "baselines")
LOGS_DIR = os.path.join(ROOT, "logs")
HEALTH_LOG = os.path.join(LOGS_DIR, "guardian.log")

# ---- tunables (env-overridable) --------------------------------------------
GEO_MAX_CITIES = int(os.environ.get("GUARDIAN_GEO_MAX_CITIES", "2"))   # one store in >N cities = contamination
PRICE_CITIES_MAX = int(os.environ.get("GUARDIAN_PRICE_CITIES_MAX", "6"))  # identical price across >N far cities
PRICED_FLOOR = int(os.environ.get("GUARDIAN_PRICED_FLOOR", "15"))     # abs floor of in-stock priced rows
PRICED_FLOOR_MIN = int(os.environ.get("GUARDIAN_PRICED_FLOOR_MIN", "5"))  # never relax below this
NULL_PRICE_FRAC = float(os.environ.get("GUARDIAN_NULL_PRICE_FRAC", "0.6"))  # padding tell
PERLITRE_MULT = float(os.environ.get("GUARDIAN_PERLITRE_MULT", "2.5"))   # row /L vs SKU median
PERLITRE_ABS_MAX = float(os.environ.get("GUARDIAN_PERLITRE_ABS_MAX", "6000"))  # Rs/L hard ceiling
PERLITRE_OUTLIER_FRAC = float(os.environ.get("GUARDIAN_PERLITRE_FRAC", "0.34"))  # systemic, not 1 row
SKU_FLOOR = int(os.environ.get("GUARDIAN_SKU_FLOOR", "6"))            # min distinct Jivo SKUs
RETRY_CAP = int(os.environ.get("GUARDIAN_RETRY_CAP", "2"))            # self-heal re-runs
RUN_TIMEOUT = int(os.environ.get("GUARDIAN_RUN_TIMEOUT", "2400"))     # per ./run.sh recovery (s)

BLOCK_MARKERS = (
    "captcha", "are you a robot", "access denied", "403 forbidden",
    "forbidden", "session_expired", "bb_session_expired", "not authorized",
    "please verify", "unusual traffic", "blocked", "to continue, please",
)

PLATFORMS = (os.environ.get("ECOM_PLATFORMS")
             or "blinkit flipkart-minutes flipkart amazon zepto "
                "amazon-fresh amazon-now bigbasket").split()

# ===========================================================================
# small helpers
# ===========================================================================
def now_utc():
    return datetime.datetime.now(datetime.timezone.utc)


def log(msg):
    try:
        os.makedirs(LOGS_DIR, exist_ok=True)
        with open(HEALTH_LOG, "a") as f:
            f.write(f"[{now_utc():%Y-%m-%d %H:%M:%S}Z] {msg}\n")
    except Exception:
        pass


def num(v):
    try:
        if v is None or v == "":
            return None
        return float(v)
    except (TypeError, ValueError):
        return None


def result_path(platform, override=None):
    return override or os.path.join(PLATFORMS_DIR, platform, "result.json")


def load_result(platform, override=None):
    with open(result_path(platform, override)) as f:
        return json.load(f)


def priced_floor_for(platform):
    """Effective in-stock-priced-rows floor for `platform` (class-4 deep check).

    RECALIBRATION (2026-06-06): the one static PRICED_FLOOR (15) was sized for the
    big catalogs and mis-fired on bigbasket MEMBER mode, whose stable healthy
    profile is 10 priced of 23 in-stock rows since the 2026-06-05 member-session
    switch (smaller member catalog, OOS-heavy hub) — guardian called every sweep
    BROKEN (false alarm: quarantine + 2 heal re-runs + owner alert each time)
    while review.py correctly said OK. When the platform's OWN rolling baseline
    (baselines/<p>.json, seeded only by review-accepted OK runs) says its normal
    priced-row count is small, derive the floor from that instead:

        floor = clamp(round(0.6 * median(baseline priced_rows)),
                      PRICED_FLOOR_MIN, PRICED_FLOOR)

    0.6x mirrors review.py's PRICED_SUSPECT_DROP=0.40 boundary. The clamp means
    the floor can only RELAX below the static 15 (never get stricter), and never
    below PRICED_FLOOR_MIN. Today only bigbasket qualifies (median 10 -> floor 6;
    every other platform's 0.6x median is >= 15 and stays clamped at 15; no
    baseline priced_rows -> static 15). Env GUARDIAN_PRICED_FLOOR_<PLATFORM>
    (e.g. GUARDIAN_PRICED_FLOOR_BIGBASKET) overrides everything. Never raises.
    """
    env = os.environ.get(
        "GUARDIAN_PRICED_FLOOR_" + platform.upper().replace("-", "_"))
    if env:
        try:
            return int(env)
        except ValueError:
            pass
    try:
        with open(os.path.join(BASELINES_DIR, platform + ".json")) as f:
            bl = json.load(f)
        pr = sorted(s.get("priced_rows") for s in bl.get("samples", [])
                    if isinstance(s.get("priced_rows"), (int, float)))
        if not pr:
            return PRICED_FLOOR
        med = pr[len(pr) // 2] if len(pr) % 2 else (pr[len(pr) // 2 - 1]
                                                    + pr[len(pr) // 2]) / 2.0
        return max(PRICED_FLOOR_MIN, min(PRICED_FLOOR, int(round(0.6 * med))))
    except Exception as e:
        log(f"{platform}: priced_floor_for fell back to static ({e})")
        return PRICED_FLOOR


def extract_rows(data):
    rows = data.get("allRows")
    if isinstance(rows, list) and rows:
        return rows
    flat = []
    for pin in data.get("perPin", []) or []:
        for r in pin.get("rows", []) or []:
            flat.append(r)
    return flat


def is_per_pincode(data):
    summary = data.get("summary", {}) or {}
    total = summary.get("pincodes_total")
    if isinstance(total, int):
        return total > 1
    pins = {p.get("pincode") for p in (data.get("perPin", []) or [])}
    pins.discard("-")
    pins.discard(None)
    return len(pins) > 1


# ===========================================================================
# THE 11 BUG-CLASS DEEP CHECKS — an independent second opinion.
# Each appends {class, name, pass, severity, detail}; severity in {broken,suspect}.
# Per-platform-aware: geo/coverage checks are skipped on national platforms so we
# never false-positive a legitimately national price.
# ===========================================================================
def deep_checks(platform, data):
    rows = extract_rows(data)
    per_pin = is_per_pincode(data)
    summary = data.get("summary", {}) or {}
    checks = []

    def add(klass, name, ok, severity, detail):
        checks.append({"class": klass, "name": name, "pass": bool(ok),
                       "severity": severity, "detail": detail})

    n_rows = len(rows)
    canon = lambda r: r.get("canonical") or r.get("sku_raw")
    skus = {canon(r) for r in rows if canon(r)}

    # ---- CLASS 1: WRONG SURFACE / 11: block markers -----------------------
    # scan free-text fields + any top-level status/error/marker fields.
    block_hit = None
    blob_fields = ("sku_raw", "canonical", "store_name", "locality", "city")
    for r in rows[:5000]:
        for fld in blob_fields:
            txt = str(r.get(fld) or "").lower()
            for m in BLOCK_MARKERS:
                if m in txt:
                    block_hit = (fld, m)
                    break
            if block_hit:
                break
        if block_hit:
            break
    # top-level markers (e.g. {"marker":"BB_SESSION_EXPIRED"}, error/status)
    for k in ("marker", "error", "status", "scrape_status", "note"):
        v = str(data.get(k) or summary.get(k) or "").lower()
        for m in BLOCK_MARKERS:
            if m in v:
                block_hit = block_hit or (k, m)
                break
    add(1, "no_block_markers", block_hit is None, "broken",
        "no captcha/403/expired-session markers" if not block_hit
        else f"block marker {block_hit[1]!r} in {block_hit[0]}")

    # ---- CLASS 2/8: GEO-CONTAMINATION (per-pincode only) ------------------
    # A real hyperlocal store serves ONE metro. A store_id appearing across many
    # distinct cities == the blinkit default-store fallback bleeding one store's
    # catalogue under foreign cities. Strong, unambiguous tell.
    if per_pin:
        store_cities = defaultdict(set)
        n_with_store = 0
        for r in rows:
            sid = r.get("store_id")
            if sid in (None, "", "-"):
                continue
            n_with_store += 1
            city = (r.get("city") or "").strip()
            if city:
                store_cities[str(sid)].add(city)
        store_cov = (n_with_store / n_rows) if n_rows else 0.0
        worst = max(((s, c) for s, c in store_cities.items()),
                    key=lambda x: len(x[1]), default=(None, set()))
        worst_sid, worst_set = worst
        if worst_sid is not None and len(worst_set) > GEO_MAX_CITIES:
            # one hyperlocal store can only serve ONE metro — many = contamination
            add(2, "geo_store_one_city", False, "broken",
                f"store_id {worst_sid} spans {len(worst_set)} cities "
                f"({', '.join(sorted(worst_set)[:8])}…) — default-store contamination")
        elif store_cov >= 0.5:
            # store_id is the authoritative geo signal and it is clean. A platform
            # with real per-store ids that each map to ONE city is contamination-free,
            # even when many stores quote the SAME chain-wide price (legit national
            # pricing) — so we do NOT also run the noisy price-identity tell here.
            ncities = len({(r.get('city') or '').strip()
                           for r in rows if (r.get('city') or '').strip()})
            add(2, "geo_consistency", True, "broken",
                f"no store spans >{GEO_MAX_CITIES} cities "
                f"({len(store_cities)} stores, {ncities} cities, "
                f"{store_cov:.0%} rows carry a store_id)")
        else:
            # store_id largely ABSENT -> fall back to the price-identity tell:
            # one canonical at an identical price across many far-apart cities.
            # VARIANCE-AWARE (2026-06-10): a lone flat SKU is NOT contamination —
            # stable national-price SKUs do that legitimately (amazon-now carries
            # no store_id, yet healthy runs show 6-7 prices/SKU across 10 cities).
            # TRUE default-store contamination (the blinkit incident) flattens
            # MOST SKUs to one price — so flag only when a MAJORITY (>50%) of the
            # multi-city canonicals are price-flat; lone identities are logged.
            price_cities = defaultdict(lambda: defaultdict(set))
            for r in rows:
                c = canon(r)
                sale = num(r.get("sale"))
                city = (r.get("city") or "").strip()
                if c and sale is not None and city and r.get("in_stock"):
                    price_cities[c][sale].add(city)
            n_multi = 0  # canonicals seen in >PRICE_CITIES_MAX cities
            flat = []    # ...of those, (canon, price, n_cities) at ONE price everywhere
            for c, pm in price_cities.items():
                cities_all = set().union(*pm.values())
                if len(cities_all) <= PRICE_CITIES_MAX:
                    continue
                n_multi += 1
                if len(pm) == 1:
                    flat.append((c, next(iter(pm)), len(cities_all)))
            if flat and len(flat) * 2 > n_multi:
                worst = max(flat, key=lambda t: t[2])
                add(2, "geo_price_identity", False, "suspect",
                    f"{len(flat)}/{n_multi} multi-city SKUs price-identical, e.g. "
                    f"{worst[0]} at identical ₹{worst[1]} across {worst[2]} cities "
                    f"w/o store_id — possible contamination")
            else:
                if flat:  # minority — legit national pricing: record, don't flag
                    log(f"{platform}: geo note — {len(flat)}/{n_multi} multi-city "
                        f"SKUs price-flat (below majority, not flagged): "
                        + "; ".join(f"{c} ₹{s} x{n} cities" for c, s, n in flat[:4]))
                add(2, "geo_consistency", True, "suspect",
                    f"no price spans >{PRICE_CITIES_MAX} cities (store_id sparse)"
                    if not n_multi else
                    f"{len(flat)}/{n_multi} multi-city SKUs price-identical "
                    f"(majority needed; store_id sparse)")
    else:
        add(2, "geo_consistency", True, "suspect", "national platform — geo n/a")

    # ---- CLASS 3: CATALOG INCOMPLETENESS ----------------------------------
    add(3, "catalog_floor", len(skus) >= SKU_FLOOR, "suspect",
        f"{len(skus)} distinct Jivo SKUs (floor {SKU_FLOOR})")

    # ---- CLASS 4/11: PRICED-ROW FLOOR + null-price padding ----------------
    # floor is per-platform (baseline-derived for small healthy catalogs like
    # bigbasket member mode; static 15 elsewhere) — see priced_floor_for().
    instock = [r for r in rows if r.get("in_stock")]
    priced = [r for r in instock if num(r.get("sale")) and num(r.get("sale")) > 0]
    n_instock = len(instock)
    null_frac = (1 - len(priced) / n_instock) if n_instock else 0.0
    eff_floor = priced_floor_for(platform)
    floor_note = f"floor {eff_floor}" + (
        ", baseline-derived" if eff_floor != PRICED_FLOOR else "")
    add(4, "priced_row_floor", len(priced) >= eff_floor, "broken",
        f"{len(priced)} in-stock priced rows ({floor_note})")
    add(11, "null_price_padding",
        not (n_instock >= eff_floor and null_frac > NULL_PRICE_FRAC), "suspect",
        f"{null_frac:.0%} of {n_instock} in-stock rows have no price"
        + (" — looks padded" if null_frac > NULL_PRICE_FRAC else ""))

    # ---- CLASS 4/2: SHARED (sale,mrp) across DISTINCT canonicals ----------
    pair_to_skus = defaultdict(set)
    for r in rows:
        sale, mrp = num(r.get("sale")), num(r.get("mrp"))
        c = canon(r)
        if sale and mrp and c:
            pair_to_skus[(round(sale, 2), round(mrp, 2))].add(c)
    dup_pairs = {p: s for p, s in pair_to_skus.items() if len(s) >= 2}
    if dup_pairs:
        ex = next(iter(dup_pairs.items()))
        add(4, "shared_price_dup", False, "suspect",
            f"{len(dup_pairs)} (sale,mrp) pairs shared by distinct SKUs, e.g. "
            f"₹{ex[0][0]}/₹{ex[0][1]} -> {', '.join(sorted(ex[1])[:3])}")
    else:
        add(4, "shared_price_dup", True, "suspect",
            "no (sale,mrp) pair shared across distinct SKUs")

    # ---- CLASS 5/6: PER-LITRE / VOLUME / COMBO ----------------------------
    by_canon = defaultdict(list)
    for r in priced:
        pl = num(r.get("per_litre"))
        if pl and pl > 0:
            by_canon[canon(r)].append(pl)
    # A combo/volume PARSE bug inflates per_litre SYSTEMICALLY for a SKU (the wrong
    # denominator is used on every combo row), not on a lone row — so we flag a SKU
    # only when a SUBSTANTIAL fraction of its rows are outliers (or the SKU's own
    # median blows past the absolute ceiling). This ignores legitimate per-store
    # price dispersion (a single premium store quoting 2x) which is NOT a parse bug.
    pl_outliers = []
    for c, vals in by_canon.items():
        if len(vals) < 3:
            continue
        vals_sorted = sorted(vals)
        med = vals_sorted[len(vals_sorted) // 2]
        n_out = sum(1 for v in vals if med and v > PERLITRE_MULT * med)
        if (med and med > PERLITRE_ABS_MAX) or n_out >= max(2, PERLITRE_OUTLIER_FRAC * len(vals)):
            hi = max(vals)
            pl_outliers.append((c, hi, med, n_out, len(vals)))
    add(5, "per_litre_sanity", len(pl_outliers) == 0, "suspect",
        "per_litre within band for all SKUs" if not pl_outliers
        else f"{len(pl_outliers)} SKU(s) w/ systemic per_litre outlier, e.g. "
             f"{pl_outliers[0][0]} ₹{pl_outliers[0][1]:.0f}/L vs median "
             f"₹{pl_outliers[0][2]:.0f}/L ({pl_outliers[0][3]}/{pl_outliers[0][4]} "
             f"rows — combo/volume parse?)")
    null_vol = sum(1 for r in priced if not num(r.get("vol_ml")))
    add(6, "volume_parse",
        not (priced and null_vol / max(1, len(priced)) > 0.2), "suspect",
        f"{null_vol}/{len(priced)} priced rows missing vol_ml")

    # ---- CLASS 7: OOS handling --------------------------------------------
    stock_vals = {1 if r.get("in_stock") else 0 for r in rows}
    add(7, "oos_captured", len(rows) == 0 or len(stock_vals) >= 1, "suspect",
        f"in_stock present ({n_instock}/{n_rows} in stock)")

    # ---- CLASS 9: FRESHNESS / STALENESS -----------------------------------
    fresh = summary.get("freshness") or {}
    pct_cached = num(fresh.get("pct_cached"))
    captured_at = summary.get("captured_at")
    stale = False
    detail9 = f"captured_at={captured_at}"
    if captured_at:
        try:
            ts = datetime.datetime.fromisoformat(captured_at.replace("Z", "+00:00"))
            age_h = (now_utc() - ts).total_seconds() / 3600
            detail9 = f"captured {age_h:.1f}h ago"
            if age_h > 24:
                stale = True
                detail9 += " (>24h stale)"
        except Exception:
            pass
    if pct_cached is not None and pct_cached >= 90:
        stale = True
        detail9 += f"; {pct_cached:.0f}% cache-served prices"
    add(9, "freshness", not stale, "suspect", detail9)

    # ---- CLASS 10: CANONICAL / DEDUP --------------------------------------
    # same (location-key, canonical) showing wildly divergent prices = dedup/parse
    # leak. location-key = store_id or pincode.
    lockey = lambda r: (r.get("store_id") or r.get("pincode"), canon(r))
    grp = defaultdict(set)
    for r in priced:
        grp[lockey(r)].add(num(r.get("sale")))
    dedup_bad = sum(1 for v in grp.values()
                    if len(v) >= 2 and max(v) > 3 * min(v))
    add(10, "canonical_dedup", dedup_bad == 0, "suspect",
        "no divergent-price dedup leak" if not dedup_bad
        else f"{dedup_bad} (location,SKU) keys w/ >3x price spread")

    return checks


# ===========================================================================
# review.py bridge
# ===========================================================================
def newest_review(platform):
    """Newest existing reviews/<p>-YYYY-*.json (the one run.sh produced)."""
    import glob
    files = sorted(glob.glob(os.path.join(
        REVIEWS_DIR, f"{platform}-[0-9][0-9][0-9][0-9]-*.json")))
    if not files:
        return None
    try:
        with open(files[-1]) as f:
            return json.load(f)
    except Exception:
        return None


def call_review(platform, run_id, no_baseline=False):
    """CALL tools/review.py (subprocess). Returns its verdict dict (or None).

    When no_baseline=True we snapshot baselines/<p>.json and restore it after, so a
    diagnostic/forced review can never pollute the rolling baseline (review.py
    updates the baseline on an OK verdict)."""
    bpath = os.path.join(BASELINES_DIR, f"{platform}.json")
    saved = None
    if no_baseline and os.path.isfile(bpath):
        with open(bpath) as f:
            saved = f.read()
    try:
        r = subprocess.run(
            [sys.executable, os.path.join(ROOT, "tools", "review.py"),
             platform, run_id],
            cwd=ROOT, capture_output=True, text=True, timeout=300)
        log(f"{platform}: review.py exit={r.returncode} :: "
            f"{(r.stdout or r.stderr).strip()[:200]}")
    except Exception as e:
        log(f"{platform}: review.py call failed (ignored): {e}")
    finally:
        if no_baseline:
            try:
                if saved is not None:
                    with open(bpath, "w") as f:
                        f.write(saved)
                elif os.path.isfile(bpath):
                    os.remove(bpath)  # review.py created it during the diag run
            except Exception as e:
                log(f"{platform}: baseline restore failed: {e}")
    rp = os.path.join(REVIEWS_DIR, f"{platform}-{run_id}.json")
    try:
        with open(rp) as f:
            return json.load(f)
    except Exception:
        return None


# ===========================================================================
# combine + actions
# ===========================================================================
RANK = {"OK": 0, "SUSPECT": 1, "BROKEN": 2}
RANK_INV = {0: "OK", 1: "SUSPECT", 2: "BROKEN"}


def combine(review_verdict, deep):
    rscore = RANK.get(str((review_verdict or {}).get("verdict", "")).upper(), 0)
    dscore = 0
    deep_reasons = []
    for c in deep:
        if not c["pass"]:
            s = 2 if c["severity"] == "broken" else 1
            dscore = max(dscore, s)
            deep_reasons.append(f"[class {c['class']}] {c['name']}: {c['detail']}")
    final = RANK_INV[max(rscore, dscore)]
    return final, deep_reasons, rscore, dscore


def snapshot_last_good(platform, data, override=None):
    """Keep last-good: copy a non-broken result.json aside for fallback serving."""
    try:
        src = result_path(platform, override)
        dst = os.path.join(PLATFORMS_DIR, platform, "result.last-good.json")
        shutil.copyfile(src, dst)
        log(f"{platform}: last-good snapshot updated")
    except Exception as e:
        log(f"{platform}: last-good snapshot failed: {e}")


def tg_alert(text):
    """Best-effort Telegram alert (same secrets.env pattern as run.sh/selfheal)."""
    secrets = os.path.join(ROOT, "secrets.env")
    tg = ch = None
    if os.path.isfile(secrets):
        for line in open(secrets):
            line = line.strip()
            if line.startswith("TELEGRAM_BOT_TOKEN="):
                tg = line.split("=", 1)[1].strip().strip('"').strip("'")
            elif line.startswith("TELEGRAM_CHAT_ID="):
                ch = line.split("=", 1)[1].strip().strip('"').strip("'")
    if not tg or not ch:
        log("TG: creds missing, alert skipped")
        return False
    try:
        subprocess.run(
            ["curl", "-s", "--max-time", "60", "-X", "POST",
             f"https://api.telegram.org/bot{tg}/sendMessage",
             "--data-urlencode", f"chat_id={ch}",
             "--data-urlencode", f"text={text}"],
            capture_output=True, timeout=70)
        log("TG: alert sent")
        return True
    except Exception as e:
        log(f"TG: alert failed (ignored): {e}")
        return False


def pull_spooled_report(platform, verdict_out):
    """DEFENSE-IN-DEPTH (2026-06-06): a guardian-quarantined report must never ride
    an already-spooled deadline batch.

    Gap this closes: review.py=OK makes run.sh SPOOL the report to
    output/.batch/$SWEEP_ID/<p>.json (defer mode), then the guardian's independent
    deep-check can go BROKEN — quarantine + heals fired, owner alerted, but the
    spooled file stayed and send_batch.py shipped it at the barrier (bigbasket,
    both 2026-06-06 sweeps). On a FINAL BROKEN verdict under defer mode we PULL
    the spooled report, replacing it with a held-marker in run.sh's exact shape
    so the batch footer reports it ("Held back ...: <p> [BROKEN]").

    Inert unless DEFER_DELIVERY=1 and SWEEP_ID are set (plain ./run_all.sh and the
    18:00 read-only deep-dive carry no env -> no-op). If send_batch already
    retired <p>.json to .json.sent the batch has shipped — too late to pull; log
    loudly instead. Atomic replace; never raises (failure-proof like every stage).
    """
    try:
        if os.environ.get("DEFER_DELIVERY") != "1":
            return False
        sweep = os.environ.get("SWEEP_ID")
        if not sweep:
            return False
        bdir = os.path.join(ROOT, "output", ".batch", sweep)
        spool = os.path.join(bdir, f"{platform}.json")
        if os.path.isfile(spool + ".sent"):
            log(f"{platform}: spool-pull TOO LATE — {spool}.sent exists "
                f"(batch already shipped this report)")
            return False
        os.makedirs(bdir, exist_ok=True)
        was = "none"
        if os.path.isfile(spool):
            try:
                with open(spool) as f:
                    was = "held" if json.load(f).get("held") else "ok-report"
            except Exception:
                was = "unreadable"
        marker = {
            "platform": platform,
            "verdict": verdict_out.get("verdict", "BROKEN"),
            "held": True,
            "reasons": "guardian: " + str(verdict_out.get("diagnosis") or
                                          "quarantined (BROKEN)"),
            "pulled_by": "guardian",
            "ts": int(now_utc().timestamp()),
        }
        tmp = spool + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(marker, f, ensure_ascii=False)
            f.write("\n")
        os.replace(tmp, spool)  # atomic: send_batch never sees a half-written file
        log(f"{platform}: spool-pull — replaced {was} at {spool} with held-marker "
            f"(sweep {sweep}, verdict {marker['verdict']})")
        return True
    except Exception as e:
        log(f"{platform}: spool-pull failed (ignored): {e}")
        return False


def heal(platform):
    """Bounded self-heal: re-run ./run.sh <platform> under a lock, cap RETRY_CAP.
    Returns the fresh combined verdict after the last attempt."""
    # SAME lock file tools/selfheal.sh uses (.heal-<p>.lock) so the inline guardian
    # heal and the end-of-sweep selfheal backstop mutually exclude — a platform the
    # guardian is (or just finished) healing is never double-scraped by selfheal.
    lock = os.path.join(LOGS_DIR, f".heal-{platform}.lock")
    # non-blocking lock so two guardians (e.g. inline + daily) never double-heal.
    import fcntl
    lf = open(lock, "w")
    try:
        fcntl.flock(lf, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        log(f"{platform}: heal already in progress elsewhere — skipping")
        return None
    last = None
    try:
        for attempt in range(1, RETRY_CAP + 1):
            log(f"{platform}: SELF-HEAL attempt {attempt}/{RETRY_CAP} "
                f"-> ./run.sh {platform}")
            try:
                subprocess.run(["bash", os.path.join(ROOT, "run.sh"), platform],
                               cwd=ROOT, timeout=RUN_TIMEOUT,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception as e:
                log(f"{platform}: heal run.sh failed (attempt {attempt}): {e}")
            # run.sh's own pipeline re-ran review.py + wrote a fresh verdict during
            # the recovery — read THAT (force_review=False) so we neither double-call
            # review.py nor double-update the rolling baseline.
            last = evaluate(platform, force_review=False, no_baseline=False)
            log(f"{platform}: post-heal verdict (attempt {attempt}) = "
                f"{last['verdict']}")
            if last["verdict"] != "BROKEN":
                return last
        return last
    finally:
        try:
            fcntl.flock(lf, fcntl.LOCK_UN)
            lf.close()
        except Exception:
            pass


# ===========================================================================
# evaluate (no side effects beyond writing the guardian verdict + last-good)
# ===========================================================================
def evaluate(platform, run_id=None, override=None, force_review=False,
             no_baseline=False):
    run_id = run_id or now_utc().strftime("%Y-%m-%d-%H%M")
    # 1) load data (a missing/corrupt result.json is itself BROKEN)
    try:
        data = load_result(platform, override)
    except Exception as e:
        deep = []
        verdict_out = {
            "platform": platform, "run_id": run_id,
            "verdict": "BROKEN", "review_verdict": None,
            "reasons": [f"cannot load result.json: {e}"],
            "deep_checks": deep, "diagnosis": f"result.json unreadable: {e}",
            "evaluated_at": now_utc().isoformat(),
        }
        write_guardian_verdict(platform, run_id, verdict_out)
        return verdict_out

    # 2) review.py verdict — read the fresh one run.sh produced, or force a call
    if force_review:
        review_verdict = call_review(platform, run_id, no_baseline=no_baseline)
    else:
        review_verdict = newest_review(platform)
        if review_verdict is None:
            review_verdict = call_review(platform, run_id, no_baseline=no_baseline)

    # 3) the independent 11-class deep checks
    try:
        deep = deep_checks(platform, data)
    except Exception as e:
        log(f"{platform}: deep_checks raised (treated as SUSPECT): {e}")
        deep = [{"class": 0, "name": "deep_checks_error", "pass": False,
                 "severity": "suspect", "detail": f"deep checks raised: {e}"}]

    final, deep_reasons, rscore, dscore = combine(review_verdict, deep)
    review_reasons = list((review_verdict or {}).get("reasons", []) or [])

    diagnosis = diagnose(platform, final, deep, review_verdict)
    verdict_out = {
        "platform": platform,
        "run_id": run_id,
        "verdict": final,
        "review_verdict": (review_verdict or {}).get("verdict"),
        "review_reasons": review_reasons,
        "deep_reasons": deep_reasons,
        "reasons": (review_reasons + deep_reasons) or ["all checks pass"],
        "deep_checks": deep,
        "diagnosis": diagnosis,
        "quarantined": final == "BROKEN",
        "evaluated_at": now_utc().isoformat(),
        "source_result": result_path(platform, override),
    }
    write_guardian_verdict(platform, run_id, verdict_out)

    # 4) keep last-good ONLY when not broken (quarantine preserves prior good data)
    if final != "BROKEN":
        snapshot_last_good(platform, data, override)
    return verdict_out


def diagnose(platform, final, deep, review_verdict):
    """One specific, human-readable line naming the dominant failure + heal hint."""
    if final == "OK":
        return f"{platform}: healthy"
    broken = [c for c in deep if not c["pass"] and c["severity"] == "broken"]
    suspect = [c for c in deep if not c["pass"] and c["severity"] == "suspect"]
    lead = broken[0] if broken else (suspect[0] if suspect else None)
    hint = {
        2: "blinkit-style default-store contamination -> re-resolve store + re-scrape",
        1: "block / expired session -> refresh login cookies / retry",
        4: "priced-row collapse / padding -> re-scrape (selector or block?)",
        9: "stale/cache-served prices -> re-fetch live from PDP",
    }.get(lead["class"], "re-run scrape") if lead else "see review.py reasons"
    src = "deep-check" if lead else "review.py"
    head = (lead["detail"] if lead
            else "; ".join((review_verdict or {}).get("reasons", [])[:2])
            or "review flagged")
    return f"{platform} {final} ({src}): {head} | heal: {hint}"


def write_guardian_verdict(platform, run_id, obj):
    try:
        os.makedirs(GUARDIAN_DIR, exist_ok=True)
        with open(os.path.join(GUARDIAN_DIR, f"{platform}-{run_id}.json"), "w") as f:
            json.dump(obj, f, indent=2)
        # stable "latest" pointer for the daily report / quarantine marker
        with open(os.path.join(GUARDIAN_DIR, f"{platform}-latest.json"), "w") as f:
            json.dump(obj, f, indent=2)
    except Exception as e:
        log(f"{platform}: failed to write guardian verdict: {e}")


# ===========================================================================
# main
# ===========================================================================
def run_one(platform, force_review=False, do_heal=False, run_id=None,
            override=None, no_baseline=False):
    v = evaluate(platform, run_id=run_id, override=override,
                 force_review=force_review, no_baseline=no_baseline)
    log(f"{platform}: VERDICT={v['verdict']} :: {v['diagnosis']}")

    if v["verdict"] != "BROKEN":
        # clear any stale quarantine marker
        mk = os.path.join(LOGS_DIR, f".guardian-broken-{platform}")
        if os.path.exists(mk):
            try:
                os.remove(mk)
            except Exception:
                pass
        return v

    # BROKEN -> QUARANTINE (already: not published, last-good preserved, marker set)
    try:
        with open(os.path.join(LOGS_DIR, f".guardian-broken-{platform}"), "w") as f:
            f.write(v["diagnosis"] + "\n")
    except Exception:
        pass
    log(f"{platform}: QUARANTINED — {v['diagnosis']}")

    if not do_heal:
        # FINAL verdict is BROKEN (no heal requested) — under defer mode the
        # spooled report (if any) must not ride the batch.
        pull_spooled_report(platform, v)
        return v

    healed = heal(platform)
    if healed is not None:
        v = healed
    if v["verdict"] != "BROKEN":
        log(f"{platform}: RECOVERED after self-heal -> {v['verdict']}")
        mk = os.path.join(LOGS_DIR, f".guardian-broken-{platform}")
        if os.path.exists(mk):
            try:
                os.remove(mk)
            except Exception:
                pass
        return v

    # still broken -> PULL any spooled report (defer mode), then ALERT the owner.
    # A heal attempt's run.sh may have re-spooled an OK report (review.py=OK while
    # the deep-check stays BROKEN — the bigbasket 2026-06-06 gap); the pull is
    # therefore AFTER the heal loop, on the FINAL verdict.
    pull_spooled_report(platform, v)
    msg = (f"🚑 ecom-intel AUTO-HEAL: *{platform}* still BROKEN after "
           f"{RETRY_CAP} self-heal retries.\n\n{v['diagnosis']}\n\n"
           f"Run QUARANTINED — last-good data kept, nothing published.")
    tg_alert(msg)
    return v


def main(argv):
    args = argv[1:]
    if not args or args[0] in ("-h", "--help"):
        sys.stderr.write(__doc__)
        return 2
    platform = args[0]
    force_review = "--review" in args
    do_heal = "--heal" in args
    as_json = "--json" in args
    no_baseline = "--no-baseline" in args
    run_id = override = None
    if "--run-id" in args:
        run_id = args[args.index("--run-id") + 1]
    if "--result" in args:
        override = args[args.index("--result") + 1]

    if platform == "all":
        results = {}
        for p in PLATFORMS:
            results[p] = run_one(p, force_review, do_heal, run_id, None, no_baseline)
        if as_json:
            print(json.dumps(results, indent=2))
        else:
            for p, v in results.items():
                print(f"{v['verdict']:8s} {p:18s} {v['diagnosis']}")
        worst = max((RANK.get(v["verdict"], 0) for v in results.values()),
                    default=0)
        return 0 if worst == 0 else (1 if worst == 1 else 2)

    v = run_one(platform, force_review, do_heal, run_id, override, no_baseline)
    if as_json:
        print(json.dumps(v, indent=2))
    else:
        print(f"[guardian] {platform}: {v['verdict']}")
        for r in v["reasons"][:8]:
            print(f"    - {r}")
        print(f"  diagnosis: {v['diagnosis']}")
    return RANK.get(v["verdict"], 0) if v["verdict"] != "OK" else 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except SystemExit:
        raise
    except Exception as e:
        # FAILURE-PROOF: a guardian crash must never abort a cron sweep.
        log(f"guardian fatal (ignored): {e}")
        sys.stderr.write(f"[guardian] fatal (ignored): {e}\n")
        sys.exit(0)
