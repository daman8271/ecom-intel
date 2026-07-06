#!/usr/bin/env python3
"""Merge validated pincode shard results into one platform result JSON.

Usage:
  merge_platform_shards.py <platform> <out.json> <manifest.json> <result.json> [...]

The caller must pass manifest/result pairs. The merge refuses:
- mixed platform/run/config metadata
- duplicate shard indexes
- duplicate pincode results
- incomplete shard sets
- a union that differs from the original source config pincode set
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
from typing import Any


def load_json(path: str | Path) -> Any:
    return json.loads(Path(path).read_text())


def pincode(x: dict) -> str:
    return str(x.get("pincode", "")).strip()


def recompute_summary(platform: str, results: list[dict], per_pin: list[dict], all_rows: list[dict]) -> dict:
    summaries = [r.get("summary", {}) for r in results]
    summary = {
        "pincodes_total": len(per_pin),
        "pincodes_with_jivo": sum(1 for p in per_pin if p.get("rows")),
        "pincodes_blocked": sum(1 for p in per_pin if p.get("blocked") or p.get("partial_block")),
        "total_rows": len(all_rows),
        "unique_skus": len({r.get("canonical") for r in all_rows if r.get("canonical")}),
        "wall_s": sum(int(s.get("wall_s") or 0) for s in summaries),
        "partial": any(bool(r.get("partial") or r.get("summary", {}).get("partial")) for r in results),
        "captured_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "merged_shards": len(results),
        "merge_authority": "vps",
    }

    if any("resolved" in p for p in per_pin):
        summary["pincodes_resolved"] = sum(1 for p in per_pin if p.get("resolved"))
        summary["pincodes_unresolved"] = sum(1 for p in per_pin if not p.get("resolved"))
    if any("serviceable" in p for p in per_pin):
        summary["pincodes_serviceable"] = sum(1 for p in per_pin if p.get("serviceable"))

    if platform == "blinkit":
        summary["auth_session"] = 1 if summaries and all(bool(s.get("auth_session")) for s in summaries) else 0
        summary["auth_required"] = 1 if any(bool(s.get("auth_required")) for s in summaries) else 0

    if platform == "zepto" or any("freshness" in s for s in summaries):
        summary["rows_in_stock"] = sum(1 for r in all_rows if r.get("in_stock"))
        summary["rows_oos"] = sum(1 for r in all_rows if not r.get("in_stock"))
        summary["rows_seed_pdp"] = sum(1 for r in all_rows if r.get("source") == "pdp_seed")
        summary["skus_via_seed"] = len({r.get("canonical") for r in all_rows if r.get("source") == "pdp_seed" and r.get("canonical")})
        markets = {s.get("marketplace") for s in summaries if s.get("marketplace")}
        if len(markets) == 1:
            summary["marketplace"] = next(iter(markets))
        fresh = [s.get("freshness", {}) for s in summaries if isinstance(s.get("freshness"), dict)]
        if fresh:
            rows_total = sum(int(f.get("rows_total") or 0) for f in fresh)
            rows_cached = sum(int(f.get("rows_cached") or 0) for f in fresh)
            stores_total = sum(int(f.get("stores_total") or 0) for f in fresh)
            stores_non_realtime = sum(int(f.get("stores_non_realtime") or 0) for f in fresh)
            reasons: dict[str, int] = {}
            for f in fresh:
                for k, v in (f.get("realtime_not_enabled_reasons") or {}).items():
                    reasons[k] = reasons.get(k, 0) + int(v or 0)
            summary["freshness"] = {
                "rows_total": rows_total,
                "rows_cached": rows_cached,
                "pct_cached": round((rows_cached / rows_total) * 100, 1) if rows_total else 0,
                "stores_total": stores_total,
                "stores_non_realtime": stores_non_realtime,
                "pct_non_realtime": round((stores_non_realtime / stores_total) * 100, 1) if stores_total else 0,
                "realtime_not_enabled_reasons": reasons,
            }

    modes = {s.get("mode") for s in summaries if s.get("mode")}
    if len(modes) == 1:
        summary["mode"] = next(iter(modes))
    return summary


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("platform")
    ap.add_argument("out_json")
    ap.add_argument("pairs", nargs="+", help="manifest/result pairs")
    args = ap.parse_args()

    if len(args.pairs) % 2:
        raise SystemExit("pass manifest/result pairs")

    manifests = []
    results = []
    for i in range(0, len(args.pairs), 2):
        manifests.append(load_json(args.pairs[i]))
        results.append(load_json(args.pairs[i + 1]))

    if not manifests:
        raise SystemExit("no shards supplied")

    base = manifests[0]
    for m in manifests:
        if m.get("schema") != "jivo-shard-manifest-v1":
            raise SystemExit(f"bad manifest schema in shard {m}")
        for key in ("platform", "run_id", "shard_total", "source_sha256", "source_count"):
            if m.get(key) != base.get(key):
                raise SystemExit(f"manifest mismatch for {key}")
        if m.get("platform") != args.platform:
            raise SystemExit(f"manifest platform {m.get('platform')} != {args.platform}")

    total = int(base["shard_total"])
    indexes = [int(m["shard_index"]) for m in manifests]
    if sorted(indexes) != list(range(total)):
        raise SystemExit(f"need shard indexes {list(range(total))}, got {sorted(indexes)}")

    expected = [str(p) for p in base["source_pincodes"]]
    expected_set = set(expected)
    shard_union: set[str] = set()
    per_pin_by_pin: dict[str, dict] = {}
    all_rows: list[dict] = []

    for m, result in zip(manifests, results):
        shard_pins = {str(p) for p in m.get("shard_pincodes", [])}
        if len(shard_pins) != int(m.get("shard_count", -1)):
            raise SystemExit(f"shard {m['shard_index']} manifest has duplicate pincode entries")
        if shard_union & shard_pins:
            dup = sorted(shard_union & shard_pins)[:10]
            raise SystemExit(f"duplicate pincode in manifests: {dup}")
        shard_union |= shard_pins

        per_pin = result.get("perPin")
        if not isinstance(per_pin, list):
            raise SystemExit(f"result for shard {m['shard_index']} has no perPin list")
        result_pins = {pincode(p) for p in per_pin}
        if result_pins != shard_pins:
            missing = sorted(shard_pins - result_pins)[:10]
            extra = sorted(result_pins - shard_pins)[:10]
            raise SystemExit(f"result/manifest pincode mismatch shard {m['shard_index']} missing={missing} extra={extra}")
        for row in per_pin:
            pin = pincode(row)
            if pin in per_pin_by_pin:
                raise SystemExit(f"duplicate perPin pincode {pin}")
            per_pin_by_pin[pin] = row
        rows = result.get("allRows") or []
        if not isinstance(rows, list):
            raise SystemExit(f"result for shard {m['shard_index']} has non-list allRows")
        all_rows.extend(rows)

    if shard_union != expected_set:
        missing = sorted(expected_set - shard_union)[:20]
        extra = sorted(shard_union - expected_set)[:20]
        raise SystemExit(f"shard union != source config missing={missing} extra={extra}")

    order = {pin: i for i, pin in enumerate(expected)}
    merged_per_pin = sorted(per_pin_by_pin.values(), key=lambda row: order[pincode(row)])
    out = {
        "summary": recompute_summary(args.platform, results, merged_per_pin, all_rows),
        "perPin": merged_per_pin,
        "allRows": all_rows,
        "partial": any(bool(r.get("partial") or r.get("summary", {}).get("partial")) for r in results),
        "shard_merge": {
            "schema": "jivo-shard-merge-v1",
            "platform": args.platform,
            "run_id": base["run_id"],
            "source_sha256": base["source_sha256"],
            "source_count": base["source_count"],
            "shard_total": total,
            "merged_at_utc": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        },
    }

    out_path = Path(args.out_json)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = out_path.with_suffix(out_path.suffix + ".tmp")
    tmp.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    os.replace(tmp, out_path)
    print(json.dumps({"out": str(out_path), "summary": out["summary"]}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
