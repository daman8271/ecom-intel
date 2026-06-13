#!/usr/bin/env python3
"""
autoheal_amazon.py — reactive, identity-only auto-heal for the Amazon
canonical-collision (shared_price_dup) hold.

Spec: docs/superpowers/specs/2026-06-13-amazon-canonical-autoheal-design.md

WHAT
  When an Amazon report is about to be HELD *solely* because of the
  shared_price_dup canonical-collision flag (and nothing hard-fails), wake Claude
  to decide, per colliding canonical group, whether the colliding IDs are the
  SAME underlying product (a truncated/stub canonical vs the full one — Amazon
  sometimes returns a short product title for a few rows, minting a second
  canonical for the same listing) or GENUINELY DIFFERENT products that happen to
  share a price. For SAME groups, merge the stub canonical(s) into the full
  survivor in THIS run's result.json (identity-only — NEVER touches
  price/mrp/discount), rebuild the report xlsx, and re-run review.py so the
  verdict flips to OK naturally. Genuinely-distinct or suspicious collisions are
  left HELD.

GUARDRAILS (non-negotiable — see spec §3)
  - identity-only: only `canonical` (+ `item` when present) is rewritten; `sale`,
    `mrp`, `discount_pct` are NEVER modified, and NO row is added or dropped. A
    post-merge tripwire proves the per-row priced multiset is byte-identical; if
    it ever differs, everything is rolled back from the snapshot.
  - trigger gate: platform in the Amazon family; verdict == SUSPECT (not BROKEN);
    EVERY review reason is a shared_price_dup reason; nothing hard-failed.
  - reversible: snapshots result.json + the verdict before any change.
  - fail-safe: Claude unreachable / unparseable / merges nothing -> NO change, the
    report stays held (exactly today's behaviour). The verdict can only ever be
    *improved* to OK by a fresh, independent review.py run on the healed data —
    this script never writes a verdict itself.
  - bounded: one `claude -p` call; no retry loop.
  - audited: every action -> logs/autoheal.log + one Telegram note to the owner.

USAGE  python3 tools/autoheal_amazon.py <platform> <run_id>
EXIT   0 always (best-effort; must never fail the run). The OUTCOME is conveyed
       by the reviews/<platform>-<run_id>.json verdict that the re-review writes,
       which run.sh re-reads right after calling this script.
"""

import datetime
import json
import os
import re
import shutil
import subprocess
import sys

TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS_DIR)
PLATFORMS_DIR = os.path.join(ROOT, "platforms")
REVIEWS_DIR = os.path.join(ROOT, "reviews")
LOGS_DIR = os.path.join(ROOT, "logs")
BACKUPS_DIR = os.path.join(ROOT, "backups", "autoheal")
SECRETS_ENV = os.path.join(ROOT, "secrets.env")
LOG_PATH = os.path.join(LOGS_DIR, "autoheal.log")

AMAZON_PLATFORMS = {"amazon-now", "amazon", "amazon-fresh"}
# Default model: the owner's Max-included default on this VPS. One-line override.
MODEL = os.environ.get("AUTOHEAL_MODEL", "claude-fable-5")
CLI_TIMEOUT_S = int(os.environ.get("AUTOHEAL_CLI_TIMEOUT_S", "180"))

# Mirror review.py's shared_price_dup identity/combo logic so we recompute the
# SAME colliding groups the gate saw (the verdict reason only names the worst pair).
_COMBO_RE = re.compile(r"\+|\bcombo\b|pack of \d+")
_WS_RE = re.compile(r"\s+")


def log(msg):
    """Append a timestamped line to logs/autoheal.log. Never raises."""
    try:
        os.makedirs(LOGS_DIR, exist_ok=True)
        stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with open(LOG_PATH, "a") as f:
            f.write(f"[{stamp}] {msg}\n")
    except Exception:
        pass


def _num(v):
    try:
        return None if v is None else float(v)
    except (TypeError, ValueError):
        return None


def _is_combo(r):
    for fld in (r.get("item"), r.get("sku_raw")):
        if fld and _COMBO_RE.search(str(fld).lower()):
            return True
    return False


def _identity(r):
    """The key review.py + guardian both count: human `item` if present, else canonical."""
    it = r.get("item")
    if it:
        return ("item", _WS_RE.sub(" ", str(it).strip().lower()))
    return ("canon", r.get("canonical"))


def all_rows(data):
    """Flat authoritative list — same precedence as review.extract_rows."""
    rows = data.get("allRows")
    if isinstance(rows, list) and rows:
        return rows
    flat = []
    for pin in data.get("perPin", []) or []:
        for r in pin.get("rows", []) or []:
            flat.append(r)
    return flat


def colliding_pairs(rows):
    """
    Recompute the discounted (sale,mrp) pairs shared by >= 2 DISTINCT identities,
    exactly as review.py/guardian do. Returns a list of dicts, one per colliding
    pair: {sale, mrp, identities: {identity -> {canonicals:set, asins:set,
    sample_title, rows}}}.
    """
    pair = {}  # (sale,mrp) -> { identity -> agg }
    for r in rows:
        s, m, c = _num(r.get("sale")), _num(r.get("mrp")), r.get("canonical")
        if s is None or m is None or not c:
            continue
        if s <= 0 or abs(s - m) < 0.5:      # require a genuine discount
            continue
        if _is_combo(r):                    # combos legitimately share a bundle price
            continue
        ident = _identity(r)
        agg = pair.setdefault((round(s, 2), round(m, 2)), {}).setdefault(
            ident, {"canonicals": set(), "asins": set(), "sample_title": None, "rows": 0})
        agg["canonicals"].add(c)
        if r.get("asin"):
            agg["asins"].add(str(r.get("asin")))
        if not agg["sample_title"] and r.get("sku_raw"):
            agg["sample_title"] = str(r.get("sku_raw"))
        agg["rows"] += 1

    out = []
    for (s, m), idents in pair.items():
        if len(idents) >= 2:
            out.append({"sale": s, "mrp": m, "identities": idents})
    return out


def build_evidence(pairs):
    """Compact, identity-only evidence for Claude. No price-correctness asked."""
    ev = []
    for p in pairs:
        members = []
        for ident, agg in p["identities"].items():
            for c in sorted(agg["canonicals"]):
                members.append({
                    "canonical": c,
                    "sample_title": agg["sample_title"],
                    "asins": sorted(agg["asins"])[:3],
                    "rows": agg["rows"],
                })
        ev.append({"shared_sale": p["sale"], "shared_mrp": p["mrp"], "products": members})
    return ev


PROMPT_HEADER = (
    "You are adjudicating DUPLICATE PRODUCT IDENTITIES in ONE Amazon scrape of the "
    "brand Jivo (edible/olive oils and other Jivo grocery lines). A quality gate "
    "flagged that several distinct product IDs (`canonical`) share the EXACT same "
    "(sale, mrp). The usual cause: Amazon returned a TRUNCATED product title for a "
    "few rows, so the SAME physical product got a second, shorter `canonical` (a "
    "\"stub\", often cut mid-word or ending in -na). Decide which canonicals are the "
    "SAME underlying product (one is a truncation/variant of another) vs GENUINELY "
    "DIFFERENT products that merely share a price.\n\n"
    "RULES:\n"
    "- Same ASIN => definitely the SAME product.\n"
    "- A `canonical` that is a prefix/truncation of a longer one, with a matching "
    "(shorter) title, is the SAME product (the stub). The survivor is the FULLER / "
    "longer canonical.\n"
    "- If you are NOT confident two are the same physical product, mark them "
    "DISTINCT. Bias toward DISTINCT when unsure. NEVER merge two genuinely "
    "different products.\n"
    "- You judge IDENTITY ONLY. Do not comment on whether prices are right.\n\n"
    "Return ONLY a JSON object, no prose:\n"
    "{\"merges\":[{\"survivor\":\"<canonical>\",\"stubs\":[\"<canonical>\",...],"
    "\"why\":\"<short>\"}],\"distinct\":[\"<canonical>\",...]}\n"
    "An empty \"merges\" list means nothing should be merged.\n\n"
    "COLLISIONS:\n"
)


def _claude_cli():
    try:
        out = subprocess.run(["bash", "-lc", "command -v claude"],
                             capture_output=True, text=True, timeout=10)
        return out.stdout.strip() or None
    except Exception:
        return None


def _model_chain():
    """
    Models to try, in order, until one returns a usable verdict. Robust to any one
    model being temporarily unavailable (e.g. Fable 5 outages): AUTOHEAL_MODEL (or
    the owner's Max-included default) -> the CLI's own default -> always-up Haiku.
    `None` means 'no --model flag' (use the CLI default).
    """
    chain = [os.environ.get("AUTOHEAL_MODEL") or MODEL, None, "claude-haiku-4-5"]
    seen, out = set(), []
    for m in chain:
        key = m or "__default__"
        if key not in seen:
            seen.add(key)
            out.append(m)
    return out


def adjudicate(evidence):
    """
    One bounded adjudication, trying the model chain until one returns a usable
    {"merges":[...], "distinct":[...]} object. Returns that dict, or None on total
    failure (fail-safe -> caller keeps the report held). No retry loop per model.
    """
    cli = _claude_cli()
    if not cli:
        log("adjudicate: no `claude` CLI on PATH -> fail-safe (keep held)")
        return None
    prompt = PROMPT_HEADER + json.dumps(evidence, ensure_ascii=False, indent=2)
    for model in _model_chain():
        cmd = [cli, "-p", prompt] + (["--model", model] if model else [])
        tag = model or "cli-default"
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True,
                                  timeout=CLI_TIMEOUT_S, cwd=ROOT)
        except Exception as e:
            log(f"adjudicate[{tag}]: claude CLI raised ({e}); trying next model")
            continue
        text = (proc.stdout or "").strip()
        parsed = _extract_json(text)
        if parsed is not None and (("merges" in parsed) or ("distinct" in parsed)):
            log(f"adjudicate[{tag}]: usable verdict "
                f"(merges={len(parsed.get('merges') or [])}, distinct={len(parsed.get('distinct') or [])})")
            return parsed
        log(f"adjudicate[{tag}]: no usable JSON (exit {proc.returncode}) :: {text[:160]!r}; trying next model")
    log("adjudicate: all models failed -> fail-safe (keep held)")
    return None


def _extract_json(text):
    """Best-effort: whole string, then ```json fenced block, then first {...last }."""
    for candidate in _json_candidates(text):
        try:
            obj = json.loads(candidate)
            if isinstance(obj, dict):
                return obj
        except Exception:
            continue
    return None


def _json_candidates(text):
    yield text
    fence = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
    if fence:
        yield fence.group(1)
    i, j = text.find("{"), text.rfind("}")
    if 0 <= i < j:
        yield text[i:j + 1]


def validate_merges(parsed, present_canonicals):
    """
    Keep only well-formed merge directives whose survivor + stubs all exist in the
    data, stub != survivor, and no canonical is claimed by two merges. Returns a
    flat map {stub_canonical -> survivor_canonical}.
    """
    merge_map = {}
    claimed = set()
    for d in (parsed.get("merges") or []):
        if not isinstance(d, dict):
            continue
        survivor = d.get("survivor")
        stubs = d.get("stubs") or []
        if survivor not in present_canonicals or not isinstance(stubs, list):
            log(f"validate: dropping merge w/ unknown survivor {survivor!r}")
            continue
        for stub in stubs:
            if stub == survivor:
                continue
            if stub not in present_canonicals:
                log(f"validate: dropping unknown stub {stub!r}")
                continue
            if stub in claimed or stub in merge_map or stub == survivor:
                continue
            if survivor in merge_map:   # never chain: survivor must be terminal
                log(f"validate: survivor {survivor!r} is itself a stub elsewhere; skipping {stub!r}")
                continue
            merge_map[stub] = survivor
            claimed.add(stub)
    return merge_map


def priced_signature(rows):
    """Sorted multiset of per-row priced values — the tripwire for 'never touch prices'."""
    sig = []
    for r in rows:
        sig.append((round(_num(r.get("sale")) or 0, 2),
                    round(_num(r.get("mrp")) or 0, 2),
                    round(_num(r.get("discount_pct")) or 0, 2),
                    1 if r.get("in_stock") else 0))
    sig.sort()
    return sig


def survivor_item(rows, survivor):
    """The `item` value carried by the survivor's rows (None on amazon-now)."""
    for r in rows:
        if r.get("canonical") == survivor and r.get("item"):
            return r.get("item")
    return None


def apply_merges(data, merge_map):
    """
    Rewrite `canonical` (+ `item`) on every stub row -> survivor, in BOTH allRows
    and perPin[].rows. Identity-only: no price field is touched, no row added or
    dropped. Returns the number of rows rewritten.
    """
    survivor_items = {sv: survivor_item(all_rows(data), sv) for sv in set(merge_map.values())}
    rewritten = 0

    def fix(rowlist):
        nonlocal rewritten
        for r in rowlist or []:
            sv = merge_map.get(r.get("canonical"))
            if sv:
                r["canonical"] = sv
                it = survivor_items.get(sv)
                if it:
                    r["item"] = it
                rewritten += 1

    fix(data.get("allRows"))
    for pin in data.get("perPin", []) or []:
        fix(pin.get("rows"))
    return rewritten


def refresh_summary(data):
    """Keep summary counts consistent with the merged rows (report cosmetics)."""
    rows = all_rows(data)
    summ = data.setdefault("summary", {})
    summ["unique_skus"] = len({r.get("canonical") for r in rows if r.get("canonical")})
    summ["total_rows"] = len(rows)


def rebuild_report(platform, run_id):
    """Re-run the SAME xlsx build chain run.sh uses, so the delivered report reflects
    the merged identities. Best-effort: review.py reads result.json (not the xlsx),
    so a sheet-builder hiccup never blocks the verdict flip."""
    pdir = os.path.join(PLATFORMS_DIR, platform)

    def run(cmd, cwd, label):
        try:
            r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=600)
            if r.returncode != 0:
                log(f"rebuild {label}: exit {r.returncode}: {(r.stderr or '')[:160]}")
        except Exception as e:
            log(f"rebuild {label}: raised ({e})")

    def newest_xlsx():
        xs = [os.path.join(pdir, f) for f in os.listdir(pdir)
              if f.startswith("Jivo-") and f.endswith(".xlsx")]
        return max(xs, key=os.path.getmtime) if xs else None

    run(["python3", "build_excel.py"], pdir, "build_excel")
    xlsx = newest_xlsx()
    if xlsx:
        run(["python3", os.path.join(TOOLS_DIR, "predict.py"), platform, xlsx], ROOT, "predict")
        addpm = os.path.join(TOOLS_DIR, "pricematch", "add_pricematch_sheet.py")
        if os.path.isfile(addpm):
            run(["python3", addpm, platform, xlsx], ROOT, "add_pricematch_sheet")
        dash = os.path.join(TOOLS_DIR, "report_dashboard.py")
        if os.path.isfile(dash):
            run(["python3", dash, platform, xlsx], ROOT, "report_dashboard")
        try:
            shutil.copy2(xlsx, os.path.join(ROOT, "output"))
        except Exception as e:
            log(f"rebuild: cp to output/ failed ({e})")


def re_review(platform, run_id):
    """Fresh, independent review.py on the healed data -> rewrites the verdict JSON."""
    try:
        subprocess.run(["python3", os.path.join(TOOLS_DIR, "review.py"), platform, run_id],
                       cwd=ROOT, capture_output=True, text=True, timeout=300)
    except Exception as e:
        log(f"re_review: review.py raised ({e})")


def read_verdict(path):
    try:
        with open(path) as f:
            d = json.load(f)
        return (d.get("verdict") or "").upper(), d
    except Exception:
        return "", {}


def telegram(text):
    """One owner notification. Best-effort; never raises."""
    env = {}
    try:
        if os.path.isfile(SECRETS_ENV):
            with open(SECRETS_ENV) as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("#") or "=" not in line:
                        continue
                    k, _, v = line.partition("=")
                    env[k.strip()] = v.strip().strip('"').strip("'")
    except Exception:
        pass
    tg = env.get("TELEGRAM_BOT_TOKEN") or os.environ.get("TELEGRAM_BOT_TOKEN")
    ch = (env.get("TELEGRAM_OWNER_CHAT_ID") or env.get("TELEGRAM_CHAT_ID")
          or os.environ.get("TELEGRAM_OWNER_CHAT_ID") or os.environ.get("TELEGRAM_CHAT_ID"))
    if not tg or not ch:
        return
    try:
        import urllib.parse
        import urllib.request
        body = urllib.parse.urlencode({"chat_id": ch, "text": text}).encode()
        req = urllib.request.Request(
            f"https://api.telegram.org/bot{tg}/sendMessage", data=body, method="POST")
        urllib.request.urlopen(req, timeout=30).read()
    except Exception as e:
        log(f"telegram: send failed ({e})")


def eligible(platform, verdict_path):
    """Trigger gate (spec §4). Returns (ok, verdict_dict, why_not)."""
    if platform not in AMAZON_PLATFORMS:
        return False, {}, f"platform {platform} not in Amazon family"
    verdict, d = read_verdict(verdict_path)
    if not d:
        return False, {}, "no verdict file"
    if verdict != "SUSPECT":
        return False, d, f"verdict={verdict} (only SUSPECT is eligible)"
    reasons = d.get("reasons") or []
    if not reasons:
        return False, d, "SUSPECT but no reasons recorded"
    if not all(str(r).startswith("shared_price_dup:") for r in reasons):
        return False, d, "other failing checks present (only shared_price_dup is in scope)"
    return True, d, ""


def main(argv):
    if len(argv) < 3:
        sys.stderr.write("usage: tools/autoheal_amazon.py <platform> <run_id>\n")
        return 0
    platform, run_id = argv[1], argv[2]
    verdict_path = os.path.join(REVIEWS_DIR, f"{platform}-{run_id}.json")

    ok, verdict_d, why = eligible(platform, verdict_path)
    if not ok:
        log(f"{platform} {run_id}: not eligible — {why}")
        return 0
    log(f"{platform} {run_id}: ELIGIBLE (SUSPECT, shared_price_dup-only) — adjudicating")

    result_path = os.path.join(PLATFORMS_DIR, platform, "result.json")
    try:
        with open(result_path) as f:
            data = json.load(f)
    except Exception as e:
        log(f"{platform} {run_id}: cannot load result.json ({e}) -> keep held")
        return 0

    rows = all_rows(data)
    pairs = colliding_pairs(rows)
    if not pairs:
        log(f"{platform} {run_id}: no colliding pairs recomputed -> keep held")
        return 0

    present = {r.get("canonical") for r in rows if r.get("canonical")}
    sku_before = len(present)
    sig_before = priced_signature(rows)

    parsed = adjudicate(build_evidence(pairs))
    if parsed is None:
        telegram(f"🔧 ecom auto-heal · {platform} {run_id}\n"
                 f"Claude unreachable/unparseable — report kept HELD (no change). Needs a look.")
        log(f"{platform} {run_id}: adjudication failed -> kept held")
        return 0

    merge_map = validate_merges(parsed, present)
    if not merge_map:
        distinct = parsed.get("distinct") or []
        telegram(f"🔧 ecom auto-heal · {platform} {run_id}\n"
                 f"Claude judged the {len(pairs)} price-collision(s) as genuinely distinct / "
                 f"not mergeable — report kept HELD. ({len(distinct)} distinct call(s))")
        log(f"{platform} {run_id}: Claude merged nothing (distinct/unsure) -> kept held :: {parsed}")
        return 0

    # ---- snapshot BEFORE any change (reversible) ----
    snap_dir = os.path.join(BACKUPS_DIR, f"{platform}-{run_id}")
    try:
        os.makedirs(snap_dir, exist_ok=True)
        shutil.copy2(result_path, os.path.join(snap_dir, "result.json.bak"))
        if os.path.isfile(verdict_path):
            shutil.copy2(verdict_path, os.path.join(snap_dir, "verdict.json.bak"))
    except Exception as e:
        log(f"{platform} {run_id}: snapshot failed ({e}) -> ABORT (keep held, no change)")
        return 0

    # ---- apply identity-only merges ----
    rewritten = apply_merges(data, merge_map)
    refresh_summary(data)
    rows_after = all_rows(data)

    # ---- TRIPWIRE: prices must be byte-identical (only identity changed) ----
    if priced_signature(rows_after) != sig_before:
        log(f"{platform} {run_id}: TRIPWIRE — priced multiset changed; ROLLING BACK")
        try:
            shutil.copy2(os.path.join(snap_dir, "result.json.bak"), result_path)
        except Exception as e:
            log(f"{platform} {run_id}: rollback copy failed ({e})")
        telegram(f"⚠️ ecom auto-heal · {platform} {run_id}\n"
                 f"Internal price tripwire fired — rolled back, report kept HELD. Investigate.")
        return 0

    try:
        tmp = result_path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(data, f, ensure_ascii=False)
        os.replace(tmp, result_path)
    except Exception as e:
        log(f"{platform} {run_id}: writing healed result.json failed ({e}) -> restoring")
        try:
            shutil.copy2(os.path.join(snap_dir, "result.json.bak"), result_path)
        except Exception:
            pass
        return 0

    sku_after = len({r.get("canonical") for r in rows_after if r.get("canonical")})
    pretty = "\n".join(f"• {stub} → {sv}" for stub, sv in list(merge_map.items())[:6])
    log(f"{platform} {run_id}: merged {len(merge_map)} stub canonical(s), {rewritten} row(s) "
        f"rewritten, SKUs {sku_before}->{sku_after}; rebuilding + re-reviewing")

    # ---- rebuild the delivered report + fresh independent re-review ----
    rebuild_report(platform, run_id)
    re_review(platform, run_id)
    new_verdict, _ = read_verdict(verdict_path)

    if new_verdict == "OK":
        telegram(f"🔧 ecom auto-heal · {platform} {run_id} — RELEASED ✅\n"
                 f"Claude merged {len(merge_map)} stub SKU(s) into their real product:\n{pretty}\n"
                 f"unique SKUs {sku_before}→{sku_after} · prices unchanged · verdict SUSPECT→OK")
        log(f"{platform} {run_id}: verdict SUSPECT->OK after heal -> RELEASED")
    else:
        telegram(f"🔧 ecom auto-heal · {platform} {run_id}\n"
                 f"Merged {len(merge_map)} stub SKU(s) but verdict is still {new_verdict} "
                 f"(remaining distinct collisions) — kept HELD.\n{pretty}")
        log(f"{platform} {run_id}: post-heal verdict={new_verdict} (still held)")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except SystemExit:
        raise
    except Exception as e:
        # Last-resort guard: this helper must NEVER fail the run. Log + exit 0.
        try:
            log(f"FATAL (ignored, report left in its current state): {e}")
        except Exception:
            pass
        sys.exit(0)
