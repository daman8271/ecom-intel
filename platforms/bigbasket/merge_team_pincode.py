#!/usr/bin/env python3
"""Merge detached BigBasket pincode team-run shards.

The team runner writes one JSON result per worker. This utility chooses the best
record per requested pincode, normalizes requested city/locality from the pinned
config, and recomputes the summary used by build_excel_pincode.py.
"""

import argparse
import collections
import datetime as dt
import glob
import json
import os
from pathlib import Path


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def status_rank(pin):
    status = str(pin.get("set_status") or "")
    if status == "ok":
        return 3
    if status and status != "failed:exception":
        return 2
    if status == "failed:exception":
        return 1
    return 0


def row_count(pin):
    return len(pin.get("rows") or [])


def is_failed(pin):
    return str(pin.get("set_status") or "").startswith("failed")


def better_pin(old, new):
    if old is None:
        return True
    if row_count(new) != row_count(old):
        return row_count(new) > row_count(old)
    if status_rank(new) != status_rank(old):
        return status_rank(new) > status_rank(old)
    return False


def normalize_pin(pin, config):
    pin = dict(pin)
    pincode = str(pin.get("pincode") or "")
    cfg = config.get(pincode) or {}
    old_city = pin.get("city") or ""
    old_locality = pin.get("locality") or ""

    if cfg:
        city = cfg.get("city") or old_city
        locality = cfg.get("locality") or old_locality
        if old_city and old_city != city and not pin.get("resolved_city"):
            pin["resolved_city"] = old_city
        if old_locality and old_locality != locality and not pin.get("resolved_locality"):
            pin["resolved_locality"] = old_locality
        pin["requested_city"] = city
        pin["requested_locality"] = locality
        pin["city"] = city
        pin["locality"] = locality
        pin["tier"] = cfg.get("tier", pin.get("tier", 0))

    pin.setdefault("resolved_city", "")
    pin.setdefault("resolved_locality", "")
    pin.setdefault("resolved_pincode", "")

    for row in pin.get("rows") or []:
        row["pincode"] = pincode
        if cfg:
            row["requested_city"] = pin.get("requested_city", "")
            row["requested_locality"] = pin.get("requested_locality", "")
            row["city"] = pin.get("city", "")
            row["locality"] = pin.get("locality", "")
        row.setdefault("resolved_pincode", pin.get("resolved_pincode") or "")
        row.setdefault("resolved_city", pin.get("resolved_city") or "")
        row.setdefault("resolved_locality", pin.get("resolved_locality") or "")
    return pin


def candidate_files(run_dir, manifest):
    if manifest and os.path.exists(manifest):
        data = load_json(manifest)
        files = []
        for worker in data.get("workers", []):
            name = worker.get("name")
            if not name:
                continue
            files.append(os.path.join(run_dir, f"{name}.json"))
        return files

    out = []
    skip_prefixes = ("pincodes.", "manifest", "merged-", "backfill-")
    for path in glob.glob(os.path.join(run_dir, "*.json")):
        base = os.path.basename(path)
        if base.startswith(skip_prefixes):
            continue
        out.append(path)
    return sorted(out)


def recompute_summary(per_pin, shard_summaries, source, run_id):
    all_rows = [row for pin in per_pin for row in (pin.get("rows") or [])]
    price_sets = collections.defaultdict(set)
    for row in all_rows:
        canonical = row.get("canonical")
        sale = row.get("sale")
        if canonical and sale is not None:
            price_sets[canonical].add(round(float(sale), 2))

    varied = sum(1 for vals in price_sets.values() if len(vals) > 1)
    target = len(per_pin)
    return {
        "pincodes_total": len(per_pin),
        "pincodes_with_jivo": sum(1 for pin in per_pin if pin.get("rows")),
        "unique_skus": len({row.get("canonical") for row in all_rows if row.get("canonical")}),
        "total_rows": len(all_rows),
        "skus_with_price_variance": varied,
        "verdict": "HYPERLOCAL - Jivo price varies by pincode" if varied else "NO PRICE VARIANCE DETECTED in captured pincodes",
        "source": source,
        "queries": sorted({q for s in shard_summaries for q in (s.get("queries") or [])}) or ["jivo"],
        "session_ok": all(bool(s.get("session_ok")) for s in shard_summaries) if shard_summaries else False,
        "member": all(bool(s.get("member")) for s in shard_summaries) if shard_summaries else False,
        "pricing_mode": "member" if shard_summaries and all(bool(s.get("member")) for s in shard_summaries) else "guest",
        "captured_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "pincodes_target": target,
        "pincode_pull_complete": all(pin.get("set_status") == "ok" for pin in per_pin),
        "min_pincodes_required": max(20, int(target * 0.75 + 0.999)),
        "coverage_ok": len(per_pin) >= max(20, int(target * 0.75 + 0.999)),
        "team_run_id": run_id,
        "shards": shard_summaries,
        "failed_pincodes": sum(1 for pin in per_pin if is_failed(pin)),
        "zero_row_pincodes": sum(1 for pin in per_pin if not pin.get("rows")),
        "location_mismatch_pincodes": sum(
            1
            for pin in per_pin
            if pin.get("resolved_pincode") and str(pin.get("resolved_pincode")) != str(pin.get("pincode"))
        ),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--manifest")
    ap.add_argument("--pins", default=os.path.join(os.path.dirname(__file__), "pincodes_jivo.json"))
    ap.add_argument("--output", required=True)
    ap.add_argument("--allow-missing", action="store_true")
    ap.add_argument("--source", default="BigBasket logged-in browser pincode team (VPS + Mac Pro + KVM1)")
    args = ap.parse_args()

    run_dir = os.path.abspath(args.run_dir)
    run_id = os.path.basename(run_dir)
    config_list = load_json(args.pins)
    config = {str(item["pincode"]): item for item in config_list}
    order = [str(item["pincode"]) for item in config_list]

    chosen = {}
    shard_summaries = {}
    missing = []
    for path in candidate_files(run_dir, args.manifest):
        worker = Path(path).stem
        if not os.path.exists(path):
            missing.append(path)
            continue
        data = load_json(path)
        shard_summaries[worker] = data.get("summary") or {}
        for pin in data.get("perPin") or []:
            pincode = str(pin.get("pincode") or "")
            if not pincode:
                continue
            if better_pin(chosen.get(pincode), pin):
                chosen[pincode] = pin

    if missing and not args.allow_missing:
        raise SystemExit("Missing shard result(s): " + ", ".join(missing))

    per_pin = []
    for pincode in order:
        pin = chosen.get(pincode)
        if pin is None:
            cfg = config[pincode]
            pin = {
                "city": cfg.get("city", ""),
                "pincode": pincode,
                "locality": cfg.get("locality", ""),
                "tier": cfg.get("tier", 0),
                "store_id": "",
                "store_name": "BigBasket",
                "set_status": "missing",
                "fetch_ok": False,
                "serving_sa": "",
                "rows": [],
            }
        per_pin.append(normalize_pin(pin, config))

    all_rows = [row for pin in per_pin for row in (pin.get("rows") or [])]
    summary = recompute_summary(
        per_pin,
        [{"worker": k, **v} for k, v in sorted(shard_summaries.items())],
        args.source,
        run_id,
    )
    payload = {"summary": summary, "perPin": per_pin, "allRows": all_rows}

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    tmp = args.output + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
        f.write("\n")
    os.replace(tmp, args.output)
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
