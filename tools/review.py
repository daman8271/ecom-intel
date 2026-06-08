#!/usr/bin/env python3
"""
tools/review.py <platform> <RUN_ID>

End-of-run automated REVIEW step for the ecom-intel cron pipeline.

Pipeline order (orchestrator wires run.sh; this tool is one step):
    scrape -> build_excel -> review.py -> self-heal(if verdict!=OK)
            -> vault_note.py -> Telegram -> git push

Goal: never silently ship garbage, while staying CHEAP. We run FREE
deterministic sanity checks first, and only OPTIONALLY make a single tiny
LLM call (Claude Haiku) when model access is configured. The LLM layer is
strictly optional and failure-proof: it can never crash the run.

Reads:   platforms/<platform>/result.json   (handles both per-pincode and
                                              national shapes)
Writes:  reviews/<platform>-<RUN_ID>.json    (the verdict, per CONTRACT)
         baselines/<platform>.json           (rolling expected, OK runs only)
         logs/review.log                      (diagnostics, esp. LLM errors)

Exit code: 0 for OK/SUSPECT, non-zero (2) for BROKEN, so run.sh/self-heal
can react.

stdlib only. No pip deps. No network unless the optional LLM layer is on.
"""

import os
import sys
import csv
import json
import time
import datetime
import urllib.request
import urllib.error
import subprocess
import traceback
from collections import Counter

# --- paths (resolve relative to repo root = parent of tools/) ---------------
TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS_DIR)
PLATFORMS_DIR = os.path.join(ROOT, "platforms")
BASELINES_DIR = os.path.join(ROOT, "baselines")
REVIEWS_DIR = os.path.join(ROOT, "reviews")
LOGS_DIR = os.path.join(ROOT, "logs")
LOG_PATH = os.path.join(LOGS_DIR, "review.log")
SECRETS_ENV = os.path.join(ROOT, "secrets.env")

# --- tunables (kept consistent with healthcheck.sh conventions) -------------
HAIKU_MODEL = "claude-haiku-4-5-20251001"
LLM_MAX_TOKENS = 200            # tiny on purpose; we only want a short verdict
LLM_TIMEOUT_S = 25
LLM_SAMPLE_ROWS = 6            # rows included in the digest sent to the LLM

# Absolute floors -> below these, the run is BROKEN regardless of baseline.
ABS_MIN_ROWS = 20             # matches healthcheck.sh MIN_ROWS
FRESHNESS_MAX_AGE_H = 15      # matches healthcheck.sh MAX_AGE_H

# Plausible retail price band (INR) for a single SKU listing.
PRICE_MIN = 1
PRICE_MAX = 100000

# In-stock rows can legitimately have NO displayed price on Amazon (price shown only
# in the cart for some bulk SKUs, e.g. Jivo Sunflower 4L). A small fraction is normal
# (~1% on Amazon Fresh/Now); only a SYSTEMIC loss above this fraction of in-stock rows
# means the price selector likely broke -> SUSPECT.
PRICE_MISSING_SUSPECT_FRAC = 0.25

# Baseline drift tolerances (fraction of the rolling baseline).
ROWS_SUSPECT_DROP = 0.40      # <60% of baseline rows -> SUSPECT
ROWS_BROKEN_DROP = 0.75       # <25% of baseline rows -> BROKEN
ROWS_SUSPECT_SPIKE = 3.0      # >3x baseline rows -> SUSPECT (shape changed?)
SKU_SUSPECT_DROP = 0.40       # <60% of baseline unique SKUs -> SUSPECT
COVERAGE_SUSPECT_DROP = 0.40  # per-pincode: <60% of baseline coverage -> SUSPECT
COVERAGE_BROKEN_DROP = 0.75   # per-pincode: <25% of baseline coverage -> BROKEN

BASELINE_WINDOW = 10          # rolling window of recent OK runs to average over

# --- geo-consistency (per-pincode platforms with a resolved store id) -------
# One physical dark-store / merchant serves ONE city/metro. If a single store_id is
# recorded under many distinct cities, a default/fallback store was scraped and
# mislabeled across cities (blinkit default-store contamination: id 31719 spanned 10
# cities at one identical price). National platforms carry an empty store_id and are n/a.
GEO_STORE_CITY_SPAN_BROKEN = 4    # one store_id across >= this many distinct cities -> BROKEN
GEO_STORE_CITY_SPAN_SUSPECT = 3   # exactly this many -> SUSPECT

# --- priced-row floor / block scan ------------------------------------------
# Static-catalog scrapers (amazon, flipkart) emit a ROW PER CATALOG ENTRY even when the
# fetch was blocked/threw, so total_rows never collapses on a block -> the row-count
# checks stay green. We additionally scan for block/error MARKERS and a priced-in-stock
# floor so a fully/partly blocked run can never pass as OK.
BLOCK_FRAC_BROKEN = 0.40     # >= this fraction of rows carry block/error markers -> BROKEN
BLOCK_FRAC_SUSPECT = 0.15    # >= this fraction -> SUSPECT
BLOCK_RATE_BROKEN = 30.0     # summary.block_rate_pct >= this -> BROKEN
BLOCK_RATE_SUSPECT = 10.0    # summary.block_rate_pct >= this -> SUSPECT
PRICED_BROKEN_DROP = 0.75    # priced-in-stock rows < 25% of baseline -> BROKEN
PRICED_SUSPECT_DROP = 0.40   # priced-in-stock rows < 60% of baseline -> SUSPECT
# status / scrape_status VALUES that mean a block/throttle (NOT legit 'ok'/'oos'/'notfound'/'no_jsonld').
STATUS_BLOCK_VALUES = (
    "blocked", "block", "error", "captcha", "throttled", "throttle",
    "403", "429", "timeout", "timed_out", "forbidden", "rate_limit", "ratelimited",
)
# Row text fields that may carry a block/error string (beyond name/locality).
BLOCK_TEXT_FIELDS = ("availability_text", "avail_text", "error", "note")
STATUS_FIELDS = ("status", "scrape_status")

# --- per-litre / combo volume sanity ----------------------------------------
# The scraper's per_litre = sale / (vol_ml/1000). If vol_ml UNDERCOUNTS a combo pack
# (e.g. '5+1 LTR' parsed as 1000ml not 6000ml) the published Rs/L is inflated. We
# re-derive the pack's TOTAL volume from the `pack` string and flag rows where the
# recorded vol_ml is materially below it.
COMBO_VOL_MARGIN = 1.4       # parsed total volume > recorded vol_ml * this -> per_litre inflated
# Absolute backstop: a real Jivo cooking/olive OIL never retails above this Rs/L (premium
# extra-virgin olive oil tops out well under ₹2000/L). Any priced OIL SKU above it has an
# inflated per_litre — typically a combo whose volume token lives in the NAME (not the
# `pack` field the structural check reads, e.g. amazon-fresh '5 L with 5 L'), so this fires
# REGARDLESS of pack. Gated to oil SKUs: a 1g saffron / small non-oil pack legitimately
# shows a huge nominal Rs/L (flipkart 'KESAR 1GM' ≈ ₹353000/L) and must NOT be flagged.
ABS_PER_LITRE_OIL_MAX = 6000.0

# --- shared (sale,mrp) duplication (fabrication / cross-sell bleed) ----------
# A specific DISCOUNTED (sale,mrp) pair shared by several DISTINCT canonical products is
# a fabrication tell (flipkart cross-sell carousel bled one PDP's price onto delisted
# SKUs). We require sale != mrp (a genuine same-list-price collision across cheap SKUs,
# e.g. several items at sale==mrp==50, is normal and excluded).
SHARED_PRICE_MIN_CANON = 2       # a "qualifying pair" = a discounted (sale,mrp) held by >= this many canonicals
SHARED_PRICE_BROKEN_CANON = 5    # any single pair held by >= this many canonicals -> BROKEN
SHARED_PRICE_SUSPECT_CANON = 3   # any single pair held by >= this many canonicals -> SUSPECT
# Row-share backstop: a couple of coincidental same-price collisions in a big catalog is
# normal; a LARGE share of priced rows tied up in shared discounted pairs is fabrication.
# (Audited contaminated flipkart 2026-06-04: max_canon=3, shared_frac=12% -> SUSPECT.)
SHARED_PRICE_BROKEN_FRAC = 0.25  # >= this share of priced rows in shared discounted pairs -> BROKEN
SHARED_PRICE_SUSPECT_FRAC = 0.08 # >= this share -> SUSPECT

# --- staleness alarm (hybrid search-API platforms, e.g. Zepto) --------------
# Goal: flag when we may be recording a LAGGING catalogue rather than the live price (the bug the
# owner reported on Zepto). The true lag signal is NOT the per-product `cached` flag — Zepto leaves
# it false even when serving a stale snapshot — it is the per-store `is_realtime_model_data_fetched`:
# when false (reason e.g. mongo_data_exists) the store was served from a NON-realtime snapshot that
# can stick. So the alarm raises SUSPECT when a SKU's modal price is FROZEN across >= N runs WHILE a
# high share of stores are on the snapshot path. The frozen branch reads data/<p>/history.csv and
# works regardless of `cached`. A frozen price on the REALTIME path is a live, genuinely-stable price
# (not flagged). Failure-proof; n/a for platforms that emit no freshness signal.
NONREALTIME_GATE_PCT = 50.0      # >= this % of stores on the non-realtime snapshot path opens the gate
STALE_FROZEN_RUNS = 9            # modal price identical across >= this many runs -> "frozen"

# Markers that, if found in scraped text, mean we captured an error page.
BLOCK_MARKERS = (
    "captcha", "are you a robot", "access denied", "403 forbidden",
    "request blocked", "blocked", "enter the characters", "robot check",
    "to discuss automated access", "verify you are human", "cloudfront",
    "<!doctype html", "<html", "service unavailable", "rate limit",
)

REQUIRED_ROW_FIELDS = ("sku_raw", "canonical", "sale", "mrp", "discount_pct", "in_stock")


# --- logging ----------------------------------------------------------------
def log(msg):
    """Append a timestamped line to logs/review.log. Never raises."""
    try:
        os.makedirs(LOGS_DIR, exist_ok=True)
        stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with open(LOG_PATH, "a") as f:
            f.write(f"[{stamp}] {msg}\n")
    except Exception:
        pass  # logging must never break the run


# --- data loading / shape normalization -------------------------------------
def load_result(platform):
    path = os.path.join(PLATFORMS_DIR, platform, "result.json")
    with open(path) as f:
        return json.load(f), path


def extract_rows(data):
    """
    Return a flat list of row dicts, handling BOTH shapes:
      - national:    {"allRows": [ {...row...}, ... ]}
      - per-pincode: {"perPin": [ {..., "rows": [ {...row...} ]}, ... ]}
    Real files carry both keys; allRows is the authoritative flat list when
    present, otherwise we flatten perPin[].rows.
    """
    rows = data.get("allRows")
    if isinstance(rows, list) and rows:
        return rows
    flat = []
    for pin in data.get("perPin", []) or []:
        for r in pin.get("rows", []) or []:
            flat.append(r)
    return flat


def is_per_pincode(data):
    """National runs cover a single 'All India' pseudo-pincode (total<=1)."""
    summary = data.get("summary", {}) or {}
    total = summary.get("pincodes_total")
    if isinstance(total, int):
        return total > 1
    # fallback: count distinct real pincodes
    pins = {p.get("pincode") for p in (data.get("perPin", []) or [])}
    pins.discard("-")
    pins.discard(None)
    return len(pins) > 1


def pincodes_with_jivo(data, rows):
    summary = data.get("summary", {}) or {}
    val = summary.get("pincodes_with_jivo")
    if isinstance(val, int):
        return val
    # derive: distinct pincodes that have >=1 row
    if data.get("perPin"):
        return len({p.get("pincode") for p in data["perPin"]
                    if (p.get("rows") or [])})
    return len({r.get("pincode") for r in rows if r.get("pincode")})


# --- baselines --------------------------------------------------------------
def load_baseline(platform):
    path = os.path.join(BASELINES_DIR, f"{platform}.json")
    if not os.path.isfile(path):
        return None
    try:
        with open(path) as f:
            return json.load(f)
    except Exception as e:
        log(f"{platform}: failed to read baseline ({e}); treating as none")
        return None


def normalize_baseline(platform, bl):
    """
    Coerce ANY pre-existing/legacy baseline shape into the canonical
    {"platform":..., "samples":[ {rows, unique_skus, pincodes_with_jivo} ]}.
    Tolerates: None, a bare number, {"rows":N}, {"summary":{"total_rows":N}},
    or our own {"samples":[...]} format. Never raises.
    """
    canon = {"platform": platform, "samples": []}
    if bl is None:
        return canon
    try:
        if isinstance(bl, dict) and isinstance(bl.get("samples"), list):
            canon["samples"] = list(bl["samples"])
            if bl.get("updated_at"):
                canon["updated_at"] = bl["updated_at"]
            return canon

        # --- legacy / foreign shapes -> one synthetic seed sample ---
        rows = None
        if isinstance(bl, (int, float)):
            rows = bl
        elif isinstance(bl, dict):
            if isinstance(bl.get("rows"), (int, float)):
                rows = bl["rows"]
            elif isinstance(bl.get("total_rows"), (int, float)):
                rows = bl["total_rows"]
            elif isinstance(bl.get("summary"), dict) and \
                    isinstance(bl["summary"].get("total_rows"), (int, float)):
                rows = bl["summary"]["total_rows"]
        if rows is not None:
            seed = {"run_id": "seed", "rows": rows}
            for k in ("unique_skus", "pincodes_with_jivo"):
                v = bl.get(k) if isinstance(bl, dict) else None
                if isinstance(v, (int, float)):
                    seed[k] = v
            canon["samples"] = [seed]
    except Exception as e:
        log(f"{platform}: could not normalize legacy baseline ({e}); using empty")
    return canon


def baseline_expected(bl):
    """Rolling expected values = mean over recent OK samples (or None)."""
    if not bl:
        return None
    samples = bl.get("samples", [])
    if not samples:
        return None

    def avg(key):
        vals = [s[key] for s in samples if isinstance(s.get(key), (int, float))]
        return (sum(vals) / len(vals)) if vals else None

    return {
        "rows": avg("rows"),
        "unique_skus": avg("unique_skus"),
        "pincodes_with_jivo": avg("pincodes_with_jivo"),
        "priced_rows": avg("priced_rows"),
        "n": len(samples),
    }


def update_baseline(platform, sample):
    """Append this run's metrics to the rolling baseline. OK runs only."""
    path = os.path.join(BASELINES_DIR, f"{platform}.json")
    bl = normalize_baseline(platform, load_baseline(platform))
    bl["samples"].append(sample)
    bl["samples"] = bl["samples"][-BASELINE_WINDOW:]
    bl["updated_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    try:
        os.makedirs(BASELINES_DIR, exist_ok=True)
        with open(path, "w") as f:
            json.dump(bl, f, indent=2)
        log(f"{platform}: baseline updated (n={len(bl['samples'])}, "
            f"rows={sample['rows']}, skus={sample['unique_skus']})")
    except Exception as e:
        log(f"{platform}: failed to write baseline ({e})")


# --- deterministic checks ---------------------------------------------------
def num(v):
    """Coerce to float or None."""
    try:
        if v is None:
            return None
        return float(v)
    except (TypeError, ValueError):
        return None


def _modal(vals):
    """Most common value (ties -> smallest), ignoring None. Returns None if empty."""
    vals = [v for v in vals if v is not None]
    if not vals:
        return None
    cnt = Counter(vals)
    top = max(cnt.values())
    return min(p for p, n in cnt.items() if n == top)


def _modal_series(platform, rows, run_id):
    """
    {canonical -> [modal price per run]} over the newest STALE_FROZEN_RUNS runs (history +
    this run), None-modals dropped per canonical. history.csv is written AFTER review, so it
    does not yet contain this run — we fold in this run's modal prices from `rows`.
    Returns {} when there is not yet enough history to judge. Best-effort; never raises.
    """
    hist_path = os.path.join(ROOT, "data", platform, "history.csv")
    by_run = {}   # run_id -> {canonical -> [prices]}
    try:
        if os.path.isfile(hist_path):
            with open(hist_path, newline="") as f:
                for row in csv.DictReader(f):
                    rid = row.get("run_id")
                    canon = row.get("canonical_sku")
                    if not rid or not canon:
                        continue
                    try:
                        price = float(row.get("price")) if row.get("price") not in (None, "") else None
                    except (TypeError, ValueError):
                        price = None
                    by_run.setdefault(rid, {}).setdefault(canon, []).append(price)
    except Exception as e:
        log(f"{platform}: frozen-sku history read failed ({e}); skipping frozen check")
        return {}

    # Fold in THIS run's prices. history.csv is written AFTER review, so normally run_id is absent
    # here; but a self-heal re-run reuses the same run_id and it MAY already be present. Either way
    # we REBUILD this run's entry from the current rows (authoritative) rather than appending, so we
    # never double-count an existing run_id into a corrupted modal.
    cur = {}
    by_run[run_id] = cur
    for r in rows:
        c = r.get("canonical")
        s = num(r.get("sale"))
        if c:
            cur.setdefault(c, []).append(s)

    # modal price per run, newest STALE_FROZEN_RUNS runs only
    recent = sorted(by_run.keys())[-STALE_FROZEN_RUNS:]
    if len(recent) < STALE_FROZEN_RUNS:
        return {}   # not enough history yet to judge "frozen"
    series = {}
    for canon in set(cur.keys()):
        modals = [_modal(by_run[rid].get(canon, [])) for rid in recent]
        modals = [m for m in modals if m is not None]
        series[canon] = modals
    return series


def _frozen_skus(platform, rows, run_id):
    """
    SKUs whose MODAL price has been identical across the last STALE_FROZEN_RUNS runs.
    Returns a sorted list of frozen canonical SKU names.
    """
    series = _modal_series(platform, rows, run_id)
    return sorted(c for c, modals in series.items()
                  if len(modals) >= STALE_FROZEN_RUNS and len(set(modals)) == 1)


def _price_movers(platform, rows, run_id):
    """
    SKUs whose MODAL price CHANGED across the recent-run window — proof the data path is
    LIVE (a stuck snapshot would freeze every SKU). Returns a sorted list of canonicals
    with >= 2 distinct modal prices over the window.
    """
    series = _modal_series(platform, rows, run_id)
    return sorted(c for c, modals in series.items()
                  if len(modals) >= 2 and len(set(modals)) > 1)


def _pct_non_realtime(data, fresh):
    """
    Share of serviceable stores served from the NON-realtime (snapshot) path. Prefer the
    scraper's aggregate; else derive from perPin store markers. Returns (pct, reason_str).
    """
    reasons = (fresh or {}).get("realtime_not_enabled_reasons") or {}
    if fresh and isinstance(fresh.get("pct_non_realtime"), (int, float)):
        pct = float(fresh["pct_non_realtime"])
    else:
        served = nonrt = 0
        derived = {}
        for p in data.get("perPin", []) or []:
            if not p.get("serviceable"):
                continue
            served += 1
            m = ((p.get("freshness") or {}).get("markers")) or {}
            if m.get("is_realtime_model_data_fetched") is False:
                nonrt += 1
                r = m.get("realtime_model_not_enabled_reason")
                if r:
                    derived[r] = derived.get(r, 0) + 1
        pct = (100.0 * nonrt / served) if served else 0.0
        if not reasons:
            reasons = derived
    reason_str = ", ".join(f"{k}={v}" for k, v in sorted(reasons.items())) if reasons else ""
    return pct, reason_str


def staleness_alarm(data, rows, platform, run_id):
    """
    Returns (ok, detail, severity). ok=False drives a SUSPECT verdict. No freshness signal in
    the data => n/a (ok). SUSPECT when a SKU's modal price is FROZEN across >= STALE_FROZEN_RUNS
    runs AND a high share of stores are on the non-realtime snapshot path (the stuck-snapshot
    case). The frozen check works regardless of the per-product `cached` flag.
    """
    summary = data.get("summary", {}) or {}
    fresh = summary.get("freshness") if isinstance(summary.get("freshness"), dict) else None
    has_signal = bool(fresh) or any(
        ("cached" in r) for r in rows[: min(50, len(rows))]) or bool(data.get("perPin"))
    if not has_signal:
        return True, "no freshness signal in data (n/a for this platform)", "suspect"

    pct_nonrt, reason_str = _pct_non_realtime(data, fresh)
    snapshot_served = pct_nonrt >= NONREALTIME_GATE_PCT
    frozen = _frozen_skus(platform, rows, run_id)
    movers = _price_movers(platform, rows, run_id)

    # SUSPECT only for a TRULY-STUCK scraper. A frozen price is genuine market stability,
    # not a stale snapshot, whenever OTHER SKUs on the SAME path MOVED across the window —
    # that proves the path is live (zepto 2026-06-08: 9/23 SKUs moved while 14 held steady,
    # bigbasket-confirmed stable, yet the old gate held the whole platform). So we alarm
    # only when prices are frozen, the snapshot path is open, AND not a single SKU moved
    # across the window (nothing is live -> the scraper is stuck, not the market).
    if frozen and snapshot_served and not movers:
        return (False,
                f"{len(frozen)} SKU(s) price-frozen across {STALE_FROZEN_RUNS} runs while "
                f"{pct_nonrt:.0f}% of stores are on the non-realtime snapshot path AND NO SKU "
                f"moved across the window"
                f"{(' (' + reason_str + ')') if reason_str else ''} — path looks stuck, "
                f"prices may be stale: {', '.join(frozen[:6])}",
                "suspect")

    # Pass, but report state.
    bits = [f"{pct_nonrt:.0f}% stores non-realtime/snapshot"
            + (f" ({reason_str})" if reason_str else "")]
    if frozen:
        if movers:
            why = (f"path proven live by {len(movers)} SKU(s) that moved "
                   f"(e.g. {', '.join(movers[:3])}) -> genuinely stable")
        elif snapshot_served:
            why = "(snapshot path)"
        else:
            why = "(realtime path -> live, treated as genuinely stable)"
        bits.append(
            f"{len(frozen)} SKU(s) price-stable across {STALE_FROZEN_RUNS} runs " + why)
    else:
        bits.append(f"no SKU frozen across {STALE_FROZEN_RUNS} runs")
    if movers:
        bits.append(f"{len(movers)} SKU(s) moved over the window")
    return True, "; ".join(bits), "suspect"


# --- new systemic guards (geo / block / per-litre / fabrication) ------------
_UNIT_ML = {"ml": 1.0, "l": 1000.0, "ltr": 1000.0, "litre": 1000.0,
            "liter": 1000.0, "litres": 1000.0, "liters": 1000.0}
_NUM_UNIT_RE = __import__("re").compile(
    r"(\d+(?:\.\d+)?)\s*(ml|ltr|litres|liters|litre|liter|l)\b")
# Explicit WEIGHT token ("200 gm", "1 kg"): a non-oil freebie in a mixed bundle
# ("1LTR + 200 GM (BUNDLE)"). It contributes NO volume and must NEVER fall through
# to the bare-number branch and inherit a sibling's litre unit (the 2026-06-06
# false-SUSPECT: '200 GM' read as 200 litres -> "implies 201000ml").
_NUM_WEIGHT_RE = __import__("re").compile(
    r"(\d+(?:\.\d+)?)\s*(kgs?|gms?|grams?|g)\b")
_NUM_RE = __import__("re").compile(r"(\d+(?:\.\d+)?)")
_ADD_SPLIT_RE = __import__("re").compile(r"\s*\+\s*|\s+with\s+|\s*&\s*|\s+and\s+|\s+plus\s+")
_ADD_PRESENT_RE = __import__("re").compile(r"\+|\swith\s|\s&\s|\sand\s|\splus\s")
_MULT_A_RE = __import__("re").compile(r"(\d+(?:\.\d+)?)\s*(ml|ltr|litres?|liters?|l)\s*[x×]\s*(\d+)")
_MULT_B_RE = __import__("re").compile(r"(\d+)\s*[x×]\s*(\d+(?:\.\d+)?)\s*(ml|ltr|litres?|liters?|l)\b")
_PACK_OF_RE = __import__("re").compile(r"pack of (\d+)")


def parse_total_vol_ml(pack):
    """
    TOTAL millilitres implied by a `pack` string, or None if it carries no volume token.
    Handles additive combos ('5+1 LTR', '200 ML + 5LTR', '5 Litre with 5 Litre',
    '5 + 1 + 1 LTR' with a shared trailing unit), multiplicative packs ('1 L X 2',
    'Pack of 2 ... 1 L') and plain single packs. An explicit WEIGHT addend
    ('1LTR + 200 GM' = oil + seed freebie) contributes no volume — it is never
    read as litres. Used only to DETECT under-counted combo volumes — it never
    rewrites the scraper's value. Never raises.
    """
    if not pack:
        return None
    try:
        t = str(pack).lower()
        # multiplicative: 'M unit x N'  or  'N x M unit'
        m = _MULT_A_RE.search(t)
        if m:
            um = _UNIT_ML.get(m.group(2))
            if um:
                return float(m.group(1)) * um * float(m.group(3))
        m = _MULT_B_RE.search(t)
        if m:
            um = _UNIT_ML.get(m.group(3))
            if um:
                return float(m.group(1)) * float(m.group(2)) * um
        # additive: sum every volume token; a unit-less addend inherits the shared trailing unit
        if _ADD_PRESENT_RE.search(t):
            parts = _ADD_SPLIT_RE.split(t)
            shared = None
            for p in reversed(parts):
                nu = _NUM_UNIT_RE.search(p)
                if nu:
                    shared = nu.group(2)
                    break
            total, got = 0.0, False
            for p in parts:
                nu = _NUM_UNIT_RE.search(p)
                if nu:
                    um = _UNIT_ML.get(nu.group(2))
                    if um:
                        total += float(nu.group(1)) * um
                        got = True
                elif _NUM_WEIGHT_RE.search(p):
                    # explicit weight addend (g/gm/kg) = non-oil freebie in a
                    # mixed bundle -> zero volume, and crucially NOT a bare
                    # number that inherits the shared litre unit.
                    continue
                else:
                    nm = _NUM_RE.search(p)
                    if nm and shared:
                        um = _UNIT_ML.get(shared)
                        if um:
                            total += float(nm.group(1)) * um
                            got = True
            return total if got else None
        # single token, optionally multiplied by 'pack of N'
        nu = _NUM_UNIT_RE.search(t)
        if nu:
            um = _UNIT_ML.get(nu.group(2))
            if um:
                base = float(nu.group(1)) * um
                pof = _PACK_OF_RE.search(t)
                if pof:
                    base *= int(pof.group(1))
                return base
    except Exception:
        return None
    return None


def geo_consistency(rows, per_pincode):
    """
    (ok, detail, severity). Flags a single resolved store_id recorded under many distinct
    cities (default/fallback-store contamination). n/a for national platforms (empty
    store_id). Reinforces with the identical-modal-price tell in the detail string.
    """
    if not per_pincode:
        return True, "national run (no per-store geo); n/a", "broken"
    by_store_cities = {}
    by_store_prices = {}
    for r in rows:
        sid = r.get("store_id")
        if sid in (None, "", "-"):
            continue
        city = r.get("city")
        if not city:
            continue
        by_store_cities.setdefault(sid, set()).add(city)
        by_store_prices.setdefault(sid, []).append(num(r.get("sale")))
    if not by_store_cities:
        return True, "no resolved store_id on rows; geo check n/a", "broken"
    worst_sid, worst_cities = max(by_store_cities.items(), key=lambda kv: len(kv[1]))
    span = len(worst_cities)
    if span >= GEO_STORE_CITY_SPAN_SUSPECT:
        modal = _modal(by_store_prices.get(worst_sid, []))
        n_rows = len(by_store_prices.get(worst_sid, []))
        sample = ", ".join(sorted(str(c) for c in worst_cities)[:6])
        detail = (f"store_id {worst_sid} spans {span} distinct cities "
                  f"({sample}{'…' if span > 6 else ''}) across {n_rows} rows"
                  f"{f', identical modal sale ₹{modal:g}' if modal is not None else ''}"
                  f" — default/fallback-store contamination")
        sev = "broken" if span >= GEO_STORE_CITY_SPAN_BROKEN else "suspect"
        return False, detail, sev
    return True, f"max store_id city-span = {span} (stores stay local)", "broken"


def block_and_priced_floor(data, rows, expected):
    """
    (ok, detail, severity). Catches a blocked/throttled run that pads placeholder rows so
    the row-count checks stay green: scans status/scrape_status values + block text, reads
    summary.block_rate_pct, and floors priced-in-stock rows (absolute + vs baseline).
    """
    summary = data.get("summary", {}) or {}
    n = len(rows)
    blocked_rows = 0
    for r in rows:
        hit = False
        for f in STATUS_FIELDS:
            v = str(r.get(f) or "").strip().lower()
            if v and v in STATUS_BLOCK_VALUES:
                hit = True
                break
        if not hit:
            for f in BLOCK_TEXT_FIELDS:
                txt = str(r.get(f) or "").lower()
                if txt and any(mk in txt for mk in BLOCK_MARKERS):
                    hit = True
                    break
        if hit:
            blocked_rows += 1
    block_frac = (blocked_rows / n) if n else 0.0

    rate = num(summary.get("block_rate_pct"))
    priced_instock = sum(1 for r in rows
                         if r.get("in_stock") and (num(r.get("sale")) or 0) > 0)

    sev = None
    reasons = []
    if block_frac >= BLOCK_FRAC_BROKEN:
        sev = "broken"
        reasons.append(f"{blocked_rows}/{n} rows ({block_frac:.0%}) carry block/error markers")
    elif block_frac >= BLOCK_FRAC_SUSPECT:
        sev = sev or "suspect"
        reasons.append(f"{blocked_rows}/{n} rows ({block_frac:.0%}) carry block/error markers")
    if rate is not None and rate >= BLOCK_RATE_BROKEN:
        sev = "broken"
        reasons.append(f"summary.block_rate_pct={rate:g}%")
    elif rate is not None and rate >= BLOCK_RATE_SUSPECT:
        sev = sev or "suspect"
        reasons.append(f"summary.block_rate_pct={rate:g}%")
    if n > 0 and priced_instock == 0:
        sev = "broken"
        reasons.append(f"0 priced in-stock rows out of {n} (all OOS/placeholder — scrape likely failed)")
    elif expected and expected.get("priced_rows"):
        base = expected["priced_rows"]
        ratio = priced_instock / base if base else 1.0
        if ratio < (1 - PRICED_BROKEN_DROP):
            sev = "broken"
            reasons.append(f"{priced_instock} priced in-stock rows is {ratio:.0%} of baseline {base:.0f} (collapse)")
        elif ratio < (1 - PRICED_SUSPECT_DROP):
            sev = sev or "suspect"
            reasons.append(f"{priced_instock} priced in-stock rows is {ratio:.0%} of baseline {base:.0f}")

    if sev:
        return False, "; ".join(reasons), sev
    base_note = (f", vs baseline {expected['priced_rows']:.0f}"
                 if (expected and expected.get("priced_rows")) else "")
    return True, (f"{priced_instock} priced in-stock rows{base_note}; "
                  f"{blocked_rows} block/error-marked rows"), "broken"


def _is_oil_row(r):
    """True if the row is a cooking/olive oil SKU (so the absolute Rs/L ceiling applies).
    Uses an explicit is_oil flag when present, else looks for 'oil' in the name/category."""
    if r.get("is_oil"):
        return True
    txt = " ".join(str(r.get(k) or "")
                   for k in ("sku_raw", "canonical", "category", "sub_category")).lower()
    return "oil" in txt


def _row_per_litre(r):
    """Published per_litre if present, else derived sale/(vol_ml/1000). None if neither."""
    pl = num(r.get("per_litre"))
    if pl is not None:
        return pl
    s = num(r.get("sale"))
    vol = num(r.get("vol_ml"))
    if s is not None and s > 0 and vol and vol > 0:
        return s / (vol / 1000.0)
    return None


def per_litre_combo_sanity(rows):
    """
    (ok, detail, severity). Flags inflated per_litre two complementary ways:
      (a) STRUCTURAL — recorded vol_ml materially undercounts the `pack` string's parsed
          total volume (combo/multipack mis-parse the pack field exposes); and
      (b) ABSOLUTE CEILING — a priced OIL SKU whose per_litre exceeds ABS_PER_LITRE_OIL_MAX,
          which catches combos whose volume token lives in the NAME (invisible to the pack
          parse) without false-flagging legit tiny non-oil packs.
    """
    bad = []
    for r in rows:
        vol = r.get("vol_ml")
        if not isinstance(vol, (int, float)) or vol <= 0:
            continue
        total = parse_total_vol_ml(r.get("pack"))
        if total and total > vol * COMBO_VOL_MARGIN:
            bad.append((r.get("pack"), vol, total, r.get("per_litre")))

    over = []   # priced oil SKUs above the absolute Rs/L ceiling
    for r in rows:
        s = num(r.get("sale"))
        if not s or s <= 0 or not _is_oil_row(r):
            continue
        pl = _row_per_litre(r)
        if pl is not None and pl > ABS_PER_LITRE_OIL_MAX:
            over.append((r.get("sku_raw"), r.get("pack"), pl))

    if not bad and not over:
        return True, (f"per_litre consistent with parsed pack volume and within the "
                      f"₹{ABS_PER_LITRE_OIL_MAX:.0f}/L oil ceiling for all rows"), "suspect"

    bits = []
    if bad:
        packs = {}
        for pack, vol, total, pl in bad:
            packs.setdefault((pack, vol), (total, pl))
        (epack, evol), (etot, epl) = next(iter(sorted(
            packs.items(), key=lambda kv: -(kv[1][1] or 0))))
        bits.append(f"{len(bad)} rows / {len(packs)} packs per_litre inflated by an "
                    f"under-counted combo volume e.g. pack {epack!r} recorded {evol:g}ml but "
                    f"implies {etot:g}ml (per_litre ₹{epl})")
    if over:
        ename, epack, epl = max(over, key=lambda x: x[2])
        bits.append(f"{len(over)} priced oil SKU(s) over ₹{ABS_PER_LITRE_OIL_MAX:.0f}/L "
                    f"ceiling e.g. {str(ename)[:40]!r} (pack {epack!r}) = ₹{epl:.0f}/L "
                    f"(likely a name-hidden combo)")
    return False, "; ".join(bits), "suspect"


_COMBO_RE = __import__("re").compile(r"\+|\bcombo\b|pack of \d+")
_WS_RE = __import__("re").compile(r"\s+")


def _is_combo_listing(r):
    """
    True if this row is a multipack/combo listing. Combos legitimately share ONE bundle
    price across sellers/variants (e.g. flipkart 'CANOLA 5+1L', '1L+1L+1L' 3-oil packs),
    so they must NOT count as fabrication. Detected from the human name fields (item /
    sku_raw): a '+' addend, the word 'combo', or 'pack of N'. Falls back to None-safe.
    """
    for fld in (r.get("item"), r.get("sku_raw")):
        if fld and _COMBO_RE.search(str(fld).lower()):
            return True
    return False


def _product_identity(r):
    """
    A normalized key for the UNDERLYING product, so seller-duplicate listings of the same
    product (distinct per-FSN canonicals, identical product) collapse to ONE identity.
    Prefer the human name (`item`, e.g. flipkart 'CANOLA 5L') normalized to lowercase /
    collapsed whitespace; else fall back to the per-FSN `canonical`. On platforms with no
    `item` field this is exactly the old canonical-counting behaviour.
    """
    it = r.get("item")
    if it:
        return ("item", _WS_RE.sub(" ", str(it).strip().lower()))
    return ("canon", r.get("canonical"))


def shared_price_dup(rows):
    """
    (ok, detail, severity). Flags a DISCOUNTED (sale,mrp) pair shared by several DISTINCT
    UNDERLYING PRODUCTS — a price-fabrication / cross-sell-bleed tell. sale==mrp collisions
    (many cheap SKUs at one list price) are excluded.

    Identity-aware (2026-06-08, W1): the genuine signal is ONE price appearing across
    truly-UNRELATED products. Two things are NOT that and must not fire:
      - seller-duplicate listings of the SAME product (distinct per-FSN canonicals, same
        `item`) — collapsed to one identity via _product_identity; and
      - COMBO / multipack listings, which legitimately share a bundle price — excluded
        entirely via _is_combo_listing.
    So we count distinct PRODUCT IDENTITIES among non-combo rows, not raw canonicals. This
    is monotonically RELAXING vs the old canonical count (identities <= canonicals, combos
    dropped), so it can only clear false positives, never newly flag a clean platform.
    """
    pair = {}
    priced = 0
    for r in rows:
        s = num(r.get("sale"))
        m = num(r.get("mrp"))
        c = r.get("canonical")
        if s is not None and s > 0:
            priced += 1
        if s is None or m is None or not c:
            continue
        if abs(s - m) < 0.5:        # require a genuine discount
            continue
        if _is_combo_listing(r):    # combos legitimately share a bundle price
            continue
        pair.setdefault((round(s, 2), round(m, 2)), set()).add(_product_identity(r))
    qual = {k: v for k, v in pair.items() if len(v) >= SHARED_PRICE_MIN_CANON}
    if not qual:
        return True, "no discounted (sale,mrp) pair shared across distinct products", "suspect"
    max_canon = max(len(v) for v in qual.values())
    # share of priced rows that are a non-combo discounted row in one of the shared pairs
    shared_rows = sum(1 for r in rows
                      if (num(r.get("sale")) is not None and num(r.get("mrp")) is not None
                          and abs(num(r.get("sale")) - num(r.get("mrp"))) >= 0.5
                          and not _is_combo_listing(r)
                          and (round(num(r.get("sale")), 2), round(num(r.get("mrp")), 2)) in qual))
    shared_frac = (shared_rows / priced) if priced else 0.0
    worst = max(qual.items(), key=lambda kv: len(kv[1]))
    detail = (f"{len(qual)} discounted (sale,mrp) pair(s) shared by >= "
              f"{SHARED_PRICE_MIN_CANON} distinct products; worst {worst[0]} held by "
              f"{len(worst[1])} products; {shared_rows}/{priced} priced rows "
              f"({shared_frac:.0%}) in shared pairs — possible fabrication/cross-sell bleed")
    if max_canon >= SHARED_PRICE_BROKEN_CANON or shared_frac >= SHARED_PRICE_BROKEN_FRAC:
        return False, detail, "broken"
    if max_canon >= SHARED_PRICE_SUSPECT_CANON or shared_frac >= SHARED_PRICE_SUSPECT_FRAC:
        return False, detail, "suspect"
    return True, detail + " (below trigger)", "suspect"


def run_checks(data, rows, per_pincode, expected, run_id, platform):
    """
    Run all FREE deterministic checks. Each appends a dict
    {name, pass, detail} and tags severity in the returned list-of-tuples
    (check, severity) where severity is 'broken' or 'suspect' on failure.
    Returns (checks, reasons, hard_broken, soft_suspect).
    """
    checks = []
    reasons = []
    hard_broken = False
    soft_suspect = False

    def add(name, ok, detail, severity="suspect"):
        nonlocal hard_broken, soft_suspect
        checks.append({"name": name, "pass": bool(ok), "detail": detail})
        if not ok:
            reasons.append(f"{name}: {detail}")
            if severity == "broken":
                hard_broken = True
            else:
                soft_suspect = True

    n_rows = len(rows)
    skus = {r.get("canonical") for r in rows if r.get("canonical")}
    n_skus = len(skus)

    # 1) non-zero rows -----------------------------------------------------
    add("non_zero_rows", n_rows > 0,
        f"{n_rows} rows" if n_rows else "0 rows scraped",
        severity="broken")

    # 2) rows above absolute floor ----------------------------------------
    add("rows_above_floor", n_rows >= ABS_MIN_ROWS,
        f"{n_rows} rows (floor {ABS_MIN_ROWS})",
        severity="broken")

    # 3) rows vs baseline --------------------------------------------------
    if expected and expected.get("rows"):
        base = expected["rows"]
        ratio = n_rows / base if base else 1.0
        if ratio < (1 - ROWS_BROKEN_DROP):
            add("rows_vs_baseline", False,
                f"{n_rows} rows is {ratio:.0%} of baseline {base:.0f} (collapse)",
                severity="broken")
        elif ratio < (1 - ROWS_SUSPECT_DROP):
            add("rows_vs_baseline", False,
                f"{n_rows} rows is {ratio:.0%} of baseline {base:.0f}",
                severity="suspect")
        elif ratio > ROWS_SUSPECT_SPIKE:
            add("rows_vs_baseline", False,
                f"{n_rows} rows is {ratio:.0%} of baseline {base:.0f} (spike)",
                severity="suspect")
        else:
            add("rows_vs_baseline", True,
                f"{n_rows} rows vs baseline {base:.0f} ({ratio:.0%})")
    else:
        add("rows_vs_baseline", True, "no baseline yet (first OK run seeds it)")

    # 4) unique SKUs vs baseline ------------------------------------------
    if expected and expected.get("unique_skus"):
        base = expected["unique_skus"]
        ratio = n_skus / base if base else 1.0
        ok = ratio >= (1 - SKU_SUSPECT_DROP)
        add("skus_vs_baseline", ok,
            f"{n_skus} unique SKUs vs baseline {base:.0f} ({ratio:.0%})")
    else:
        add("skus_vs_baseline", True,
            f"{n_skus} unique SKUs (no baseline yet)")

    # 5) prices > 0 and within plausible band (IN-STOCK rows only — an out-of-stock
    #    listing legitimately has no current price). Two cases are NOT the same failure:
    #      (a) a NUMERIC but implausible price (<=0 or outside the band) -> real
    #          garbage; flag SUSPECT even for a single row.
    #      (b) an in-stock row with NO displayed price (sale is None) -> legitimate
    #          on Amazon for a few bulk SKUs ("see price in cart"). A small fraction
    #          is normal; only a SYSTEMIC loss (a high fraction of in-stock rows with
    #          no price) means the price selector likely broke -> SUSPECT.
    bad_price = []          # in-stock rows with a numeric but implausible price
    no_price = 0            # in-stock rows with no displayed price at all
    n_instock = 0
    for i, r in enumerate(rows):
        if not r.get("in_stock"):   # skip out-of-stock (0/False/None): no current price
            continue
        n_instock += 1
        sale = num(r.get("sale"))
        if sale is None:
            no_price += 1
            continue
        if sale <= 0 or sale < PRICE_MIN or sale > PRICE_MAX:
            bad_price.append((i, r.get("sku_raw"), r.get("sale")))
    noprice_frac = (no_price / n_instock) if n_instock else 0.0
    systemic_noprice = noprice_frac > PRICE_MISSING_SUSPECT_FRAC
    ok = (len(bad_price) == 0) and (not systemic_noprice)
    if ok:
        detail = "all sale prices in (0, band]"
        if no_price:
            detail += (f" ({no_price}/{n_instock} in-stock rows have no displayed "
                       f"price — Amazon 'see price in cart', within tolerance)")
    elif bad_price:
        detail = (f"{len(bad_price)} rows w/ implausible price e.g. "
                  f"{bad_price[0][1]!r}={bad_price[0][2]!r}")
        if no_price:
            detail += f"; plus {no_price}/{n_instock} in-stock rows w/ no price"
    else:  # systemic_noprice
        detail = (f"{no_price}/{n_instock} in-stock rows ({noprice_frac:.0%}) have no "
                  f"displayed price (> {PRICE_MISSING_SUSPECT_FRAC:.0%} tolerance); "
                  f"price selector may have broken")
    add("prices_in_band", ok, detail, severity="suspect")

    # 6) MRP >= sale price -------------------------------------------------
    bad_mrp = []
    for r in rows:
        sale = num(r.get("sale"))
        mrp = num(r.get("mrp"))
        if sale is not None and mrp is not None and mrp > 0 and sale > 0:
            if mrp < sale - 0.5:  # tolerate float noise
                bad_mrp.append((r.get("sku_raw"), mrp, sale))
    ok = len(bad_mrp) == 0
    add("mrp_ge_sale", ok,
        "MRP >= sale for all priced rows" if ok
        else f"{len(bad_mrp)} rows w/ MRP<sale e.g. {bad_mrp[0]}",
        severity="suspect")

    # 7) discount_pct in [0,100] ------------------------------------------
    bad_disc = []
    for r in rows:
        d = num(r.get("discount_pct"))
        if d is not None and (d < 0 or d > 100):
            bad_disc.append((r.get("sku_raw"), d))
    ok = len(bad_disc) == 0
    add("discount_in_range", ok,
        "discount_pct in [0,100] for all rows" if ok
        else f"{len(bad_disc)} rows w/ discount out of range e.g. {bad_disc[0]}",
        severity="suspect")

    # 8) SKU names non-empty / not garbled --------------------------------
    empty_names = sum(1 for r in rows if not str(r.get("sku_raw") or "").strip())
    # garbled = no alphabetic chars at all in the name
    garbled = sum(1 for r in rows
                  if str(r.get("sku_raw") or "").strip()
                  and not any(c.isalpha() for c in str(r.get("sku_raw"))))
    ok = empty_names == 0 and garbled == 0
    add("sku_names_sane", ok,
        "all SKU names present and readable" if ok
        else f"{empty_names} empty, {garbled} garbled SKU names",
        severity="suspect")

    # 9) no captcha/403/blocked markers in the data -----------------------
    hits = []
    for r in rows:
        for field in ("sku_raw", "canonical", "store_name", "locality"):
            txt = str(r.get(field) or "").lower()
            for m in BLOCK_MARKERS:
                if m in txt:
                    hits.append((field, m))
                    break
            if hits:
                break
        if hits:
            break
    ok = len(hits) == 0
    add("no_block_markers", ok,
        "no captcha/403/blocked markers in data" if ok
        else f"block marker {hits[0][1]!r} found in {hits[0][0]}",
        severity="broken")

    # 10) pincode coverage (per-pincode platforms only) -------------------
    pin_jivo = pincodes_with_jivo(data, rows)
    if per_pincode:
        if expected and expected.get("pincodes_with_jivo"):
            base = expected["pincodes_with_jivo"]
            ratio = pin_jivo / base if base else 1.0
            if ratio < (1 - COVERAGE_BROKEN_DROP):
                add("pincode_coverage", False,
                    f"{pin_jivo} pincodes w/ Jivo is {ratio:.0%} of "
                    f"baseline {base:.0f} (collapsed)", severity="broken")
            elif ratio < (1 - COVERAGE_SUSPECT_DROP):
                add("pincode_coverage", False,
                    f"{pin_jivo} pincodes w/ Jivo is {ratio:.0%} of "
                    f"baseline {base:.0f}", severity="suspect")
            else:
                add("pincode_coverage", True,
                    f"{pin_jivo} pincodes w/ Jivo vs baseline {base:.0f} "
                    f"({ratio:.0%})")
        else:
            ok = pin_jivo > 0
            add("pincode_coverage", ok,
                f"{pin_jivo} pincodes w/ Jivo (no baseline yet)"
                if ok else "0 pincodes carry Jivo",
                severity="broken" if not ok else "suspect")
    else:
        add("pincode_coverage", True, "national run (single 'All India'); n/a")

    # 11) schema integrity (required fields present) ----------------------
    sample = rows[: min(50, len(rows))]
    missing_counts = {}
    for r in sample:
        for fld in REQUIRED_ROW_FIELDS:
            if fld not in r:
                missing_counts[fld] = missing_counts.get(fld, 0) + 1
    ok = len(missing_counts) == 0
    add("schema_integrity", ok,
        f"all required fields present ({', '.join(REQUIRED_ROW_FIELDS)})" if ok
        else f"missing fields in rows: {missing_counts}",
        severity="broken")

    # 12) freshness: captured_at is from THIS run, not stale ---------------
    captured_at = (data.get("summary", {}) or {}).get("captured_at")
    fresh_ok, fresh_detail = check_freshness(captured_at, run_id)
    add("freshness", fresh_ok, fresh_detail, severity="broken")

    # 13) price staleness alarm: cache-served / frozen prices (hybrid APIs) -
    try:
        st_ok, st_detail, st_sev = staleness_alarm(data, rows, platform, run_id)
    except Exception as e:
        log(f"{platform}: staleness_alarm raised (ignored): {e}")
        st_ok, st_detail, st_sev = True, f"staleness check error (ignored): {e}", "suspect"
    add("price_staleness", st_ok, st_detail, severity=st_sev)

    # 14) geo-consistency: one store_id must not span many cities (default-store
    #     contamination — blinkit). Per-pincode platforms only; national => n/a.
    try:
        g_ok, g_detail, g_sev = geo_consistency(rows, per_pincode)
    except Exception as e:
        log(f"{platform}: geo_consistency raised (ignored): {e}")
        g_ok, g_detail, g_sev = True, f"geo check error (ignored): {e}", "suspect"
    add("geo_consistency", g_ok, g_detail, severity=g_sev)

    # 15) priced-row floor + block scan: a blocked run that pads placeholder rows
    #     must not pass green (amazon/flipkart static-catalog row-padding).
    try:
        b_ok, b_detail, b_sev = block_and_priced_floor(data, rows, expected)
    except Exception as e:
        log(f"{platform}: block_and_priced_floor raised (ignored): {e}")
        b_ok, b_detail, b_sev = True, f"block/priced check error (ignored): {e}", "suspect"
    add("priced_floor_block", b_ok, b_detail, severity=b_sev)

    # 16) per-litre / combo volume sanity: under-counted combo volume inflates Rs/L
    #     (amazon parseVolMl combo bug).
    try:
        p_ok, p_detail, p_sev = per_litre_combo_sanity(rows)
    except Exception as e:
        log(f"{platform}: per_litre_combo_sanity raised (ignored): {e}")
        p_ok, p_detail, p_sev = True, f"per_litre check error (ignored): {e}", "suspect"
    add("per_litre_sanity", p_ok, p_detail, severity=p_sev)

    # 17) shared (sale,mrp) duplication across distinct SKUs (fabrication / cross-sell
    #     bleed — flipkart).
    try:
        d_ok, d_detail, d_sev = shared_price_dup(rows)
    except Exception as e:
        log(f"{platform}: shared_price_dup raised (ignored): {e}")
        d_ok, d_detail, d_sev = True, f"shared-price check error (ignored): {e}", "suspect"
    add("shared_price_dup", d_ok, d_detail, severity=d_sev)

    return checks, reasons, hard_broken, soft_suspect


def check_freshness(captured_at, run_id):
    """
    captured_at should be recent (< FRESHNESS_MAX_AGE_H old) AND, when the
    RUN_ID timestamp is parseable, on/near the run. RUN_ID = %Y-%m-%d-%H%M.
    """
    if not captured_at:
        return False, "no captured_at in summary"
    try:
        cap = datetime.datetime.fromisoformat(str(captured_at).replace("Z", "+00:00"))
    except Exception:
        return False, f"unparseable captured_at={captured_at!r}"

    now = datetime.datetime.now(datetime.timezone.utc)
    age_h = (now - cap).total_seconds() / 3600.0
    if age_h > FRESHNESS_MAX_AGE_H:
        return False, (f"captured_at {captured_at} is {age_h:.1f}h old "
                       f"(> {FRESHNESS_MAX_AGE_H}h); stale file?")
    if age_h < -1:  # captured in the future by >1h -> clock/garbage
        return False, f"captured_at {captured_at} is in the future ({age_h:.1f}h)"

    # Cross-check against RUN_ID date when it parses (best-effort).
    try:
        rid = datetime.datetime.strptime(run_id, "%Y-%m-%d-%H%M")
        cap_naive_date = cap.date()
        # allow same day or +/- 1 day (UTC vs IST boundary)
        if abs((rid.date() - cap_naive_date).days) > 1:
            return False, (f"captured_at date {cap_naive_date} far from "
                           f"RUN_ID date {rid.date()}; stale?")
    except Exception:
        pass

    return True, f"captured_at {captured_at} is {age_h:.1f}h old (fresh)"


# --- optional LLM layer -----------------------------------------------------
def maybe_source_secrets():
    """Best-effort: pull ANTHROPIC_API_KEY out of secrets.env if not in env."""
    if os.environ.get("ANTHROPIC_API_KEY"):
        return
    if not os.path.isfile(SECRETS_ENV):
        return
    try:
        with open(SECRETS_ENV) as f:
            for line in f:
                line = line.strip()
                if line.startswith("#") or "=" not in line:
                    continue
                k, _, v = line.partition("=")
                k = k.strip()
                if k == "ANTHROPIC_API_KEY" and k not in os.environ:
                    os.environ[k] = v.strip().strip('"').strip("'")
    except Exception as e:
        log(f"could not parse secrets.env for API key: {e}")


def build_digest(platform, per_pincode, n_rows, n_skus, pin_jivo, expected, rows):
    """Compact digest: counts + a few sample rows. Kept tiny on purpose."""
    samples = []
    for r in rows[:LLM_SAMPLE_ROWS]:
        samples.append({
            "name": r.get("sku_raw"),
            "pack": r.get("pack"),
            "sale": r.get("sale"),
            "mrp": r.get("mrp"),
            "disc%": r.get("discount_pct"),
            "in_stock": r.get("in_stock"),
        })
    digest = {
        "platform": platform,
        "shape": "per_pincode" if per_pincode else "national",
        "rows": n_rows,
        "unique_skus": n_skus,
        "pincodes_with_jivo": pin_jivo if per_pincode else None,
        "baseline_rows": round(expected["rows"]) if (expected and expected.get("rows")) else None,
        "sample_rows": samples,
    }
    return digest


def llm_judge(digest):
    """
    Single small, cheap LLM call. Returns a short note string, or None if no
    backend is configured / it fails. NEVER raises.

    Backends, auto-detected in priority order:
      (a) ANTHROPIC_API_KEY -> Messages API via stdlib urllib (no pip deps).
      (b) `claude -p` CLI headless fallback if the CLI exists and no key.
    Degrades gracefully to deterministic-only if neither exists.
    """
    prompt = (
        "You are a data-quality auditor for a retail price scraper that tracks "
        "the brand Jivo across Indian e-commerce. Jivo is a MULTI-CATEGORY brand: "
        "edible oils, olive oils, juices, vinegar, honey and other health-food & "
        "beverage lines (incl. wheatgrass juices and fizzy/tonic water) — these "
        "are all legitimate Jivo products, NOT contamination. Given this COMPACT "
        "digest of one scrape run, judge: does this look like REAL, sensible retail "
        "data (plausible product names, prices in INR, MRP>=sale, sane discounts), "
        "or does it look broken/empty/garbled/blocked?\n"
        "Reply in ONE line: start with OK or SUSPECT, then a brief reason "
        "(<=20 words).\n\nDIGEST:\n" + json.dumps(digest, ensure_ascii=False)
    )

    maybe_source_secrets()
    api_key = os.environ.get("ANTHROPIC_API_KEY")

    if api_key:
        try:
            return _llm_via_api(api_key, prompt)
        except Exception as e:
            log(f"LLM api backend failed: {e}; trying CLI fallback")

    # CLI fallback only when there's no key (per spec).
    if not api_key and _claude_cli_path():
        try:
            return _llm_via_cli(prompt)
        except Exception as e:
            log(f"LLM cli backend failed: {e}; deterministic-only")
            return None

    if not api_key:
        log("LLM layer: no ANTHROPIC_API_KEY and no claude CLI; deterministic-only")
    return None


def _llm_via_api(api_key, prompt):
    body = json.dumps({
        "model": HAIKU_MODEL,
        "max_tokens": LLM_MAX_TOKENS,
        "messages": [{"role": "user", "content": prompt}],
    }).encode("utf-8")
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=body,
        method="POST",
        headers={
            "content-type": "application/json",
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
        },
    )
    with urllib.request.urlopen(req, timeout=LLM_TIMEOUT_S) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    parts = payload.get("content", [])
    text = "".join(p.get("text", "") for p in parts if p.get("type") == "text")
    text = text.strip()
    log(f"LLM api ok ({HAIKU_MODEL}): {text!r}")
    return text or None


def _claude_cli_path():
    try:
        out = subprocess.run(["bash", "-lc", "command -v claude"],
                             capture_output=True, text=True, timeout=10)
        path = out.stdout.strip()
        return path or None
    except Exception:
        return None


def _llm_via_cli(prompt):
    cli = _claude_cli_path()
    if not cli:
        return None
    proc = subprocess.run(
        [cli, "-p", prompt, "--model", HAIKU_MODEL],
        capture_output=True, text=True, timeout=LLM_TIMEOUT_S * 3,
    )
    text = (proc.stdout or "").strip()
    if proc.returncode != 0 and not text:
        raise RuntimeError(f"claude CLI exit {proc.returncode}: {proc.stderr[:200]}")
    log(f"LLM cli ok: {text!r}")
    return text or None


# --- main -------------------------------------------------------------------
def main(argv):
    if len(argv) < 3:
        sys.stderr.write("usage: tools/review.py <platform> <RUN_ID>\n")
        return 2
    platform = argv[1]
    run_id = argv[2]

    os.makedirs(REVIEWS_DIR, exist_ok=True)
    os.makedirs(BASELINES_DIR, exist_ok=True)

    # Load data. A missing/corrupt result.json is itself a BROKEN run.
    try:
        data, _ = load_result(platform)
    except Exception as e:
        log(f"{platform}: cannot load result.json: {e}")
        verdict_out = {
            "platform": platform, "run_id": run_id,
            "captured_at": None, "verdict": "BROKEN",
            "rows": 0, "unique_skus": 0, "pincodes_with_jivo": None,
            "baseline_rows": None,
            "checks": [{"name": "load_result", "pass": False,
                        "detail": f"cannot load result.json: {e}"}],
            "reasons": [f"cannot load result.json: {e}"],
            "llm_note": None,
        }
        write_verdict(platform, run_id, verdict_out)
        print(f"[review] {platform} {run_id}: BROKEN (result.json unreadable)")
        return 2

    rows = extract_rows(data)
    per_pincode = is_per_pincode(data)
    summary = data.get("summary", {}) or {}
    captured_at = summary.get("captured_at")

    n_rows = len(rows)
    n_skus = len({r.get("canonical") for r in rows if r.get("canonical")})
    pin_jivo = pincodes_with_jivo(data, rows)
    priced_rows = sum(1 for r in rows
                      if r.get("in_stock") and (num(r.get("sale")) or 0) > 0)

    expected = baseline_expected(normalize_baseline(platform, load_baseline(platform)))
    baseline_rows = round(expected["rows"]) if (expected and expected.get("rows")) else None

    checks, reasons, hard_broken, soft_suspect = run_checks(
        data, rows, per_pincode, expected, run_id, platform)

    # Decide verdict from deterministic checks first.
    if hard_broken:
        verdict = "BROKEN"
    elif soft_suspect:
        verdict = "SUSPECT"
    else:
        verdict = "OK"

    # Optional LLM layer: only consult when not already BROKEN (no point
    # spending a token on an obviously dead run). Failure-proof.
    llm_note = None
    if verdict != "BROKEN":
        try:
            digest = build_digest(platform, per_pincode, n_rows, n_skus,
                                   pin_jivo, expected, rows)
            llm_note = llm_judge(digest)
        except Exception as e:
            log(f"{platform}: LLM layer raised (ignored): {e}\n"
                f"{traceback.format_exc()}")
            llm_note = None

        if llm_note:
            checks.append({
                "name": "llm_judgment", "pass": not _llm_flags(llm_note),
                "detail": llm_note,
            })
            if _llm_flags(llm_note):
                reasons.append(f"llm_judgment: {llm_note}")
                if verdict == "OK":
                    verdict = "SUSPECT"

    verdict_out = {
        "platform": platform,
        "run_id": run_id,
        "captured_at": captured_at,
        "verdict": verdict,
        "rows": n_rows,
        "unique_skus": n_skus,
        "pincodes_with_jivo": pin_jivo if per_pincode else None,
        "baseline_rows": baseline_rows,
        "checks": checks,
        "reasons": reasons,
        "llm_note": llm_note,
    }
    write_verdict(platform, run_id, verdict_out)

    # Update the rolling baseline on OK runs, AND on runs that are SUSPECT *only* because of the
    # price-staleness alarm: those have healthy row/SKU/coverage counts (staleness is orthogonal to
    # the row-count baseline), so excluding them would freeze the baseline whenever a price sits
    # legitimately stable on the snapshot path. Other platforms never emit a price_staleness reason,
    # so this branch never changes their behaviour.
    staleness_only = (
        verdict == "SUSPECT"
        and bool(reasons)
        and all(r.startswith("price_staleness:") for r in reasons)
    )
    if verdict == "OK" or staleness_only:
        if staleness_only:
            log(f"{platform} {run_id}: SUSPECT (staleness-only) — still seeding baseline")
        update_baseline(platform, {
            "run_id": run_id,
            "captured_at": captured_at,
            "rows": n_rows,
            "unique_skus": n_skus,
            "pincodes_with_jivo": pin_jivo if per_pincode else None,
            "priced_rows": priced_rows,
        })

    # One-line summary to stdout.
    cov = f" cov={pin_jivo}" if per_pincode else ""
    base = f" base={baseline_rows}" if baseline_rows is not None else " base=none"
    note = f" | llm: {llm_note}" if llm_note else ""
    print(f"[review] {platform} {run_id}: {verdict} "
          f"(rows={n_rows} skus={n_skus}{cov}{base}){note}")
    if reasons:
        print("  reasons: " + "; ".join(reasons[:5]))

    log(f"{platform} {run_id}: {verdict} rows={n_rows} skus={n_skus} "
        f"cov={pin_jivo if per_pincode else 'n/a'} reasons={reasons}")

    # Exit code: 0 for OK/SUSPECT, non-zero for BROKEN.
    return 0 if verdict != "BROKEN" else 2


def _llm_flags(note):
    """True if the LLM's one-line verdict starts with/contains a SUSPECT/BROKEN flag."""
    head = (note or "").strip().upper()
    return head.startswith("SUSPECT") or head.startswith("BROKEN") \
        or "SUSPECT" in head[:12] or "BROKEN" in head[:12]


def write_verdict(platform, run_id, obj):
    path = os.path.join(REVIEWS_DIR, f"{platform}-{run_id}.json")
    try:
        os.makedirs(REVIEWS_DIR, exist_ok=True)
        with open(path, "w") as f:
            json.dump(obj, f, indent=2)
    except Exception as e:
        log(f"{platform}: failed to write verdict {path}: {e}")


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except SystemExit:
        raise
    except Exception as e:
        # Last-resort guard: review must never crash the cron with a traceback
        # in a way that masks the verdict. Log and exit BROKEN.
        log(f"FATAL in review.py: {e}\n{traceback.format_exc()}")
        sys.stderr.write(f"[review] FATAL: {e}\n")
        sys.exit(2)
