#!/usr/bin/env python3
"""Patch selected Blinkit pincode results from a targeted repair into a shard.

This keeps the original shard manifest/source pincode set intact, replacing only
the repaired perPin entries and their allRows. The result still has to pass the
normal merge, ingest, and quality gates before publication.
"""
from __future__ import annotations

import datetime as dt
import json
import sys
from pathlib import Path


def load(path: str) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def pincode(row: dict) -> str:
    return str(row.get("pincode") or "").strip()


def recompute_summary(base_summary: dict, per_pin: list[dict], rows: list[dict]) -> dict:
    summary = dict(base_summary)
    summary.update(
        {
            "pincodes_total": len(per_pin),
            "pincodes_resolved": sum(1 for p in per_pin if p.get("resolved")),
            "pincodes_unresolved": sum(1 for p in per_pin if not p.get("resolved")),
            "pincodes_with_jivo": sum(1 for p in per_pin if p.get("rows")),
            "pincodes_blocked": sum(1 for p in per_pin if p.get("blocked") or p.get("partial_block")),
            "total_rows": len(rows),
            "unique_skus": len({r.get("canonical") for r in rows if r.get("canonical")}),
            "auth_session": 1,
            "auth_required": 1,
            "auth_verified_pincodes": sum(1 for p in per_pin if p.get("auth_accepted")),
            "oos_probe_enabled": 1,
            "pdp_oos_probe_enabled": 1,
            "pdp_price_probe_enabled": 1,
            "pdp_price_probe_failed": sum(1 for r in rows if r.get("pdp_price_probe_failed")),
            "unverified_oos": sum(
                1
                for r in rows
                if not r.get("in_stock")
                and not r.get("pdp_checked")
                and str(r.get("stock_source") or "").strip().lower() not in {"pdp", "pdp_probe"}
            ),
            "captured_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        }
    )
    summary["auth_verified"] = 1 if summary["auth_verified_pincodes"] == len(per_pin) else 0
    return summary


def main() -> int:
    if len(sys.argv) < 4:
        raise SystemExit(
            "usage: blinkit_apply_targeted_shard_repair.py <base-shard-result.json> "
            "<target-result.json> <out.json>"
        )
    base_path, target_path, out_path = sys.argv[1:4]
    base = load(base_path)
    target = load(target_path)

    base_per = base.get("perPin") or []
    base_rows = base.get("allRows") or []
    target_per = target.get("perPin") or []
    target_rows = target.get("allRows") or []
    target_pins = {pincode(p) for p in target_per}
    if not target_pins:
        raise SystemExit("target repair has no perPin pincodes")

    missing = sorted(target_pins - {pincode(p) for p in base_per})
    if missing:
        raise SystemExit(f"target pins not present in base shard: {missing[:10]}")

    if any(not p.get("auth_accepted") for p in target_per):
        bad = [pincode(p) for p in target_per if not p.get("auth_accepted")]
        raise SystemExit(f"target repair still has unverified auth pincodes: {bad[:10]}")

    target_by_pin = {pincode(p): p for p in target_per}
    repaired_per = [target_by_pin.get(pincode(p), p) for p in base_per]
    repaired_rows = [r for r in base_rows if pincode(r) not in target_pins] + target_rows

    out = dict(base)
    out["perPin"] = repaired_per
    out["allRows"] = repaired_rows
    out["summary"] = recompute_summary(base.get("summary") or {}, repaired_per, repaired_rows)
    out["targeted_repair"] = {
        "source": str(target_path),
        "pins": sorted(target_pins),
        "repaired_at_utc": out["summary"]["captured_at"],
    }

    tmp = Path(out_path).with_suffix(Path(out_path).suffix + ".tmp")
    tmp.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    tmp.replace(out_path)
    print(json.dumps({"out": out_path, "summary": out["summary"], "pins": sorted(target_pins)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
