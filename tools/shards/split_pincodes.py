#!/usr/bin/env python3
"""Create a deterministic pincode shard and manifest.

The split rule is intentionally simple and stable:

    shard_index = original_index % shard_total

That makes retries deterministic and prevents the VPS and Mac from duplicating
pincodes for the same source config.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path


def load_config(path: Path) -> list[dict]:
    data = json.loads(path.read_text())
    if not isinstance(data, list):
        raise SystemExit(f"{path} must contain a JSON list")
    for i, row in enumerate(data):
        if not isinstance(row, dict):
            raise SystemExit(f"{path}: entry {i} is not an object")
        if "pincode" not in row:
            raise SystemExit(f"{path}: entry {i} has no pincode")
    return data


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
      for chunk in iter(lambda: f.read(1024 * 1024), b""):
          h.update(chunk)
    return h.hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("platform")
    ap.add_argument("source_config")
    ap.add_argument("out_dir")
    ap.add_argument("--total", type=int, required=True)
    ap.add_argument("--index", type=int, required=True)
    ap.add_argument("--run-id", default=dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ"))
    ap.add_argument("--role", default="worker")
    args = ap.parse_args()

    if args.total < 1:
        raise SystemExit("--total must be >= 1")
    if args.index < 0 or args.index >= args.total:
        raise SystemExit("--index must satisfy 0 <= index < total")

    source = Path(args.source_config).resolve()
    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    config = load_config(source)
    shard = [row for i, row in enumerate(config) if i % args.total == args.index]

    shard_name = f"pincodes.{args.index}-of-{args.total}.json"
    manifest_name = f"manifest.{args.index}-of-{args.total}.json"
    shard_path = out_dir / shard_name
    manifest_path = out_dir / manifest_name

    shard_path.write_text(json.dumps(shard, indent=2, ensure_ascii=False) + "\n")
    manifest = {
        "schema": "jivo-shard-manifest-v1",
        "platform": args.platform,
        "run_id": args.run_id,
        "role": args.role,
        "shard_index": args.index,
        "shard_total": args.total,
        "source_config": str(source),
        "source_sha256": sha256_file(source),
        "source_count": len(config),
        "source_pincodes": [str(row["pincode"]) for row in config],
        "shard_count": len(shard),
        "shard_pincodes": [str(row["pincode"]) for row in shard],
        "created_at_utc": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "shard_config": str(shard_path),
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({
        "manifest": str(manifest_path),
        "pincodes_file": str(shard_path),
        "shard_count": len(shard),
        "source_count": len(config),
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
