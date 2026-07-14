#!/usr/bin/env python3
"""Resume helper for the Blinkit device-team VPS rescue (agent-2, fleet-blinkfix).

Turns a *partial* Mac shard (whatever pins the Mac finished before it died) plus
a VPS *rescue* scrape of only the MISSING pins into ONE shard result that is
indistinguishable from a clean, full-shard scrape to
tools/shards/merge_platform_shards.py and platforms/blinkit/ingest.sh.

Two subcommands:

  plan     --shard-config <full shard pincodes.json>
           [--partial <mac out-file OR .progress.json OR none>]
           --out-remaining <remaining-pincodes.json>
    Decide which shard pins are ALREADY DONE-and-KEEPABLE in the partial and
    which must be (re)scraped. Writes the remaining-pins config (same object
    schema the scraper consumes) and prints a JSON plan to stdout.

  combine  --shard-config <full shard pincodes.json>
           [--partial <mac partial OR none>]
           [--rescue <VPS rescue result.json OR none>]
           --out <combined shard result.json>
    Reassemble kept-partial pins + rescue pins into one shard result.json whose
    perPin covers EXACTLY the shard's pincodes, with allRows and a recomputed
    summary.

KEEP-vs-RESCRAPE rule (mirrors platforms/blinkit/ingest.sh per-pin gates 1:1):
a partial pin is kept ONLY if resolved AND auth_accepted==1 AND not blocked AND
no stock_unverified row. Everything else (unreached, unresolved, auth-failed,
blocked, unverified-row) goes into the remaining set so the gates stay honest.
On overlap, the rescue (newest capture) wins.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
from typing import Any, Iterable


# ---- predicates copied verbatim from platforms/blinkit/ingest.sh ------------
def flag_is_one(value: Any) -> bool:
    if value is True:
        return True
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return value == 1
    return str(value).strip().lower() in {"1", "true", "yes", "y"}


def truthy(value: Any) -> bool:
    if value is True:
        return True
    if value is False or value is None:
        return False
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return value != 0
    return str(value).strip().lower() in {"1", "true", "yes", "y"}


def is_stock_unverified_row(row: dict) -> bool:
    status = str(row.get("listing_status") or row.get("status") or "").strip().lower()
    source = str(row.get("stock_source") or "").strip().lower()
    return bool(row.get("stock_unverified")) or status == "stock_unverified" or source.endswith("_unverified")


def is_oos_row(row: dict) -> bool:
    value = row.get("in_stock")
    if value is False or value == 0:
        return True
    if str(value).strip().lower() in {"0", "false", "no"}:
        return True
    status = str(row.get("listing_status") or row.get("status") or row.get("availability") or "").lower()
    return "out_of_stock" in status or "out of stock" in status or status == "oos"


def pdp_verified_oos(row: dict) -> bool:
    return flag_is_one(row.get("pdp_checked")) or str(row.get("stock_source") or "").strip().lower() == "pdp"


def pin_of(obj: dict) -> str:
    return str(obj.get("pincode", "")).strip()


def keepable(p: dict) -> bool:
    """True iff this partial per-pin entry would individually pass every
    per-pin Blinkit ingest gate, so keeping it can never cause a refusal.

    Mirrors ingest.sh: auth_accepted (:288), not blocked (:291), no
    stock_unverified row (:337), and no OOS row lacking PDP verification
    (:375-384, unverified_oos>0). Also requires resolved, so kept pins add ZERO
    to the merged unresolved count (the max_unresolved=45 gate) — unresolved pins
    are re-scraped for a fresh daytime resolution attempt instead."""
    if not truthy(p.get("resolved")):
        return False
    if not flag_is_one(p.get("auth_accepted")):
        return False
    if truthy(p.get("blocked")) or truthy(p.get("partial_block")):
        return False
    for r in (p.get("rows") or []):
        if is_stock_unverified_row(r):
            return False
        if is_oos_row(r) and not pdp_verified_oos(r):
            return False
    return True


# ---- IO ---------------------------------------------------------------------
def load_json(path: str | Path) -> Any:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def is_none_arg(path: str | None) -> bool:
    return path is None or str(path).strip().lower() in {"", "none", "-"} or not Path(path).exists()


def normalize_partial(path: str | None) -> dict[str, dict]:
    """Return {pincode: perPin-obj} from any partial shape the Mac may leave:
    the finished out-file {perPin:[...]}, the incremental .progress.json
    (dict keyed by pincode), or a bare list. Corrupt/missing -> {} (full rescue)."""
    if is_none_arg(path):
        return {}
    try:
        data = load_json(path)
    except Exception:
        return {}
    entries: Iterable[dict]
    if isinstance(data, dict) and isinstance(data.get("perPin"), list):
        entries = data["perPin"]
    elif isinstance(data, dict):
        # progress file: keyed by pincode -> per-pin object
        entries = [v for v in data.values() if isinstance(v, dict) and "pincode" in v]
    elif isinstance(data, list):
        entries = [v for v in data if isinstance(v, dict) and "pincode" in v]
    else:
        return {}
    out: dict[str, dict] = {}
    for e in entries:
        pin = pin_of(e)
        if pin:
            out[pin] = e  # last write wins within one file
    return out


def summary_of(path: str | None) -> dict:
    if is_none_arg(path):
        return {}
    try:
        data = load_json(path)
    except Exception:
        return {}
    if isinstance(data, dict) and isinstance(data.get("summary"), dict):
        return data["summary"]
    return {}


# ---- plan -------------------------------------------------------------------
def do_plan(args) -> int:
    shard_cfg = load_json(args.shard_config)
    if not isinstance(shard_cfg, list):
        raise SystemExit("shard-config must be a JSON list of pincode objects")
    full_order = [pin_of(o) for o in shard_cfg]
    full_set = set(full_order)

    partial = normalize_partial(args.partial)
    kept = {pin for pin, p in partial.items() if pin in full_set and keepable(p)}
    remaining_order = [pin for pin in full_order if pin not in kept]
    remaining_cfg = [o for o in shard_cfg if pin_of(o) in set(remaining_order)]

    Path(args.out_remaining).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out_remaining).write_text(
        json.dumps(remaining_cfg, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    partial_seen = len(partial)
    partial_unkeepable = sum(1 for pin, p in partial.items() if pin in full_set and not keepable(p))
    plan = {
        "shard_pins": len(full_order),
        "partial_pins_seen": partial_seen,
        "kept": len(kept),
        "remaining": len(remaining_order),
        "partial_seen_but_unkeepable": partial_unkeepable,
        "mode": (
            "full_rescue" if not kept
            else "finalize_only" if not remaining_order
            else "resume"
        ),
        "out_remaining": str(args.out_remaining),
    }
    print(json.dumps(plan, indent=2))
    return 0


# ---- combine ----------------------------------------------------------------
def _iso_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _min_iso(*vals: str | None) -> str | None:
    xs = [v for v in vals if v]
    return min(xs) if xs else None


def _max_iso(*vals: str | None) -> str | None:
    xs = [v for v in vals if v]
    return max(xs) if xs else None


def do_combine(args) -> int:
    shard_cfg = load_json(args.shard_config)
    if not isinstance(shard_cfg, list):
        raise SystemExit("shard-config must be a JSON list of pincode objects")
    full_order = [pin_of(o) for o in shard_cfg]
    full_set = set(full_order)

    partial = normalize_partial(args.partial)
    kept_partial = {pin: p for pin, p in partial.items() if pin in full_set and keepable(p)}

    rescue = normalize_partial(args.rescue)  # rescue result.json -> {pin: perPin}
    rescue = {pin: p for pin, p in rescue.items() if pin in full_set}

    # Assemble perPin in the shard's canonical order. Rescue (newest) wins overlaps.
    merged: dict[str, dict] = dict(kept_partial)
    overlaps = sorted(set(rescue) & set(kept_partial))
    merged.update(rescue)  # rescue wins

    missing = [pin for pin in full_order if pin not in merged]
    if missing:
        raise SystemExit(
            f"combine incomplete: {len(missing)} shard pins covered by neither "
            f"kept-partial nor rescue (sample={missing[:10]})"
        )
    extra = [pin for pin in merged if pin not in full_set]
    if extra:
        raise SystemExit(f"combine has {len(extra)} out-of-shard pins (sample={sorted(extra)[:10]})")

    per_pin = [merged[pin] for pin in full_order]
    all_rows: list[dict] = []
    for p in per_pin:
        all_rows.extend(p.get("rows") or [])

    ps = summary_of(args.partial)
    rs = summary_of(args.rescue)
    have = [s for s in (ps, rs) if s]

    def all_flag(key: str) -> int:
        return 1 if have and all(flag_is_one(s.get(key)) for s in have) else 0

    def any_flag(key: str) -> int:
        return 1 if any(flag_is_one(s.get(key)) for s in have) else 0

    def sum_int(key: str) -> int:
        return sum(int(s.get(key) or 0) for s in have)

    auth_verified_pincodes = sum(1 for p in per_pin if flag_is_one(p.get("auth_accepted")))
    resolved = sum(1 for p in per_pin if truthy(p.get("resolved")))
    unverified_oos = sum(
        1
        for r in all_rows
        if not r.get("in_stock")
        and not r.get("pdp_checked")
        and str(r.get("stock_source") or "").strip().lower() not in {"pdp", "pdp_probe"}
    )
    # wall_s must report the OPERATIVE fresh-scrape leg, NOT the sum of the Mac's
    # pre-death hours + rescue — otherwise the merge inherits a >BLINKIT_MAX_WALL_S
    # (9500) value and the drop is refused on wall even with perfect data
    # (agent-15 blocker #4). The rescue leg only scraped the remaining pins, so its
    # wall is the honest "was this stressed" signal; finalize-only falls back to
    # the partial's wall.
    rescue_wall = int(rs.get("wall_s") or 0)
    partial_wall = int(ps.get("wall_s") or 0)
    wall_s = rescue_wall if rs else partial_wall

    summary = {
        "pincodes_total": len(per_pin),
        "pincodes_resolved": resolved,
        "pincodes_unresolved": len(per_pin) - resolved,
        "pincodes_with_jivo": sum(1 for p in per_pin if p.get("rows")),
        "pincodes_blocked": sum(1 for p in per_pin if truthy(p.get("blocked")) or truthy(p.get("partial_block"))),
        "total_rows": len(all_rows),
        "unique_skus": len({r.get("canonical") for r in all_rows if r.get("canonical")}),
        "wall_s": wall_s,
        "partial": False,
        "auth_session": all_flag("auth_session"),
        "auth_required": any_flag("auth_required") or all_flag("auth_required"),
        "auth_verified": 1 if auth_verified_pincodes == len(per_pin) and len(per_pin) > 0 else 0,
        "auth_verified_pincodes": auth_verified_pincodes,
        "oos_probe_enabled": all_flag("oos_probe_enabled"),
        "oos_probe_flips": sum_int("oos_probe_flips"),
        "pdp_oos_probe_enabled": all_flag("pdp_oos_probe_enabled"),
        "pdp_oos_probe_flips": sum_int("pdp_oos_probe_flips"),
        "pdp_price_probe_enabled": all_flag("pdp_price_probe_enabled"),
        "pdp_price_probe_attempted": sum_int("pdp_price_probe_attempted"),
        "pdp_price_probe_checked": sum_int("pdp_price_probe_checked"),
        "pdp_price_probe_failed": sum_int("pdp_price_probe_failed"),
        "pdp_price_probe_updates": sum_int("pdp_price_probe_updates"),
        "unverified_oos": unverified_oos,
        "scraper_sha256": rs.get("scraper_sha256") or ps.get("scraper_sha256"),
        "started_at": _min_iso(ps.get("started_at"), rs.get("started_at")),
        "captured_at": _max_iso(ps.get("captured_at"), rs.get("captured_at")) or _iso_now(),
        "resume_combined": {
            "kept_from_partial": len(kept_partial),
            "from_rescue": len(rescue),
            "overlaps_rescue_won": len(overlaps),
        },
    }

    out = {"summary": summary, "perPin": per_pin, "allRows": all_rows, "partial": False}
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = out_path.with_suffix(out_path.suffix + ".tmp")
    tmp.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    tmp.replace(out_path)
    print(json.dumps({
        "out": str(out_path),
        "pincodes_total": summary["pincodes_total"],
        "kept_from_partial": len(kept_partial),
        "from_rescue": len(rescue),
        "overlaps_rescue_won": len(overlaps),
        "auth_verified": summary["auth_verified"],
        "auth_verified_pincodes": auth_verified_pincodes,
        "total_rows": summary["total_rows"],
        "unique_skus": summary["unique_skus"],
        "pincodes_unresolved": summary["pincodes_unresolved"],
    }, indent=2))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("plan")
    p.add_argument("--shard-config", required=True)
    p.add_argument("--partial", default=None)
    p.add_argument("--out-remaining", required=True)
    p.set_defaults(func=do_plan)

    c = sub.add_parser("combine")
    c.add_argument("--shard-config", required=True)
    c.add_argument("--partial", default=None)
    c.add_argument("--rescue", default=None)
    c.add_argument("--out", required=True)
    c.set_defaults(func=do_combine)

    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
