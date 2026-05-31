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
import json
import time
import datetime
import urllib.request
import urllib.error
import subprocess
import traceback

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

# Baseline drift tolerances (fraction of the rolling baseline).
ROWS_SUSPECT_DROP = 0.40      # <60% of baseline rows -> SUSPECT
ROWS_BROKEN_DROP = 0.75       # <25% of baseline rows -> BROKEN
ROWS_SUSPECT_SPIKE = 3.0      # >3x baseline rows -> SUSPECT (shape changed?)
SKU_SUSPECT_DROP = 0.40       # <60% of baseline unique SKUs -> SUSPECT
COVERAGE_SUSPECT_DROP = 0.40  # per-pincode: <60% of baseline coverage -> SUSPECT
COVERAGE_BROKEN_DROP = 0.75   # per-pincode: <25% of baseline coverage -> BROKEN

BASELINE_WINDOW = 10          # rolling window of recent OK runs to average over

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


def run_checks(data, rows, per_pincode, expected, run_id):
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

    # 5) prices > 0 and within plausible band (IN-STOCK rows only — an
    #    out-of-stock listing legitimately has no current price, e.g. Amazon) -
    bad_price = []
    for i, r in enumerate(rows):
        if not r.get("in_stock"):   # skip out-of-stock (0/False/None): no current price
            continue
        sale = num(r.get("sale"))
        if sale is None or sale <= 0 or sale < PRICE_MIN or sale > PRICE_MAX:
            bad_price.append((i, r.get("sku_raw"), r.get("sale")))
    ok = len(bad_price) == 0
    add("prices_in_band", ok,
        "all sale prices in (0, band]" if ok
        else f"{len(bad_price)} rows w/ implausible price e.g. "
             f"{bad_price[0][1]!r}={bad_price[0][2]!r}",
        severity="suspect")

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

    expected = baseline_expected(normalize_baseline(platform, load_baseline(platform)))
    baseline_rows = round(expected["rows"]) if (expected and expected.get("rows")) else None

    checks, reasons, hard_broken, soft_suspect = run_checks(
        data, rows, per_pincode, expected, run_id)

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

    # Update the rolling baseline ONLY on OK runs.
    if verdict == "OK":
        update_baseline(platform, {
            "run_id": run_id,
            "captured_at": captured_at,
            "rows": n_rows,
            "unique_skus": n_skus,
            "pincodes_with_jivo": pin_jivo if per_pincode else None,
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
