#!/usr/bin/env python3
"""Gate direct-device reports on an atomic promotion receipt."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", required=True)
    parser.add_argument("--date", required=True)
    parser.add_argument("--inbox", default="shards/mac-direct-ready")
    parser.add_argument("--receipts", default="logs/direct-report-receipts")
    parser.add_argument("--mode", choices=("gate", "source"), default="gate")
    args = parser.parse_args()

    report = Path(args.file).resolve()
    platform = "blinkit" if "Blinkit" in report.name else "zepto" if "Zepto" in report.name else ""
    if not platform:
        return 0

    direct_source_exists = False
    pattern = f"{args.date.replace('-', '')}*/report.ready.json"
    for ready in Path(args.inbox).glob(pattern):
        try:
            source = json.loads(ready.read_text(encoding="utf-8-sig"))
            if source.get("date_ist") == args.date and source.get("platform") == platform:
                direct_source_exists = True
                break
        except (OSError, ValueError):
            direct_source_exists = True
            break
    receipt_paths = list((Path(args.receipts) / args.date).glob("*.json"))
    if not direct_source_exists:
        for receipt_path in receipt_paths:
            try:
                receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
                if receipt.get("status") == "accepted" and receipt.get("platform") == platform:
                    direct_source_exists = True
                    break
            except (OSError, ValueError):
                continue
    if args.mode == "source":
        return 0 if direct_source_exists else 1
    if not direct_source_exists:
        return 0
    if not report.is_file():
        return 1

    actual_sha = sha256(report)
    for receipt_path in receipt_paths:
        try:
            receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
            if receipt.get("status") != "accepted" or receipt.get("platform") != platform:
                continue
            for entry in receipt.get("workbooks", []):
                if entry.get("name") == report.name and entry.get("sha256") == actual_sha:
                    return 0
        except (OSError, ValueError):
            continue
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
